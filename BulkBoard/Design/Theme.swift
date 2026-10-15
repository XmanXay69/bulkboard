import AppKit
import BulkCore
import SwiftUI

/// Design tokens. Court-inspired: deep navy floor, hardwood orange, scoreboard amber.
enum Theme {
    // Brand
    static let hardwood = Color(hex: 0xF07A2A)
    static let hardwoodDeep = Color(hex: 0xC4561A)
    static let scoreboard = Color(light: 0xB87A00, dark: 0xFFB224)
    static let net = Color(hex: 0x2FC48D)
    static let rim = Color(hex: 0xEF4F55)
    static let paint = Color(hex: 0x4D8EFF)

    // Macros: brighter on dark surfaces, deeper on light ones so small text stays readable.
    static let kcal = Color(light: 0xB27500, dark: 0xFFB224)
    static let protein = Color(light: 0xD0581C, dark: 0xF07A2A)
    static let carbs = Color(light: 0x2A6FD0, dark: 0x4D8EFF)
    static let fat = Color(light: 0x0F8A7E, dark: 0x2EC4B6)

    // Surfaces
    static let background = Color(light: 0xF6F2EC, dark: 0x0A1020)
    static let surface = Color(light: 0xFFFFFF, dark: 0x121A2E)
    static let surfaceRaised = Color(light: 0xF0EBE3, dark: 0x1A2440)
    static let sidebar = Color(light: 0xEDE6DC, dark: 0x070C18)
    static let stroke = Color(light: 0x0E1726, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.08)
    static let textPrimary = Color(light: 0x0E1726, dark: 0xF2F4F8)
    static let textSecondary = Color(light: 0x5A6478, dark: 0x9AA6BF)

    static let cornerRadius: CGFloat = 16
    static let spacing: CGFloat = 20

    static func color(for dayType: DayType) -> Color {
        switch dayType {
        case .lifting: hardwood
        case .conditioning: paint
        case .rest: net
        }
    }

    static var heroGradient: LinearGradient {
        LinearGradient(colors: [hardwood, hardwoodDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Font {
    /// Big, heavy, monospaced-digit numerals for scoreboard stats.
    static func scoreboard(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded).monospacedDigit()
    }

    /// Small uppercase label above a section.
    static let eyebrow = Font.system(size: 11, weight: .bold, design: .rounded)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// A color that follows the effective light/dark appearance.
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case dark, light, system

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}
