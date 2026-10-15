import Foundation

/// Knobs for splitting calories into macros.
public struct MacroSettings: Sendable, Equatable, Codable {
    /// Grams of protein per pound of bodyweight.
    public var proteinPerLb: Double
    /// Share of calories from fat (0–1).
    public var fatPercent: Double

    public init(proteinPerLb: Double, fatPercent: Double) {
        self.proteinPerLb = proteinPerLb
        self.fatPercent = fatPercent
    }
}

public extension GoalMode {
    var defaultMacroSettings: MacroSettings {
        switch self {
        case .bulk: MacroSettings(proteinPerLb: 0.9, fatPercent: 0.28)
        case .bulkPerformance: MacroSettings(proteinPerLb: 0.9, fatPercent: 0.25)
        case .recomp: MacroSettings(proteinPerLb: 1.0, fatPercent: 0.28)
        case .cut: MacroSettings(proteinPerLb: 1.0, fatPercent: 0.28)
        case .maintain: MacroSettings(proteinPerLb: 0.8, fatPercent: 0.30)
        }
    }
}

/// One line of the "show the math" breakdown.
public struct MathStep: Hashable, Sendable, Identifiable {
    public var label: String
    public var formula: String
    public var result: String

    public var id: String { label }

    public init(label: String, formula: String, result: String) {
        self.label = label
        self.formula = formula
        self.result = result
    }
}

public struct TargetsResult: Sendable {
    public var bmr: Double
    public var tdee: Double
    public var rate: RatePlan
    public var settings: MacroSettings
    /// Average daily target across the week.
    public var daily: Macros
    /// Targets per day type; protein and fat stay fixed, carbs move with the day's demands.
    public var byDayType: [DayType: Macros]
    public var schedule: [DayType: Int]
    public var steps: [MathStep]
    public var warnings: [TargetWarning]

    public func target(for dayType: DayType) -> Macros { byDayType[dayType] ?? daily }
}

public enum TargetsCalculator {
    /// Relative calorie offsets per day type before they're re-centred on the weekly average.
    public static let dayTypeOffsets: [DayType: Double] = [.lifting: 0, .conditioning: 150, .rest: -200]

    public static func defaultSchedule(for profile: BodyProfile) -> [DayType: Int] {
        let lifting = max(0, min(7, profile.liftingDaysPerWeek))
        let court = max(0, min(7 - lifting, profile.courtDaysPerWeek))
        return [.lifting: lifting, .conditioning: court, .rest: 7 - lifting - court]
    }

    public static func compute(profile: BodyProfile, today: Date, settings: MacroSettings? = nil,
                               weeklyRateOverrideKg: Double? = nil, schedule: [DayType: Int]? = nil,
                               unitSystem: UnitSystem = .imperial, calendar: Calendar = .bulk) -> TargetsResult {
        let settings = settings ?? profile.mode.defaultMacroSettings
        let schedule = schedule ?? defaultSchedule(for: profile)
        var steps: [MathStep] = []

        // 1. BMR and TDEE
        let bmr = Energy.bmr(weightKg: profile.weightKg, heightCm: profile.heightCm, age: profile.age, sex: profile.sex)
        let sexTerm = profile.sex == .male ? "+ 5" : "− 161"
        steps.append(MathStep(
            label: "BMR (Mifflin-St Jeor)",
            formula: "10 × \(Fmt.number(profile.weightKg)) kg + 6.25 × \(Fmt.number(profile.heightCm)) cm − 5 × \(profile.age) \(sexTerm)",
            result: "\(Fmt.int(bmr)) kcal"))

        let tdee = Energy.tdee(bmr: bmr, activity: profile.activity)
        steps.append(MathStep(
            label: "Maintenance (TDEE)",
            formula: "\(Fmt.int(bmr)) × \(Fmt.number(profile.activity.multiplier, maxDecimals: 3)) (\(profile.activity.title))",
            result: "\(Fmt.int(tdee)) kcal"))

        // 2. Rate and adjustment
        let rate = GoalPlanner.plan(profile: profile, today: today, weeklyRateOverrideKg: weeklyRateOverrideKg, calendar: calendar)
        var warnings = rate.warnings
        if let fixed = profile.mode.ratePolicy.fixedDailyAdjustment {
            steps.append(MathStep(label: "\(profile.mode.title) adjustment",
                                  formula: "Fixed for \(profile.mode.title)",
                                  result: "\(Fmt.signed(fixed)) kcal"))
        } else {
            let weekly = unitSystem == .imperial
                ? "\(Fmt.number(abs(rate.weeklyChangeLb), maxDecimals: 2)) lb"
                : "\(Fmt.number(abs(rate.weeklyChangeKg), maxDecimals: 2)) kg"
            var formula = "\(weekly)/week"
            if let required = rate.requiredWeeklyChangeKg {
                let requiredText = unitSystem == .imperial
                    ? "\(Fmt.number(abs(Units.lb(fromKg: required)), maxDecimals: 2)) lb"
                    : "\(Fmt.number(abs(required), maxDecimals: 2)) kg"
                formula += " (your date needs \(requiredText)/week)"
            }
            steps.append(MathStep(label: profile.mode.isGain ? "Rate of gain" : "Rate of loss",
                                  formula: formula, result: "\(rate.weeklyChangeKg >= 0 ? "+" : "−")\(weekly)/wk"))
            steps.append(MathStep(
                label: profile.mode.isGain ? "Daily surplus" : "Daily deficit",
                formula: "\(Fmt.number(abs(rate.weeklyChangeKg), maxDecimals: 2)) kg × 7,700 kcal ÷ 7 days",
                result: "\(Fmt.signed(rate.dailyAdjustmentKcal)) kcal"))
        }

        var kcal = roundTo10(tdee + rate.dailyAdjustmentKcal)
        let floor = max(bmr, profile.sex == .male ? 1500 : 1200)
        if kcal < floor {
            kcal = roundTo10(floor)
            warnings.append(.caloriesAtFloor(floorKcal: kcal))
        }
        steps.append(MathStep(label: "Daily calories",
                              formula: "\(Fmt.int(tdee)) \(rate.dailyAdjustmentKcal >= 0 ? "+" : "−") \(Fmt.int(abs(rate.dailyAdjustmentKcal)))",
                              result: "\(Fmt.int(kcal)) kcal"))

        // 3. Macros
        let weightLb = Units.lb(fromKg: profile.weightKg)
        let protein = (settings.proteinPerLb * weightLb).rounded()
        let fat = (kcal * settings.fatPercent / 9).rounded()
        let carbs = max(0, ((kcal - protein * 4 - fat * 9) / 4).rounded())
        steps.append(MathStep(label: "Protein",
                              formula: "\(Fmt.number(settings.proteinPerLb, maxDecimals: 2)) g × \(Fmt.number(weightLb)) lb bodyweight",
                              result: "\(Fmt.int(protein)) g (\(Fmt.int(protein * 4)) kcal)"))
        steps.append(MathStep(label: "Fat",
                              formula: "\(Fmt.int(settings.fatPercent * 100))% × \(Fmt.int(kcal)) kcal ÷ 9",
                              result: "\(Fmt.int(fat)) g (\(Fmt.int(fat * 9)) kcal)"))
        steps.append(MathStep(label: "Carbs",
                              formula: "(\(Fmt.int(kcal)) − \(Fmt.int(protein * 4)) − \(Fmt.int(fat * 9))) ÷ 4",
                              result: "\(Fmt.int(carbs)) g"))
        let daily = Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat)

        if schedule[.conditioning, default: 0] > 0 && carbs < 2 * profile.weightKg {
            warnings.append(.lowCarbs(grams: carbs))
        }

        // 4. Day types: carbs move, protein and fat hold. Offsets are re-centred so the week averages out.
        let total = schedule.values.reduce(0, +)
        let mean = total > 0
            ? DayType.allCases.reduce(0.0) { $0 + dayTypeOffsets[$1, default: 0] * Double(schedule[$1, default: 0]) } / Double(total)
            : 0
        var byDayType: [DayType: Macros] = [:]
        for dayType in DayType.allCases {
            let offset = dayTypeOffsets[dayType, default: 0] - mean
            let dayKcal = roundTo10(kcal + offset)
            let dayCarbs = max(0, ((dayKcal - protein * 4 - fat * 9) / 4).rounded())
            byDayType[dayType] = Macros(kcal: dayKcal, protein: protein, carbs: dayCarbs, fat: fat)
            if schedule[dayType, default: 0] > 0 {
                steps.append(MathStep(label: dayType.title,
                                      formula: "\(schedule[dayType, default: 0])×/week, \(Fmt.signed(offset)) kcal from carbs",
                                      result: "\(Fmt.int(dayKcal)) kcal · \(Fmt.int(dayCarbs)) g carbs"))
            }
        }

        return TargetsResult(bmr: bmr, tdee: tdee, rate: rate, settings: settings, daily: daily,
                             byDayType: byDayType, schedule: schedule, steps: steps, warnings: warnings)
    }

    /// Replaces computed day-type targets with any manual overrides.
    public static func applying(overrides: [DayType: Macros], to targets: [DayType: Macros]) -> [DayType: Macros] {
        targets.merging(overrides) { _, override in override }
    }

    static func roundTo10(_ value: Double) -> Double { (value / 10).rounded() * 10 }
}
