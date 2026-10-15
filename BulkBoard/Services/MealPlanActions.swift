import BulkCore
import Foundation
import SwiftData

/// Lookups for foods and recipes, built from records.
struct MealLibrary {
    var foods: [UUID: FoodItem]
    var foodRecords: [UUID: FoodRecord]
    var templates: [UUID: MealTemplate]
    var recipes: [UUID: RecipeRecord]

    init(foods: [FoodRecord], recipes: [RecipeRecord]) {
        foodRecords = Dictionary(foods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.foods = foodRecords.mapValues(\.item)
        self.recipes = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        templates = self.recipes.mapValues(\.template)
    }

    init(_ context: ModelContext) {
        self.init(foods: context.fetchAll(FoodRecord.self), recipes: context.fetchAll(RecipeRecord.self))
    }

    /// Meals the planner may pick: every recipe that isn't archived.
    var candidates: [PlannerCandidate] {
        recipes.values.filter { !$0.isArchived }
            .sorted { $0.name < $1.name }
            .map { PlannerCandidate(template: templates[$0.id]!, foods: foods) }
    }

    func macros(recipeID: UUID?, foodID: UUID?, servings: Double) -> Macros {
        if let recipeID, let template = templates[recipeID] { return template.macros(foods: foods) * servings }
        if let foodID, let food = foods[foodID] { return food.macros * servings }
        return .zero
    }

    func macros(for entry: PlanEntryRecord) -> Macros {
        macros(recipeID: entry.recipeID, foodID: entry.foodID, servings: entry.servings)
    }

    func name(for entry: PlanEntryRecord) -> String {
        if let id = entry.recipeID, let recipe = recipes[id] { return recipe.name }
        if let id = entry.foodID, let food = foodRecords[id] { return food.name }
        return "Missing meal"
    }

    func perServing(recipeID: UUID) -> Macros { templates[recipeID]?.macros(foods: foods) ?? .zero }
}

enum MealPlanActions {
    static func entries(weekOf date: Date, context: ModelContext) -> [PlanEntryRecord] {
        let start = date.weekStart
        let end = start.adding(days: 7)
        let descriptor = FetchDescriptor<PlanEntryRecord>(predicate: #Predicate { $0.day >= start && $0.day < end })
        return (try? context.fetch(descriptor)) ?? []
    }

    static func eatenEntryIDs(context: ModelContext, from start: Date, to end: Date) -> Set<UUID> {
        let descriptor = FetchDescriptor<IntakeRecord>(predicate: #Predicate { $0.day >= start && $0.day < end })
        return Set(((try? context.fetch(descriptor)) ?? []).compactMap(\.planEntryID))
    }

    /// Fills every unlocked, not-yet-eaten slot of the week so each day lands on its day-type target.
    static func autoFill(weekOf date: Date, context: ModelContext, seed: UInt64) {
        guard let profile = context.profile else { return }
        let start = date.weekStart
        let days = WeekMath.days(ofWeekStarting: start)
        let slots = profile.mealSlots
        let plan = context.workoutPlan
        let snapshot = profile.targets(latestWeightKg: context.latestWeightKg)
        let library = MealLibrary(context)
        let existing = entries(weekOf: start, context: context)
        let eaten = eatenEntryIDs(context: context, from: start, to: start.adding(days: 7))
        let keep = existing.filter { $0.isLocked || eaten.contains($0.id) }

        let requests: [DayRequest] = days.map { day in
            var locked: [Int: PlannedMeal] = [:]
            for entry in keep where entry.day == day && entry.slotIndex < slots.count {
                if let meal = entry.plannedMeal { locked[entry.slotIndex] = meal }
            }
            return DayRequest(target: snapshot.target(for: TrainingActions.dayType(for: day, plan: plan)),
                              slots: slots, locked: locked)
        }

        // Foods placed directly in a slot aren't planner candidates, so give them a stand-in with real macros.
        var candidates = library.candidates
        for entry in keep where entry.recipeID == nil {
            if let id = entry.foodID, let food = library.foods[id] {
                candidates.append(PlannerCandidate(id: id, name: food.name, slots: [], macros: food.macros))
            }
        }

        let variety = MealVariety(rawValue: UserDefaults.standard.string(forKey: "mealVariety") ?? "") ?? .balanced
        let options = PlannerOptions(variety: variety, dislikes: profile.dislikes, avoidAllergens: profile.allergens)
        let result = MealPlanner.planWeek(requests, candidates: candidates, options: options, seed: seed)

        for entry in existing where !keep.contains(where: { $0 === entry }) { context.delete(entry) }
        for (dayIndex, dayPlan) in result.enumerated() {
            for (slotIndex, meal) in dayPlan.meals.enumerated() where requests[dayIndex].locked[slotIndex] == nil {
                guard let meal else { continue }
                let entry = PlanEntryRecord(day: days[dayIndex], slotIndex: slotIndex, slot: slots[slotIndex])
                entry.recipeID = meal.candidateID
                entry.servings = meal.servings
                entry.isDemo = profile.isDemo
                context.insert(entry)
            }
        }
        try? context.save()
    }

    /// Puts a recipe or a single food into a slot, replacing what was there.
    static func assign(recipeID: UUID? = nil, foodID: UUID? = nil, day: Date, slotIndex: Int, slot: MealSlot,
                       servings: Double = 1, context: ModelContext) {
        let day = day.dayStart
        let existing = entries(weekOf: day, context: context).first { $0.day == day && $0.slotIndex == slotIndex }
        let entry = existing ?? PlanEntryRecord(day: day, slotIndex: slotIndex, slot: slot)
        entry.recipeID = recipeID
        entry.foodID = recipeID == nil ? foodID : nil
        entry.servings = servings
        entry.slot = slot
        if existing == nil {
            entry.isDemo = context.profile?.isDemo ?? false
            context.insert(entry)
        }
        try? context.save()
    }

    static func clearWeek(_ date: Date, context: ModelContext) {
        for entry in entries(weekOf: date, context: context) where !entry.isLocked { context.delete(entry) }
        try? context.save()
    }
}

enum IntakeActions {
    static func intake(for entry: PlanEntryRecord, in intake: [IntakeRecord]) -> IntakeRecord? {
        intake.first { $0.planEntryID == entry.id }
    }

    /// Logs a planned meal as eaten (snapshotting its macros), or un-logs it.
    static func toggleEaten(_ entry: PlanEntryRecord, library: MealLibrary, context: ModelContext) {
        let entryID = entry.id
        let descriptor = FetchDescriptor<IntakeRecord>(predicate: #Predicate { $0.planEntryID == entryID })
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            existing.forEach(context.delete)
        } else {
            let record = IntakeRecord(day: entry.day, name: library.name(for: entry))
            record.slotRaw = entry.slotRaw
            record.macros = library.macros(for: entry)
            record.planEntryID = entry.id
            record.isDemo = entry.isDemo
            context.insert(record)
        }
        try? context.save()
    }

    static func logQuick(name: String, macros: Macros, slot: MealSlot, day: Date = .now, context: ModelContext) {
        let record = IntakeRecord(day: day.dayStart, name: name)
        record.slotRaw = slot.rawValue
        record.macros = macros
        context.insert(record)
        try? context.save()
    }
}
