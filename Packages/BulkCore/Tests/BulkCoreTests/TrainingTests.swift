import Foundation
import Testing
@testable import BulkCore

@Suite("PR detection")
struct PRTests {
    let bench = StableID.uuid("exercise", "bench_press")
    let squat = StableID.uuid("exercise", "back_squat")
    let pullUp = StableID.uuid("exercise", "pull_up")

    func set(_ id: UUID, _ weight: Double, _ reps: Int, day: Int = 0, warmup: Bool = false) -> LoggedSet {
        LoggedSet(exerciseID: id, date: Fixture.day(day), reps: reps, weightKg: weight, isWarmup: warmup)
    }

    @Test func epley() {
        #expect(abs(Strength.estimated1RM(weight: 100, reps: 5) - 116.6667) < 1e-3)
        #expect(Strength.estimated1RM(weight: 100, reps: 1) == 100)
        #expect(Strength.estimated1RM(weight: 0, reps: 5) == 0)
    }

    var history: [LoggedSet] { [set(bench, 100, 5, day: -7), set(bench, 105, 3, day: -3), set(squat, 200, 5, day: -3)] }

    @Test func heaviestSingle() {
        #expect(Strength.detectPRs(set(bench, 110, 1), history: history) == [.heaviestWeight])
    }

    @Test func repsAndE1RM() {
        #expect(Strength.detectPRs(set(bench, 100, 7), history: history) == [.bestE1RM, .repPR])
    }

    @Test func noPRWhenBelowBest() {
        #expect(Strength.detectPRs(set(bench, 95, 5), history: history).isEmpty)
    }

    @Test func firstLogIsBaselineNotPR() {
        #expect(Strength.detectPRs(set(pullUp, 20, 8), history: history).isEmpty)
    }

    @Test func warmupsNeverPR() {
        #expect(Strength.detectPRs(set(bench, 150, 1, warmup: true), history: history).isEmpty)
        // Warm-up history doesn't count as a baseline either.
        #expect(Strength.detectPRs(set(pullUp, 20, 8), history: [set(pullUp, 30, 10, day: -1, warmup: true)]).isEmpty)
    }

    @Test func bodyweightRepPR() {
        let prior = [set(pullUp, 0, 8, day: -2)]
        #expect(Strength.detectPRs(set(pullUp, 0, 10), history: prior) == [.repPR])
    }

    @Test func highRepSetsSkipE1RM() {
        let prior = [set(bench, 60, 10, day: -2)]
        #expect(!Strength.detectPRs(set(bench, 60, 20), history: prior).contains(.bestE1RM))
    }

    @Test func sameSessionSetsCount() {
        // Second identical set in a session isn't a fresh PR once the first is in history.
        let first = set(bench, 110, 1)
        #expect(Strength.detectPRs(set(bench, 110, 1), history: history + [first]).isEmpty)
    }
}

@Suite("Progressive overload")
struct OverloadTests {
    @Test func topOfRangeAddsWeight() {
        let suggestion = OverloadAdvisor.suggest(lastSession: [(8, 135), (8, 135), (8, 135)], repLow: 6, repHigh: 8, increment: 5, unit: "lb")
        #expect(suggestion.kind == .addWeight)
        #expect(suggestion.weight == 140)
        #expect(suggestion.message == "Last time 135 × 8 lb. Try 140 today.")
    }

    @Test func insideRangeAddsReps() {
        let suggestion = OverloadAdvisor.suggest(lastSession: [(8, 135), (7, 135), (6, 135)], repLow: 6, repHigh: 8, increment: 5, unit: "lb")
        #expect(suggestion.kind == .addReps)
        #expect(suggestion.weight == 135)
        #expect(suggestion.targetReps == 8)
    }

    @Test func belowRangeRepeatsThenDeloads() {
        let sets: [(reps: Int, weight: Double)] = [(5, 135), (4, 135)]
        #expect(OverloadAdvisor.suggest(lastSession: sets, repLow: 6, repHigh: 8, increment: 5, unit: "lb").kind == .repeatWeight)
        let deload = OverloadAdvisor.suggest(lastSession: sets, repLow: 6, repHigh: 8, increment: 5, unit: "lb", missedSessions: 2)
        #expect(deload.kind == .deload)
        #expect(deload.weight == 120)
    }

    @Test func onlyTopWeightSetsCount() {
        // Back-off sets at lighter weight don't hold back progression.
        let suggestion = OverloadAdvisor.suggest(lastSession: [(8, 135), (8, 135), (5, 115)], repLow: 6, repHigh: 8, increment: 5, unit: "lb")
        #expect(suggestion.kind == .addWeight)
    }

    @Test func firstTimeAndBodyweight() {
        #expect(OverloadAdvisor.suggest(lastSession: [], repLow: 8, repHigh: 12, increment: 5, unit: "lb").kind == .firstTime)
        let bodyweight = OverloadAdvisor.suggest(lastSession: [(9, 0)], repLow: 6, repHigh: 10, increment: 5, unit: "lb")
        #expect(bodyweight.targetReps == 10)
    }

    @Test func metricIncrementRounding() {
        let suggestion = OverloadAdvisor.suggest(lastSession: [(5, 61.2), (5, 61.2)], repLow: 3, repHigh: 5, increment: 2.5, unit: "kg")
        #expect(suggestion.weight == 62.5)
    }
}

@Suite("Weekly split generator")
struct SplitTests {
    func types(_ days: [PlannedDay]) -> [DayType] { days.map(\.dayType) }

    @Test(arguments: [(2, 2), (3, 2), (4, 2), (5, 2), (6, 1), (4, 3), (0, 2), (3, 0)])
    func countsMatchRequest(lifting: Int, court: Int) {
        let days = SplitGenerator.generate(liftingDays: lifting, courtDays: court, mode: .bulkPerformance)
        #expect(days.count == 7)
        #expect(days.map(\.weekday) == Array(0..<7))
        #expect(days.filter { $0.dayType == .lifting }.count == lifting)
        #expect(days.filter { $0.dayType == .conditioning }.count == court)
        #expect(days.filter { $0.dayType == .rest }.count == 7 - lifting - court)
    }

    @Test func defaultWeekSpacesCourtDays() {
        let days = SplitGenerator.generate(liftingDays: 4, courtDays: 2, mode: .bulkPerformance)
        for index in 0..<7 {
            let today = days[index], tomorrow = days[(index + 1) % 7]
            #expect(!(today.dayType == .conditioning && tomorrow.dayType == .conditioning))
            #expect(!(today.title.hasPrefix("Lower") && tomorrow.dayType == .conditioning), "Leg day right before court: \(today.title)")
        }
    }

    @Test func clampsWhenOverbooked() {
        let days = SplitGenerator.generate(liftingDays: 9, courtDays: 5, mode: .bulk)
        #expect(days.filter { $0.dayType == .lifting }.count == 6)
        #expect(days.filter { $0.dayType == .conditioning }.count == 1)
    }

    @Test func performanceModeAddsPlyos() {
        let box = StableID.uuid("exercise", "box_jump")
        let perf = SplitGenerator.generate(liftingDays: 4, courtDays: 2, mode: .bulkPerformance)
        let bulk = SplitGenerator.generate(liftingDays: 4, courtDays: 2, mode: .bulk)
        #expect(perf.contains { $0.exercises.contains { $0.exerciseID == box } })
        #expect(!bulk.contains { $0.exercises.contains { $0.exerciseID == box } })
    }

    @Test func gameAndRestDaysCarryBlocks() {
        let days = SplitGenerator.generate(liftingDays: 4, courtDays: 2, mode: .bulkPerformance)
        #expect(days.filter { $0.dayType != .lifting }.allSatisfy { $0.block != nil && $0.exercises.isEmpty })
        #expect(days.filter { $0.dayType == .lifting }.allSatisfy { !$0.exercises.isEmpty })
    }

    @Test func deterministic() {
        #expect(types(SplitGenerator.generate(liftingDays: 5, courtDays: 2, mode: .bulk))
            == types(SplitGenerator.generate(liftingDays: 5, courtDays: 2, mode: .bulk)))
    }
}
