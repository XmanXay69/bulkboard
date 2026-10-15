import Foundation

public enum MuscleGroup: String, Codable, CaseIterable, Sendable {
    case chest, back, shoulders, biceps, triceps
    case quads, hamstrings, glutes, calves
    case core, fullBody, conditioning

    public var title: String {
        switch self {
        case .fullBody: "Full body"
        default: rawValue.capitalized
        }
    }

    public var region: BodyRegion {
        switch self {
        case .chest, .back, .shoulders, .biceps, .triceps: .upper
        case .quads, .hamstrings, .glutes, .calves: .lower
        case .core: .core
        case .fullBody: .full
        case .conditioning: .conditioning
        }
    }
}

public enum BodyRegion: String, Codable, CaseIterable, Sendable {
    case upper, lower, core, full, conditioning
}

public enum Equipment: String, Codable, CaseIterable, Sendable {
    case barbell, dumbbell, machine, cable, bodyweight, kettlebell, medicineBall, court, other

    public var title: String {
        switch self {
        case .medicineBall: "Med ball"
        default: rawValue.capitalized
        }
    }
}

public struct ExerciseDef: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var muscle: MuscleGroup
    public var equipment: Equipment
    public var isCompound: Bool
    public var defaultRestSeconds: Int

    public init(id: UUID = UUID(), name: String, muscle: MuscleGroup, equipment: Equipment,
                isCompound: Bool, defaultRestSeconds: Int = 90) {
        self.id = id
        self.name = name
        self.muscle = muscle
        self.equipment = equipment
        self.isCompound = isCompound
        self.defaultRestSeconds = defaultRestSeconds
    }
}

public struct PlannedExercise: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var exerciseID: UUID
    public var sets: Int
    public var repLow: Int
    public var repHigh: Int
    public var restSeconds: Int
    public var note: String?

    public init(id: UUID = UUID(), exerciseID: UUID, sets: Int, repLow: Int, repHigh: Int,
                restSeconds: Int, note: String? = nil) {
        self.id = id
        self.exerciseID = exerciseID
        self.sets = sets
        self.repLow = repLow
        self.repHigh = repHigh
        self.restSeconds = restSeconds
        self.note = note
    }

    public var repText: String { repLow == repHigh ? "\(repLow)" : "\(repLow)–\(repHigh)" }
}

/// A court conditioning block for game days.
public struct CourtBlock: Codable, Hashable, Sendable {
    public var title: String
    public var drills: [String]
    public var minutes: Int

    public init(title: String, drills: [String], minutes: Int) {
        self.title = title
        self.drills = drills
        self.minutes = minutes
    }
}

public struct PlannedDay: Codable, Hashable, Sendable, Identifiable {
    /// 0 = Monday … 6 = Sunday.
    public var weekday: Int
    public var dayType: DayType
    public var title: String
    public var focus: String
    public var exercises: [PlannedExercise]
    public var court: CourtBlock?

    public var id: Int { weekday }

    public init(weekday: Int, dayType: DayType, title: String, focus: String,
                exercises: [PlannedExercise] = [], court: CourtBlock? = nil) {
        self.weekday = weekday
        self.dayType = dayType
        self.title = title
        self.focus = focus
        self.exercises = exercises
        self.court = court
    }
}

/// One logged working or warm-up set. Weight is in kilograms.
public struct LoggedSet: Codable, Hashable, Sendable {
    public var exerciseID: UUID
    public var date: Date
    public var reps: Int
    public var weightKg: Double
    public var isWarmup: Bool

    public init(exerciseID: UUID, date: Date, reps: Int, weightKg: Double, isWarmup: Bool = false) {
        self.exerciseID = exerciseID
        self.date = date
        self.reps = reps
        self.weightKg = weightKg
        self.isWarmup = isWarmup
    }

    public var volumeKg: Double { Double(reps) * weightKg }
}

public enum CourtSessionKind: String, Codable, CaseIterable, Sendable {
    case pickup, leagueGame, skills, conditioning, shooting

    public var title: String {
        switch self {
        case .pickup: "Pickup"
        case .leagueGame: "League game"
        case .skills: "Skills + drills"
        case .conditioning: "Conditioning"
        case .shooting: "Shooting"
        }
    }
}

/// A logged basketball session. Load uses session-RPE (minutes × RPE).
public struct CourtSessionLog: Codable, Hashable, Sendable {
    public var date: Date
    public var kind: CourtSessionKind
    public var minutes: Int
    public var rpe: Int

    public init(date: Date, kind: CourtSessionKind, minutes: Int, rpe: Int) {
        self.date = date
        self.kind = kind
        self.minutes = minutes
        self.rpe = rpe
    }

    public var load: Int { minutes * max(1, min(10, rpe)) }
}
