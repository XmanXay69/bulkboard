import BulkCore
import Foundation

/// Finds nutrition for a typed item: your food list first (instant), then Open Food Facts online.
enum ItemLookup {
    static func search(_ item: ItemDraft, library: MealLibrary) async {
        let product = item.product.trimmingCharacters(in: .whitespaces)
        guard !product.isEmpty else { return }
        item.state = .searching
        item.onlineNote = nil
        item.match = nil
        let local = library.searchFoods(product, brand: item.brand).prefix(4).map { food in
            ItemCandidate(id: "food:\(food.id)", kind: .library(food.id), name: food.name,
                          subtitle: [food.brand, food.servingLabel].compactMap { $0 }.joined(separator: " · "),
                          facts: food.item.nutritionFacts, badge: food.isBuiltIn ? "Food list" : "Your food")
        }
        item.results = Array(local)

        let lookup = NutritionLookup.shared
        guard lookup.isEnabled else {
            item.state = item.results.isEmpty ? .failed("Nothing in your food list matches. Turn on online lookup in Settings, estimate it, or enter the numbers.") : .idle
            return
        }
        do {
            let products = try await lookup.search(product: product, brand: item.brand)
            let online = products.compactMap { p -> ItemCandidate? in
                guard let facts = OpenFoodFacts.facts(for: p) else { return nil }
                return ItemCandidate(id: "off:\(p.code)", kind: .product(p), name: p.name, subtitle: p.subtitle,
                                     facts: facts, badge: "Open Food Facts")
            }
            item.results += online
            item.state = item.results.isEmpty ? .failed("No matches. Try fewer words, check the brand, or estimate it.") : .idle
            // A barcode is exact: take it straight away.
            if OpenFoodFacts.isBarcode(product), online.count == 1 { await choose(online[0], for: item, library: library) }
        } catch {
            item.onlineNote = error.localizedDescription
            item.state = item.results.isEmpty ? .failed(error.localizedDescription) : .idle
        }
    }

    static func choose(_ candidate: ItemCandidate, for item: ItemDraft, library: MealLibrary) async {
        switch candidate.kind {
        case let .library(id):
            guard let food = library.foodRecords[id] else { return }
            item.apply(ItemMatch(name: food.name, brand: food.brand, facts: candidate.facts,
                                 source: food.isAIEstimate ? .aiEstimate(model: "saved estimate") : .library(foodID: id),
                                 detail: "\(food.isBuiltIn ? "Food list" : "Your food") · \(food.servingLabel)"))
        case let .product(product):
            item.state = .loadingDetails
            // Search results lack serving and package sizes; fetch the full product.
            let detailed = (try? await NutritionLookup.shared.product(code: product.code)) ?? nil
            let best = detailed ?? product
            let facts = OpenFoodFacts.facts(for: best) ?? candidate.facts
            var detail = "Open Food Facts"
            if let serving = best.servingSize { detail += " · \(serving) per serving" }
            if let quantity = best.quantity { detail += " · \(quantity) package" }
            item.apply(ItemMatch(name: best.name.isEmpty ? candidate.name : best.name, brand: best.brand,
                                 facts: facts, source: .openFoodFacts(code: product.code), detail: detail))
        }
        if item.brand.isEmpty, let brand = item.match?.brand { item.brand = brand }
    }

    /// Asks the local model for one unit of the item, so the amount can scale it.
    static func estimate(_ item: ItemDraft) async {
        let client = OllamaClient.shared
        item.state = .estimating
        let unitText: String = switch item.unit {
        case .grams, .ounces: "100 g"
        default: "1 \(item.unit.label(quantity: 1, liquid: false))"
        }
        do {
            let estimate = try await client.estimateItem(product: item.product, brand: item.brand, unit: unitText)
            let facts: NutritionFacts = unitText == "100 g"
                ? NutritionFacts(per100: estimate.macros)
                : NutritionFacts(perServing: estimate.macros, servingText: unitText == "1 serving" ? estimate.serving : unitText)
            if case .package = item.unit { item.unit = .piece("package") }
            item.apply(ItemMatch(name: item.product, brand: item.brand.isEmpty ? nil : item.brand, facts: facts,
                                 source: .aiEstimate(model: client.model), detail: "AI estimate for \(unitText) · check a label when you can"))
        } catch {
            item.state = .failed(error.localizedDescription)
        }
    }

    /// Fills items from what the vision model sees in the photo, then looks each one up.
    static func fillFromPhoto(_ draft: MealDraft, library: MealLibrary) async {
        guard let photo = draft.photo else { return }
        draft.isReadingPhoto = true
        draft.photoMessage = nil
        defer { draft.isReadingPhoto = false }
        do {
            let guesses = try await OllamaClient.shared.identifyMeal(photo: photo)
            guard !guesses.isEmpty else {
                draft.photoMessage = "Couldn't make out any food. Add the items yourself."
                return
            }
            draft.removeBlankItems()
            let known = Set(draft.items.map { $0.product.lowercased() })
            let added = guesses.filter { !known.contains($0.name.lowercased()) }.map { guess -> ItemDraft in
                let item = ItemDraft()
                item.product = guess.name
                item.brand = guess.brand
                item.quantity = guess.amount > 0 ? guess.amount : 1
                item.unit = PortionUnit.parse(guess.unit)
                item.fromPhoto = true
                return item
            }
            draft.items += added
            draft.photoMessage = "AI guessed \(added.count) item\(added.count == 1 ? "" : "s"). Check brands and amounts before logging."
            for item in added { await search(item, library: library) }
        } catch {
            draft.photoMessage = error.localizedDescription
        }
    }

    /// Looks for barcodes in a new photo, so a package shot can be looked up exactly.
    static func scanBarcodes(_ draft: MealDraft) async {
        guard let photo = draft.photo, photo != draft.scannedPhoto else { return }
        draft.scannedPhoto = photo
        draft.barcodes = await BarcodeReader.codes(in: photo)
    }

    static func lookUpBarcode(_ code: String, in draft: MealDraft, library: MealLibrary) async {
        let item = draft.items.first { $0.isBlank && $0.match == nil } ?? {
            let item = ItemDraft()
            draft.items.append(item)
            return item
        }()
        item.product = code
        draft.barcodes.removeAll { $0 == code }
        await search(item, library: library)
    }
}

extension MealLibrary {
    /// Foods whose name (and brand) share words with the query, your own foods first.
    func searchFoods(_ text: String, brand: String = "") -> [FoodRecord] {
        let query = Self.words(text + " " + brand)
        guard !query.isEmpty else { return [] }
        let needed = max(1, Int((Double(query.count) / 2).rounded(.up)))
        return foodRecords.values.filter { !$0.isArchived }.compactMap { food -> (FoodRecord, Int)? in
            let words = Self.words(food.name + " " + (food.brand ?? ""))
            let hits = query.filter { q in words.contains { $0 == q || ($0.count >= 3 && q.count >= 3 && ($0.hasPrefix(q) || q.hasPrefix($0))) } }.count
            return hits >= needed ? (food, hits) : nil
        }
        .sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            if a.0.isBuiltIn != b.0.isBuiltIn { return !a.0.isBuiltIn }
            return a.0.name < b.0.name
        }
        .map(\.0)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 1 }
    }
}
