import BulkCore
import SwiftData
import SwiftUI

/// Ask the local model for a food's macros. Results are always labeled as estimates.
struct AIEstimateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var query: String
    var onApply: (MacroEstimate) -> Void

    @State private var estimate: MacroEstimate?
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                Text("Estimate macros").font(.system(size: 18, weight: .semibold))
                Spacer()
                Text(OllamaClient.shared.model).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textSecondary)
            }
            TextField("Food and amount, e.g. 2 slices pepperoni pizza", text: $query, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
            if let estimate {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(estimate.name).font(.system(size: 14, weight: .bold))
                        AIEstimateBadge()
                    }
                    Text(estimate.serving).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    MacroPill(macros: estimate.macros)
                    Text("Estimated by a local model. Check a label when you can.")
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
                .card(padding: 12)
            }
            if let error { WarningBanner(message: error, serious: true) }
            HStack {
                if isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if let estimate {
                    Button("Use estimate") {
                        onApply(estimate)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Estimate") { Task { await run() } }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .keyboardShortcut(.defaultAction)
                        .disabled(query.isEmpty || isWorking)
                }
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private func run() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do { estimate = try await OllamaClient.shared.estimateMacros(for: query) } catch { self.error = error.localizedDescription }
    }
}

/// "Ask the coach": meal ideas, quick macro estimates, and higher-protein swaps, all local.
struct AskCoachSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var profile: ProfileRecord

    enum Mode: String, CaseIterable {
        case ideas = "Meal ideas"
        case estimate = "Macro estimate"
        case swap = "Higher-protein swap"

        var placeholder: String {
            switch self {
            case .ideas: "e.g. 3 cheap high-calorie lunches I can prep Sunday"
            case .estimate: "e.g. Chipotle burrito with double chicken"
            case .swap: "e.g. spaghetti with marinara and garlic bread"
            }
        }
    }

    @State private var mode: Mode = .ideas
    @State private var prompt = ""
    @State private var answer = ""
    @State private var estimate: MacroEstimate?
    @State private var error: String?
    @State private var isWorking = false
    @State private var saved = false

    private var client: OllamaClient { OllamaClient.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles").font(.system(size: 18)).foregroundStyle(Theme.accent)
                Text("Ask the coach").font(.system(size: 22, weight: .semibold))
                Spacer()
                if client.isAvailable {
                    Label(client.model, systemImage: "cpu").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                }
            }
            if !client.isAvailable {
                WarningBanner(message: OllamaError.unavailable.errorDescription ?? "", serious: false)
            }
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: mode) { answer = ""; estimate = nil; error = nil; saved = false }
            TextField(mode.placeholder, text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let estimate {
                        HStack { Text(estimate.name).font(.system(size: 15, weight: .bold)); AIEstimateBadge() }
                        Text(estimate.serving).foregroundStyle(Theme.textSecondary)
                        MacroSummary(macros: estimate.macros, size: 24)
                        Button(saved ? "Saved to My foods" : "Save as a custom food") { saveEstimate(estimate) }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(saved)
                    }
                    if !answer.isEmpty {
                        Text(LocalizedStringKey(answer))
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                        Label("AI suggestions are estimates.", systemImage: "info.circle")
                            .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                    if let error { WarningBanner(message: error, serious: true) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 220)
            HStack {
                if isWorking { ProgressView().controlSize(.small); Text("Thinking locally…").foregroundStyle(Theme.textSecondary) }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Ask") { Task { await run() } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(prompt.isEmpty || isWorking || !client.isAvailable)
            }
        }
        .padding(24)
        .frame(width: 600, height: 560)
        .task { await client.connect() }
    }

    private func run() async {
        isWorking = true
        error = nil
        answer = ""
        estimate = nil
        saved = false
        defer { isWorking = false }
        do {
            switch mode {
            case .ideas:
                answer = try await client.mealIdeas(prompt, context: CoachContext.build(context))
            case .estimate:
                estimate = try await client.estimateMacros(for: prompt)
            case .swap:
                answer = try await client.higherProteinSwap(prompt)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveEstimate(_ estimate: MacroEstimate) {
        let food = FoodRecord(name: estimate.name)
        food.servingLabel = estimate.serving
        food.macros = estimate.macros
        food.isAIEstimate = true
        context.insert(food)
        try? context.save()
        saved = true
    }
}
