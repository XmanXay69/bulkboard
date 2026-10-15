import Foundation
import Observation

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, meals, grocery, training, progress, targets, library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .meals: "Meal Plan"
        case .grocery: "Grocery List"
        case .training: "Training"
        case .progress: "Progress"
        case .targets: "Targets"
        case .library: "Foods & Recipes"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "rectangle.3.group.fill"
        case .meals: "fork.knife"
        case .grocery: "cart.fill"
        case .training: "dumbbell.fill"
        case .progress: "chart.line.uptrend.xyaxis"
        case .targets: "target"
        case .library: "books.vertical.fill"
        }
    }

    /// ⌘1…⌘7
    var shortcutKey: Character {
        Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 1))
    }
}

/// App-wide UI state: navigation, sheets, and transient banners.
@Observable
final class AppModel {
    var section: AppSection = .dashboard
    var onboardingStep: OnboardingView.Step = .welcome
    var startupError: String?
}
