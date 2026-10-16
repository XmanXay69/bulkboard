import AppKit
import BulkCore
import Foundation
import SwiftData
import Testing
@testable import BulkBoard

@Suite("Logging your own meals")
@MainActor
struct MealLogTests {
    static let pizza = NutritionFacts(per100: Macros(kcal: 230.8, protein: 11.5, carbs: 28.5, fat: 8.5),
                                      perServing: Macros(kcal: 300, protein: 15, carbs: 37, fat: 11),
                                      servingGrams: 130, servingText: "1/6 pizza (130 g)", packageGrams: 780)

    static func pizzaItem(_ servings: Double = 2) -> LoggedFoodItem {
        LoggedFoodItem(name: "Rising Crust Pepperoni Pizza", brand: "DiGiorno", quantity: servings, unit: .serving,
                       facts: pizza, source: .openFoodFacts(code: "0071921962395"))
    }

    static func photo() -> Data {
        let image = NSImage(size: NSSize(width: 64, height: 48))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 48).fill()
        image.unlockFocus()
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }

    @Test func logsItemsTotalsAndAPhoto() throws {
        let context = try makeContext()
        onboard(context)
        let soda = LoggedFoodItem(name: "Coke", quantity: 1, unit: .piece("can"),
                                  facts: NutritionFacts(perServing: Macros(kcal: 140, carbs: 39), servingText: "1 can (355 ml)", isLiquid: true),
                                  source: .manual)
        let record = try MealLogActions.log(name: "", items: [Self.pizzaItem(), soda], slot: .lunch, day: .now,
                                            photo: Self.photo(), context: context)
        #expect(record.name == "Rising Crust Pepperoni Pizza + Coke", "Unnamed meals are named after their items")
        #expect(record.macros == Macros(kcal: 740, protein: 30, carbs: 113, fat: 22))
        #expect(record.items.count == 2)
        let photo = try #require(record.photoFilename)
        #expect(FileManager.default.fileExists(atPath: PhotoStore.url(for: photo).path))
        #expect(MealPlanActions.entries(weekOf: .now, context: context).isEmpty, "Logging never creates suggestions")

        MealLogActions.delete(record, context: context)
        #expect(context.fetchAll(IntakeRecord.self).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: PhotoStore.url(for: photo).path), "Deleting a meal deletes its photo")
    }

    @Test func editingChangesAmountsAndPhoto() throws {
        let context = try makeContext()
        onboard(context)
        let record = try MealLogActions.log(name: "Pizza", items: [Self.pizzaItem()], slot: .dinner, day: .now,
                                            photo: Self.photo(), context: context)
        let firstPhoto = try #require(record.photoFilename)
        try MealLogActions.update(record, name: "Pizza", items: [Self.pizzaItem(3)], slot: .dinner, day: .now,
                                  photo: .replace(Self.photo()), notes: "Post-game", context: context)
        #expect(record.kcal == 900)
        #expect(record.notes == "Post-game")
        #expect(record.photoFilename != firstPhoto)
        #expect(!FileManager.default.fileExists(atPath: PhotoStore.url(for: firstPhoto).path))
        try MealLogActions.update(record, name: "Pizza", items: record.items, slot: .dinner, day: .now, photo: .remove,
                                  notes: "", context: context)
        #expect(record.photoFilename == nil)
    }

    @Test func savingAsAMealReusesProductsByBarcode() throws {
        let context = try makeContext()
        onboard(context)
        let foodsBefore = context.fetchAll(FoodRecord.self).count
        let recipe = MealLogActions.saveAsMeal(name: "Pizza night", items: [Self.pizzaItem()], slot: .dinner, context: context)
        _ = MealLogActions.saveAsMeal(name: "Pizza again", items: [Self.pizzaItem(1)], slot: .dinner, context: context)
        #expect(context.fetchAll(FoodRecord.self).count == foodsBefore + 1, "The same barcode becomes one food")
        let food = try #require(context.fetchAll(FoodRecord.self).first { $0.seedKey == "off:0071921962395" })
        #expect(food.brand == "DiGiorno")
        #expect(food.servingLabel == "1/6 pizza (130 g)")

        let library = MealLibrary(context)
        #expect(abs(library.perServing(recipeID: recipe.id).kcal - 600) < 0.01)
        #expect(recipe.slots == [.dinner])
        #expect(library.candidates.contains { $0.id == recipe.id }, "Saved meals feed Suggested")

        let logged = try MealLogActions.log(recipe: recipe, servings: 0.5, slot: .dinner, day: .now, library: library, context: context)
        #expect(abs(logged.kcal - 300) < 0.01)
        #expect(logged.recipeID == recipe.id)
        #expect(logged.items.first?.source == .library(foodID: food.id))
    }

    @Test func duplicateLogsAgainWithoutThePhoto() throws {
        let context = try makeContext()
        onboard(context)
        let record = try MealLogActions.log(name: "Pizza", items: [Self.pizzaItem()], slot: .lunch, day: .now.adding(days: -1),
                                            photo: Self.photo(), context: context)
        let copy = MealLogActions.duplicate(record, to: .now, context: context)
        #expect(copy.day == Date.now.dayStart)
        #expect(copy.items == record.items)
        #expect(copy.photoFilename == nil)
    }

    @Test func searchFindsYourFoodsFirst() throws {
        let context = try makeContext()
        onboard(context)
        let mine = FoodRecord(name: "Chicken Breast Strips")
        mine.brand = "Kirkland Signature"
        context.insert(mine)
        try context.save()
        let results = MealLibrary(context).searchFoods("chicken breast", brand: "")
        #expect(results.first?.name == "Chicken Breast Strips")
        #expect(results.contains { $0.isBuiltIn })
        #expect(MealLibrary(context).searchFoods("zzzz").isEmpty)
    }

    @Test func draftsMatchUnitsAndFallBack() {
        let item = ItemDraft()
        item.product = "pizza"
        item.quantity = 2
        item.unit = .piece("slice")
        item.apply(ItemMatch(name: "Pizza", brand: nil, facts: Self.pizza, source: .openFoodFacts(code: "1"), detail: ""))
        #expect(item.unit == .piece("pizza"), "Falls back to the label's own piece")
        #expect(item.unitNote != nil, "And says why")

        let manual = ItemDraft()
        manual.product = "Mom's chili"
        manual.quantity = 2
        manual.unit = .piece("bowl")
        manual.manual = Macros(kcal: 900, protein: 60, carbs: 70, fat: 40)
        manual.applyManual()
        #expect(manual.macros?.kcal == 900, "Typed numbers are for the amount entered")
        manual.quantity = 3
        #expect(manual.macros?.kcal == 1350)
    }

    @Test func suggestionsDontCountUntilLogged() throws {
        let context = try makeContext()
        onboard(context)
        suggestWeek(context)
        let today = Date.now.dayStart
        #expect(context.fetchAll(IntakeRecord.self).filter { $0.day == today }.isEmpty)
        let entry = try #require(MealPlanActions.entries(weekOf: today, context: context).first { $0.day == today })
        MealLogActions.toggleSuggestion(entry, library: MealLibrary(context), context: context)
        #expect(context.fetchAll(IntakeRecord.self).filter { $0.day == today }.count == 1)
    }

    @Test func defaultSlotFollowsTheClock() {
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            Calendar.bulk.date(bySettingHour: hour, minute: minute, second: 0, of: .now)!
        }
        #expect(MealLogActions.defaultSlot(at: at(8)) == .breakfast)
        #expect(MealLogActions.defaultSlot(at: at(12, 30)) == .lunch)
        #expect(MealLogActions.defaultSlot(at: at(15)) == .snack)
        #expect(MealLogActions.defaultSlot(at: at(19)) == .dinner)
        #expect(MealLogActions.defaultSlot(at: at(23)) == .snack)
    }
}
