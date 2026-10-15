import Foundation

/// Energy (kcal) and macronutrients (grams).
public struct Macros: Codable, Hashable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double

    public init(kcal: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    public static let zero = Macros()

    /// Calories implied by the macros using 4/4/9 kcal per gram.
    public var kcalFromMacros: Double { protein * 4 + carbs * 4 + fat * 9 }

    public static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(kcal: lhs.kcal + rhs.kcal, protein: lhs.protein + rhs.protein,
               carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat)
    }

    public static func - (lhs: Macros, rhs: Macros) -> Macros {
        Macros(kcal: lhs.kcal - rhs.kcal, protein: lhs.protein - rhs.protein,
               carbs: lhs.carbs - rhs.carbs, fat: lhs.fat - rhs.fat)
    }

    public static func * (lhs: Macros, rhs: Double) -> Macros {
        Macros(kcal: lhs.kcal * rhs, protein: lhs.protein * rhs,
               carbs: lhs.carbs * rhs, fat: lhs.fat * rhs)
    }

    public static func += (lhs: inout Macros, rhs: Macros) { lhs = lhs + rhs }

    /// Rounded to whole numbers, for display and stable comparisons.
    public var rounded: Macros {
        Macros(kcal: kcal.rounded(), protein: protein.rounded(),
               carbs: carbs.rounded(), fat: fat.rounded())
    }
}

public extension Sequence where Element == Macros {
    func sum() -> Macros { reduce(.zero, +) }
}
