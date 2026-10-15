import BulkCore
import Foundation
import SwiftData
import Testing
@testable import BulkBoard

@MainActor
func makeContext() throws -> ModelContext {
    ModelContext(try Persistence.makeContainer(inMemory: true))
}

@MainActor
func onboard(_ context: ModelContext, configure: (OnboardingDraft) -> Void = { _ in }) -> ProfileRecord {
    let draft = OnboardingDraft()
    draft.age = 24
    draft.weight = 180
    draft.goalWeight = 192
    draft.liftingDays = 4
    draft.courtDays = 2
    configure(draft)
    return ProfileActions.completeOnboarding(draft, context: context)
}

@Suite("Onboarding and targets")
@MainActor
struct OnboardingFlowTests {
    @Test func completingOnboardingCreatesProfilePlanAndWeighIn() throws {
        let context = try makeContext()
        let profile = onboard(context)
        #expect(context.profile === profile)
        #expect(context.fetchAll(WeightRecord.self).count == 1)
        let plan = try #require(context.workoutPlan)
        #expect(plan.days.count == 7)
        #expect(plan.days.filter { $0.dayType == .lifting }.count == 4)
        #expect(plan.days.filter { $0.dayType == .conditioning }.count == 2)
    }

    @Test func targetsUseLatestWeighIn() throws {
        let context = try makeContext()
        let profile = onboard(context)
        let before = profile.targets(latestWeightKg: context.latestWeightKg).result.daily
        context.insert(WeightRecord(date: .now.adding(days: 1), weightKg: Units.kg(fromLb: 190)))
        let after = profile.targets(latestWeightKg: context.latestWeightKg).result.daily
        #expect(after.protein > before.protein)
        #expect(after.kcal > before.kcal)
    }

    @Test func metricDraftConvertsCleanly() {
        let draft = OnboardingDraft()
        draft.weight = 180
        draft.heightFeet = 6
        draft.heightInches = 0
        draft.unitSystem = .metric
        #expect(abs(draft.weight - 81.6) < 0.05)
        #expect(draft.heightCm == 183)
        #expect(abs(draft.weightKg - 81.6) < 0.05)
    }

    @Test func dayTargetOverridesRoundTrip() throws {
        let context = try makeContext()
        let profile = onboard(context)
        let custom = Macros(kcal: 4000, protein: 200, carbs: 520, fat: 100)
        profile.dayTargetOverrides = [.conditioning: custom]
        let snapshot = profile.targets()
        #expect(snapshot.target(for: .conditioning) == custom)
        #expect(snapshot.isOverridden(.conditioning))
        #expect(!snapshot.isOverridden(.lifting))
        profile.dayTargetOverrides = [:]
        #expect(profile.dayTargetOverridesData == nil)
    }

    @Test func dislikesParseFromCommaList() {
        let draft = OnboardingDraft()
        draft.dislikesText = "salmon, mushrooms ,\n cottage cheese,,"
        #expect(draft.dislikes == ["salmon", "mushrooms", "cottage cheese"])
    }
}
