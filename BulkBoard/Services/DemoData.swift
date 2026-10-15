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
        for record in context.fetchAll(PlanEntryRecord.self) { record.isDemo = true }
        for record in context.fetchAll(WeightRecord.self) { record.isDemo = true }
        context.workoutPlan?.isDemo = true

        GroceryActions.generate(weekOf: .now, context: context)
        for item in context.fetchAll(GroceryItemRecord.self).sorted(by: { $0.sortIndex < $1.sortIndex }).prefix(7) {
            item.isChecked = true
        }
        GroceryActions.addManual(name: "Sports tape", amount: "2 rolls", section: .other, context: context)
        for item in context.fetchAll(GroceryItemRecord.self) { item.isDemo = true }
        try? context.save()
    }
}
