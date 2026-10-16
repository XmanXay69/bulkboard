import BulkCore
import Foundation
import SwiftData
import Testing
@testable import BulkBoard

@Suite("Meal planning flows")
@MainActor
struct MealFlowTests {
    @Test func seedingIsIdempotent() throws {
        let context = try makeContext()
        SeedService.ensureBuiltIns(context)
        let counts = (context.fetchAll(FoodRecord.self).count, context.fetchAll(RecipeRecord.self).count,
                      context.fetchAll(ExerciseRecord.self).count)
        SeedService.ensureBuiltIns(context)
        #expect(counts.0 >= 75 && counts.1 >= 35 && counts.2 >= 45)
        #expect(context.fetchAll(FoodRecord.self).count == counts.0)
        #expect(context.fetchAll(RecipeRecord.self).count == counts.1)
        #expect(context.fetchAll(ExerciseRecord.self).count == counts.2)
        let whey = try #require(context.fetchAll(FoodRecord.self).first { $0.seedKey == "ascent_whey" })
        #expect(!whey.isBuiltIn) // lives in "My foods" so it's clearly editable
    }

    @Test func onboardingLeavesMealsToYouAndSuggestionsHitTargets() throws {
        let context = try makeContext()
        let profile = onboard(context)
        #expect(MealPlanActions.entries(weekOf: .now, context: context).isEmpty, "No meals appear until you ask for suggestions")
        #expect(context.fetchAll(IntakeRecord.self).isEmpty)
        suggestWeek(context)
        let entries = MealPlanActions.entries(weekOf: .now, context: context)
        #expect(entries.count == 7 * profile.mealSlots.count)

        let library = MealLibrary(context)
        let snapshot = profile.targets(latestWeightKg: context.latestWeightKg)
        for day in WeekMath.days(ofWeekStarting: Date.now.weekStart) {
            let total = entries.filter { $0.day == day }.map(library.macros(for:)).sum()
            let target = snapshot.target(for: TrainingActions.dayType(for: day, plan: context.workoutPlan))
            #expect(abs(total.kcal - target.kcal) / target.kcal < 0.08)
            #expect(total.protein >= target.protein * 0.9)
        }
    }

    @Test func shuffleKeepsLockedAndEatenMeals() throws {
        let context = try makeContext()
        onboard(context)
        suggestWeek(context)
        let library = MealLibrary(context)
        let entries = MealPlanActions.entries(weekOf: .now, context: context).sorted { ($0.day, $0.slotIndex) < ($1.day, $1.slotIndex) }
        let locked = entries[0]
        locked.isLocked = true
        let eaten = entries[1]
        MealLogActions.toggleSuggestion(eaten, library: library, context: context)
        let lockedID = locked.id, lockedMeal = locked.recipeID, eatenID = eaten.id

        for seed in 1...4 { MealPlanActions.autoFill(weekOf: .now, context: context, seed: UInt64(seed)) }

        let after = MealPlanActions.entries(weekOf: .now, context: context)
        #expect(after.contains { $0.id == lockedID && $0.recipeID == lockedMeal })
        #expect(after.contains { $0.id == eatenID })
        #expect(after.count == 7 * 5)
    }

    @Test func assignReplacesSlot() throws {
        let context = try makeContext()
        onboard(context)
        let day = Date.now.dayStart
        let shake = SeedLibrary.mealID("classic_bulk_shake")
        MealPlanActions.assign(recipeID: shake, day: day, slotIndex: 4, slot: .shake, servings: 1.5, context: context)
        let slot = MealPlanActions.entries(weekOf: day, context: context).filter { $0.day == day && $0.slotIndex == 4 }
        #expect(slot.count == 1)
        #expect(slot.first?.recipeID == shake)
        #expect(slot.first?.servings == 1.5)

        let banana = SeedLibrary.foodID("banana")
        MealPlanActions.assign(foodID: banana, day: day, slotIndex: 4, slot: .shake, context: context)
        let replaced = MealPlanActions.entries(weekOf: day, context: context).first { $0.day == day && $0.slotIndex == 4 }
        #expect(replaced?.foodID == banana)
        #expect(replaced?.recipeID == nil)
    }

    @Test func eatingLogsAndUnlogsIntake() throws {
        let context = try makeContext()
        onboard(context)
        suggestWeek(context)
        let library = MealLibrary(context)
        let entry = try #require(MealPlanActions.entries(weekOf: .now, context: context).first)
        MealLogActions.toggleSuggestion(entry, library: library, context: context)
        let logged = try #require(context.fetchAll(IntakeRecord.self).first)
        #expect(abs(logged.macros.kcal - library.macros(for: entry).kcal) < 0.5)
        #expect(logged.planEntryID == entry.id)
        #expect(!logged.items.isEmpty, "Suggestions log with their ingredients as items")
        MealLogActions.toggleSuggestion(entry, library: library, context: context)
        #expect(context.fetchAll(IntakeRecord.self).isEmpty)
    }

    @Test func autoFillRespectsAllergies() throws {
        let context = try makeContext()
        onboard(context) { $0.allergens = [.peanut, .dairy] }
        suggestWeek(context)
        let library = MealLibrary(context)
        for entry in MealPlanActions.entries(weekOf: .now, context: context) {
            let template = try #require(library.templates[entry.recipeID!])
            let allergens = template.ingredients.compactMap { library.foods[$0.foodID] }.flatMap(\.allergens)
            #expect(!allergens.contains(.peanut) && !allergens.contains(.dairy), "\(template.name)")
        }
    }
}

@Suite("Grocery list flows")
@MainActor
struct GroceryFlowTests {
    @Test func generatesMergedListFromThePlan() throws {
        let context = try makeContext()
        onboard(context)
        suggestWeek(context)
        GroceryActions.generate(weekOf: .now, context: context)
        let items = context.fetchAll(GroceryItemRecord.self)
        #expect(items.count >= 10)
        #expect(Set(items.map { $0.name.lowercased() }).count == items.count, "Each food appears once")
        #expect(items.allSatisfy { !$0.amountText.isEmpty })
        #expect(items.allSatisfy { !$0.isManual })
    }

    @Test func regeneratingKeepsManualItemsAndChecks() throws {
        let context = try makeContext()
        onboard(context)
        suggestWeek(context)
        GroceryActions.generate(weekOf: .now, context: context)
        GroceryActions.addManual(name: "Paper towels", amount: "1 pack", section: .other, context: context)
        let first = try #require(context.fetchAll(GroceryItemRecord.self).first { !$0.isManual })
        first.isChecked = true
        let checkedName = first.name

        GroceryActions.generate(weekOf: .now, context: context)
        let items = context.fetchAll(GroceryItemRecord.self)
        #expect(items.contains { $0.isManual && $0.name == "Paper towels" })
        #expect(items.first { $0.name == checkedName }?.isChecked == true)
        #expect(items.filter { $0.name == "Paper towels" }.count == 1)
    }

    @Test func plainTextGroupsByAisle() throws {
        let context = try makeContext()
        onboard(context)
        suggestWeek(context)
        GroceryActions.generate(weekOf: .now, context: context)
        let text = GroceryActions.plainText(context.fetchAll(GroceryItemRecord.self), weekStart: Date.now.weekStart)
        #expect(text.hasPrefix("BulkBoard groceries · week of"))
        #expect(text.contains("DAIRY & EGGS"))
        #expect(text.contains("[ ] "))
    }

    @Test func clearCheckedRemovesOnlyChecked() throws {
        let context = try makeContext()
        onboard(context)
        suggestWeek(context)
        GroceryActions.generate(weekOf: .now, context: context)
        let total = context.fetchAll(GroceryItemRecord.self).count
        context.fetchAll(GroceryItemRecord.self).prefix(3).forEach { $0.isChecked = true }
        GroceryActions.clearChecked(context: context)
        #expect(context.fetchAll(GroceryItemRecord.self).count == total - 3)
    }
}
