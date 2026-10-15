import BulkCore
import Foundation
import SwiftData
import Testing
@testable import BulkBoard

@Suite("Training flows")
@MainActor
struct TrainingFlowTests {
    func firstLiftingDay(_ context: ModelContext) throws -> PlannedDay {
        try #require(context.workoutPlan?.days.first { $0.dayType == .lifting })
    }

    @Test func startingASessionPrefillsThePlan() throws {
        let context = try makeContext()
        onboard(context)
        let day = try firstLiftingDay(context)
        let session = TrainingActions.startSession(from: day, context: context)
        #expect(session.sets.count == day.exercises.map(\.sets).reduce(0, +))
        #expect(session.sets.allSatisfy { !$0.isDone })
        #expect(TrainingActions.activeSession(context) === session)
    }

    @Test func prDetectionAndOverloadAcrossSessions() throws {
        let context = try makeContext()
        onboard(context)
        let bench = SeedLibrary.exerciseID("bench_press")

        // Session 1: 135 × 6 for three sets, the top of a 4–6 range.
        let first = TrainingActions.startSession(from: nil, on: .now.adding(days: -3), context: context)
        first.sets = (0..<3).map { _ in SessionSet(exerciseID: bench, reps: 6, weightKg: Units.kg(fromLb: 135)) }
        for set in first.sets { #expect(TrainingActions.setDone(set.id, done: true, in: first, context: context).isEmpty) }
        TrainingActions.finish(first, context: context)
        #expect(first.isCompleted)
        #expect(first.prCount == 0) // first time is a baseline

        let advice = TrainingActions.suggestion(for: bench, repLow: 4, repHigh: 6,
                                                sessions: TrainingActions.completedSessions(context), units: .imperial)
        #expect(advice.kind == .addWeight)
        #expect(advice.weight == 140)
        #expect(advice.message.contains("135 × 6"))

        // Session 2: 140 × 5 is a new heaviest and e1RM.
        let second = TrainingActions.startSession(from: nil, context: context)
        second.sets = [SessionSet(exerciseID: bench, reps: 5, weightKg: Units.kg(fromLb: 140)),
                       SessionSet(exerciseID: bench, reps: 5, weightKg: Units.kg(fromLb: 140))]
        let kinds = TrainingActions.setDone(second.sets[0].id, done: true, in: second, context: context)
        #expect(kinds.contains(.heaviestWeight))
        #expect(kinds.contains(.bestE1RM))
        // The identical second set isn't another PR.
        #expect(TrainingActions.setDone(second.sets[1].id, done: true, in: second, context: context).isEmpty)
        TrainingActions.finish(second, context: context)
        #expect(second.prCount == 1)
    }

    @Test func finishDropsUnloggedSets() throws {
        let context = try makeContext()
        onboard(context)
        let session = TrainingActions.startSession(from: try firstLiftingDay(context), context: context)
        let firstID = session.sets[0].id
        TrainingActions.setDone(firstID, done: true, in: session, context: context)
        TrainingActions.finish(session, context: context)
        #expect(session.sets.count == 1)
        #expect(session.sets[0].id == firstID)
        #expect(TrainingActions.activeSession(context) == nil)
    }

    @Test func courtSessionsCarryLoad() throws {
        let context = try makeContext()
        onboard(context)
        TrainingActions.logCourtSession(date: .now, kind: .pickup, minutes: 75, rpe: 8, notes: "", context: context)
        let record = try #require(context.fetchAll(CourtSessionRecord.self).first)
        #expect(record.log.load == 600)
    }

    @Test func regeneratingFollowsTrainingDays() throws {
        let context = try makeContext()
        let profile = onboard(context)
        profile.liftingDays = 5
        profile.courtDays = 1
        TrainingActions.regeneratePlan(for: profile, context: context)
        let plan = try #require(context.workoutPlan)
        #expect(context.fetchAll(WorkoutPlanRecord.self).count == 1)
        #expect(plan.days.filter { $0.dayType == .lifting }.count == 5)
        #expect(plan.days.filter { $0.dayType == .conditioning }.count == 1)
    }
}

@Suite("Demo data")
@MainActor
struct DemoDataTests {
    @Test func loadsEveryScreenAndWipesClean() throws {
        let context = try makeContext()
        SeedService.ensureBuiltIns(context)
        let builtInFoods = context.fetchAll(FoodRecord.self).count
        DemoData.load(into: context)

        #expect(context.profile?.isDemo == true)
        #expect(context.fetchAll(WeightRecord.self).count > 40)
        let sessions = TrainingActions.completedSessions(context)
        #expect(sessions.count >= 30)
        #expect(sessions.map(\.prCount).reduce(0, +) > 10)
        #expect(context.fetchAll(CourtSessionRecord.self).count >= 15)
        #expect(context.fetchAll(IntakeRecord.self).count > 50)
        #expect(!context.fetchAll(GroceryItemRecord.self).isEmpty)
        #expect(DemoData.hasDemoData(context))

        DemoData.wipe(context)
        #expect(context.profile == nil)
        #expect(context.fetchAll(WeightRecord.self).isEmpty)
        #expect(context.fetchAll(WorkoutSessionRecord.self).isEmpty)
        #expect(context.fetchAll(IntakeRecord.self).isEmpty)
        #expect(context.fetchAll(FoodRecord.self).count == builtInFoods, "Built-in foods survive a demo wipe")
    }
}
