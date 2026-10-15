import BulkCore
import SwiftData
import SwiftUI

/// Menu bar commands and keyboard shortcuts.
struct BulkBoardCommands: Commands {
    var appModel: AppModel
    var container: ModelContainer

    private var context: ModelContext { container.mainContext }

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(AppSection.allCases) { section in
                Button(section.title) { appModel.section = section }
                    .keyboardShortcut(KeyEquivalent(section.shortcutKey), modifiers: .command)
            }
            .disabled(!appModel.hasProfile)
        }

        CommandMenu("Plan") {
            Group {
                Button("Auto-fill Week") {
                    MealPlanActions.autoFill(weekOf: appModel.planWeekStart, context: context, seed: UInt64.random(in: 1...UInt64.max))
                    appModel.section = .meals
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Shuffle Unlocked Meals") {
                    MealPlanActions.autoFill(weekOf: appModel.planWeekStart, context: context, seed: UInt64.random(in: 1...UInt64.max))
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Build Grocery List") {
                    appModel.groceryRequest = appModel.planWeekStart
                    appModel.section = .grocery
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                Divider()
                Button("Previous Week") { appModel.planWeekStart = appModel.planWeekStart.adding(days: -7) }
                    .keyboardShortcut("[", modifiers: .command)
                Button("Next Week") { appModel.planWeekStart = appModel.planWeekStart.adding(days: 7) }
                    .keyboardShortcut("]", modifiers: .command)
                Button("This Week") { appModel.planWeekStart = Date.now.weekStart }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            .disabled(!appModel.hasProfile)
        }

        CommandMenu("Log") {
            Group {
                Button("Weigh-In…") { appModel.activeSheet = .weighIn }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                Button("Quick Add Food…") { appModel.activeSheet = .quickAdd }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Start Today's Workout") { startTodaysWorkout() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Log Basketball Session…") { appModel.activeSheet = .court(minutes: 60, kind: .pickup) }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Divider()
                Button("Ask the Coach…") { appModel.activeSheet = .coach }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(!OllamaClient.shared.isAvailable)
            }
            .disabled(!appModel.hasProfile)
        }

        CommandGroup(replacing: .importExport) {
            Button("Export Backup…") { BackupService.exportJSON(context) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Export CSV Logs…") { BackupService.exportCSV(context) }
            Button("Import Backup…") { BackupService.importJSON(context) }
        }

        CommandGroup(replacing: .help) {
            Link("BulkBoard on GitHub", destination: URL(string: "https://github.com/XmanXay69/bulkboard")!)
        }
    }

    private func startTodaysWorkout() {
        appModel.section = .training
        appModel.trainingTab = .log
        guard TrainingActions.activeSession(context) == nil,
              let today = context.workoutPlan?.day(for: .now), today.dayType == .lifting else { return }
        TrainingActions.startSession(from: today, context: context)
    }
}
