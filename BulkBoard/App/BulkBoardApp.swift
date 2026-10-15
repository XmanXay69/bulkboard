import SwiftData
import SwiftUI

@main
struct BulkBoardApp: App {
    @State private var appModel: AppModel
    @AppStorage("appearance") private var appearance: AppearancePreference = .dark

    private let container: ModelContainer

    init() {
        // `--appearance=light|dark|system` overrides the saved preference for this run only (screenshots, testing).
        if let override = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--appearance=") })?.split(separator: "=").last {
            UserDefaults.standard.setVolatileDomain(["appearance": String(override)], forName: UserDefaults.argumentDomain)
        }
        let model = AppModel()
        do {
            container = try Persistence.makeContainer()
        } catch {
            // A broken store shouldn't brick the app; fall back to memory and surface the error.
            container = try! Persistence.makeContainer(inMemory: true)
            model.startupError = "Couldn't open your data store (\(error.localizedDescription)). Running with a temporary store."
        }
        _appModel = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup("BulkBoard", id: "main") {
            RootView()
                .environment(appModel)
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(container)
        .defaultSize(width: 1280, height: 840)
        .windowToolbarStyle(.unified)
        .commands { BulkBoardCommands(appModel: appModel, container: container) }

        Window("Grocery Run", id: "grocery") {
            GroceryPopoutView()
                .environment(appModel)
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(container)
        .defaultSize(width: 390, height: 780)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(appModel)
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(container)
    }
}
