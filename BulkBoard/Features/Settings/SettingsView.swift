import BulkCore
import SwiftData
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            OnlineSettings().tabItem { Label("Online", systemImage: "network") }
            AISettings().tabItem { Label("Local AI", systemImage: "sparkles") }
            DataSettings().tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 580, height: 500)
    }
}

struct GeneralSettings: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [ProfileRecord]
    @AppStorage("appearance") private var appearance: AppearancePreference = .system
    @AppStorage("mealVariety") private var variety: MealVariety = .balanced

    var body: some View {
        Form {
            Section("Look") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("System follows macOS.").font(.caption).foregroundStyle(.secondary)
            }
            if let profile = profiles.first {
                Section("Units & goal") {
                    Picker("Units", selection: Binding(get: { profile.unitSystem }, set: { profile.unitSystem = $0 })) {
                        Text("Pounds / feet").tag(UnitSystem.imperial)
                        Text("Kilograms / cm").tag(UnitSystem.metric)
                    }
                    Picker("Goal", selection: Binding(get: { profile.goalMode }, set: { profile.goalMode = $0 })) {
                        ForEach(GoalMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Stepper("Snacks per day: \(count(.snack, in: profile))", value: slotBinding(.snack, profile: profile), in: 0...3)
                    Stepper("Shakes per day: \(count(.shake, in: profile))", value: slotBinding(.shake, profile: profile), in: 0...3)
                    Picker("Suggestion variety", selection: $variety) {
                        ForEach(MealVariety.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Suggested meals")
                } footer: {
                    Text("Breakfast, lunch and dinner are always on. Re-suggest the week after changing slots.")
                }
                Section("Food preferences") {
                    TextField("Dislikes (comma-separated)", text: Binding(
                        get: { profile.dislikes.joined(separator: ", ") },
                        set: { text in profile.dislikes = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                    FlowLayout(spacing: 6) {
                        ForEach(Allergen.allCases, id: \.self) { allergen in
                            Chip(title: allergen.title, isOn: profile.allergens.contains(allergen)) {
                                if profile.allergens.contains(allergen) { profile.allergens.remove(allergen) } else { profile.allergens.insert(allergen) }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func count(_ slot: MealSlot, in profile: ProfileRecord) -> Int {
        profile.mealSlots.filter { $0 == slot }.count
    }

    private func slotBinding(_ slot: MealSlot, profile: ProfileRecord) -> Binding<Int> {
        Binding {
            count(slot, in: profile)
        } set: { newCount in
            let snacks = slot == .snack ? newCount : count(.snack, in: profile)
            let shakes = slot == .shake ? newCount : count(.shake, in: profile)
            var slots: [MealSlot] = [.breakfast, .lunch]
            if snacks > 0 { slots.append(.snack) }
            slots.append(.dinner)
            slots += Array(repeating: .snack, count: max(0, snacks - 1))
            slots += Array(repeating: .shake, count: shakes)
            profile.mealSlots = slots
            try? context.save()
        }
    }
}

struct OnlineSettings: View {
    @State private var updater = Updater.shared
    @State private var lookup = NutritionLookup.shared

    var body: some View {
        Form {
            Section {
                Toggle("Check for updates automatically", isOn: $updater.autoCheck)
                LabeledContent("Version") { Text(updater.currentVersion.description) }
                LabeledContent("Last checked") {
                    Text(updater.lastChecked?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                }
                HStack {
                    Button("Check now") { Task { await updater.check(userInitiated: true) } }
                        .disabled(updater.isBusy)
                    if updater.phase == .checking { ProgressView().controlSize(.small) }
                    if let message = updater.lastMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
                if updater.location == .diskImage || updater.location == .translocated {
                    Button("Move to Applications") { updater.moveToApplications() }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Asks GitHub every few hours whether a newer release is out (github.com/\(Updater.repository)). The update button in the toolbar lights up when there is. Nothing about you is sent.")
            }
            Section {
                Toggle("Look up nutrition online", isOn: $lookup.isEnabled)
            } header: {
                Text("Food lookup")
            } footer: {
                Text("When you look up an item, the product and brand you typed (or a barcode) are sent to Open Food Facts, a free, open food database, to find the label numbers. Off: only your food list and the local AI are searched.")
            }
        }
        .formStyle(.grouped)
    }
}

struct AISettings: View {
    @State private var client = OllamaClient.shared

    var body: some View {
        Form {
            Section {
                Toggle("Use local AI", isOn: $client.isEnabled)
                Toggle("Start Ollama automatically when it's installed", isOn: $client.autoStart)
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(client.isAvailable ? Theme.positive : Theme.textSecondary).frame(width: 8, height: 8)
                        Text(statusText)
                    }
                }
                if client.isAvailable {
                    Picker("Text model", selection: $client.model) {
                        ForEach(client.models, id: \.self) { Text($0).tag($0) }
                    }
                    if !client.visionModels.isEmpty {
                        Picker("Photo model", selection: $client.visionModel) {
                            ForEach(client.visionModels, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
                HStack {
                    Button("Check again") { Task { await client.connect() } }
                    if !client.isAvailable && client.isInstalled {
                        Button("Start Ollama") { Task { await client.startServer() } }.disabled(client.isStarting)
                    }
                }
            } header: {
                Text("Ollama")
            } footer: {
                Text("BulkBoard only talks to Ollama on this Mac (127.0.0.1:11434). No cloud, no API keys. Everything works without it; AI numbers are labeled as estimates.")
            }
            Section {
                AIModelSetupView()
            } header: {
                Text("Photo model")
            }
        }
        .formStyle(.grouped)
        .task { await client.connect() }
    }

    private var statusText: String {
        if client.isChecking || client.isStarting { return "Connecting…" }
        if client.isAvailable { return "Ready · \(client.models.count) model\(client.models.count == 1 ? "" : "s")" }
        if !client.isInstalled { return "Ollama isn't installed" }
        return "Not running"
    }
}

/// Install / download state for the local AI, with the one action that gets it working.
struct AIModelSetupView: View {
    @State private var client = OllamaClient.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pull = client.pull {
                Text("Downloading \(pull.model)…").font(.system(size: 13, weight: .medium))
                if let fraction = pull.fraction {
                    ProgressView(value: fraction) { Text(pull.status).font(.caption).foregroundStyle(.secondary) }
                } else {
                    ProgressView { Text(pull.status).font(.caption).foregroundStyle(.secondary) }
                }
            } else if !client.isInstalled {
                Text("Install Ollama (free) to get photo reviews, meal photo reading and macro estimates, all on this Mac.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    Link("Download Ollama", destination: URL(string: "https://ollama.com/download/mac")!)
                    Text("or: brew install ollama").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                }
            } else if client.canSeeImages {
                Label("\(client.visionModel) can read photos.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.positive).font(.system(size: 12))
            } else {
                Text("Download \(OllamaClient.recommendedModel) (\(OllamaClient.recommendedModelSize)) to review check-in photos and read meal photos. It also handles text.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Download photo model") { Task { await client.pullModel() } }
            }
            if let error = client.pullError {
                Text(error).font(.caption).foregroundStyle(Theme.negative)
            }
        }
    }
}

struct DataSettings: View {
    @Environment(\.modelContext) private var context
    @AppStorage("autoBackup") private var autoBackup = true
    @AppStorage("backupFolder") private var backupFolder = ""
    @State private var lastBackup = BackupService.newestBackupDate()
    @State private var confirmReset = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Toggle("Back up automatically once a day", isOn: $autoBackup)
                LabeledContent("Folder") {
                    HStack {
                        Text(BackupService.backupFolder.path(percentEncoded: false))
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Change…") { chooseFolder() }
                        Button("Show") { NSWorkspace.shared.open(ensureFolder()) }
                    }
                }
                LabeledContent("Last backup") {
                    Text(lastBackup?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                }
                Button("Back up now") {
                    do {
                        let url = try BackupService.writeBackup(context)
                        lastBackup = BackupService.newestBackupDate()
                        message = "Saved \(url.lastPathComponent)"
                    } catch { message = error.localizedDescription }
                }
            } header: {
                Text("Backups")
            } footer: {
                Text("Keeps the 14 most recent. Backups contain your health data, meals and measurements; photos stay in the Photos folder and aren't included. Updates never touch your data, and each new version copies the database aside before its first launch (Snapshots folder).")
            }
            Section("Export & import") {
                HStack {
                    Button("Export JSON backup…") { BackupService.exportJSON(context) }
                    Button("Export CSV logs…") { BackupService.exportCSV(context) }
                    Button("Import backup…") { BackupService.importJSON(context) }
                }
            }
            Section("Danger zone") {
                Button("Reset all data…", role: .destructive) { confirmReset = true }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Erase everything and start over?", isPresented: $confirmReset) {
            Button("Back up and reset", role: .destructive) {
                if context.profile != nil { _ = try? BackupService.writeBackup(context) }
                BackupService.deleteAll(context)
                BackupService.deletePhotos()
                SeedService.ensureBuiltIns(context)
            }
        } message: {
            Text("A backup is saved first. This can't be undone from inside the app.")
        }
    }

    private func ensureFolder() -> URL {
        let folder = BackupService.backupFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { backupFolder = url.path(percentEncoded: false) }
    }
}
