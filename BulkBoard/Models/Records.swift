import BulkCore
import Foundation
import SwiftData

// SwiftData records. Records hold only scalar fields, string arrays and JSON blobs, and
// reference each other by UUID. That keeps the store simple to migrate, export and wipe.
// Every record carries `isDemo` so demo data can be removed in one pass.

@Model
final class ProfileRecord {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var age: Int = 25
    var sexRaw: String = Sex.male.rawValue
    var heightCm: Double = 180
    var weightKg: Double = 80
    var goalWeightKg: Double = 85
    var startDate: Date = Date()
    var targetDate: Date = Date()
    var activityRaw: String = ActivityLevel.moderate.rawValue
    var goalModeRaw: String = GoalMode.bulkPerformance.rawValue
    var liftingDays: Int = 4
    var courtDays: Int = 2
    var dislikes: [String] = []
    var allergensRaw: [String] = []
    var unitSystemRaw: String = UnitSystem.imperial.rawValue
    var proteinPerLbOverride: Double?
    var fatPercentOverride: Double?
    var weeklyRateOverrideKg: Double?
    /// JSON `[String: Macros]` keyed by `DayType.rawValue`; manual per-day-type target overrides.
    var dayTargetOverridesData: Data?
    var mealSlotsRaw: [String] = MealSlot.defaultDay.map(\.rawValue)
    /// Muscle groups getting extra volume (`MuscleGroup.rawValue`).
    var focusMusclesRaw: [String] = []
    /// Adds jump training to the plan.
    var dunkGoal: Bool = false
    var isDemo: Bool = false

    init() {}
}

@Model
final class FoodRecord {
    var id: UUID = UUID()
    var seedKey: String?
    var name: String = ""
    var brand: String?
    var servingLabel: String = "1 serving"
    var servingAmount: Double = 1
    var servingUnitRaw: String = GroceryUnit.serving.rawValue
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var sectionRaw: String = StoreSection.other.rawValue
    var allergensRaw: [String] = []
    var shakerSafe: Bool = false
    var isBuiltIn: Bool = false
    var isAIEstimate: Bool = false
    var isFavorite: Bool = false
    var isArchived: Bool = false
    var isDemo: Bool = false
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

@Model
final class RecipeRecord {
    var id: UUID = UUID()
    var seedKey: String?
    var name: String = ""
    var slotsRaw: [String] = []
    /// JSON `[Ingredient]`.
    var ingredientsData: Data = Data()
    var isShake: Bool = false
    var notes: String = ""
    var isBuiltIn: Bool = false
    var isFavorite: Bool = false
    var isArchived: Bool = false
    var isDemo: Bool = false
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// One meal assigned to a slot on a given day of the meal plan.
@Model
final class PlanEntryRecord {
    var id: UUID = UUID()
    var day: Date = Date()
    var slotIndex: Int = 0
    var slotRaw: String = MealSlot.breakfast.rawValue
    var recipeID: UUID?
    var foodID: UUID?
    var servings: Double = 1
    var isLocked: Bool = false
    var isDemo: Bool = false

    init(day: Date, slotIndex: Int, slot: MealSlot) {
        self.day = day
        self.slotIndex = slotIndex
        self.slotRaw = slot.rawValue
    }
}

/// What was actually eaten. Macros are snapshotted so edits to foods don't rewrite history.
@Model
final class IntakeRecord {
    var id: UUID = UUID()
    var day: Date = Date()
    var timestamp: Date = Date()
    var slotRaw: String = MealSlot.snack.rawValue
    var name: String = ""
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var planEntryID: UUID?
    var isDemo: Bool = false

    init(day: Date, name: String) {
        self.day = day
        self.name = name
    }
}

@Model
final class GroceryItemRecord {
    var id: UUID = UUID()
    var name: String = ""
    var amountText: String = ""
    var sectionRaw: String = StoreSection.other.rawValue
    var isChecked: Bool = false
    var isManual: Bool = false
    var sortIndex: Int = 0
    var isDemo: Bool = false
    var createdAt: Date = Date()

    init(name: String) {
        self.name = name
    }
}

@Model
final class ExerciseRecord {
    var id: UUID = UUID()
    var seedKey: String?
    var name: String = ""
    var muscleRaw: String = MuscleGroup.fullBody.rawValue
    var equipmentRaw: String = Equipment.other.rawValue
    var isCompound: Bool = false
    var defaultRestSeconds: Int = 90
    var notes: String = ""
    var isBuiltIn: Bool = false
    var isArchived: Bool = false
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// The current weekly training plan, stored as JSON `[PlannedDay]`.
@Model
final class WorkoutPlanRecord {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var liftingDays: Int = 4
    var courtDays: Int = 2
    var daysData: Data = Data()
    var isDemo: Bool = false

    init() {}
}

@Model
final class WorkoutSessionRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    var title: String = ""
    var dayTypeRaw: String = DayType.lifting.rawValue
    /// JSON `[SessionSet]`.
    var setsData: Data = Data()
    var durationSeconds: Int = 0
    var notes: String = ""
    var isCompleted: Bool = false
    var prCount: Int = 0
    var isDemo: Bool = false

    init(date: Date, title: String) {
        self.date = date
        self.title = title
    }
}

@Model
final class CourtSessionRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    var kindRaw: String = CourtSessionKind.pickup.rawValue
    var minutes: Int = 60
    var rpe: Int = 7
    var notes: String = ""
    var isDemo: Bool = false

    init(date: Date) {
        self.date = date
    }
}

@Model
final class WeightRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    var weightKg: Double = 0
    var note: String = ""
    var isDemo: Bool = false

    init(date: Date, weightKg: Double) {
        self.date = date
        self.weightKg = weightKg
    }
}

/// A body check-in: tape measurements, jump numbers, an optional photo and any AI notes.
@Model
final class BodyCheckInRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    /// JSON `BodyMeasurements`.
    var measurementsData: Data = Data()
    /// File name inside the Photos folder; the image itself never goes in the database.
    var photoFilename: String?
    var aiNotes: String?
    var aiModel: String?
    var isDemo: Bool = false

    init(date: Date) {
        self.date = date
    }
}
