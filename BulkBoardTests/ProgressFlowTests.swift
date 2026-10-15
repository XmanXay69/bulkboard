import BulkCore
import Foundation
import SwiftData
import Testing
@testable import BulkBoard

@Suite("Progress stats")
@MainActor
struct ProgressFlowTests {
    func stats(_ context: ModelContext) throws -> ProgressStats {
        let profile = try #require(context.profile)
        return ProgressService.stats(profile: profile, weights: context.fetchAll(WeightRecord.self),
                                     intake: context.fetchAll(IntakeRecord.self),
                                     sessions: context.fetchAll(WorkoutSessionRecord.self),
                                     court: context.fetchAll(CourtSessionRecord.self), plan: context.workoutPlan)
    }

    @Test func demoHistoryProducesTrendProjectionAndXP() throws {
        let context = try makeContext()
        SeedService.ensureBuiltIns(context)
        DemoData.load(into: context)
        let stats = try stats(context)
        #expect(stats.trend.count == stats.weights.count)
        let projection = try #require(stats.projection)
        #expect(projection.kgPerWeek > 0) // the demo is bulking
        #expect(projection.projectedGoalDate != nil)
        #expect(stats.longestStreak >= stats.currentStreak)
        #expect(stats.xp > 1000)
        #expect(!stats.weeklyVolume.isEmpty)
        #expect(!stats.weeklyCourtLoad.isEmpty)
        #expect(stats.lastWeek.workoutsCompleted >= 3)
    }

    @Test func eatingTheWholeDayHitsTargetAndStartsAStreak() throws {
        let context = try makeContext()
        onboard(context)
        let library = MealLibrary(context)
        let today = Date.now.dayStart
        for entry in MealPlanActions.entries(weekOf: today, context: context) where entry.day == today {
            IntakeActions.toggleEaten(entry, library: library, context: context)
        }
        let stats = try stats(context)
        let day = try #require(stats.adherence(on: today))
        #expect(day.isHit, "Auto-filled plan eaten in full should land on target")
        #expect(stats.currentStreak == 1)
        #expect(stats.thisWeek.daysHitMacros == 1)
    }

    @Test func freshProfileHasNoProjection() throws {
        let context = try makeContext()
        onboard(context)
        let stats = try stats(context)
        #expect(stats.projection == nil)
        #expect(stats.currentStreak == 0)
        #expect(stats.level.level == 1)
    }
}
