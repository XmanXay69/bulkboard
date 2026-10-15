import AppKit
import BulkCore
import SwiftUI

/// Design tokens. Neutral surfaces, one accent, and two status colors used sparingly.
enum Theme {
    static let accent = Color(light: 0x2563EB, dark: 0x4C8DFF)
    static let positive = Color(light: 0x15803D, dark: 0x32D74B)
    static let negative = Color(light: 0xDC2626, dark: 0xFF6961)

    static let background = Color(light: 0xF5F5F7, dark: 0x161618)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1F1F22)
    static let surfaceRaised = Color(light: 0xEEEEF1, dark: 0x2A2A2E)
    static let sidebar = Color(light: 0xECECEF, dark: 0x1A1A1D)
    static let stroke = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.08)
    static let textPrimary = Color(light: 0x1D1D1F, dark: 0xF2F2F4)
    static let textSecondary = Color(light: 0x6E6E73, dark: 0x9A9AA0)

    static let cornerRadius: CGFloat = 12
    static let spacing: CGFloat = 20
}

extension Font {
    /// Numbers that matter: semibold with tabular digits.
    static func stat(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold).monospacedDigit()
    }
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
    case system, light, dark

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
