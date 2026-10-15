import Foundation
import Testing
@testable import BulkCore

@Suite("Meal planner")
struct MealPlannerTests {
    static func meal(_ name: String, _ slot: MealSlot, _ kcal: Double, _ p: Double, _ c: Double, _ f: Double,
                     allergens: Set<Allergen> = []) -> PlannerCandidate {
        PlannerCandidate(id: StableID.uuid("test", name), name: name, slots: [slot],
                         macros: Macros(kcal: kcal, protein: p, carbs: c, fat: f), allergens: allergens)
    }

    let candidates: [PlannerCandidate] = [
        meal("Egg Stack", .breakfast, 700, 40, 80, 22),
        meal("PB Oats", .breakfast, 650, 25, 90, 20, allergens: [.peanut]),
        meal("Bagel + Eggs", .breakfast, 800, 45, 85, 30),
        meal("Chicken Rice Bowl", .lunch, 750, 55, 80, 20),
        meal("Turkey Club", .lunch, 700, 50, 75, 18),
        meal("Beef Burrito Bowl", .lunch, 850, 45, 100, 28),
        meal("Salmon Rice Plate", .dinner, 900, 60, 90, 30),
        meal("Pasta Bolognese", .dinner, 800, 55, 85, 25),
        meal("Steak + Potatoes", .dinner, 950, 50, 110, 30),
        meal("Trail Mix", .snack, 300, 10, 40, 12, allergens: [.treeNut]),
        meal("Greek Yogurt Cup", .snack, 250, 20, 25, 8),
        meal("Classic Bulk Shake", .shake, 540, 66, 30, 20),
        meal("Chocolate Gainer", .shake, 680, 64, 75, 13),
    ]

    let target = Macros(kcal: 3200, protein: 180, carbs: 400, fat: 90)

    func week(locked: [Int: PlannedMeal] = [:]) -> [DayRequest] {
        Array(repeating: DayRequest(target: target, slots: MealSlot.defaultDay, locked: locked), count: 7)
    }

    @Test func autoFillHitsTargets() {
        let plans = MealPlanner.planWeek(week(), candidates: candidates, seed: 42)
        #expect(plans.count == 7)
        for plan in plans {
            #expect(abs(plan.totals.kcal - target.kcal) / target.kcal < 0.05)
            #expect(plan.totals.protein >= target.protein * 0.95)
            #expect(plan.meals.allSatisfy { $0 != nil })
        }
    }

    @Test func fillsEachSlotWithAMatchingMeal() {
        let plans = MealPlanner.planWeek(week(), candidates: candidates, seed: 7)
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        for plan in plans {
            for (index, slot) in MealSlot.defaultDay.enumerated() {
                #expect(byID[plan.meals[index]!.candidateID]!.slots.contains(slot))
            }
        }
    }

    @Test func lockedMealsStayPut() {
        let locked = PlannedMeal(candidateID: candidates[2].id, servings: 1.5)
        let plans = MealPlanner.planWeek(week(locked: [0: locked]), candidates: candidates, seed: 1)
        #expect(plans.allSatisfy { $0.meals[0] == locked })
    }

    @Test func respectsDislikesAndAllergies() {
        let options = PlannerOptions(dislikes: ["salmon", " "], avoidAllergens: [.peanut, .treeNut])
        let plans = MealPlanner.planWeek(week(), candidates: candidates, options: options, seed: 3)
        let banned: Set<UUID> = [candidates[1].id, candidates[6].id, candidates[9].id]
        for plan in plans {
            #expect(plan.meals.compactMap { $0?.candidateID }.allSatisfy { !banned.contains($0) })
        }
    }

    @Test func sameSeedSamePlan_differentSeedShuffles() {
        let a = MealPlanner.planWeek(week(), candidates: candidates, seed: 99)
        let b = MealPlanner.planWeek(week(), candidates: candidates, seed: 99)
        #expect(a == b)
        let shuffled = (100..<106).map { MealPlanner.planWeek(week(), candidates: candidates, seed: UInt64($0)) }
        #expect(shuffled.contains { $0 != a })
    }

    @Test func spreadsMealsAcrossTheWeek() {
        let plans = MealPlanner.planWeek(week(), candidates: candidates, seed: 5)
        let used = Set(plans.flatMap { $0.meals.compactMap { $0?.candidateID } })
        #expect(used.count >= 8)
    }

    @Test func mealPrepRepeatsMoreThanMixItUp() {
        func distinct(_ variety: MealVariety) -> Int {
            let plans = MealPlanner.planWeek(week(), candidates: candidates, options: PlannerOptions(variety: variety), seed: 21)
            return Set(plans.flatMap { $0.meals.compactMap { $0?.candidateID } }).count
        }
        #expect(distinct(.prep) < distinct(.mixItUp))
        let prep = MealPlanner.planWeek(week(), candidates: candidates, options: PlannerOptions(variety: .prep), seed: 21)
        for plan in prep { #expect(abs(plan.totals.kcal - target.kcal) / target.kcal < 0.05) }
    }

    @Test func emptySlotWhenNothingFits() {
        let noShakes = candidates.filter { !$0.slots.contains(.shake) }
        let plans = MealPlanner.planWeek(week(), candidates: noShakes, seed: 2)
        #expect(plans.allSatisfy { $0.meals[4] == nil })
    }

    @Test func candidateFromTemplateSumsIngredients() {
        let whey = FoodItem(name: "Whey", servingLabel: "1 scoop", servingAmount: 1, servingUnit: .scoop,
                            macros: Macros(kcal: 120, protein: 25, carbs: 3, fat: 2), section: .supplements, allergens: [.dairy])
        let milk = FoodItem(name: "Whole milk", servingLabel: "1 cup", servingAmount: 1, servingUnit: .cup,
                            macros: Macros(kcal: 150, protein: 8, carbs: 12, fat: 8), section: .dairyEggs, allergens: [.dairy])
        let shake = MealTemplate(name: "Shake", slots: [.shake],
                                 ingredients: [Ingredient(foodID: whey.id, servings: 2), Ingredient(foodID: milk.id, servings: 2)], isShake: true)
        let candidate = PlannerCandidate(template: shake, foods: [whey.id: whey, milk.id: milk])
        #expect(candidate.macros == Macros(kcal: 540, protein: 66, carbs: 30, fat: 20))
        #expect(candidate.allergens == [.dairy])
        #expect(candidate.searchText.contains("whole milk"))
    }

    @Test func scorePrefersTargetAndForgivesExtraProtein() {
        let onTarget = MealPlanner.score(target, target: target)
        let extraProtein = MealPlanner.score(target + Macros(protein: 20), target: target)
        let lowProtein = MealPlanner.score(target - Macros(protein: 20), target: target)
        #expect(onTarget == 0)
        #expect(extraProtein < lowProtein)
    }
}

@Suite("Grocery merge")
struct GroceryTests {
    let chicken = FoodItem(name: "Chicken breast", servingLabel: "6 oz raw", servingAmount: 6, servingUnit: .oz,
                           macros: Macros(kcal: 204, protein: 38, carbs: 0, fat: 4.4), section: .meatSeafood)
    let milkCup = FoodItem(name: "Whole milk", servingLabel: "1 cup", servingAmount: 1, servingUnit: .cup,
                           macros: Macros(kcal: 150, protein: 8, carbs: 12, fat: 8), section: .dairyEggs)
    let milkML = FoodItem(name: "whole milk ", servingLabel: "240 ml", servingAmount: 240, servingUnit: .ml,
                          macros: Macros(kcal: 150, protein: 8, carbs: 12, fat: 8), section: .dairyEggs)
    let eggs = FoodItem(name: "Eggs", servingLabel: "1 large egg", servingAmount: 1, servingUnit: .piece,
                        macros: Macros(kcal: 72, protein: 6.3, carbs: 0.4, fat: 4.8), section: .dairyEggs)
    let bananas = FoodItem(name: "Banana", servingLabel: "1 medium", servingAmount: 1, servingUnit: .piece,
                           macros: Macros(kcal: 105, protein: 1.3, carbs: 27, fat: 0.4), section: .produce)

    @Test func mergesSameFoodAcrossMeals() {
        let sections = GroceryBuilder.build([
            FoodUse(food: chicken, servings: 1.5), FoodUse(food: chicken, servings: 2), FoodUse(food: chicken, servings: 1),
        ], unitSystem: .imperial)
        let line = sections.flatMap(\.lines).first!
        #expect(sections.flatMap(\.lines).count == 1)
        #expect(abs(line.grams - 27 * GroceryUnit.oz.toBase) < 1e-6)
        #expect(line.amountText == "1.7 lb")
    }

    @Test func convertsCompatibleUnitsByName() {
        let sections = GroceryBuilder.build([FoodUse(food: milkCup, servings: 2), FoodUse(food: milkML, servings: 1)], unitSystem: .imperial)
        let lines = sections.flatMap(\.lines)
        #expect(lines.count == 1)
        #expect(abs(lines[0].milliliters - (2 * GroceryUnit.cup.toBase + 240)) < 1e-6)
        #expect(lines[0].amountText == "3 cups")
    }

    @Test func countsRoundUpToWholeItems() {
        let sections = GroceryBuilder.build([FoodUse(food: eggs, servings: 3), FoodUse(food: eggs, servings: 5.5)], unitSystem: .imperial)
        #expect(sections.flatMap(\.lines).first?.amountText == "9 pc")
    }

    @Test func groupsBySectionInWalkingOrder() {
        let sections = GroceryBuilder.build([
            FoodUse(food: eggs, servings: 2), FoodUse(food: chicken, servings: 1), FoodUse(food: bananas, servings: 3),
        ], unitSystem: .imperial)
        #expect(sections.map(\.section) == [.produce, .meatSeafood, .dairyEggs])
    }

    @Test func metricDisplay() {
        let sections = GroceryBuilder.build([FoodUse(food: chicken, servings: 4.5), FoodUse(food: milkCup, servings: 8)], unitSystem: .metric)
        let lines = Dictionary(uniqueKeysWithValues: sections.flatMap(\.lines).map { ($0.name, $0.amountText) })
        #expect(lines["Chicken breast"] == "770 g")
        #expect(lines["Whole milk"] == "1.9 L")
    }

    @Test func largeVolumesUseGallons() {
        #expect(GroceryBuilder.volumeText(ml: 3785.41 * 1.5, unitSystem: .imperial) == "1.5 gal")
        #expect(GroceryBuilder.volumeText(ml: 1000, unitSystem: .imperial) == "1.1 qt")
        #expect(GroceryBuilder.volumeText(ml: 30, unitSystem: .imperial) == "2 tbsp")
    }

    @Test func expandsMealsIntoIngredients() {
        let template = MealTemplate(name: "Chicken Bowl", slots: [.lunch], ingredients: [Ingredient(foodID: chicken.id, servings: 1)])
        let uses = GroceryBuilder.uses(
            meals: [PlannedMeal(candidateID: template.id, servings: 1.5), PlannedMeal(candidateID: eggs.id, servings: 2)],
            templates: [template.id: template], foods: [chicken.id: chicken, eggs.id: eggs])
        #expect(uses.count == 2)
        #expect(uses[0].servings == 1.5)
        #expect(uses[1].food.name == "Eggs")
    }

    @Test func plainTextExport() {
        let text = GroceryBuilder.plainText(title: "Groceries", sections: [
            (.meatSeafood, [("Chicken breast", "1.7 lb", false)]),
            (.produce, []),
            (.dairyEggs, [("Eggs", "9 pc", true), ("Paper towels", "", false)]),
        ])
        #expect(text == "Groceries\n\nMEAT & SEAFOOD\n[ ] Chicken breast — 1.7 lb\n\nDAIRY & EGGS\n[x] Eggs — 9 pc\n[ ] Paper towels\n")
    }
}
