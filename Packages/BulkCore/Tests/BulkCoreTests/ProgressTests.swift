import Foundation
import Testing
@testable import BulkCore

@Suite("Trend and projection")
struct TrendTests {
    func points(_ values: [Double], start: Int = 0) -> [WeightPoint] {
        values.enumerated().map { WeightPoint(date: Fixture.day(start + $0.offset), kg: $0.element) }
    }

    @Test func movingAverageOverWindow() {
        let averaged = Trend.movingAverage(points([80, 81, 82, 83, 84, 85, 86, 87]))
        #expect(averaged[2].kg == 81)  // mean(80, 81, 82)
        #expect(averaged[6].kg == 83)  // mean(80…86)
        #expect(averaged[7].kg == 84)  // window slides
    }

    @Test func movingAverageSkipsGapsHonestly() {
        let sparse = [WeightPoint(date: Fixture.day(0), kg: 80), WeightPoint(date: Fixture.day(10), kg: 90)]
        #expect(Trend.movingAverage(sparse).last?.kg == 90)
    }

    @Test func movingAverageOfConstantIsConstant() {
        #expect(Trend.movingAverage(points(Array(repeating: 82.5, count: 20))).allSatisfy { $0.kg == 82.5 })
    }

    @Test func linearFitIsExactOnALine() {
        let line = (0..<10).map { WeightPoint(date: Fixture.day($0), kg: 80 + 0.1 * Double($0)) }
        let fit = Trend.linearFit(line, origin: Fixture.today)!
        #expect(abs(fit.slopePerDay - 0.1) < 1e-9)
        #expect(abs(fit.intercept - 80) < 1e-9)
    }

    @Test func projectsGoalDate() {
        // Gaining 0.1 kg/day over the last four weeks, ending today at 82.8.
        let history = (0...28).map { WeightPoint(date: Fixture.day(-28 + $0), kg: 80 + 0.1 * Double($0)) }
        let projection = Trend.project(history, goalKg: 82.8 + 7, targetDate: Fixture.day(100), today: Fixture.today)!
        #expect(abs(projection.kgPerWeek - 0.7) < 1e-9)
        #expect(abs(projection.currentTrendKg - 82.8) < 1e-9)
        #expect(projection.projectedGoalDate == Fixture.day(70))
        #expect(abs(projection.projectedAtTargetKg! - 92.8) < 1e-9)
        #expect(projection.line.first?.date == Fixture.today)
    }

    @Test func noGoalDateWhenTrendingAway() {
        let losing = (0...14).map { WeightPoint(date: Fixture.day(-14 + $0), kg: 85 - 0.05 * Double($0)) }
        let projection = Trend.project(losing, goalKg: 90, targetDate: Fixture.day(60), today: Fixture.today)!
        #expect(projection.projectedGoalDate == nil)
        #expect(projection.kgPerWeek < 0)
    }

    @Test func needsEnoughData() {
        #expect(Trend.project(points([80, 80.2], start: -1), goalKg: 85, targetDate: Fixture.day(30), today: Fixture.today) == nil)
        // Three points but all within two days.
        #expect(Trend.project(points([80, 80.1, 80.2], start: -2), goalKg: 85, targetDate: Fixture.day(30), today: Fixture.today) == nil)
    }
}

@Suite("Adherence, streaks, summaries, XP")
struct SummaryTests {
    let target = Macros(kcal: 3000, protein: 180, carbs: 380, fat: 85)

    @Test func hitRules() {
        #expect(Adherence.isHit(eaten: Macros(kcal: 2750, protein: 165), target: target))
        #expect(Adherence.isHit(eaten: Macros(kcal: 3300, protein: 200), target: target))
        #expect(!Adherence.isHit(eaten: Macros(kcal: 2650, protein: 190), target: target))
        #expect(!Adherence.isHit(eaten: Macros(kcal: 3000, protein: 150), target: target))
        #expect(!Adherence.isHit(eaten: Macros(kcal: 3000, protein: 180), target: .zero))
    }

    @Test func currentStreakSurvivesUntilTodayIsLogged() {
        let hits: Set<Date> = [Fixture.day(-1), Fixture.day(-2), Fixture.day(-3), Fixture.day(-5)]
        #expect(Streaks.current(hitDays: hits, today: Fixture.today) == 3)
        #expect(Streaks.current(hitDays: hits.union([Fixture.today]), today: Fixture.today) == 4)
        #expect(Streaks.current(hitDays: [Fixture.day(-2)], today: Fixture.today) == 0)
    }

    @Test func longestStreak() {
        let hits: Set<Date> = [Fixture.day(1), Fixture.day(2), Fixture.day(3), Fixture.day(5), Fixture.day(6)]
        #expect(Streaks.longest(hitDays: hits) == 3)
        #expect(Streaks.longest(hitDays: []) == 0)
    }

    @Test func weeklySummary() {
        let week = Fixture.today
        let adherence = [
            DayAdherence(day: Fixture.day(0), eaten: Macros(kcal: 3000, protein: 185), target: target),
            DayAdherence(day: Fixture.day(1), eaten: Macros(kcal: 2500, protein: 185), target: target),
            DayAdherence(day: Fixture.day(2), eaten: Macros(kcal: 3050, protein: 175), target: target),
            DayAdherence(day: Fixture.day(3), eaten: .zero, target: target),
            DayAdherence(day: Fixture.day(8), eaten: Macros(kcal: 3000, protein: 185), target: target),
        ]
        let workouts = [WorkoutDigest(date: Fixture.day(0), volumeKg: 8000, prs: 2), WorkoutDigest(date: Fixture.day(2), volumeKg: 7000, prs: 0),
                        WorkoutDigest(date: Fixture.day(-1), volumeKg: 9000, prs: 1)]
        let court = [CourtSessionLog(date: Fixture.day(3), kind: .pickup, minutes: 60, rpe: 8)]
        let weights = (-7...6).map { WeightPoint(date: Fixture.day($0), kg: 80 + 0.05 * Double($0 + 7)) }

        let summary = Summaries.weekly(weekStart: week, adherence: adherence, workouts: workouts, plannedWorkouts: 4,
                                       court: court, weights: weights)
        #expect(summary.daysHitMacros == 2)
        #expect(summary.daysLogged == 3)
        #expect(summary.workoutsCompleted == 2)
        #expect(summary.liftingVolumeKg == 15000)
        #expect(summary.prs == 2)
        #expect(summary.courtSessions == 1)
        #expect(summary.courtLoad == 480)
        #expect(abs(summary.weightChangeKg! - 0.35) < 1e-9)
    }

    @Test func weeklyVolumeAndE1RMHistory() {
        let bench = StableID.uuid("exercise", "bench_press")
        let sets = [
            LoggedSet(exerciseID: bench, date: Fixture.day(0), reps: 5, weightKg: 100),
            LoggedSet(exerciseID: bench, date: Fixture.day(0), reps: 5, weightKg: 60, isWarmup: true),
            LoggedSet(exerciseID: bench, date: Fixture.day(2), reps: 3, weightKg: 105),
            LoggedSet(exerciseID: bench, date: Fixture.day(7), reps: 8, weightKg: 90),
        ]
        let volume = Summaries.weeklyVolume(sets)
        #expect(volume.map(\.kg) == [815, 720])
        let history = Summaries.e1RMHistory(sets, exerciseID: bench)
        #expect(history.count == 3)
        #expect(abs(history[0].kg - 116.6667) < 1e-3)
    }

    @Test func xpLevels() {
        #expect(XP.level(for: 0) == (1, 0, 300))
        #expect(XP.level(for: 300) == (2, 0, 400))
        #expect(XP.level(for: 750) == (3, 50, 500))
        #expect(XP.total(macroDays: 2, workouts: 1, courtSessions: 1, prs: 2, weighIns: 3) == 340)
    }
}

@Suite("Formatting and week math")
struct SupportTests {
    @Test func numbers() {
        #expect(Fmt.int(3416.4) == "3,416")
        #expect(Fmt.int(-1_234_567) == "-1,234,567")
        #expect(Fmt.int(999) == "999")
        #expect(Fmt.number(135.0) == "135")
        #expect(Fmt.number(2.5) == "2.5")
        #expect(Fmt.number(0.75, maxDecimals: 2) == "0.75")
        #expect(Fmt.signed(375) == "+375")
        #expect(Fmt.signed(-250) == "-250")
    }

    @Test func weekStartsMonday() {
        let thursday = Fixture.day(3)
        #expect(WeekMath.startOfWeek(thursday) == Fixture.today)
        #expect(WeekMath.weekdayIndex(Fixture.today) == 0)
        #expect(WeekMath.weekdayIndex(Fixture.day(6)) == 6)
        #expect(WeekMath.days(ofWeekStarting: Fixture.today).count == 7)
    }

    @Test func stableIDsAreStable() {
        #expect(StableID.uuid("food", "whole_milk") == StableID.uuid("food", "whole_milk"))
        #expect(StableID.uuid("food", "whole_milk") != StableID.uuid("food", "skim_milk"))
    }

    @Test func unitRoundTrip() {
        #expect(abs(Units.lb(fromKg: Units.kg(fromLb: 135)) - 135) < 1e-9)
        #expect(abs(Units.cm(fromInches: 74) - 187.96) < 1e-9)
    }
}
