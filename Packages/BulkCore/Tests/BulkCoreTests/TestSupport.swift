import Foundation
@testable import BulkCore

enum Fixture {
    static let calendar = Calendar.bulk

    /// Monday, 5 Jan 2026.
    static let today = date(2026, 1, 5)

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func day(_ offset: Int, from base: Date = today) -> Date {
        calendar.date(byAdding: .day, value: offset, to: base)!
    }

    static func profile(weightKg: Double = 80, goalKg: Double? = nil, weeks: Double = 16,
                        mode: GoalMode = .bulkPerformance, sex: Sex = .male, age: Int = 25,
                        heightCm: Double = 180, activity: ActivityLevel = .active,
                        lifting: Int = 4, court: Int = 2) -> BodyProfile {
        BodyProfile(age: age, sex: sex, heightCm: heightCm, weightKg: weightKg,
                    goalWeightKg: goalKg ?? weightKg + Units.kg(fromLb: 10),
                    startDate: today, targetDate: day(Int(weeks * 7)),
                    activity: activity, mode: mode, liftingDaysPerWeek: lifting, courtDaysPerWeek: court)
    }
}
