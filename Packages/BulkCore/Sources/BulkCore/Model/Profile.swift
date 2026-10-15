import Foundation

public enum Sex: String, Codable, CaseIterable, Sendable {
    case male
    case female

    public var title: String { self == .male ? "Male" : "Female" }
}

public enum ActivityLevel: String, Codable, CaseIterable, Sendable {
    case sedentary
    case light
    case moderate
    case active
    case veryActive

    /// Standard TDEE multipliers applied to Mifflin-St Jeor BMR.
    public var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }

    public var title: String {
        switch self {
        case .sedentary: "Sedentary"
        case .light: "Light"
        case .moderate: "Moderate"
        case .active: "Active"
        case .veryActive: "Very active"
        }
    }

    public var detail: String {
        switch self {
        case .sedentary: "Desk job, little exercise"
        case .light: "1–3 sessions a week"
        case .moderate: "3–5 sessions a week"
        case .active: "6–7 sessions a week"
        case .veryActive: "Hard daily training or a physical job"
        }
    }

    /// A reasonable starting point based on total weekly sessions.
    public static func suggested(forSessionsPerWeek sessions: Int) -> ActivityLevel {
        switch sessions {
        case ...0: .sedentary
        case 1...2: .light
        case 3...5: .moderate
        case 6...7: .active
        default: .veryActive
        }
    }
}

public enum GoalMode: String, Codable, CaseIterable, Sendable {
    case bulk
    case bulkPerformance
    case recomp
    case cut
    case maintain

    public var title: String {
        switch self {
        case .bulk: "Bulk"
        case .bulkPerformance: "Bulk + Performance"
        case .recomp: "Recomp"
        case .cut: "Cut"
        case .maintain: "Maintain"
        }
    }

    public var detail: String {
        switch self {
        case .bulk: "Max size. Steady surplus, hypertrophy-focused lifting."
        case .bulkPerformance: "Gain weight while keeping your legs and lungs for the court."
        case .recomp: "Hold weight, build muscle, lose a little fat."
        case .cut: "Lose fat while keeping strength."
        case .maintain: "Hold steady and keep training."
        }
    }

    /// +1 for gaining, -1 for losing, 0 for holding.
    public var direction: Int {
        switch self {
        case .bulk, .bulkPerformance: 1
        case .cut: -1
        case .recomp, .maintain: 0
        }
    }

    public var isGain: Bool { direction > 0 }
}

/// The kind of training day.
public enum DayType: String, Codable, CaseIterable, Sendable {
    case lifting
    case conditioning
    case rest

    public var title: String {
        switch self {
        case .lifting: "Lift day"
        case .conditioning: "Court day"
        case .rest: "Rest day"
        }
    }

    public var subtitle: String {
        switch self {
        case .lifting: "Weight room"
        case .conditioning: "Basketball / conditioning"
        case .rest: "Recovery and mobility"
        }
    }

    public var symbol: String {
        switch self {
        case .lifting: "dumbbell.fill"
        case .conditioning: "basketball.fill"
        case .rest: "bed.double.fill"
        }
    }
}

/// Everything the energy and macro math needs about a person.
public struct BodyProfile: Codable, Hashable, Sendable {
    public var age: Int
    public var sex: Sex
    public var heightCm: Double
    public var weightKg: Double
    public var goalWeightKg: Double
    public var startDate: Date
    public var targetDate: Date
    public var activity: ActivityLevel
    public var mode: GoalMode
    public var liftingDaysPerWeek: Int
    public var courtDaysPerWeek: Int

    public init(age: Int, sex: Sex, heightCm: Double, weightKg: Double, goalWeightKg: Double,
                startDate: Date, targetDate: Date, activity: ActivityLevel, mode: GoalMode,
                liftingDaysPerWeek: Int, courtDaysPerWeek: Int) {
        self.age = age
        self.sex = sex
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.goalWeightKg = goalWeightKg
        self.startDate = startDate
        self.targetDate = targetDate
        self.activity = activity
        self.mode = mode
        self.liftingDaysPerWeek = liftingDaysPerWeek
        self.courtDaysPerWeek = courtDaysPerWeek
    }
}
