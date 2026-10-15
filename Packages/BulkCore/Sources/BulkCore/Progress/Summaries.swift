import Foundation

public struct DayAdherence: Sendable, Hashable {
    public var day: Date
    public var eaten: Macros
    public var target: Macros

    public init(day: Date, eaten: Macros, target: Macros) {
        self.day = day
        self.eaten = eaten
        self.target = target
    }

    public var kcalPercent: Double { target.kcal > 0 ? eaten.kcal / target.kcal : 0 }
    public var proteinPercent: Double { target.protein > 0 ? eaten.protein / target.protein : 0 }
    public var isHit: Bool { Adherence.isHit(eaten: eaten, target: target) }
}

public enum Adherence {
    /// A day counts as "hit" when calories land within ±10% and protein reaches 90% of target.
    public static func isHit(eaten: Macros, target: Macros, kcalTolerance: Double = 0.10, proteinFloor: Double = 0.90) -> Bool {
        guard target.kcal > 0 else { return false }
        let kcalRatio = eaten.kcal / target.kcal
        let proteinOK = target.protein <= 0 || eaten.protein >= target.protein * proteinFloor
        return abs(kcalRatio - 1) <= kcalTolerance + 1e-9 && proteinOK
    }
}

public enum Streaks {
    /// Consecutive hit days ending today. If today isn't hit yet, the streak can still be alive from yesterday.
    public static func current(hitDays: Set<Date>, today: Date, calendar: Calendar = .bulk) -> Int {
        let days = Set(hitDays.map { calendar.startOfDay(for: $0) })
        var cursor = calendar.startOfDay(for: today)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    public static func longest(hitDays: Set<Date>, calendar: Calendar = .bulk) -> Int {
        let days = hitDays.map { calendar.startOfDay(for: $0) }.sorted()
        var longest = 0, run = 0
        var previous: Date?
        for day in days {
            if let previous, WeekMath.daysBetween(previous, day, calendar: calendar) == 1 { run += 1 } else { run = 1 }
            longest = max(longest, run)
            previous = day
        }
        return longest
    }
}

public struct WorkoutDigest: Sendable, Hashable {
    public var date: Date
    public var volumeKg: Double
    public var prs: Int

    public init(date: Date, volumeKg: Double, prs: Int) {
        self.date = date
        self.volumeKg = volumeKg
        self.prs = prs
    }
}

public struct WeeklySummary: Sendable, Equatable {
    public var weekStart: Date
    public var daysHitMacros: Int
    public var daysLogged: Int
    public var workoutsCompleted: Int
    public var workoutsPlanned: Int
    public var courtSessions: Int
    public var courtLoad: Int
    public var liftingVolumeKg: Double
    public var prs: Int
    /// Change in 7-day average weight over the week.
    public var weightChangeKg: Double?
}

public enum Summaries {
    public static func weekly(weekStart: Date, adherence: [DayAdherence], workouts: [WorkoutDigest],
                              plannedWorkouts: Int, court: [CourtSessionLog], weights: [WeightPoint],
                              calendar: Calendar = .bulk) -> WeeklySummary {
        let start = calendar.startOfDay(for: weekStart)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        func inWeek(_ date: Date) -> Bool { date >= start && date < end }

        let days = adherence.filter { inWeek($0.day) && $0.eaten.kcal > 0 }
        let weekWorkouts = workouts.filter { inWeek($0.date) }
        let weekCourt = court.filter { inWeek($0.date) }

        let averaged = Trend.movingAverage(weights, calendar: calendar)
        let endValue = averaged.last { $0.date < end }
        let startValue = averaged.last { $0.date < start }
        var change: Double?
        if let endValue, let startValue, inWeek(endValue.date) { change = endValue.kg - startValue.kg }

        return WeeklySummary(
            weekStart: start,
            daysHitMacros: days.filter(\.isHit).count,
            daysLogged: days.count,
            workoutsCompleted: weekWorkouts.count,
            workoutsPlanned: plannedWorkouts,
            courtSessions: weekCourt.count,
            courtLoad: weekCourt.map(\.load).reduce(0, +),
            liftingVolumeKg: weekWorkouts.map(\.volumeKg).reduce(0, +),
            prs: weekWorkouts.map(\.prs).reduce(0, +),
            weightChangeKg: change)
    }

    /// Working-set tonnage per week (week start → kg).
    public static func weeklyVolume(_ sets: [LoggedSet], calendar: Calendar = .bulk) -> [(weekStart: Date, kg: Double)] {
        let grouped = Dictionary(grouping: sets.filter { !$0.isWarmup }) { WeekMath.startOfWeek($0.date, calendar: calendar) }
        return grouped.map { ($0.key, $0.value.map(\.volumeKg).reduce(0, +)) }.sorted { $0.weekStart < $1.weekStart }
    }

    /// Best estimated 1RM per session day for one exercise.
    public static func e1RMHistory(_ sets: [LoggedSet], exerciseID: UUID, calendar: Calendar = .bulk) -> [(date: Date, kg: Double)] {
        let relevant = sets.filter { $0.exerciseID == exerciseID && !$0.isWarmup && $0.reps <= Strength.maxRepsForE1RM }
        let grouped = Dictionary(grouping: relevant) { calendar.startOfDay(for: $0.date) }
        return grouped.compactMap { day, daySets in
            let best = daySets.map { Strength.estimated1RM(weight: $0.weightKg, reps: $0.reps) }.max() ?? 0
            return best > 0 ? (day, best) : nil
        }.sorted { $0.date < $1.date }
    }
}

/// Light gamification: XP for showing up, levels that get a little longer each time.
public enum XP {
    public static let perMacroDay = 50
    public static let perWorkout = 100
    public static let perCourtSession = 60
    public static let perPR = 25
    public static let perWeighIn = 10

    public static func total(macroDays: Int, workouts: Int, courtSessions: Int, prs: Int, weighIns: Int) -> Int {
        macroDays * perMacroDay + workouts * perWorkout + courtSessions * perCourtSession + prs * perPR + weighIns * perWeighIn
    }

    /// XP needed to go from `level` to `level + 1`.
    public static func size(ofLevel level: Int) -> Int { 300 + 100 * (level - 1) }

    public static func level(for xp: Int) -> (level: Int, into: Int, needed: Int) {
        var level = 1
        var remaining = max(0, xp)
        while remaining >= size(ofLevel: level) {
            remaining -= size(ofLevel: level)
            level += 1
        }
        return (level, remaining, size(ofLevel: level))
    }
}
