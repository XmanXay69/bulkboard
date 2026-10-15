import BulkCore
import SwiftData
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AISettings().tabItem { Label("Local AI", systemImage: "sparkles") }
            DataSettings().tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 560, height: 470)
    }
}

struct GeneralSettings: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [ProfileRecord]
    @AppStorage("appearance") private var appearance: AppearancePreference = .dark
    @AppStorage("mealVariety") private var variety: MealVariety = .balanced

    var body: some View {
        Form {
            Section("Look") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Dark is the default. System follows macOS.").font(.caption).foregroundStyle(.secondary)
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
                    Picker("Auto-fill variety", selection: $variety) {
                        ForEach(MealVariety.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Meal plan")
                } footer: {
                    Text("Breakfast, lunch and dinner are always on. Re-fill the week after changing slots.")
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

struct AISettings: View {
    @State private var client = OllamaClient.shared

    var body: some View {
        Form {
            Section {
                Toggle("Use local AI when Ollama is running", isOn: $client.isEnabled)
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(client.isAvailable ? Theme.positive : Theme.textSecondary).frame(width: 8, height: 8)
                        Text(client.isChecking ? "Checking…" : client.isAvailable ? "Connected" : "Not running")
                    }
                }
                if client.isAvailable {
                    Picker("Text model", selection: $client.model) {
                        ForEach(client.models, id: \.self) { Text($0).tag($0) }
                    }
                    if client.visionModels.isEmpty {
                        LabeledContent("Photo model") {
                            Text("None installed (ollama pull llama3.2-vision)").foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("Photo model", selection: $client.visionModel) {
                            ForEach(client.visionModels, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
                Button("Check again") { Task { await client.refresh() } }
            } header: {
                Text("Ollama")
            } footer: {
                Text("BulkBoard only talks to Ollama on this Mac (127.0.0.1:11434). No cloud, no API keys. Everything works without it; AI numbers are labeled as estimates.")
            }
            if !client.isAvailable {
                Section("Set it up") {
                    Text("1. Install Ollama from ollama.com\n2. Run: ollama pull llama3.2\n3. For photo reviews also run: ollama pull llama3.2-vision\n4. Keep Ollama running, then press Check again.")
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .task { await client.refresh() }
    }
}

struct DataSettings: View {
    @Environment(\.modelContext) private var context
    @AppStorage("autoBackup") private var autoBackup = true
    @AppStorage("backupFolder") private var backupFolder = ""
    @AppStorage("lastBackup") private var lastBackup: Double = 0
    @State private var confirmReset = false
    @State private var confirmWipeDemo = false
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
                    Text(lastBackup > 0 ? Date(timeIntervalSince1970: lastBackup).formatted(date: .abbreviated, time: .shortened) : "Never")
                }
                Button("Back up now") {
                    do {
                        let url = try BackupService.writeBackup(context)
                        message = "Saved \(url.lastPathComponent)"
                    } catch { message = error.localizedDescription }
                }
            } header: {
                Text("Backups")
            } footer: {
                Text("Keeps the 14 most recent. Backups contain your health data and measurements; progress photos stay in the Photos folder and aren't included.")
            }
            Section("Export & import") {
                HStack {
                    Button("Export JSON backup…") { BackupService.exportJSON(context) }
                    Button("Export CSV logs…") { BackupService.exportCSV(context) }
                    Button("Import backup…") { BackupService.importJSON(context) }
                }
            }
            Section("Demo data") {
                HStack {
                    Button("Load demo data") { DemoData.load(into: context) }
                        .disabled(context.profile != nil)
                        .help(context.profile != nil ? "Demo data loads from a fresh start (use Reset first)" : "")
                    Button("Wipe demo data", role: .destructive) { confirmWipeDemo = true }
                        .disabled(!DemoData.hasDemoData(context))
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
        .confirmationDialog("Remove all demo data?", isPresented: $confirmWipeDemo) {
            Button("Wipe demo data", role: .destructive) { DemoData.wipe(context) }
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
