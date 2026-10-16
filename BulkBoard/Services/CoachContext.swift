import BulkCore
import Foundation
import Observation
import SwiftData

/// Everything BulkBoard knows about you, as plain text for the local model, so its advice
/// starts from your actual numbers instead of a blank slate. Never leaves 127.0.0.1.
enum CoachContext {
    static func build(_ context: ModelContext, checkIn: BodyCheckInRecord? = nil) -> String {
        guard let profile = context.profile else { return "" }
        let units = UnitFormatter(system: profile.unitSystem)
        let weights = context.fetchAll(WeightRecord.self, sortBy: [SortDescriptor(\.date)])
        let latestKg = weights.last?.weightKg ?? profile.weightKg
        var lines: [String] = []

        lines.append("\(profile.sex.title), \(profile.age), \(units.tall(profile.heightCm)), \(units.weight(latestKg)).")
        lines.append("Goal: \(profile.goalMode.title), \(units.weight(profile.goalWeightKg)) by \(profile.targetDate.formatted(date: .abbreviated, time: .omitted)).")
        let targets = profile.targets(latestWeightKg: latestKg)
        let lift = targets.target(for: .lifting)
        lines.append("Daily targets: \(Fmt.int(lift.kcal)) kcal, \(Fmt.int(lift.protein)) g protein, \(Fmt.int(lift.carbs)) g carbs, \(Fmt.int(lift.fat)) g fat on lifting days.")
        if !profile.dislikes.isEmpty { lines.append("Dislikes: \(profile.dislikes.joined(separator: ", ")).") }
        if !profile.allergens.isEmpty { lines.append("Allergies: \(profile.allergens.map(\.title).sorted().joined(separator: ", ")).") }

        var training = "Trains \(profile.liftingDays) lifting days and \(profile.courtDays) basketball days a week."
        if !profile.focusMuscles.isEmpty { training += " Extra volume for: \(profile.focusMuscles.map(\.title).sorted().joined(separator: ", "))." }
        if profile.dunkGoal { training += " Goal: dunk a basketball." }
        lines.append(training)
        if let plan = context.workoutPlan {
            let days = plan.days.enumerated().map { "\(WeekMath.weekdayShort[$0.offset]) \($0.element.title)" }
            lines.append("This week's plan: \(days.joined(separator: "; ")).")
        }

        let since = Date.now.adding(days: -14).dayStart
        let intake = context.fetchAll(IntakeRecord.self).filter { $0.day >= since }
        let loggedDays = Set(intake.map(\.day))
        if !loggedDays.isEmpty {
            let average = intake.map(\.macros).sum() * (1 / Double(loggedDays.count))
            lines.append("Last 14 days: logged food on \(loggedDays.count) days, averaging \(Fmt.int(average.kcal)) kcal and \(Fmt.int(average.protein)) g protein per logged day.")
        } else {
            lines.append("Food log: nothing logged in BulkBoard yet, so actual intake is unknown (don't assume it's low).")
        }
        let sessions = context.fetchAll(WorkoutSessionRecord.self).filter { $0.isCompleted && $0.date >= since }.count
        let court = context.fetchAll(CourtSessionRecord.self).filter { $0.date >= since }.count
        lines.append("Last 14 days: \(sessions) lifting sessions and \(court) basketball sessions logged.")

        let recent = weights.filter { $0.date >= Date.now.adding(days: -28) }
        if let first = recent.first, let last = recent.last, last.date.timeIntervalSince(first.date) > 6 * 86_400 {
            let weeks = last.date.timeIntervalSince(first.date) / (7 * 86_400)
            lines.append("Weight change: \(units.signedWeight((last.weightKg - first.weightKg) / weeks, decimals: 2)) per week over \(Fmt.int(weeks)) weeks.")
        }

        let checkIns = context.fetchAll(BodyCheckInRecord.self, sortBy: [SortDescriptor(\.date, order: .reverse)])
        let current = checkIn ?? checkIns.first
        if let current, let latest = current.measurements {
            let earlier = checkIns.filter { $0.date < current.date }
            // A quick check-in (say, just weight) shouldn't hide the tape numbers from the one before.
            let m = merged(latest, with: earlier.compactMap(\.measurements))
            lines.append("")
            lines.append("Check-in \(current.date.formatted(date: .abbreviated, time: .omitted)) (blank fields filled from earlier check-ins):")
            let previous = earlier.first?.measurements
            let rows = measurementRows(m, previous: previous)
            for (label, value, old) in rows {
                var line = "- \(label): \(units.length(value))"
                if let old, abs(value - old) >= 0.2 { line += " (\(value > old ? "+" : "−")\(units.length(abs(value - old))) since last check-in)" }
                lines.append(line)
            }
            if [m.chestCm, m.armCm, m.waistCm, m.shouldersCm, m.thighCm, m.calfCm].allSatisfy({ $0 == nil }) {
                lines.append("- No tape measurements yet (chest, arms, waist, legs), so proportions can't be judged from numbers.")
            }
            if let bf = m.bodyFatPercent { lines.append("- Body fat: \(Fmt.number(bf))%") }
            let report = PhysiqueAnalyzer.analyze(m, sex: profile.sex)
            for part in report.parts {
                lines.append("- \(part.part.title) is \(Fmt.int(part.ratio * 100))% of its proportion target")
            }
            if let ffmi = report.ffmi { lines.append("- FFMI \(Fmt.number(ffmi))\(report.ffmiBand.map { " (\($0))" } ?? "")") }
            if !report.lagging.isEmpty { lines.append("- Tape says lagging: \(report.lagging.map(\.title).joined(separator: ", "))") }
            if profile.dunkGoal || m.standingVerticalCm != nil || m.approachTouchCm != nil {
                let dunk = DunkCalculator.report(BodyActions.dunkInputs(profile: profile, checkIn: current, latestWeightKg: latestKg))
                if let gap = dunk.gapCm {
                    lines.append(gap > 0 ? "- Dunk: needs \(units.length(gap)) more on a running jump." : "- Dunk: jump is already high enough.")
                } else {
                    lines.append("- Dunk: needs a \(units.length(dunk.requiredJumpCm)) running jump; current jump unknown.")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The latest value for every field, falling back to earlier check-ins (newest first).
    static func merged(_ latest: BodyMeasurements, with earlier: [BodyMeasurements]) -> BodyMeasurements {
        var m = latest
        for old in earlier {
            m.wingspanCm = m.wingspanCm ?? old.wingspanCm
            m.standingReachCm = m.standingReachCm ?? old.standingReachCm
            m.wristCm = m.wristCm ?? old.wristCm
            m.neckCm = m.neckCm ?? old.neckCm
            m.shouldersCm = m.shouldersCm ?? old.shouldersCm
            m.chestCm = m.chestCm ?? old.chestCm
            m.waistCm = m.waistCm ?? old.waistCm
            m.hipsCm = m.hipsCm ?? old.hipsCm
            m.armCm = m.armCm ?? old.armCm
            m.forearmCm = m.forearmCm ?? old.forearmCm
            m.thighCm = m.thighCm ?? old.thighCm
            m.calfCm = m.calfCm ?? old.calfCm
            m.bodyFatPercent = m.bodyFatPercent ?? old.bodyFatPercent
            m.standingVerticalCm = m.standingVerticalCm ?? old.standingVerticalCm
            m.approachTouchCm = m.approachTouchCm ?? old.approachTouchCm
        }
        return m
    }

    private static func measurementRows(_ m: BodyMeasurements, previous p: BodyMeasurements?) -> [(String, Double, Double?)] {
        let rows: [(String, Double?, Double?)] = [
            ("Wingspan", m.wingspanCm, p?.wingspanCm), ("Standing reach", m.standingReachCm, p?.standingReachCm),
            ("Wrist", m.wristCm, p?.wristCm), ("Neck", m.neckCm, p?.neckCm), ("Shoulders", m.shouldersCm, p?.shouldersCm),
            ("Chest", m.chestCm, p?.chestCm), ("Waist", m.waistCm, p?.waistCm), ("Hips", m.hipsCm, p?.hipsCm),
            ("Arm", m.armCm, p?.armCm), ("Forearm", m.forearmCm, p?.forearmCm), ("Thigh", m.thighCm, p?.thighCm),
            ("Calf", m.calfCm, p?.calfCm), ("Standing vertical", m.standingVerticalCm, p?.standingVerticalCm),
            ("Best running touch", m.approachTouchCm, p?.approachTouchCm),
        ]
        return rows.compactMap { label, value, old in value.map { (label, $0, old) } }
    }
}

/// Runs AI reviews of check-ins in the background and remembers which one is in progress,
/// so a review keeps going after the check-in sheet closes and screens can show it.
@Observable
final class BodyCoach {
    static let shared = BodyCoach()

    private(set) var reviewing: Set<UUID> = []
    private(set) var errors: [UUID: String] = [:]
    /// Check-ins already tried automatically this launch, so a failure doesn't retry in a loop.
    private var attempted: Set<UUID> = []

    /// Reviews the check-in once, automatically, if the AI is ready and it has no review yet.
    func reviewIfNeeded(_ checkIn: BodyCheckInRecord, context: ModelContext) {
        guard checkIn.aiNotes == nil, !attempted.contains(checkIn.id), OllamaClient.shared.isAvailable else { return }
        review(checkIn, context: context)
    }

    func review(_ checkIn: BodyCheckInRecord, context: ModelContext) {
        let id = checkIn.id
        guard !reviewing.contains(id) else { return }
        attempted.insert(id)
        reviewing.insert(id)
        errors[id] = nil
        // Use this check-in's photo, or the most recent one before it.
        let photoSource = checkIn.photoFilename != nil ? checkIn
            : context.fetchAll(BodyCheckInRecord.self, sortBy: [SortDescriptor(\.date, order: .reverse)])
                .first { $0.date <= checkIn.date && $0.photoFilename != nil }
        let photo = photoSource?.photoFilename.flatMap { PhotoStore.jpegData($0) }
        let photoDate = photoSource?.date
        let text = CoachContext.build(context, checkIn: checkIn)
        let teen = (context.profile?.age ?? 30) < 18
        Task {
            defer { reviewing.remove(id) }
            do {
                let client = OllamaClient.shared
                var review = try await client.reviewPhysique(photo: photo, context: text, teen: teen)
                if review.usedPhoto == true { review.photoDate = photoDate }
                checkIn.aiNotes = String(data: Blob.encode(review), encoding: .utf8)
                checkIn.aiModel = review.usedPhoto == true ? client.visionModel : client.model
                try? context.save()
            } catch {
                errors[id] = error.localizedDescription
            }
        }
    }
}
