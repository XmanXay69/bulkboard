import BulkCore
import Foundation
import SwiftData

/// Clearly-labeled sample data for screenshots and kicking the tires. Everything it creates has `isDemo = true`.
enum DemoData {
    static func load(into context: ModelContext) {
        let draft = OnboardingDraft()
        draft.age = 24
        draft.sex = .male
        draft.heightFeet = 6
        draft.heightInches = 2
        draft.weight = 185
        draft.goalWeight = 197
        draft.targetDate = Date.now.dayStart.adding(days: 18 * 7)
        draft.mode = .bulkPerformance
        draft.liftingDays = 4
        draft.courtDays = 2
        let profile = ProfileActions.completeOnboarding(draft, context: context)
        profile.isDemo = true
        try? context.save()
    }
}
