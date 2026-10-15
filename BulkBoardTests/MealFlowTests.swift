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

    @Test func onboardingAutoFillsTheWeekOnTarget() throws {
        let context = try makeContext()
        let profile = onboard(context)
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
        let library = MealLibrary(context)
        let entries = MealPlanActions.entries(weekOf: .now, context: context).sorted { ($0.day, $0.slotIndex) < ($1.day, $1.slotIndex) }
        let locked = entries[0]
        locked.isLocked = true
        let eaten = entries[1]
        IntakeActions.toggleEaten(eaten, library: library, context: context)
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
        let library = MealLibrary(context)
        let entry = try #require(MealPlanActions.entries(weekOf: .now, context: context).first)
        IntakeActions.toggleEaten(entry, library: library, context: context)
        let logged = try #require(context.fetchAll(IntakeRecord.self).first)
        #expect(logged.macros == library.macros(for: entry))
        #expect(logged.planEntryID == entry.id)
        IntakeActions.toggleEaten(entry, library: library, context: context)
        #expect(context.fetchAll(IntakeRecord.self).isEmpty)
    }

    @Test func autoFillRespectsAllergies() throws {
        let context = try makeContext()
        onboard(context) { $0.allergens = [.peanut, .dairy] }
        let library = MealLibrary(context)
        for entry in MealPlanActions.entries(weekOf: .now, context: context) {
            let template = try #require(library.templates[entry.recipeID!])
            let allergens = template.ingredients.compactMap { library.foods[$0.foodID] }.flatMap(\.allergens)
            #expect(!allergens.contains(.peanut) && !allergens.contains(.dairy), "\(template.name)")
        }
    }
}
