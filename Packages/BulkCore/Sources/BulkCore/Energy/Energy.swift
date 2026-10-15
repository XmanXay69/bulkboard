import Foundation

public enum Energy {
    /// Rough energy content of a kilogram of gained or lost body mass (~3,500 kcal per lb).
    public static let kcalPerKg = 7700.0

    /// Mifflin-St Jeor resting energy expenditure.
    public static func bmr(weightKg: Double, heightCm: Double, age: Int, sex: Sex) -> Double {
        10 * weightKg + 6.25 * heightCm - 5 * Double(age) + (sex == .male ? 5 : -161)
    }

    public static func tdee(bmr: Double, activity: ActivityLevel) -> Double {
        bmr * activity.multiplier
    }

    /// Daily calorie change needed to move `weeklyChangeKg` per week.
    public static func dailyAdjustment(weeklyChangeKg: Double) -> Double {
        weeklyChangeKg * kcalPerKg / 7
    }
}

/// How fast each goal mode is allowed to move bodyweight.
public struct RatePolicy: Sendable, Equatable {
    public var minLbPerWeek: Double
    public var maxLbPerWeek: Double
    public var defaultLbPerWeek: Double
    /// Modes like recomp and maintain use a fixed adjustment instead of a rate.
    public var fixedDailyAdjustment: Double?
}

public extension GoalMode {
    var ratePolicy: RatePolicy {
        switch self {
        case .bulk: RatePolicy(minLbPerWeek: 0.5, maxLbPerWeek: 1.0, defaultLbPerWeek: 0.75)
        case .bulkPerformance: RatePolicy(minLbPerWeek: 0.5, maxLbPerWeek: 1.0, defaultLbPerWeek: 0.5)
        case .cut: RatePolicy(minLbPerWeek: 0.5, maxLbPerWeek: 1.5, defaultLbPerWeek: 1.0)
        case .recomp: RatePolicy(minLbPerWeek: 0, maxLbPerWeek: 0, defaultLbPerWeek: 0, fixedDailyAdjustment: -150)
        case .maintain: RatePolicy(minLbPerWeek: 0, maxLbPerWeek: 0, defaultLbPerWeek: 0, fixedDailyAdjustment: 0)
        }
    }
}

public enum TargetWarning: Hashable, Sendable {
    /// The target date needs a faster rate than is realistic; the rate was capped.
    case tooAggressive(requiredLbPerWeek: Double, cappedLbPerWeek: Double)
    /// The target date allows a slower rate than the mode minimum; you'll arrive early.
    case slowerThanMinimum(requiredLbPerWeek: Double, usingLbPerWeek: Double)
    case targetDateInPast
    case goalOppositeDirection(mode: GoalMode)
    case goalReached
    case caloriesAtFloor(floorKcal: Double)
    case lowCarbs(grams: Double)

    public var isSerious: Bool {
        switch self {
        case .tooAggressive, .targetDateInPast, .goalOppositeDirection, .caloriesAtFloor: true
        case .slowerThanMinimum, .goalReached, .lowCarbs: false
        }
    }

    public var message: String {
        switch self {
        case let .tooAggressive(required, capped):
            "Your target date needs \(Fmt.number(required, maxDecimals: 2)) lb/week. That's not realistic without a lot of fat gain or loss, so the plan is capped at \(Fmt.number(capped, maxDecimals: 2)) lb/week. Push the date back or accept arriving later."
        case let .slowerThanMinimum(required, using):
            "Your date only needs \(Fmt.number(required, maxDecimals: 2)) lb/week. Planning \(Fmt.number(using, maxDecimals: 2)) lb/week, so you'll get there early."
        case .targetDateInPast:
            "Your target date has passed. Pick a new one to get a rate-based plan."
        case let .goalOppositeDirection(mode):
            "Your goal weight points the other way from \(mode.title). Check the goal weight or switch modes."
        case .goalReached:
            "You're at your goal weight. Set a new goal or switch to Maintain."
        case let .caloriesAtFloor(floor):
            "Calories were held at a floor of \(Fmt.int(floor)) kcal. Going lower isn't a good idea without a coach."
        case let .lowCarbs(grams):
            "Carbs are only \(Fmt.int(grams)) g. That's low for court conditioning; consider lowering fat."
        }
    }
}

public struct RatePlan: Sendable, Equatable {
    /// Signed weekly change actually planned (kg/week).
    public var weeklyChangeKg: Double
    /// Signed weekly change the target date implies, if it can be computed.
    public var requiredWeeklyChangeKg: Double?
    /// Signed daily calorie adjustment applied to TDEE.
    public var dailyAdjustmentKcal: Double
    /// When the goal is reached at the planned rate.
    public var projectedGoalDate: Date?
    public var warnings: [TargetWarning]

    public var weeklyChangeLb: Double { Units.lb(fromKg: weeklyChangeKg) }
}

public enum GoalPlanner {
    /// Within this distance of the goal counts as reached.
    static let reachedToleranceKg = 0.25

    public static func plan(profile: BodyProfile, today: Date, weeklyRateOverrideKg: Double? = nil,
                            calendar: Calendar = .bulk) -> RatePlan {
        let mode = profile.mode
        let policy = mode.ratePolicy
        var warnings: [TargetWarning] = []

        if let fixed = policy.fixedDailyAdjustment {
            return RatePlan(weeklyChangeKg: 0, requiredWeeklyChangeKg: nil,
                            dailyAdjustmentKcal: fixed, projectedGoalDate: nil, warnings: [])
        }

        let delta = profile.goalWeightKg - profile.weightKg
        let direction = Double(mode.direction)
        let days = WeekMath.daysBetween(today, profile.targetDate, calendar: calendar)
        let weeks = Double(days) / 7

        let reached = abs(delta) <= reachedToleranceKg
        let opposite = !reached && (delta * direction) < 0
        if reached { warnings.append(.goalReached) }
        if opposite { warnings.append(.goalOppositeDirection(mode: mode)) }

        var requiredKg: Double?
        if days <= 0 {
            warnings.append(.targetDateInPast)
        } else if !reached && !opposite {
            requiredKg = delta / weeks
        }

        // Cuts are also capped at ~1% of bodyweight per week.
        var maxLb = policy.maxLbPerWeek
        if mode == .cut { maxLb = min(maxLb, 0.01 * Units.lb(fromKg: profile.weightKg)) }
        let minLb = min(policy.minLbPerWeek, maxLb)

        var rateLb: Double
        if let override = weeklyRateOverrideKg {
            rateLb = Units.lb(fromKg: abs(override))
            if rateLb > maxLb + 1e-9 {
                warnings.append(.tooAggressive(requiredLbPerWeek: rateLb, cappedLbPerWeek: rateLb))
            }
        } else if let required = requiredKg {
            let requiredLb = Units.lb(fromKg: abs(required))
            if requiredLb > maxLb + 1e-9 {
                rateLb = maxLb
                warnings.append(.tooAggressive(requiredLbPerWeek: requiredLb, cappedLbPerWeek: maxLb))
            } else if requiredLb < minLb - 1e-9 {
                rateLb = minLb
                warnings.append(.slowerThanMinimum(requiredLbPerWeek: requiredLb, usingLbPerWeek: minLb))
            } else {
                rateLb = requiredLb
            }
        } else {
            rateLb = min(policy.defaultLbPerWeek, maxLb)
        }

        let weeklyKg = direction * Units.kg(fromLb: rateLb)
        var projected: Date?
        if !reached && !opposite && rateLb > 0 {
            let weeksNeeded = abs(delta) / Units.kg(fromLb: rateLb)
            projected = calendar.date(byAdding: .day, value: Int((weeksNeeded * 7).rounded()), to: calendar.startOfDay(for: today))
        }

        return RatePlan(weeklyChangeKg: weeklyKg, requiredWeeklyChangeKg: requiredKg,
                        dailyAdjustmentKcal: Energy.dailyAdjustment(weeklyChangeKg: weeklyKg),
                        projectedGoalDate: projected, warnings: warnings)
    }
}
