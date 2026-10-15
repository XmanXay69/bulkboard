import AppKit
import SwiftData
import SwiftUI

/// Launch-argument driven screen capture, used for README screenshots and smoke-checking screens.
///
///     open BulkBoard.app --args --in-memory --demo --capture=<dir> [--sections=dashboard,meals] [--onboarding] [--size=1440x900] [--quit]
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

        if arguments.contains("--demo"), context.profile == nil {
            DemoData.load(into: context)
        }

        if context.profile != nil {
            let sections = value(after: "--sections")?.split(separator: ",").compactMap { AppSection(rawValue: String($0)) }
                ?? AppSection.allCases
            for (index, section) in sections.enumerated() {
                appModel.section = section
                await capture(to: directory.appendingPathComponent(String(format: "%02d-%@.png", index + 1, section.rawValue)))
            }
        }

        if arguments.contains("--quit") { NSApp.terminate(nil) }
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

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    }

    private static func capture(to url: URL) async {
        try? await Task.sleep(for: .milliseconds(1200))
        guard let window = mainWindow, let view = window.contentView?.superview ?? window.contentView else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
