import BulkCore
import Foundation
import SwiftData

enum ProfileActions {
    /// Creates the profile and the training plan. Meals start empty: you log your own, and
    /// suggestions are there when you ask for them.
    @discardableResult
    static func completeOnboarding(_ draft: OnboardingDraft, context: ModelContext) -> ProfileRecord {
        let profile = ProfileRecord()
        profile.age = draft.age
        profile.sex = draft.sex
        profile.heightCm = draft.heightCmValue
        profile.weightKg = draft.weightKg
        profile.goalWeightKg = draft.goalWeightKg
        profile.startDate = .now.dayStart
        profile.targetDate = draft.targetDate
        profile.activity = draft.activity
        profile.goalMode = draft.mode
        profile.liftingDays = draft.liftingDays
        profile.courtDays = draft.courtDays
        profile.dislikes = draft.dislikes
        profile.allergens = draft.allergens
        profile.unitSystem = draft.unitSystem
        context.insert(profile)
        context.insert(WeightRecord(date: .now, weightKg: draft.weightKg))

        SeedService.ensureBuiltIns(context)
        TrainingActions.regeneratePlan(for: profile, context: context)
        try? context.save()
        return profile
    }
}
