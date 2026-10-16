import BulkCore
import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var appModel
    @State private var draft = OnboardingDraft()

    private var step: Step {
        get { appModel.onboardingStep }
        nonmutating set { appModel.onboardingStep = newValue }
    }

    enum Step: Int, CaseIterable {
        case welcome, body, goal, training, food, results

        var title: String {
            switch self {
            case .welcome: ""
            case .body: "About you"
            case .goal: "Your goal"
            case .training: "Training week"
            case .food: "Food"
            case .results: "Your targets"
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 22) {
                if step != .welcome { progress }
                ScrollView {
                    Group {
                        switch step {
                        case .welcome: welcome
                        case .body: bodyStep
                        case .goal: goalStep
                        case .training: trainingStep
                        case .food: foodStep
                        case .results: resultsStep
                        }
                    }
                    .frame(maxWidth: 640)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.never)
                if step != .welcome { navigation }
            }
            .padding(.vertical, 28)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
    }

    // MARK: Chrome

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases.dropFirst(), id: \.self) { item in
                VStack(spacing: 6) {
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceRaised))
                        .frame(height: 4)
                    Text(item.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(item == step ? Theme.textPrimary : Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 32)
    }

    private var navigation: some View {
        HStack {
            Button("Back") { move(-1) }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Spacer()
            if step == .results {
                Button {
                    ProfileActions.completeOnboarding(draft, context: context)
                } label: {
                    Text("Get started")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Next") { move(1) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdvance)
                    .opacity(canAdvance ? 1 : 0.5)
            }
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 32)
    }

    private var canAdvance: Bool {
        switch step {
        case .body: draft.isBodyValid
        case .goal: draft.isGoalValid
        default: true
        }
    }

    private func move(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        step = next
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 60)
            AppMark(size: 72)
            VStack(spacing: 6) {
                Text("BulkBoard")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Macros, meals, groceries, training and progress for your bulk.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                feature("target", "Calorie and macro targets that show their math")
                feature("camera", "Log your meals with a photo; label numbers looked up for you")
                feature("wand.and.stars", "Suggested meals and a grocery list when you want them")
                feature("dumbbell", "Lifting and conditioning plan with PR tracking")
                feature("figure.arms.open", "Body measurements, weak-point focus and a dunk plan")
                feature("lock", "Your data stays on this Mac")
            }
            .padding(.vertical, 8)
            Button("Set up my plan") { step = .body }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.textSecondary).frame(width: 22)
        }
    }

    private var bodyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader("Tell me about you", "Used for the calorie math. Nothing leaves this Mac.")
            Form {
                Picker("Units", selection: $draft.unitSystem) {
                    Text("lb / ft").tag(UnitSystem.imperial)
                    Text("kg / cm").tag(UnitSystem.metric)
                }
                .pickerStyle(.segmented)
                Picker("Sex", selection: $draft.sex) {
                    ForEach(Sex.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                IntStepperField(label: "Age", value: $draft.age, range: 13...90, unit: "yrs")
                if draft.unitSystem == .imperial {
                    LabeledContent("Height") {
                        HStack(spacing: 10) {
                            Stepper("\(draft.heightFeet) ft", value: $draft.heightFeet, in: 4...7)
                            Stepper("\(draft.heightInches) in", value: $draft.heightInches, in: 0...11)
                        }
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    }
                } else {
                    NumberField(label: "Height", value: $draft.heightCm, unit: "cm", decimals: 0)
                }
                NumberField(label: "Current weight", value: $draft.weight, unit: draft.unitSystem.massLabel)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            if !draft.isBodyValid {
                WarningBanner(message: "Double-check age, height and weight.", serious: true)
            }
        }
    }

    private var goalStep: some View {
        let preview = draft.preview
        return VStack(alignment: .leading, spacing: 18) {
            stepHeader("What's the goal?", "You can switch modes anytime in Targets.")
            VStack(spacing: 8) {
                ForEach(GoalMode.allCases, id: \.self) { mode in
                    ChoiceCard(title: mode.title, detail: mode.detail, symbol: mode.symbol,
                               isSelected: draft.mode == mode) { draft.mode = mode }
                }
            }
            if draft.mode.ratePolicy.fixedDailyAdjustment == nil {
                Form {
                    NumberField(label: "Goal weight", value: $draft.goalWeight, unit: draft.unitSystem.massLabel)
                    DatePicker("Target date", selection: $draft.targetDate, in: Date.now.adding(days: 7)..., displayedComponents: .date)
                    LabeledContent("Planned rate") {
                        Text(rateText(preview.rate))
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                ForEach(preview.rate.warnings, id: \.self) { warning in
                    WarningBanner(message: warning.message, serious: warning.isSerious)
                }
            }
        }
    }

    private var trainingStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader("Your training week", "Builds a YMCA-friendly split: barbells, dumbbells, machines, cables, and the court.")
            Form {
                IntStepperField(label: "Lifting days", value: $draft.liftingDays, range: 0...6, unit: "/ week")
                IntStepperField(label: "Basketball / conditioning days", value: $draft.courtDays,
                                range: 0...max(0, 7 - draft.liftingDays), unit: "/ week")
                LabeledContent("Rest + mobility") {
                    Text("\(max(0, 7 - draft.liftingDays - draft.courtDays)) / week").foregroundStyle(Theme.textSecondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            SectionLabel("Overall activity level")
            VStack(spacing: 8) {
                ForEach(ActivityLevel.allCases, id: \.self) { level in
                    ChoiceCard(title: "\(level.title) · ×\(Fmt.number(level.multiplier, maxDecimals: 3))", detail: level.detail,
                               symbol: level.symbol, isSelected: draft.activity == level) {
                        draft.activity = level
                        draft.activityTouched = true
                    }
                }
            }
        }
    }

    private var foodStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader("Anything you won't eat?", "Auto-fill skips meals with these. Shakes are always shaker-bottle friendly, no blender needed.")
            SectionLabel("Allergies")
            FlowLayout(spacing: 8) {
                ForEach(Allergen.allCases, id: \.self) { allergen in
                    Chip(title: allergen.title, isOn: draft.allergens.contains(allergen)) {
                        if draft.allergens.contains(allergen) { draft.allergens.remove(allergen) } else { draft.allergens.insert(allergen) }
                    }
                }
            }
            SectionLabel("Dislikes")
            TextField("e.g. salmon, mushrooms, cottage cheese", text: $draft.dislikesText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            Text("Comma-separated. Matches meal and ingredient names.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
        }
    }

    private var resultsStep: some View {
        let preview = draft.preview
        return VStack(alignment: .leading, spacing: 18) {
            stepHeader("Here's your game plan", "\(draft.mode.title) · \(rateText(preview.rate))")
            MacroSummary(macros: preview.daily)
            DayTypeTargetsRow(targets: preview.byDayType, schedule: preview.schedule)
            ForEach(preview.warnings, id: \.self) { warning in
                WarningBanner(message: warning.message, serious: warning.isSerious)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("The math")
                MathBreakdownView(steps: preview.steps)
            }
            .card()
            Text("Everything here is editable later in Targets.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func rateText(_ rate: RatePlan) -> String {
        if draft.mode.ratePolicy.fixedDailyAdjustment != nil { return "Hold weight" }
        let value = draft.unitSystem == .imperial ? rate.weeklyChangeLb : rate.weeklyChangeKg
        return "\(value >= 0 ? "+" : "−")\(Fmt.number(abs(value), maxDecimals: 2)) \(draft.unitSystem.massLabel)/week"
    }
}

/// One card per day type: lift, court and rest day targets.
struct DayTypeTargetsRow: View {
    var targets: [DayType: Macros]
    var schedule: [DayType: Int]
    var overridden: Set<DayType> = []
    var onEdit: ((DayType) -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ForEach(DayType.allCases, id: \.self) { dayType in
                if schedule[dayType, default: 0] > 0, let macros = targets[dayType] {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            DayTypeBadge(dayType: dayType)
                            Spacer()
                            Text("\(schedule[dayType, default: 0])×/wk").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(Fmt.int(macros.kcal)).font(.stat(26)).foregroundStyle(Theme.textPrimary)
                            Text("kcal").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textSecondary)
                        }
                        MacroPill(macros: macros)
                        if let onEdit {
                            HStack {
                                if overridden.contains(dayType) {
                                    Text("Custom").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textPrimary)
                                }
                                Spacer()
                                Button("Edit") { onEdit(dayType) }.buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                    .card(padding: 14)
                }
            }
        }
    }
}
