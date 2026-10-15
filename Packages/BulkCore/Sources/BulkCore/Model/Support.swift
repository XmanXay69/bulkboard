import Foundation

public extension Calendar {
    /// Gregorian, Monday-first calendar used for all week math.
    static var bulk: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }
}

public enum WeekMath {
    public static func startOfWeek(_ date: Date, calendar: Calendar = .bulk) -> Date {
        let day = calendar.startOfDay(for: date)
        let index = weekdayIndex(day, calendar: calendar)
        return calendar.date(byAdding: .day, value: -index, to: day) ?? day
    }

    /// 0 = Monday … 6 = Sunday, independent of locale.
    public static func weekdayIndex(_ date: Date, calendar: Calendar = .bulk) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    public static func days(ofWeekStarting start: Date, calendar: Calendar = .bulk) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    public static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar = .bulk) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }

    public static let weekdayShort = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    public static let weekdayLong = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
}

/// Deterministic RNG so "shuffle" is reproducible in tests.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Locale-independent number formatting for math breakdowns and messages.
public enum Fmt {
    /// 3416 → "3,416"
    public static func int(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        let digits = String(abs(rounded))
        var out = ""
        for (index, char) in digits.reversed().enumerated() {
            if index > 0 && index % 3 == 0 { out.append(",") }
            out.append(char)
        }
        return (rounded < 0 ? "-" : "") + String(out.reversed())
    }

    /// Trims trailing zeros: 135.0 → "135", 2.50 → "2.5".
    public static func number(_ value: Double, maxDecimals: Int = 1) -> String {
        let factor = pow(10, Double(maxDecimals))
        let rounded = (value * factor).rounded() / factor
        if rounded == rounded.rounded() { return int(rounded) }
        var text = String(format: "%.\(maxDecimals)f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    /// "+375" / "-250"
    public static func signed(_ value: Double) -> String {
        value >= 0 ? "+\(int(value))" : int(value)
    }
}
