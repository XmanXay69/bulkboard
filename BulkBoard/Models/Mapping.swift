import BulkCore
import Foundation
import SwiftData

/// JSON blobs inside records. Decoding failures fall back to a default instead of crashing.
nonisolated enum Blob {
    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?, default fallback: T) -> T {
        guard let data, !data.isEmpty else { return fallback }
        return (try? JSONDecoder().decode(type, from: data)) ?? fallback
    }
}

// MARK: - Profile

extension ProfileRecord {
    var sex: Sex {
        get { Sex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }

    var activity: ActivityLevel {
        get { ActivityLevel(rawValue: activityRaw) ?? .moderate }
        set { activityRaw = newValue.rawValue }
    }

    var goalMode: GoalMode {
        get { GoalMode(rawValue: goalModeRaw) ?? .bulkPerformance }
        set { goalModeRaw = newValue.rawValue }
    }

    var unitSystem: UnitSystem {
        get { UnitSystem(rawValue: unitSystemRaw) ?? .imperial }
        set { unitSystemRaw = newValue.rawValue }
    }

    var allergens: Set<Allergen> {
        get { Set(allergensRaw.compactMap(Allergen.init(rawValue:))) }
        set { allergensRaw = newValue.map(\.rawValue).sorted() }
    }

    var mealSlots: [MealSlot] {
        get {
            let slots = mealSlotsRaw.compactMap(MealSlot.init(rawValue:))
            return slots.isEmpty ? MealSlot.defaultDay : slots
        }
        set { mealSlotsRaw = newValue.map(\.rawValue) }
    }

    var macroSettings: MacroSettings {
        let defaults = goalMode.defaultMacroSettings
        return MacroSettings(proteinPerLb: proteinPerLbOverride ?? defaults.proteinPerLb,
                             fatPercent: fatPercentOverride ?? defaults.fatPercent)
    }

    var dayTargetOverrides: [DayType: Macros] {
        get {
            let raw = Blob.decode([String: Macros].self, from: dayTargetOverridesData, default: [:])
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in DayType(rawValue: key).map { ($0, value) } })
        }
        set {
            dayTargetOverridesData = newValue.isEmpty
                ? nil
                : Blob.encode(Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) }))
        }
    }

    /// Body profile for the math. Uses the latest weigh-in when there is one.
    func bodyProfile(latestWeightKg: Double? = nil) -> BodyProfile {
        BodyProfile(age: age, sex: sex, heightCm: heightCm, weightKg: latestWeightKg ?? weightKg,
                    goalWeightKg: goalWeightKg, startDate: startDate, targetDate: targetDate,
                    activity: activity, mode: goalMode, liftingDaysPerWeek: liftingDays, courtDaysPerWeek: courtDays)
    }

    func targets(latestWeightKg: Double? = nil, today: Date = .now) -> TargetsSnapshot {
        let result = TargetsCalculator.compute(profile: bodyProfile(latestWeightKg: latestWeightKg), today: today,
                                               settings: macroSettings, weeklyRateOverrideKg: weeklyRateOverrideKg,
                                               unitSystem: unitSystem)
        return TargetsSnapshot(result: result, overrides: dayTargetOverrides)
    }
}

/// Computed targets plus any manual per-day-type overrides.
struct TargetsSnapshot {
    var result: TargetsResult
    var overrides: [DayType: Macros]

    var byDayType: [DayType: Macros] { TargetsCalculator.applying(overrides: overrides, to: result.byDayType) }

    func target(for dayType: DayType) -> Macros { byDayType[dayType] ?? result.daily }

    func isOverridden(_ dayType: DayType) -> Bool { overrides[dayType] != nil }
}

// MARK: - Foods and recipes

extension FoodRecord {
    var macros: Macros {
        get { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
        set {
            kcal = newValue.kcal
            protein = newValue.protein
            carbs = newValue.carbs
            fat = newValue.fat
        }
    }

    var servingUnit: GroceryUnit {
        get { GroceryUnit(rawValue: servingUnitRaw) ?? .serving }
        set { servingUnitRaw = newValue.rawValue }
    }

    var section: StoreSection {
        get { StoreSection(rawValue: sectionRaw) ?? .other }
        set { sectionRaw = newValue.rawValue }
    }

    var allergens: Set<Allergen> {
        get { Set(allergensRaw.compactMap(Allergen.init(rawValue:))) }
        set { allergensRaw = newValue.map(\.rawValue).sorted() }
    }

    var item: FoodItem {
        FoodItem(id: id, name: name, brand: brand, servingLabel: servingLabel, servingAmount: servingAmount,
                 servingUnit: servingUnit, macros: macros, section: section, allergens: allergens, shakerSafe: shakerSafe)
    }

    func apply(_ item: FoodItem) {
        name = item.name
        brand = item.brand
        servingLabel = item.servingLabel
        servingAmount = item.servingAmount
        servingUnit = item.servingUnit
        macros = item.macros
        section = item.section
        allergens = item.allergens
        shakerSafe = item.shakerSafe
    }
}

extension RecipeRecord {
    var ingredients: [Ingredient] {
        get { Blob.decode([Ingredient].self, from: ingredientsData, default: []) }
        set { ingredientsData = Blob.encode(newValue) }
    }

    var slots: Set<MealSlot> {
        get { Set(slotsRaw.compactMap(MealSlot.init(rawValue:))) }
        set { slotsRaw = MealSlot.allCases.filter(newValue.contains).map(\.rawValue) }
    }

    var template: MealTemplate {
        MealTemplate(id: id, name: name, slots: slots, ingredients: ingredients, isShake: isShake)
    }
}

// MARK: - Planning and logs

extension PlanEntryRecord {
    var slot: MealSlot {
        get { MealSlot(rawValue: slotRaw) ?? .snack }
        set { slotRaw = newValue.rawValue }
    }

    /// The recipe or stand-alone food this entry points at.
    var mealID: UUID? { recipeID ?? foodID }

    var plannedMeal: PlannedMeal? { mealID.map { PlannedMeal(candidateID: $0, servings: servings) } }
}

extension IntakeRecord {
    var macros: Macros {
        get { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
        set {
            kcal = newValue.kcal
            protein = newValue.protein
            carbs = newValue.carbs
            fat = newValue.fat
        }
    }

    var slot: MealSlot { MealSlot(rawValue: slotRaw) ?? .snack }
}

extension GroceryItemRecord {
    var section: StoreSection {
        get { StoreSection(rawValue: sectionRaw) ?? .other }
        set { sectionRaw = newValue.rawValue }
    }
}

extension ExerciseRecord {
    var muscle: MuscleGroup {
        get { MuscleGroup(rawValue: muscleRaw) ?? .fullBody }
        set { muscleRaw = newValue.rawValue }
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }

    var def: ExerciseDef {
        ExerciseDef(id: id, name: name, muscle: muscle, equipment: equipment, isCompound: isCompound,
                    defaultRestSeconds: defaultRestSeconds)
    }
}

extension WorkoutPlanRecord {
    var days: [PlannedDay] {
        get { Blob.decode([PlannedDay].self, from: daysData, default: []) }
        set { daysData = Blob.encode(newValue) }
    }

    func day(for date: Date) -> PlannedDay? {
        let index = WeekMath.weekdayIndex(date)
        return days.first { $0.weekday == index }
    }
}

extension WorkoutSessionRecord {
    var sets: [SessionSet] {
        get { Blob.decode([SessionSet].self, from: setsData, default: []) }
        set { setsData = Blob.encode(newValue) }
    }

    var dayType: DayType {
        get { DayType(rawValue: dayTypeRaw) ?? .lifting }
        set { dayTypeRaw = newValue.rawValue }
    }

    var loggedSets: [LoggedSet] { sets.filter(\.isDone).map { $0.logged(on: date) } }

    var volumeKg: Double { loggedSets.filter { !$0.isWarmup }.map(\.volumeKg).reduce(0, +) }
}

extension CourtSessionRecord {
    var kind: CourtSessionKind {
        get { CourtSessionKind(rawValue: kindRaw) ?? .pickup }
        set { kindRaw = newValue.rawValue }
    }

    var log: CourtSessionLog { CourtSessionLog(date: date, kind: kind, minutes: minutes, rpe: rpe) }
}

extension WeightRecord {
    var point: WeightPoint { WeightPoint(date: date, kg: weightKg) }
}

// MARK: - Fetch helpers

extension ModelContext {
    func fetchAll<T: PersistentModel>(_ type: T.Type, sortBy: [SortDescriptor<T>] = []) -> [T] {
        (try? fetch(FetchDescriptor<T>(sortBy: sortBy))) ?? []
    }

    var profile: ProfileRecord? { fetchAll(ProfileRecord.self).first }

    var workoutPlan: WorkoutPlanRecord? {
        fetchAll(WorkoutPlanRecord.self, sortBy: [SortDescriptor(\.createdAt, order: .reverse)]).first
    }

    var latestWeightKg: Double? {
        var descriptor = FetchDescriptor<WeightRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? fetch(descriptor))?.first?.weightKg
    }
}
