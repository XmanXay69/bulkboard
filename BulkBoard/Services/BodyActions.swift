import BulkCore
import Foundation
import SwiftData

enum BodyActions {
    @discardableResult
    static func saveCheckIn(_ measurements: BodyMeasurements, date: Date, photo: Data?, logWeight: Bool,
                            context: ModelContext) throws -> BodyCheckInRecord {
        let record = BodyCheckInRecord(date: date)
        record.measurements = measurements
        if let photo { record.photoFilename = try PhotoStore.save(photo) }
        record.isDemo = context.profile?.isDemo ?? false
        context.insert(record)
        if logWeight {
            let weight = WeightRecord(date: date, weightKg: measurements.weightKg)
            weight.isDemo = record.isDemo
            context.insert(weight)
        }
        if let profile = context.profile, abs(profile.heightCm - measurements.heightCm) > 0.5 {
            profile.heightCm = measurements.heightCm
        }
        try context.save()
        return record
    }

    static func delete(_ record: BodyCheckInRecord, context: ModelContext) {
        if let photo = record.photoFilename { PhotoStore.delete(photo) }
        context.delete(record)
        try? context.save()
    }

    static func report(for record: BodyCheckInRecord?, sex: Sex) -> PhysiqueReport? {
        record?.measurements.map { PhysiqueAnalyzer.analyze($0, sex: sex) }
    }

    /// Dunk inputs from the latest check-in, filling gaps from the profile.
    static func dunkInputs(profile: ProfileRecord, checkIn: BodyCheckInRecord?, latestWeightKg: Double?) -> DunkInputs {
        let m = checkIn?.measurements
        return DunkInputs(heightCm: m?.heightCm ?? profile.heightCm, wingspanCm: m?.wingspanCm, standingReachCm: m?.standingReachCm,
                          weightKg: latestWeightKg ?? m?.weightKg ?? profile.weightKg, goalWeightKg: profile.goalWeightKg,
                          standingVerticalCm: m?.standingVerticalCm, approachTouchCm: m?.approachTouchCm,
                          canPalmBall: m?.canPalmBall ?? false)
    }

    /// Sets focus muscles (and optionally a protein bump) and rebuilds the training week.
    static func applyFocus(_ muscles: Set<MuscleGroup>, raiseProtein: Bool, profile: ProfileRecord, context: ModelContext) {
        profile.focusMuscles = muscles
        if raiseProtein { profile.proteinPerLbOverride = max(profile.macroSettings.proteinPerLb, 1.0) }
        TrainingActions.regeneratePlan(for: profile, context: context)
        try? context.save()
    }

    /// Turns the dunk program on or off and optionally caps the gain rate to protect power-to-weight.
    static func setDunkGoal(_ on: Bool, leanGain: Bool, profile: ProfileRecord, context: ModelContext) {
        profile.dunkGoal = on
        if on && leanGain && profile.goalMode.isGain {
            profile.weeklyRateOverrideKg = Units.kg(fromLb: 0.5)
        }
        TrainingActions.regeneratePlan(for: profile, context: context)
        try? context.save()
    }

    /// Plain-text context for the vision model.
    static func aiContext(report: PhysiqueReport, measurements: BodyMeasurements, sex: Sex) -> String {
        var lines = ["Sex: \(sex.title). Height \(Int(measurements.heightCm)) cm, weight \(Fmt.number(measurements.weightKg)) kg."]
        for part in report.parts {
            lines.append("\(part.part.title): \(Fmt.number(part.actualCm)) cm, \(Fmt.int(part.ratio * 100))% of proportion target")
        }
        if let bf = report.bodyFatPercent { lines.append("Body fat ≈ \(Fmt.number(bf))%") }
        if !report.lagging.isEmpty { lines.append("Tape says lagging: \(report.lagging.map(\.title).joined(separator: ", "))") }
        return lines.joined(separator: "\n")
    }
}
