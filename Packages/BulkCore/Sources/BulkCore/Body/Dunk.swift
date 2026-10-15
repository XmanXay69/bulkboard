import Foundation

public struct DunkInputs: Sendable {
    public var heightCm: Double
    public var wingspanCm: Double?
    /// Measured standing reach beats the estimate when you have it.
    public var standingReachCm: Double?
    public var weightKg: Double
    public var goalWeightKg: Double?
    public var standingVerticalCm: Double?
    public var approachTouchCm: Double?
    public var canPalmBall: Bool

    public init(heightCm: Double, wingspanCm: Double? = nil, standingReachCm: Double? = nil, weightKg: Double,
                goalWeightKg: Double? = nil, standingVerticalCm: Double? = nil, approachTouchCm: Double? = nil,
                canPalmBall: Bool = false) {
        self.heightCm = heightCm
        self.wingspanCm = wingspanCm
        self.standingReachCm = standingReachCm
        self.weightKg = weightKg
        self.goalWeightKg = goalWeightKg
        self.standingVerticalCm = standingVerticalCm
        self.approachTouchCm = approachTouchCm
        self.canPalmBall = canPalmBall
    }
}

public struct DunkReport: Sendable, Equatable {
    public enum Verdict: String, Sendable { case canDunk, close, reachable, longTerm }

    public var reachCm: Double
    public var reachIsEstimate: Bool
    /// Height you need to get the ball to: rim plus clearance.
    public var requiredTouchCm: Double
    /// Jump height (from standing reach) a running dunk needs.
    public var requiredJumpCm: Double
    /// Your best running jump, measured or estimated from your standing vertical.
    public var currentJumpCm: Double?
    public var currentJumpIsEstimate: Bool
    /// Positive = still short. Zero or negative = you can dunk.
    public var gapCm: Double?
    public var peakPowerW: Double?
    /// Jump lost per kg gained at the same power.
    public var jumpLossPerKgCm: Double
    /// Running jump at the goal weight if power doesn't change.
    public var projectedJumpAtGoalCm: Double?
    /// Extra power (%) needed at the goal weight to dunk.
    public var powerIncreaseNeededAtGoal: Double?
    /// Rough weeks of focused jump training to close the gap.
    public var estimatedWeeks: ClosedRange<Int>?
    public var verdict: Verdict?
}

/// Dunk math.
///
/// - Reach: when not measured, estimated as 0.83 × height + 0.47 × wingspan (fit to NBA combine
///   measurements; lands within ~1 in for typical builds).
/// - Requirement: 10 ft rim + ~6 in to get a ball over it (≈4 in if you can palm it).
/// - Power: the Sayers equation (peak W = 60.7 × jump cm + 45.3 × mass kg − 2055) links jump height,
///   bodyweight and power, which is how adding weight on a bulk is turned into lost inches.
/// - Running jumps run ~15% higher than standing jumps.
public enum DunkCalculator {
    public static let rimCm = 304.8
    public static let clearanceCm = 15.24
    public static let palmClearanceCm = 10.16
    public static let approachFactor = 1.15

    public static func estimatedReach(heightCm: Double, wingspanCm: Double?) -> Double {
        0.83 * heightCm + 0.47 * (wingspanCm ?? heightCm)
    }

    public static func sayersPower(jumpCm: Double, massKg: Double) -> Double {
        60.7 * jumpCm + 45.3 * massKg - 2055
    }

    public static func jump(fromPower power: Double, massKg: Double) -> Double {
        (power + 2055 - 45.3 * massKg) / 60.7
    }

    /// Typical gains for a focused program: fast early, then slower.
    public static func weeksToGain(_ cm: Double) -> Int {
        var remaining = cm
        var weeks = 0
        while remaining > 1e-9 && weeks < 104 {
            remaining -= weeks < 8 ? 1.27 : weeks < 24 ? 0.64 : 0.25
            weeks += 1
        }
        return weeks
    }

    public static func report(_ input: DunkInputs) -> DunkReport {
        let reach = input.standingReachCm ?? estimatedReach(heightCm: input.heightCm, wingspanCm: input.wingspanCm)
        let requiredTouch = rimCm + (input.canPalmBall ? palmClearanceCm : clearanceCm)
        let requiredJump = requiredTouch - reach

        var current: Double?
        var currentIsEstimate = false
        if let touch = input.approachTouchCm {
            current = touch - reach
        } else if let standing = input.standingVerticalCm {
            current = standing * approachFactor
            currentIsEstimate = true
        }

        let standingJump = input.standingVerticalCm ?? current.map { $0 / approachFactor }
        let power = standingJump.map { sayersPower(jumpCm: $0, massKg: input.weightKg) }
        let lossPerKg = 45.3 / 60.7 * approachFactor

        var projected: Double?
        var powerIncrease: Double?
        if let goal = input.goalWeightKg {
            // Start from today's jump so measured and estimated numbers never disagree.
            projected = current.map { $0 - lossPerKg * (goal - input.weightKg) }
            if let power {
                let needed = sayersPower(jumpCm: requiredJump / approachFactor, massKg: goal)
                powerIncrease = max(0, needed / power - 1)
            }
        }

        var gap: Double?
        var weeks: ClosedRange<Int>?
        var verdict: DunkReport.Verdict?
        if let current {
            let shortBy = requiredJump - current
            gap = shortBy
            let inches = shortBy / 2.54 - 1e-9
            verdict = inches <= 0 ? .canDunk : inches <= 3 ? .close : inches <= 8 ? .reachable : .longTerm
            if shortBy > 0 {
                let base = weeksToGain(shortBy)
                weeks = max(2, Int(Double(base) * 0.75))...Int((Double(base) * 1.35).rounded(.up))
            }
        }

        return DunkReport(reachCm: reach, reachIsEstimate: input.standingReachCm == nil, requiredTouchCm: requiredTouch,
                          requiredJumpCm: requiredJump, currentJumpCm: current, currentJumpIsEstimate: currentIsEstimate,
                          gapCm: gap, peakPowerW: power, jumpLossPerKgCm: lossPerKg, projectedJumpAtGoalCm: projected,
                          powerIncreaseNeededAtGoal: powerIncrease, estimatedWeeks: weeks, verdict: verdict)
    }
}
