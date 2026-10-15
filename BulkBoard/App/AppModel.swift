import BulkCore
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

enum TrainingTab: String, CaseIterable {
    case week = "This Week"
    case log = "Log"
    case history = "History"
    case exercises = "Exercises"
}

/// Sheets any screen or menu command can open.
enum ActiveSheet: Identifiable, Equatable {
    case weighIn
    case quickAdd
    case court(minutes: Int, kind: CourtSessionKind)
    case coach

    var id: String {
        switch self {
        case .weighIn: "weighIn"
        case .quickAdd: "quickAdd"
        case .court: "court"
        case .coach: "coach"
        }
    }
}

/// App-wide UI state: navigation, sheets, and transient banners.
@Observable
final class AppModel {
    var section: AppSection = .dashboard
    var onboardingStep: OnboardingView.Step = .welcome
    var startupError: String?
    /// Week shown in the meal planner and used for grocery generation.
    var planWeekStart: Date = Date.now.weekStart
    /// Set to a week start to ask the grocery screen to rebuild from that week's plan.
    var groceryRequest: Date?
    var showMealLibrary = false
    var trainingTab: TrainingTab = .week
    var celebration: Celebration?
    var activeSheet: ActiveSheet?
    var hasProfile = false
    let restTimer = RestTimer()

    func celebrate(_ kind: Celebration.Kind, title: String, detail: String) {
        celebration = Celebration(kind: kind, title: title, detail: detail)
    }
}
