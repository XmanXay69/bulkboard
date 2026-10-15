import Foundation

/// Builds a 7-day plan for a standard gym (YMCA-style: barbells, dumbbells, machines, cables)
/// plus a basketball court.
public enum SplitGenerator {
    public struct Template: Sendable {
        public var title: String
        public var focus: String
        public var region: BodyRegion
        public var exercises: [(key: String, sets: Int, low: Int, high: Int)]
    }

    /// Exercise keys the templates use; they must exist in the exercise library.
    public static var allExerciseKeys: Set<String> {
        let modes: [Bool] = [true, false]
        return Set(modes.flatMap { perf in (1...6).flatMap { templates(liftingDays: $0, performance: perf) } }
            .flatMap { $0.exercises.map(\.key) })
    }

    public static func templates(liftingDays: Int, performance: Bool) -> [Template] {
        let p = performance
        switch liftingDays {
        case ...0: return []
        case 1: return [fullA(p)]
        case 2: return [fullA(p), fullB(p)]
        case 3: return [fullA(p), fullB(p), fullC(p)]
        case 4: return [upperPower(p), lowerPower(p), upperHypertrophy, lowerHypertrophy(p)]
        case 5: return [upperPower(p), lowerPower(p), push, pull, legs(p)]
        default:
            return [push, pull, legs(p), push, pull, legs(p)].enumerated().map { index, template in
                var copy = template
                copy.title += index < 3 ? " A" : " B"
                return copy
            }
        }
    }

    public static func generate(liftingDays: Int, courtDays: Int, mode: GoalMode,
                                exerciseID: (String) -> UUID = { StableID.uuid("exercise", $0) }) -> [PlannedDay] {
        let lifting = max(0, min(6, liftingDays))
        let court = max(0, min(7 - lifting, courtDays))
        let performance = mode != .bulk
        let lifts = templates(liftingDays: lifting, performance: performance)
        let sequence = bestArrangement(liftRegions: lifts.map(\.region), courtDays: court)

        var liftIndex = 0
        var courtIndex = 0
        return sequence.enumerated().map { weekday, kind in
            switch kind {
            case .lift:
                let template = lifts[liftIndex]
                liftIndex += 1
                let exercises = template.exercises.map { item in
                    PlannedExercise(exerciseID: exerciseID(item.key), sets: item.sets, repLow: item.low,
                                    repHigh: item.high, restSeconds: restSeconds(repHigh: item.high, key: item.key))
                }
                return PlannedDay(weekday: weekday, dayType: .lifting, title: template.title,
                                  focus: template.focus, exercises: exercises)
            case .court:
                let block = courtIndex % 2 == 0 ? courtConditioning : courtSkills
                courtIndex += 1
                return PlannedDay(weekday: weekday, dayType: .conditioning, title: block.title,
                                  focus: "Court work at the Y", block: block)
            case .rest:
                return PlannedDay(weekday: weekday, dayType: .rest, title: "Recovery",
                                  focus: "Walk, mobility, sleep", block: mobility)
            }
        }
    }

    // MARK: - Arrangement

    enum Kind: Hashable { case lift, court, rest }

    /// Tries every ordering of lift/court/rest days and keeps the one that best spaces court days
    /// away from leg days and from each other, and breaks up long runs without rest.
    static func bestArrangement(liftRegions: [BodyRegion], courtDays: Int) -> [Kind] {
        let restDays = 7 - liftRegions.count - courtDays
        var best: [Kind] = []
        var bestScore = Double.infinity

        func score(_ sequence: [Kind]) -> Double {
            var regions: [BodyRegion?] = Array(repeating: nil, count: 7)
            var liftIndex = 0
            for (index, kind) in sequence.enumerated() where kind == .lift {
                regions[index] = liftRegions[liftIndex]
                liftIndex += 1
            }
            var cost = 0.0
            for index in 0..<7 {
                let next = (index + 1) % 7
                let a = sequence[index], b = sequence[next]
                if a == .court && b == .court { cost += 4 }
                if a == .lift && b == .court {
                    if regions[index] == .lower { cost += 2 }
                    if regions[index] == .full { cost += 1 }
                }
                if a == .court && b == .lift && regions[next] == .lower { cost += 1 }
                if a == .rest && b == .rest { cost += 1.5 }
                if a == .lift && b == .lift && regions[index] == regions[next] && regions[index] != .full { cost += 3 }
            }
            if restDays > 0 {
                // Longest circular run of training days.
                var run = 0, longest = 0
                for index in 0..<14 {
                    if sequence[index % 7] == .rest { run = 0 } else { run += 1; longest = max(longest, min(run, 7)) }
                }
                if longest > 3 { cost += Double(longest - 3) * 1.5 }
            }
            if sequence[5] == .court { cost -= 0.5 } // Saturday hoops
            if sequence[6] == .rest { cost -= 0.4 }  // Sunday off
            if sequence[0] == .lift { cost -= 0.2 }  // Monday lift
            return cost
        }

        func build(_ current: inout [Kind], lifts: Int, courts: Int, rests: Int) {
            if current.count == 7 {
                let value = score(current)
                if value < bestScore - 1e-9 {
                    bestScore = value
                    best = current
                }
                return
            }
            if lifts > 0 { current.append(.lift); build(&current, lifts: lifts - 1, courts: courts, rests: rests); current.removeLast() }
            if courts > 0 { current.append(.court); build(&current, lifts: lifts, courts: courts - 1, rests: rests); current.removeLast() }
            if rests > 0 { current.append(.rest); build(&current, lifts: lifts, courts: courts, rests: rests - 1); current.removeLast() }
        }

        var scratch: [Kind] = []
        build(&scratch, lifts: liftRegions.count, courts: courtDays, rests: max(0, restDays))
        return best
    }

    static func restSeconds(repHigh: Int, key: String) -> Int {
        if ["box_jump", "broad_jump", "med_ball_chest_pass", "med_ball_slam"].contains(key) { return 90 }
        switch repHigh {
        case ...6: return 180
        case ...10: return 120
        default: return 75
        }
    }

    // MARK: - Templates

    static func lowerPower(_ perf: Bool) -> Template {
        Template(title: "Lower — Power", focus: "Squat strength and pop", region: .lower,
                 exercises: (perf ? [("box_jump", 3, 3, 3)] : []) + [
                    ("back_squat", 4, 4, 6), ("romanian_deadlift", 3, 6, 8), ("bulgarian_split_squat", 3, 8, 10),
                    ("standing_calf_raise", 3, 10, 15), ("hanging_knee_raise", 3, 10, 15),
                 ])
    }

    static func upperPower(_ perf: Bool) -> Template {
        Template(title: "Upper — Power", focus: "Heavy press and row", region: .upper,
                 exercises: (perf ? [("med_ball_chest_pass", 3, 5, 5)] : []) + [
                    ("bench_press", 4, 4, 6), ("barbell_row", 4, 6, 8), ("overhead_press", 3, 6, 8),
                    ("pull_up", 3, 6, 10), ("db_curl", 2, 10, 12), ("triceps_pushdown", 2, 10, 12),
                 ])
    }

    static func lowerHypertrophy(_ perf: Bool) -> Template {
        Template(title: "Lower — Volume", focus: "Leg size and hamstring health", region: .lower,
                 exercises: (perf ? [("broad_jump", 3, 3, 3)] : []) + [
                    ("trap_bar_deadlift", 3, 5, 8), ("leg_press", 3, 10, 12), ("walking_lunge", 3, 10, 12),
                    ("leg_curl", 3, 10, 12), ("leg_extension", 2, 12, 15), ("seated_calf_raise", 3, 12, 15),
                 ])
    }

    static let upperHypertrophy = Template(
        title: "Upper — Volume", focus: "Chest, back and arms", region: .upper,
        exercises: [
            ("incline_db_press", 4, 8, 12), ("lat_pulldown", 4, 10, 12), ("seated_cable_row", 3, 10, 12),
            ("db_shoulder_press", 3, 8, 12), ("lateral_raise", 3, 12, 15), ("cable_fly", 2, 12, 15),
            ("hammer_curl", 3, 10, 12), ("overhead_triceps_extension", 3, 10, 12),
        ])

    static func fullA(_ perf: Bool) -> Template {
        Template(title: "Full Body A", focus: "Squat + bench", region: .full,
                 exercises: (perf ? [("box_jump", 3, 3, 3)] : []) + [
                    ("back_squat", 3, 5, 8), ("bench_press", 3, 6, 8), ("chest_supported_row", 3, 8, 10),
                    ("romanian_deadlift", 3, 8, 10), ("pallof_press", 3, 10, 12),
                 ])
    }

    static func fullB(_ perf: Bool) -> Template {
        Template(title: "Full Body B", focus: "Hinge + press", region: .full,
                 exercises: (perf ? [("broad_jump", 3, 3, 3)] : []) + [
                    ("trap_bar_deadlift", 3, 4, 6), ("overhead_press", 3, 6, 8), ("lat_pulldown", 3, 10, 12),
                    ("walking_lunge", 3, 10, 12), ("db_curl", 2, 10, 12), ("triceps_pushdown", 2, 10, 12),
                 ])
    }

    static func fullC(_ perf: Bool) -> Template {
        Template(title: "Full Body C", focus: "Volume + glutes", region: .full,
                 exercises: (perf ? [("med_ball_slam", 3, 5, 5)] : []) + [
                    ("leg_press", 3, 10, 12), ("incline_db_press", 3, 8, 12), ("seated_cable_row", 3, 10, 12),
                    ("hip_thrust", 3, 8, 10), ("face_pull", 3, 12, 15), ("cable_crunch", 3, 12, 15),
                 ])
    }

    static let push = Template(
        title: "Push", focus: "Chest, shoulders, triceps", region: .upper,
        exercises: [
            ("bench_press", 4, 6, 8), ("overhead_press", 3, 6, 8), ("incline_db_press", 3, 8, 12),
            ("lateral_raise", 3, 12, 15), ("dips", 3, 8, 12), ("triceps_pushdown", 3, 10, 12),
        ])

    static let pull = Template(
        title: "Pull", focus: "Back and biceps", region: .upper,
        exercises: [
            ("pull_up", 4, 6, 10), ("barbell_row", 4, 6, 8), ("seated_cable_row", 3, 10, 12),
            ("face_pull", 3, 12, 15), ("db_curl", 3, 10, 12), ("hammer_curl", 2, 10, 12),
        ])

    static func legs(_ perf: Bool) -> Template {
        Template(title: "Legs", focus: "Quads, hamstrings, calves", region: .lower,
                 exercises: (perf ? [("box_jump", 3, 3, 3)] : []) + [
                    ("back_squat", 4, 6, 8), ("romanian_deadlift", 3, 8, 10), ("leg_press", 3, 10, 12),
                    ("leg_curl", 3, 10, 12), ("standing_calf_raise", 4, 10, 15), ("hanging_knee_raise", 3, 10, 15),
                 ])
    }

    static let courtConditioning = SessionBlock(
        title: "Court Conditioning",
        items: [
            "Dynamic warm-up + form shooting (10 min)",
            "Full-court layups, 3 × 2 min",
            "Defensive slides, 6 × 30 s",
            "Suicides, 6 reps (45 s rest)",
            "2 free throws after every sprint",
        ],
        minutes: 60)

    static let courtSkills = SessionBlock(
        title: "Skills + Pickup",
        items: [
            "Ball-handling series (10 min)",
            "Spot shooting, 100 makes",
            "Pickup or 1-on-1, 30–40 min",
            "17s, 3 reps to finish",
        ],
        minutes: 75)

    static let mobility = SessionBlock(
        title: "Recovery + Mobility",
        items: [
            "20–30 min easy walk or bike",
            "Hips and ankles mobility (10 min)",
            "Foam roll quads, calves, upper back",
            "Stretch hamstrings and hip flexors",
        ],
        minutes: 30)
}
