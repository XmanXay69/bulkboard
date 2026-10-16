import Foundation

/// Where an item's nutrition numbers came from.
public enum NutritionSource: Codable, Hashable, Sendable {
    /// A product in the Open Food Facts database, by barcode.
    case openFoodFacts(code: String)
    /// A food in the user's library (built-in or their own).
    case library(foodID: UUID)
    /// Estimated by a local AI model.
    case aiEstimate(model: String)
    /// Typed in by the user.
    case manual

    public var title: String {
        switch self {
        case .openFoodFacts: "Open Food Facts"
        case .library: "Food list"
        case .aiEstimate: "AI estimate"
        case .manual: "Entered by you"
        }
    }

    public var isEstimate: Bool {
        if case .aiEstimate = self { return true }
        return false
    }
}

/// One thing in a logged meal: what it is, how much, and the facts its macros come from.
public struct LoggedFoodItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var brand: String?
    public var quantity: Double
    public var unit: PortionUnit
    public var facts: NutritionFacts
    public var source: NutritionSource
    /// Snapshot of the totals for this amount, so history doesn't shift if the math is ever revised.
    public var macros: Macros

    public init(id: UUID = UUID(), name: String, brand: String? = nil, quantity: Double, unit: PortionUnit,
                facts: NutritionFacts, source: NutritionSource) {
        self.id = id
        self.name = name
        self.brand = brand
        self.quantity = quantity
        self.unit = unit
        self.facts = facts
        self.source = source
        macros = PortionMath.macros(quantity, unit, facts: facts) ?? .zero
    }

    /// "DiGiorno Rising Crust Pepperoni Pizza"
    public var displayName: String {
        guard let brand, !brand.isEmpty, !name.localizedCaseInsensitiveContains(brand) else { return name }
        return "\(brand) \(name)"
    }

    /// "2 servings (260 g)"
    public var amountText: String { PortionMath.describe(quantity, unit, facts: facts) }

    /// Label servings this amount equals, for saving the item as a recipe ingredient.
    public var servingsEquivalent: Double { PortionMath.servings(quantity, unit, facts: facts) ?? quantity }
}

public extension FoodItem {
    /// The food's serving as nutrition facts, so library foods log with the same portion math as products.
    var nutritionFacts: NutritionFacts {
        let grams: Double? = switch servingUnit.dimension {
        case .mass, .volume: servingAmount * servingUnit.toBase
        case .count: nil
        }
        return NutritionFacts(perServing: macros, servingGrams: grams, servingText: servingLabel,
                              isLiquid: servingUnit.dimension == .volume)
    }
}

public extension NutritionFacts {
    /// A food-list entry for these facts: one label serving (or 100 g when there's no serving).
    func foodItem(id: UUID = UUID(), name: String, brand: String?, section: StoreSection = .other) -> FoodItem {
        let g = isLiquid ? GroceryUnit.ml : .g
        if let serving = servingMacros {
            let label = servingText ?? servingGrams.map { "\(Fmt.number($0)) \(g.label)" } ?? "1 serving"
            return FoodItem(id: id, name: name, brand: brand, servingLabel: label,
                            servingAmount: servingGrams ?? 1, servingUnit: servingGrams == nil ? .serving : g,
                            macros: serving, section: section)
        }
        return FoodItem(id: id, name: name, brand: brand, servingLabel: "100 \(g.label)", servingAmount: 100,
                        servingUnit: g, macros: per100 ?? .zero, section: section)
    }
}
