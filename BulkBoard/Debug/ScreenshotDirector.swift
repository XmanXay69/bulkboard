import AppKit
import SwiftData
import SwiftUI

/// Launch-argument driven screen capture, used for README screenshots and smoke-checking screens.
///
///     open BulkBoard.app --args --in-memory --sample --capture=<dir> [--sections=dashboard,meals] [--onboarding] [--size=1440x900] [--full-page] [--quit]
///
/// Values use `--key=value`: a bare path argument makes AppKit treat it as a file to open and skip the main window.
/// Renders each screen with AppKit's `cacheDisplay`, so it needs no Screen Recording permission.
enum ScreenshotDirector {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    private static func value(after flag: String) -> String? {
        arguments.first { $0.hasPrefix(flag + "=") }.map { String($0.dropFirst(flag.count + 1)) }
    }

    static var isCapturing: Bool { value(after: "--capture") != nil }

    static func run(appModel: AppModel, context: ModelContext) async {
        guard let path = value(after: "--capture") else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try? await Task.sleep(for: .milliseconds(600))
        resizeWindow()

        if arguments.contains("--onboarding") {
            for step in OnboardingView.Step.allCases {
                appModel.onboardingStep = step
                await capture(to: directory.appendingPathComponent("onboarding-\(step.rawValue)-\(step).png"))
            }
        }

        #if DEBUG
        if arguments.contains("--sample"), Persistence.usesInMemoryStore, context.profile == nil {
            SampleData.load(into: context)
        }
        #endif

        if context.profile != nil {
            let sections = value(after: "--sections")?.split(separator: ",").compactMap { AppSection(rawValue: String($0)) }
                ?? AppSection.allCases
            for (index, section) in sections.enumerated() {
                appModel.section = section
                if section == .body {
                    for tab in BodyTab.allCases {
                        appModel.bodyTab = tab
                        await capture(to: directory.appendingPathComponent(String(format: "%02d-body-%@.png", index + 1, tab.rawValue.lowercased())))
                    }
                    appModel.bodyTab = .physique
                    continue
                }
                if section == .meals {
                    for tab in MealsTab.allCases {
                        appModel.mealsTab = tab
                        await capture(to: directory.appendingPathComponent(String(format: "%02d-meals-%@.png", index + 1, tab == .mine ? "mine" : "suggested")))
                    }
                    appModel.mealsTab = .mine
                    continue
                }
                if section == .training {
                    for tab in TrainingTab.allCases {
                        appModel.trainingTab = tab
                        if tab == .log { startSampleSession(context) }
                        await capture(to: directory.appendingPathComponent(String(format: "%02d-training-%@.png", index + 1, tab.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))))
                    }
                    appModel.trainingTab = .week
                    continue
                }
                await capture(to: directory.appendingPathComponent(String(format: "%02d-%@.png", index + 1, section.rawValue)))
            }
        }

        if value(after: "--sheet") == "log-meal", context.profile != nil {
            await captureLogMeal(appModel: appModel, context: context, to: directory)
        }
        if value(after: "--sheet") == "update", context.profile != nil {
            await Updater.shared.check(userInitiated: false)
            Updater.shared.showSheet = Updater.shared.isUpdateAvailable
            await capture(to: directory.appendingPathComponent("update.png"), sheet: true)
            Updater.shared.showSheet = false
        }

        if arguments.contains("--quit") { NSApp.terminate(nil) }
    }

    /// Opens Log a meal with two typed items, looks them up for real (food list + Open Food Facts),
    /// picks the top match for each, and captures the sheet.
    private static func captureLogMeal(appModel: AppModel, context: ModelContext, to directory: URL) async {
        appModel.section = .meals
        let draft = MealDraft(day: .now, slot: .lunch)
        let pizza = draft.items[0]
        pizza.product = "pepperoni pizza"
        pizza.brand = "DiGiorno"
        pizza.quantity = 2
        pizza.unit = .serving
        let shake = ItemDraft()
        shake.product = "chocolate protein shake"
        shake.brand = "Fairlife"
        shake.quantity = 1
        shake.unit = .piece("bottle")
        draft.items.append(shake)
        appModel.activeSheet = .logMeal(draft)
        try? await Task.sleep(for: .milliseconds(800))
        let library = MealLibrary(context)
        for item in draft.items {
            await ItemLookup.search(item, library: library)
            if let online = item.results.first(where: { if case .product = $0.kind { true } else { false } }) ?? item.results.first {
                await ItemLookup.choose(online, for: item, library: library)
            }
            print("lookup:", item.product, "->", item.match?.name ?? "none", item.match?.detail ?? "", item.macros.map { "\($0.kcal) kcal" } ?? "")
        }
        await capture(to: directory.appendingPathComponent("log-meal.png"), sheet: true)
        appModel.activeSheet = nil
    }

    /// A half-finished session so the logger screenshot shows previous performance, suggestions and PRs.
    private static func startSampleSession(_ context: ModelContext) {
        guard TrainingActions.activeSession(context) == nil,
              let day = context.workoutPlan?.day(for: .now).flatMap({ $0.dayType == .lifting ? $0 : nil })
                ?? context.workoutPlan?.days.first(where: { $0.dayType == .lifting }) else { return }
        let session = TrainingActions.startSession(from: day, on: .now.addingTimeInterval(-23 * 60), context: context)
        for set in session.sets.prefix(5) {
            TrainingActions.setDone(set.id, done: true, in: session, context: context)
        }
    }

    private static func resizeWindow() {
        guard let window = mainWindow else { return }
        var size = CGSize(width: 1440, height: 900)
        if let text = value(after: "--size") {
            let parts = text.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 { size = CGSize(width: parts[0], height: parts[1]) }
        }
        window.setContentSize(size)
        window.center()
    }

    /// The tallest scrollable page in the window, for whole-page captures.
    private static func largestScrollDocument(in root: NSView) -> NSView? {
        var best: NSView?
        func visit(_ view: NSView) {
            if let scroll = view as? NSScrollView, let document = scroll.documentView,
               document.bounds.height > (best?.bounds.height ?? 0), scroll.bounds.width > 600 {
                best = document
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        return best
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    }

    private static func capture(to url: URL, sheet: Bool = false) async {
        try? await Task.sleep(for: .milliseconds(Int(value(after: "--delay") ?? "") ?? 1200))
        guard let main = mainWindow else { return }
        let window = sheet ? main.attachedSheet ?? main : main
        guard var view = window.contentView?.superview ?? window.contentView else { return }
        if arguments.contains("--full-page"), let document = largestScrollDocument(in: view) {
            view = document
        }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
