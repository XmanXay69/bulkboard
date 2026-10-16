import BulkCore
import Foundation
import SwiftData

/// Logging what you actually ate: your own meals (with items, amounts and an optional photo),
/// saved meals, and suggestions you decided to eat.
enum MealLogActions {
    enum PhotoChange {
        case keep
        case replace(Data)
        case remove
    }

    /// Logs a meal you put together. Totals are summed from the items and snapshotted.
    @discardableResult
    static func log(name: String, items: [LoggedFoodItem], slot: MealSlot, day: Date, photo: Data?, notes: String = "",
                    recipeID: UUID? = nil, planEntryID: UUID? = nil, context: ModelContext) throws -> IntakeRecord {
        let record = IntakeRecord(day: day.dayStart, name: mealName(name, items: items))
        record.slot = slot
        record.items = items
        record.macros = items.map(\.macros).sum()
        record.notes = notes
        record.recipeID = recipeID
        record.planEntryID = planEntryID
        if let photo { record.photoFilename = try PhotoStore.save(photo) }
        context.insert(record)
        try context.save()
        return record
    }

    static func update(_ record: IntakeRecord, name: String, items: [LoggedFoodItem], slot: MealSlot, day: Date,
                       photo: PhotoChange, notes: String, context: ModelContext) throws {
        switch photo {
        case .keep: break
        case let .replace(data):
            let filename = try PhotoStore.save(data)
            if let old = record.photoFilename { PhotoStore.delete(old) }
            record.photoFilename = filename
        case .remove:
            if let old = record.photoFilename { PhotoStore.delete(old) }
            record.photoFilename = nil
        }
        record.name = mealName(name, items: items)
        record.items = items
        record.macros = items.map(\.macros).sum()
        record.slot = slot
        record.day = day.dayStart
        record.notes = notes
        try context.save()
    }

    static func delete(_ record: IntakeRecord, context: ModelContext) {
        if let photo = record.photoFilename { PhotoStore.delete(photo) }
        context.delete(record)
        try? context.save()
    }

    /// Logs the same meal again on another day (photo not copied).
    @discardableResult
    static func duplicate(_ record: IntakeRecord, to day: Date, context: ModelContext) -> IntakeRecord {
        let copy = IntakeRecord(day: day.dayStart, name: record.name)
        copy.slot = record.slot
        copy.itemsData = record.itemsData
        copy.macros = record.macros
        copy.recipeID = record.recipeID
        context.insert(copy)
        try? context.save()
        return copy
    }

    // MARK: Saved meals

    /// One item per ingredient, scaled to the servings eaten.
    static func items(forRecipe recipeID: UUID, servings: Double, library: MealLibrary) -> [LoggedFoodItem] {
        guard let template = library.templates[recipeID] else { return [] }
        return template.ingredients.compactMap { ingredient in
            guard let record = library.foodRecords[ingredient.foodID] else { return nil }
            return item(forFood: record, servings: ingredient.servings * servings)
        }
    }

    static func item(forFood food: FoodRecord, servings: Double) -> LoggedFoodItem {
        let item = food.item
        let source: NutritionSource = food.isAIEstimate ? .aiEstimate(model: "saved estimate") : .library(foodID: food.id)
        return LoggedFoodItem(name: item.name, brand: item.brand, quantity: servings, unit: .serving,
                              facts: item.nutritionFacts, source: source)
    }

    @discardableResult
    static func log(recipe: RecipeRecord, servings: Double, slot: MealSlot, day: Date, photo: Data? = nil,
                    library: MealLibrary, context: ModelContext) throws -> IntakeRecord {
        let name = servings == 1 ? recipe.name : "\(recipe.name) ×\(Fmt.number(servings, maxDecimals: 2))"
        return try log(name: name, items: items(forRecipe: recipe.id, servings: servings, library: library), slot: slot,
                       day: day, photo: photo, recipeID: recipe.id, context: context)
    }

    /// Saves the items to your food list and creates a reusable meal from them. Products you've saved
    /// before (same barcode) are reused, so your food list doesn't fill with duplicates.
    @discardableResult
    static func saveAsMeal(name: String, items: [LoggedFoodItem], slot: MealSlot, context: ModelContext) -> RecipeRecord {
        var ingredients: [Ingredient] = []
        let foods = context.fetchAll(FoodRecord.self)
        for item in items where item.macros.kcal > 0 || item.macros.protein > 0 {
            let food: FoodRecord
            let existing: FoodRecord? = switch item.source {
            case let .library(foodID): foods.first(where: { $0.id == foodID })
            case let .openFoodFacts(code): foods.first(where: { $0.seedKey == "off:\(code)" })
            default: nil
            }
            if let existing {
                food = existing
            } else {
                food = FoodRecord(name: item.name)
                food.apply(item.facts.foodItem(id: food.id, name: item.name, brand: item.brand))
                if case let .openFoodFacts(code) = item.source { food.seedKey = "off:\(code)" }
                food.isAIEstimate = item.source.isEstimate
                context.insert(food)
            }
            let perServing = food.macros
            let servings = perServing.kcal > 0 ? item.macros.kcal / perServing.kcal
                : perServing.protein > 0 ? item.macros.protein / perServing.protein : item.servingsEquivalent
            ingredients.append(Ingredient(foodID: food.id, servings: servings))
        }
        let recipe = RecipeRecord(name: mealName(name, items: items))
        recipe.slots = [slot]
        recipe.ingredients = ingredients
        recipe.isShake = slot == .shake
        recipe.isFavorite = true
        context.insert(recipe)
        try? context.save()
        return recipe
    }

    // MARK: Suggestions

    static func intake(for entry: PlanEntryRecord, in intake: [IntakeRecord]) -> IntakeRecord? {
        intake.first { $0.planEntryID == entry.id }
    }

    /// Logs a suggested meal as eaten (with its ingredients as items), or un-logs it.
    static func toggleSuggestion(_ entry: PlanEntryRecord, library: MealLibrary, context: ModelContext) {
        let entryID = entry.id
        let descriptor = FetchDescriptor<IntakeRecord>(predicate: #Predicate { $0.planEntryID == entryID })
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            existing.forEach { delete($0, context: context) }
            return
        }
        let items: [LoggedFoodItem]
        if let recipeID = entry.recipeID {
            items = self.items(forRecipe: recipeID, servings: entry.servings, library: library)
        } else if let foodID = entry.foodID, let food = library.foodRecords[foodID] {
            items = [item(forFood: food, servings: entry.servings)]
        } else {
            items = []
        }
        let record = IntakeRecord(day: entry.day, name: library.name(for: entry))
        record.slotRaw = entry.slotRaw
        record.items = items
        record.macros = items.isEmpty ? library.macros(for: entry) : items.map(\.macros).sum()
        record.planEntryID = entry.id
        record.recipeID = entry.recipeID
        context.insert(record)
        try? context.save()
    }

    // MARK: Helpers

    /// The name you typed, or the items joined: "Pepperoni Pizza + Coke".
    static func mealName(_ typed: String, items: [LoggedFoodItem]) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let names = items.map(\.name).filter { !$0.isEmpty }
        switch names.count {
        case 0: return "Meal"
        case 1...3: return names.joined(separator: " + ")
        default: return names.prefix(2).joined(separator: " + ") + " + \(names.count - 2) more"
        }
    }

    /// The slot that fits the time of day.
    static func defaultSlot(at date: Date = .now) -> MealSlot {
        let minutes = Calendar.bulk.component(.hour, from: date) * 60 + Calendar.bulk.component(.minute, from: date)
        switch minutes {
        case ..<630: return .breakfast
        case ..<870: return .lunch
        case ..<1020: return .snack
        case ..<1290: return .dinner
        default: return .snack
        }
    }
}
