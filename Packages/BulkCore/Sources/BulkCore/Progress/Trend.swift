import Foundation

public struct WeightPoint: Hashable, Sendable {
    public var date: Date
    public var kg: Double

    public init(date: Date, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

public struct WeightProjection: Sendable, Equatable {
    /// Fitted rate of change (kg/week); positive = gaining.
    public var kgPerWeek: Double
    /// Fitted weight today.
    public var currentTrendKg: Double
    /// Where the trend lands on the target date.
    public var projectedAtTargetKg: Double?
    /// When the trend crosses the goal weight, if it's heading there.
    public var projectedGoalDate: Date?
    /// Weekly points from today along the fitted line, for charting.
    public var line: [WeightPoint]
}

public enum Trend {
    /// Trailing moving average over a time window: each point is the mean of all weigh-ins in the
    /// `windowDays` ending on that date. Handles missed days without inventing data.
    public static func movingAverage(_ points: [WeightPoint], windowDays: Int = 7, calendar: Calendar = .bulk) -> [WeightPoint] {
        let sorted = points.sorted { $0.date < $1.date }
        return sorted.map { point in
            let start = calendar.date(byAdding: .day, value: -(windowDays - 1), to: calendar.startOfDay(for: point.date)) ?? point.date
            let window = sorted.filter { $0.date >= start && $0.date <= point.date }
            return WeightPoint(date: point.date, kg: window.map(\.kg).reduce(0, +) / Double(window.count))
        }
    }

    /// Least-squares line through the points; x is days since `origin`.
    public static func linearFit(_ points: [WeightPoint], origin: Date) -> (slopePerDay: Double, intercept: Double)? {
        guard points.count >= 2 else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(origin) / 86_400 }
        let ys = points.map(\.kg)
        let n = Double(points.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        let sxx = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard sxx > 1e-9 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let slope = sxy / sxx
        return (slope, meanY - slope * meanX)
    }

    /// Fits the last `lookbackDays` of weigh-ins and projects toward the goal.
    /// Needs at least 3 weigh-ins spanning 5+ days to say anything.
    public static func project(_ points: [WeightPoint], goalKg: Double, targetDate: Date, today: Date,
                               lookbackDays: Int = 28, calendar: Calendar = .bulk) -> WeightProjection? {
        let start = calendar.date(byAdding: .day, value: -lookbackDays, to: today) ?? today
        let recent = points.filter { $0.date >= start && $0.date <= today }.sorted { $0.date < $1.date }
        guard recent.count >= 3, let first = recent.first, let last = recent.last,
              WeekMath.daysBetween(first.date, last.date, calendar: calendar) >= 5,
              let fit = linearFit(recent, origin: today) else { return nil }

        let current = fit.intercept
        let perDay = fit.slopePerDay
        let daysToTarget = Double(WeekMath.daysBetween(today, targetDate, calendar: calendar))

        var goalDate: Date?
        let remaining = goalKg - current
        if abs(remaining) < 0.05 {
            goalDate = calendar.startOfDay(for: today)
        } else if perDay != 0 && remaining / perDay > 0 {
            let days = remaining / perDay
            if days < 3650 { goalDate = calendar.date(byAdding: .day, value: Int(days.rounded()), to: calendar.startOfDay(for: today)) }
        }

        let horizonDays = Int(min(365, max(daysToTarget, goalDate.map { Double(WeekMath.daysBetween(today, $0, calendar: calendar)) } ?? 0, 28)))
        let line = stride(from: 0, through: horizonDays, by: 7).compactMap { day -> WeightPoint? in
            guard let date = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: today)) else { return nil }
            return WeightPoint(date: date, kg: current + perDay * Double(day))
        }

        return WeightProjection(kgPerWeek: perDay * 7, currentTrendKg: current,
                                projectedAtTargetKg: daysToTarget > 0 ? current + perDay * daysToTarget : nil,
                                projectedGoalDate: goalDate, line: line)
    }
}
