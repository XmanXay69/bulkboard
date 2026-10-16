import BulkCore
import Foundation
import Observation

/// A meal being logged or edited: photo, details, and the items in it.
@Observable
final class MealDraft: Identifiable, Equatable {
    static func == (lhs: MealDraft, rhs: MealDraft) -> Bool { lhs === rhs }

    enum Mode: String, CaseIterable {
        case build = "What's in it"
        case saved = "Saved meal"
    }

    let id = UUID()
    let editing: IntakeRecord?
    var mode: Mode = .build
    var name = ""
    var day: Date
    var slot: MealSlot
    var photo: Data?
    private let originalPhoto: Data?
    var notes = ""
    var items: [ItemDraft]
    var saveAsMeal = false

    var recipeID: UUID?
    var recipeServings = 1.0

    var isReadingPhoto = false
    var photoMessage: String?
    /// Barcodes found in the photo, offered as one-click lookups.
    var barcodes: [String] = []
    var scannedPhoto: Data?

    init(day: Date = .now, slot: MealSlot? = nil) {
        editing = nil
        self.day = day.dayStart
        self.slot = slot ?? MealLogActions.defaultSlot()
        originalPhoto = nil
        items = [ItemDraft()]
    }

    init(editing record: IntakeRecord) {
        editing = record
        name = record.name
        day = record.day
        slot = record.slot
        notes = record.notes
        let photo = record.photoFilename.flatMap { PhotoStore.jpegData($0) }
        self.photo = photo
        originalPhoto = photo
        let logged = record.items
        if logged.isEmpty {
            // Logged before 0.3, or a quick add: keep its totals as one entered item.
            let item = ItemDraft()
            item.product = record.name
            item.match = ItemMatch(name: record.name, brand: nil,
                                   facts: NutritionFacts(perServing: record.macros, servingText: "1 serving"),
                                   source: .manual, detail: "Logged before items were tracked")
            items = [item]
        } else {
            items = logged.map(ItemDraft.init(logged:))
        }
    }

    var isEditing: Bool { editing != nil }

    var readyItems: [LoggedFoodItem] { items.compactMap { $0.logged() } }
    var totals: Macros { readyItems.map(\.macros).sum() }
    var pendingCount: Int { items.filter { !$0.isBlank && $0.match == nil }.count }

    var photoChange: MealLogActions.PhotoChange {
        if photo == originalPhoto { return .keep }
        return photo.map(MealLogActions.PhotoChange.replace) ?? .remove
    }

    var placeholderName: String { MealLogActions.mealName("", items: readyItems) }

    func removeBlankItems() {
        items.removeAll { $0.isBlank && $0.match == nil }
    }
}

/// One line of "what's in it": the product and brand you type, the amount, and the facts it's matched to.
@Observable
final class ItemDraft: Identifiable {
    enum LookupState: Equatable {
        case idle, searching, loadingDetails, estimating
        case failed(String)
    }

    let id = UUID()
    var product = ""
    var brand = ""
    var quantity: Double = 1
    var unit: PortionUnit = .serving
    var match: ItemMatch?
    var results: [ItemCandidate] = []
    var state: LookupState = .idle
    /// An online error shown under local results.
    var onlineNote: String?
    /// Why the unit changed after matching, e.g. the label has no slice size.
    var unitNote: String?
    var showManual = false
    var manual = Macros()
    /// Filled in by the AI from the meal photo; amounts need a check.
    var fromPhoto = false

    init() {}

    init(logged: LoggedFoodItem) {
        product = logged.name
        brand = logged.brand ?? ""
        quantity = logged.quantity
        unit = logged.unit
        match = ItemMatch(name: logged.name, brand: logged.brand, facts: logged.facts, source: logged.source,
                          detail: logged.source.title)
    }

    var isBlank: Bool { product.trimmingCharacters(in: .whitespaces).isEmpty }
    var isBusy: Bool { [.searching, .loadingDetails, .estimating].contains(state) }

    var macros: Macros? { match.flatMap { PortionMath.macros(quantity, unit, facts: $0.facts) } }

    func logged() -> LoggedFoodItem? {
        guard let match, quantity > 0 else { return nil }
        let typedBrand = brand.trimmingCharacters(in: .whitespaces)
        return LoggedFoodItem(name: match.name, brand: match.brand ?? (typedBrand.isEmpty ? nil : typedBrand),
                              quantity: quantity, unit: unit, facts: match.facts, source: match.source)
    }

    /// Units to offer: what the matched facts support, or common ones before a match.
    var unitChoices: [PortionUnit] {
        var choices: [PortionUnit]
        if let match {
            choices = PortionMath.options(for: match.facts).map(\.unit)
        } else {
            choices = [.serving, .piece("slice"), .piece("piece"), .package, .grams, .ounces]
        }
        if !choices.contains(unit) { choices.insert(unit, at: 0) }
        return choices
    }

    func unitTitle(_ unit: PortionUnit) -> String {
        if let match, let option = PortionMath.options(for: match.facts).first(where: { $0.unit == unit }) {
            if case .serving = unit, let text = match.facts.servingText { return "\(unit.label(quantity: quantity, liquid: match.facts.isLiquid)) (\(text))" }
            if case .package = unit { return option.title.replacingOccurrences(of: "package ·", with: unit.label(quantity: quantity, liquid: false)) }
            return unit.label(quantity: quantity, liquid: match.facts.isLiquid)
        }
        return unit.label(quantity: quantity, liquid: false)
    }

    /// Applies a match and keeps the amount's unit if the label supports it.
    func apply(_ match: ItemMatch) {
        let resolved = PortionMath.resolve(unit, for: match.facts)
        let wasCount = [PortionUnit.serving, .package].contains(unit) || { if case .piece = unit { true } else { false } }()
        let g = match.facts.isLiquid ? "ml" : "grams"
        if wasCount, resolved == .grams || resolved == .ounces {
            // No serving size in this entry: "1 bottle" can't become grams, so ask for the weight instead.
            unitNote = "This entry doesn't list a serving size, so enter the amount in \(g) from the label."
            if quantity < 10 { quantity = 100 }
        } else if resolved != unit, case let .piece(name) = unit {
            unitNote = "The label doesn't give a size for one \(name), so this is in \(resolved.label(quantity: 2, liquid: match.facts.isLiquid))\(match.facts.servingText.map { " (\($0) each)" } ?? ""). Adjust the amount if needed."
        } else {
            unitNote = nil
        }
        unit = resolved
        self.match = match
        results = []
        state = .idle
        showManual = false
    }

    /// Facts from numbers typed for the amount entered ("2 slices = 560 kcal").
    func applyManual() {
        let amount = max(quantity, 0.01)
        let facts: NutritionFacts
        switch unit {
        case .grams: facts = NutritionFacts(per100: manual * (100 / amount))
        case .ounces: facts = NutritionFacts(per100: manual * (100 / (amount * PortionMath.gramsPerOunce)))
        case .package:
            facts = NutritionFacts(perServing: manual * (1 / amount), servingText: "1 package")
            unit = .piece("package")
        default:
            facts = NutritionFacts(perServing: manual * (1 / amount), servingText: "1 \(unit.label(quantity: 1, liquid: false))")
        }
        apply(ItemMatch(name: product.isEmpty ? "Food" : product, brand: brand.isEmpty ? nil : brand, facts: facts,
                        source: .manual, detail: "Entered by you"))
    }
}

struct ItemMatch: Equatable {
    var name: String
    var brand: String?
    var facts: NutritionFacts
    var source: NutritionSource
    /// "Open Food Facts · 130 g per serving"
    var detail: String

    /// One serving as the database has it, to compare with the package: "1 serving (130 g) = 300 kcal · 15 g protein".
    var labelCheck: String? {
        guard let serving = facts.servingMacros else {
            return facts.per100.map { "100 \(facts.isLiquid ? "ml" : "g") = \(Fmt.int($0.kcal)) kcal · \(Fmt.int($0.protein)) g protein" }
        }
        let size = facts.servingText ?? facts.servingGrams.map { "\(Fmt.int($0)) \(facts.isLiquid ? "ml" : "g")" }
        return "1 serving\(size.map { " (\($0))" } ?? "") = \(Fmt.int(serving.kcal)) kcal · \(Fmt.int(serving.protein)) g protein"
    }
}

/// A search result for an item: a food from your list or a product from Open Food Facts.
struct ItemCandidate: Identifiable, Equatable {
    enum Kind: Equatable {
        case library(UUID)
        case product(OpenFoodFacts.Product)
    }

    var id: String
    var kind: Kind
    var name: String
    var subtitle: String
    var facts: NutritionFacts
    var badge: String

    /// "300 kcal / serving" or "231 kcal / 100 g"
    var energyText: String {
        if let serving = facts.servingMacros, facts.servingText != nil || facts.per100 == nil {
            return "\(Fmt.int(serving.kcal)) kcal / serving"
        }
        if let per100 = facts.per100 { return "\(Fmt.int(per100.kcal)) kcal / 100 \(facts.isLiquid ? "ml" : "g")" }
        return ""
    }
}
