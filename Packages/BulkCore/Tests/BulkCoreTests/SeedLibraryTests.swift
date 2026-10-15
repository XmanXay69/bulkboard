import Foundation
import Testing
@testable import BulkCore

@Suite("Built-in seed data")
struct SeedLibraryTests {
    @Test func foodsLoadWithUniqueKeys() throws {
        let foods = try SeedLibrary.foods()
        #expect(foods.count >= 75)
        #expect(Set(foods.map(\.key)).count == foods.count)
        #expect(Set(foods.map { $0.name.lowercased() }).count == foods.count, "Duplicate names would merge in grocery lists")
    }

    @Test func foodCaloriesMatchTheirMacros() throws {
        for food in try SeedLibrary.foods() where food.kcal >= 20 {
            let implied = food.p * 4 + food.c * 4 + food.f * 9
            // Fiber counts as carbs but yields ~2 kcal/g, so produce and snacks run a little under 4/4/9.
            let tolerance = [.produce, .frozen, .snacks].contains(food.section) ? 0.2 : 0.1
            #expect(abs(implied - food.kcal) / food.kcal < tolerance, "\(food.name): \(food.kcal) kcal vs \(implied) from macros")
        }
    }

    @Test func seedsTheEditableWheyScoop() throws {
        let whey = try #require(try SeedLibrary.foods().first { $0.key == "ascent_whey" })
        #expect(whey.custom == true)
        #expect(whey.shaker == true)
        #expect(whey.unit == .scoop)
    }

    @Test func mealsReferenceRealFoods() throws {
        let keys = Set(try SeedLibrary.foods().map(\.key))
        let meals = try SeedLibrary.meals()
        #expect(meals.count >= 35)
        for meal in meals {
            #expect(!meal.items.isEmpty)
            #expect(!meal.slots.isEmpty)
            for item in meal.items { #expect(keys.contains(item.f), "\(meal.name) uses unknown food \(item.f)") }
        }
    }

    @Test func shakesOnlyUseShakerSafeIngredients() throws {
        let foods = Dictionary(uniqueKeysWithValues: try SeedLibrary.foods().map { ($0.key, $0) })
        let shakes = try SeedLibrary.meals().filter { $0.shake == true || $0.slots.contains(.shake) }
        #expect(shakes.count >= 5)
        for shake in shakes {
            for item in shake.items {
                #expect(foods[item.f]?.shaker == true, "\(shake.name): \(item.f) needs a blender")
            }
        }
    }

    @Test func everySlotHasChoices() throws {
        let meals = try SeedLibrary.meals()
        for slot in MealSlot.allCases {
            #expect(meals.filter { $0.slots.contains(slot) }.count >= 5, "Not enough \(slot) options")
        }
    }

    @Test func exerciseLibraryCoversTheSplitGenerator() throws {
        let exercises = try SeedLibrary.exercises()
        let keys = Set(exercises.map(\.key))
        #expect(keys.count == exercises.count)
        #expect(SplitGenerator.allExerciseKeys.isSubset(of: keys), "Missing: \(SplitGenerator.allExerciseKeys.subtracting(keys))")
        let ids = Set(exercises.map(\.id))
        for day in SplitGenerator.generate(liftingDays: 5, courtDays: 2, mode: .bulkPerformance) {
            for exercise in day.exercises { #expect(ids.contains(exercise.exerciseID)) }
        }
    }

    @Test func autoFillWorksWithRealMealsAcrossBodySizes() throws {
        let foods = Dictionary(uniqueKeysWithValues: try SeedLibrary.foods().map { ($0.id, $0.item) })
        let candidates = try SeedLibrary.meals().map { PlannerCandidate(template: $0.template, foods: foods) }
        for kcal in [2400.0, 3200, 4000] {
            let target = Macros(kcal: kcal, protein: kcal * 0.05, carbs: kcal * 0.5 / 4, fat: kcal * 0.27 / 9)
            let days = Array(repeating: DayRequest(target: target, slots: MealSlot.defaultDay), count: 7)
            for plan in MealPlanner.planWeek(days, candidates: candidates, seed: 11) {
                #expect(abs(plan.totals.kcal - kcal) / kcal < 0.06, "\(kcal) kcal day landed at \(plan.totals.kcal)")
                #expect(plan.totals.protein >= target.protein * 0.9)
            }
        }
    }
}
