import BulkCore
import Foundation
import Observation

/// Everything onboarding collects, in display units, plus a live targets preview.
@Observable
final class OnboardingDraft {
    var unitSystem: UnitSystem = .imperial {
        didSet { if oldValue != unitSystem { convertUnits(from: oldValue) } }
    }
    var age = 24
    var sex: Sex = .male
    var heightFeet = 6
    var heightInches = 1
    var heightCm = 185.0
    var weight = 180.0
    var goalWeight = 192.0
    var targetDate = Date.now.dayStart.adding(days: 20 * 7)
    var mode: GoalMode = .bulkPerformance
    var liftingDays = 4 { didSet { syncActivity() } }
    var courtDays = 2 { didSet { syncActivity() } }
    var activity: ActivityLevel = .active
    var activityTouched = false
    var dislikesText = ""
    var allergens: Set<Allergen> = []

    var heightCmValue: Double {
        unitSystem == .imperial ? Units.cm(fromInches: Double(heightFeet * 12 + heightInches)) : heightCm
    }

    var weightKg: Double { Units.kg(fromDisplay: weight, in: unitSystem) }
    var goalWeightKg: Double { Units.kg(fromDisplay: goalWeight, in: unitSystem) }

    var dislikes: [String] {
        dislikesText.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var bodyProfile: BodyProfile {
        BodyProfile(age: age, sex: sex, heightCm: heightCmValue, weightKg: weightKg, goalWeightKg: goalWeightKg,
                    startDate: .now.dayStart, targetDate: targetDate, activity: activity, mode: mode,
                    liftingDaysPerWeek: liftingDays, courtDaysPerWeek: courtDays)
    }

    var preview: TargetsResult {
        TargetsCalculator.compute(profile: bodyProfile, today: .now, unitSystem: unitSystem)
    }

    var isBodyValid: Bool {
        (13...90).contains(age) && (120...230).contains(heightCmValue) && (35...250).contains(weightKg)
    }

    var isGoalValid: Bool { (35...250).contains(goalWeightKg) }

    private func syncActivity() {
        guard !activityTouched else { return }
        activity = ActivityLevel.suggested(forSessionsPerWeek: liftingDays + courtDays)
    }

    private func convertUnits(from old: UnitSystem) {
        let weightKg = Units.kg(fromDisplay: weight, in: old)
        let goalKg = Units.kg(fromDisplay: goalWeight, in: old)
        let cm = old == .imperial ? Units.cm(fromInches: Double(heightFeet * 12 + heightInches)) : heightCm
        weight = (Units.display(kg: weightKg, in: unitSystem) * 10).rounded() / 10
        goalWeight = (Units.display(kg: goalKg, in: unitSystem) * 10).rounded() / 10
        heightCm = cm.rounded()
        let inches = Int(Units.inches(fromCm: cm).rounded())
        heightFeet = inches / 12
        heightInches = inches % 12
    }
}
