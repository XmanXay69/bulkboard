import Foundation

public enum PRKind: String, Codable, CaseIterable, Sendable, Hashable {
    case heaviestWeight
    case bestE1RM
    case repPR

    public var title: String {
        switch self {
        case .heaviestWeight: "Heaviest"
        case .bestE1RM: "Best e1RM"
        case .repPR: "Rep PR"
        }
    }
}

public enum Strength {
    /// Sets above this many reps are too noisy for a 1RM estimate.
    public static let maxRepsForE1RM = 12

    /// Epley estimated one-rep max. A single is its own 1RM.
    public static func estimated1RM(weight: Double, reps: Int) -> Double {
        guard reps > 0, weight > 0 else { return 0 }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    /// PRs this set sets against `history` (earlier sets of any exercise; filtered here).
    /// The first time an exercise is logged sets a baseline, not a PR.
    public static func detectPRs(_ set: LoggedSet, history: [LoggedSet]) -> Set<PRKind> {
        guard !set.isWarmup, set.reps > 0 else { return [] }
        let prior = history.filter { $0.exerciseID == set.exerciseID && !$0.isWarmup && $0.reps > 0 }
        guard !prior.isEmpty else { return [] }

        let epsilon = 0.01
        var kinds: Set<PRKind> = []

        if set.weightKg > 0 {
            let heaviest = prior.map(\.weightKg).max() ?? 0
            if set.weightKg > heaviest + epsilon { kinds.insert(.heaviestWeight) }

            if set.reps <= maxRepsForE1RM {
                let bestE1RM = prior.filter { $0.reps <= maxRepsForE1RM }
                    .map { estimated1RM(weight: $0.weightKg, reps: $0.reps) }.max() ?? 0
                if estimated1RM(weight: set.weightKg, reps: set.reps) > bestE1RM + epsilon { kinds.insert(.bestE1RM) }
            }
        }

        // More reps than ever at this weight or heavier.
        let atOrAbove = prior.filter { $0.weightKg >= set.weightKg - epsilon }
        if let mostReps = atOrAbove.map(\.reps).max(), set.reps > mostReps { kinds.insert(.repPR) }

        return kinds
    }

    /// Rounds to the nearest plate increment.
    public static func roundToIncrement(_ weight: Double, increment: Double) -> Double {
        guard increment > 0 else { return weight }
        return (weight / increment).rounded() * increment
    }
}

public struct OverloadSuggestion: Hashable, Sendable {
    public enum Kind: String, Sendable { case firstTime, addWeight, addReps, repeatWeight, deload }

    public var kind: Kind
    /// In the caller's display unit.
    public var weight: Double?
    public var targetReps: Int
    public var message: String
}

/// Double progression: hit the top of the rep range on every working set, then add weight.
public enum OverloadAdvisor {
    /// - Parameters:
    ///   - lastSession: working sets (reps, weight) from the most recent session, in display units.
    ///   - increment: plate jump in display units.
    ///   - missedSessions: consecutive recent sessions that fell short of `repLow` at the top weight.
    public static func suggest(lastSession: [(reps: Int, weight: Double)], repLow: Int, repHigh: Int,
                               increment: Double, unit: String, missedSessions: Int = 0) -> OverloadSuggestion {
        let working = lastSession.filter { $0.reps > 0 }
        guard let top = working.map(\.weight).max() else {
            return OverloadSuggestion(kind: .firstTime, weight: nil, targetReps: repHigh,
                                      message: "First time. Pick a weight you can move for \(repHigh) clean reps.")
        }
        let atTop = working.filter { abs($0.weight - top) < 0.01 }
        let bestReps = atTop.map(\.reps).max() ?? 0
        let worstReps = atTop.map(\.reps).min() ?? 0
        let last = "\(Fmt.number(top)) × \(bestReps)"

        if top == 0 {
            // Bodyweight movement: progress with reps.
            return OverloadSuggestion(kind: .addReps, weight: 0, targetReps: bestReps + 1,
                                      message: "Last time \(bestReps) reps. Go for \(bestReps + 1).")
        }
        if worstReps >= repHigh {
            let next = Strength.roundToIncrement(top + increment, increment: increment)
            return OverloadSuggestion(kind: .addWeight, weight: next, targetReps: repLow,
                                      message: "Last time \(last) \(unit). Try \(Fmt.number(next)) today.")
        }
        if worstReps >= repLow {
            let goal = min(repHigh, bestReps + 1)
            return OverloadSuggestion(kind: .addReps, weight: top, targetReps: goal,
                                      message: "Last time \(last) \(unit). Stay at \(Fmt.number(top)), go for \(goal).")
        }
        if missedSessions >= 2 {
            let deload = Strength.roundToIncrement(top * 0.9, increment: increment)
            return OverloadSuggestion(kind: .deload, weight: deload, targetReps: repHigh,
                                      message: "Stuck at \(Fmt.number(top)). Deload to \(Fmt.number(deload)) and build back up.")
        }
        return OverloadSuggestion(kind: .repeatWeight, weight: top, targetReps: repLow,
                                  message: "Last time \(last) \(unit). Repeat \(Fmt.number(top)) and own \(repLow) reps.")
    }
}
