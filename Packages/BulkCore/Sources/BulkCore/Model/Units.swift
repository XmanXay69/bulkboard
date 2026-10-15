import Foundation

public enum UnitSystem: String, Codable, CaseIterable, Sendable {
    case imperial
    case metric

    public var massLabel: String { self == .imperial ? "lb" : "kg" }
}

/// Unit conversions. Everything is stored metric (kg, cm) and converted for display.
public enum Units {
    public static let kgPerLb = 0.45359237
    public static let cmPerInch = 2.54

    public static func kg(fromLb lb: Double) -> Double { lb * kgPerLb }
    public static func lb(fromKg kg: Double) -> Double { kg / kgPerLb }
    public static func cm(fromInches inches: Double) -> Double { inches * cmPerInch }
    public static func inches(fromCm cm: Double) -> Double { cm / cmPerInch }

    /// Converts kilograms to the display unit of `system`.
    public static func display(kg: Double, in system: UnitSystem) -> Double {
        system == .imperial ? lb(fromKg: kg) : kg
    }

    /// Converts a value typed in the display unit of `system` back to kilograms.
    public static func kg(fromDisplay value: Double, in system: UnitSystem) -> Double {
        system == .imperial ? kg(fromLb: value) : value
    }

    /// Smallest sensible plate jump for barbell work in each system.
    public static func plateIncrement(in system: UnitSystem) -> Double {
        system == .imperial ? 5 : 2.5
    }
}
