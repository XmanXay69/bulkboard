import BulkCore
import Foundation

/// Display formatting that depends on the user's unit system.
struct UnitFormatter {
    var system: UnitSystem

    var massUnit: String { system.massLabel }

    func weight(_ kg: Double, decimals: Int = 1) -> String {
        "\(Fmt.number(Units.display(kg: kg, in: system), maxDecimals: decimals)) \(massUnit)"
    }

    func weightValue(_ kg: Double, decimals: Int = 1) -> String {
        Fmt.number(Units.display(kg: kg, in: system), maxDecimals: decimals)
    }

    func signedWeight(_ kg: Double, decimals: Int = 1) -> String {
        let value = Units.display(kg: kg, in: system)
        return "\(value >= 0 ? "+" : "−")\(Fmt.number(abs(value), maxDecimals: decimals)) \(massUnit)"
    }

    func height(_ cm: Double) -> String {
        switch system {
        case .imperial:
            let totalInches = Int(Units.inches(fromCm: cm).rounded())
            return "\(totalInches / 12)′\(totalInches % 12)″"
        case .metric:
            return "\(Int(cm.rounded())) cm"
        }
    }

    func volume(_ kg: Double) -> String {
        let value = Units.display(kg: kg, in: system)
        return value >= 10_000 ? "\(Fmt.number(value / 1000)) k \(massUnit)" : "\(Fmt.int(value)) \(massUnit)"
    }

    var plateIncrement: Double { Units.plateIncrement(in: system) }

    var lengthUnit: String { system == .imperial ? "in" : "cm" }

    func lengthValue(_ cm: Double) -> Double { system == .imperial ? cm / 2.54 : cm }

    func cm(fromDisplay value: Double) -> Double { system == .imperial ? value * 2.54 : value }

    func length(_ cm: Double, decimals: Int = 1) -> String {
        "\(Fmt.number(lengthValue(cm), maxDecimals: decimals)) \(lengthUnit)"
    }

    /// Heights like a rim or a reach: 10′0″ or 305 cm.
    func tall(_ cm: Double) -> String {
        switch system {
        case .imperial:
            let inches = Int((cm / 2.54).rounded())
            return "\(inches / 12)′\(inches % 12)″"
        case .metric:
            return "\(Int(cm.rounded())) cm"
        }
    }
}

extension Date {
    var dayStart: Date { Calendar.bulk.startOfDay(for: self) }

    func adding(days: Int) -> Date { Calendar.bulk.date(byAdding: .day, value: days, to: self) ?? self }

    var weekStart: Date { WeekMath.startOfWeek(self) }

    var shortDay: String { formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }

    var monthDay: String { formatted(.dateTime.month(.abbreviated).day()) }
}

extension Macros {
    var kcalText: String { Fmt.int(kcal) }
    var summary: String { "\(Fmt.int(kcal)) kcal · \(Fmt.int(protein))P · \(Fmt.int(carbs))C · \(Fmt.int(fat))F" }
}
