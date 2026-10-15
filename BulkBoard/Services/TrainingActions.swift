import BulkCore
import Foundation
import SwiftData

enum TrainingActions {
    /// Replaces the weekly plan with a freshly generated split for the profile's training days.
    static func regeneratePlan(for profile: ProfileRecord, context: ModelContext) {
        for plan in context.fetchAll(WorkoutPlanRecord.self) { context.delete(plan) }
        let plan = WorkoutPlanRecord()
        plan.liftingDays = profile.liftingDays
        plan.courtDays = profile.courtDays
        plan.days = SplitGenerator.generate(liftingDays: profile.liftingDays, courtDays: profile.courtDays, mode: profile.goalMode)
        plan.isDemo = profile.isDemo
        context.insert(plan)
    }

    /// Day type for a date, from the current plan.
    static func dayType(for date: Date, plan: WorkoutPlanRecord?) -> DayType {
        plan?.day(for: date)?.dayType ?? .lifting
    }
}
