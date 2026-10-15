import BulkCore
import Foundation

/// Everything the dashboard, progress screen and sidebar need, computed in one pass from records.
struct ProgressStats {
    var weights: [WeightPoint]
    var trend: [WeightPoint]
    var projection: WeightProjection?
    var adherence: [DayAdherence]
    var hitDays: Set<Date>
    var currentStreak: Int
    var longestStreak: Int
    var weeklyVolume: [(weekStart: Date, kg: Double)]
    var weeklyCourtLoad: [(weekStart: Date, load: Int)]
    var thisWeek: WeeklySummary
    var lastWeek: WeeklySummary
    var xp: Int
    var totalPRs: Int

    var level: (level: Int, into: Int, needed: Int) { XP.level(for: xp) }
    var latestTrendKg: Double? { trend.last?.kg }

    func adherence(on day: Date) -> DayAdherence? { adherence.first { $0.day == day.dayStart } }
}

enum ProgressService {
    static func stats(profile: ProfileRecord, weights: [WeightRecord], intake: [IntakeRecord],
                      sessions: [WorkoutSessionRecord], court: [CourtSessionRecord], plan: WorkoutPlanRecord?,
                      today: Date = .now) -> ProgressStats {
        let points = weights.map(\.point).sorted { $0.date < $1.date }
        let trend = Trend.movingAverage(points)
        let projection = Trend.project(points, goalKg: profile.goalWeightKg, targetDate: profile.targetDate, today: today)
        let snapshot = profile.targets(latestWeightKg: points.last?.kg, today: today)

        // Daily intake vs that day's target.
        let eatenByDay = Dictionary(grouping: intake, by: { $0.day.dayStart }).mapValues { $0.map(\.macros).sum() }
        let adherence = eatenByDay.keys.sorted().map { day in
            DayAdherence(day: day, eaten: eatenByDay[day] ?? .zero,
                         target: snapshot.target(for: TrainingActions.dayType(for: day, plan: plan)))
        }
        let hitDays = Set(adherence.filter(\.isHit).map(\.day))

        let completed = sessions.filter(\.isCompleted)
        let allSets = completed.flatMap(\.loggedSets)
        let digests = completed.map { WorkoutDigest(date: $0.date, volumeKg: $0.volumeKg, prs: $0.prCount) }
        let courtLogs = court.map(\.log)
        let plannedWorkouts = plan?.days.filter { $0.dayType == .lifting }.count ?? profile.liftingDays

        let weekStart = today.weekStart
        let courtByWeek = Dictionary(grouping: courtLogs) { $0.date.weekStart }
            .map { (weekStart: $0.key, load: $0.value.map(\.load).reduce(0, +)) }
            .sorted { $0.weekStart < $1.weekStart }
        let totalPRs = completed.map(\.prCount).reduce(0, +)

        return ProgressStats(
            weights: points,
            trend: trend,
            projection: projection,
            adherence: adherence,
            hitDays: hitDays,
            currentStreak: Streaks.current(hitDays: hitDays, today: today),
            longestStreak: Streaks.longest(hitDays: hitDays),
            weeklyVolume: Summaries.weeklyVolume(allSets),
            weeklyCourtLoad: courtByWeek,
            thisWeek: Summaries.weekly(weekStart: weekStart, adherence: adherence, workouts: digests,
                                       plannedWorkouts: plannedWorkouts, court: courtLogs, weights: points),
            lastWeek: Summaries.weekly(weekStart: weekStart.adding(days: -7), adherence: adherence, workouts: digests,
                                       plannedWorkouts: plannedWorkouts, court: courtLogs, weights: points),
            xp: XP.total(macroDays: hitDays.count, workouts: completed.count, courtSessions: court.count,
                         prs: totalPRs, weighIns: points.count),
            totalPRs: totalPRs)
    }
}
