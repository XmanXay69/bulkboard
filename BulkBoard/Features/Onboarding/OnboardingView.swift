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
            CourtBackdrop(opacity: 0.07).ignoresSafeArea()

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
                        .fill(item.rawValue <= step.rawValue ? AnyShapeStyle(Theme.heroGradient) : AnyShapeStyle(Theme.surfaceRaised))
                        .frame(height: 5)
                    Text(item.title.uppercased())
                        .font(.eyebrow).tracking(1)
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
                .buttonStyle(GhostButtonStyle())
                .keyboardShortcut(.cancelAction)
            Spacer()
            if step == .results {
                Button {
                    ProfileActions.completeOnboarding(draft, context: context)
                } label: {
                    Label("Let's hoop", systemImage: "basketball.fill")
                }
                .buttonStyle(HardwoodButtonStyle())
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Next") { move(1) }
                    .buttonStyle(HardwoodButtonStyle())
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
            AppMark(size: 96)
            VStack(spacing: 8) {
                Text("BulkBoard")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Eat big. Lift heavy. Keep your legs for the court.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                feature("target", "Calorie and macro targets that show their math")
                feature("fork.knife", "A week of meals auto-filled to hit them")
                feature("cart.fill", "Grocery list in one tap")
                feature("dumbbell.fill", "Lifting + court conditioning plan with PR tracking")
                feature("lock.fill", "Everything stays on this Mac")
            }
            .padding(.vertical, 8)
            HStack(spacing: 12) {
                Button("Explore with demo data") {
                    DemoData.load(into: context)
                }
                .buttonStyle(GhostButtonStyle())
                Button("Set up my plan") { step = .body }
                    .buttonStyle(HardwoodButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.hardwood).frame(width: 22)
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
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
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
                            .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.hardwood)
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
            Eyebrow("Overall activity level")
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
            Eyebrow("Allergies")
            FlowLayout(spacing: 8) {
                ForEach(Allergen.allCases, id: \.self) { allergen in
                    Chip(title: allergen.title, isOn: draft.allergens.contains(allergen)) {
                        if draft.allergens.contains(allergen) { draft.allergens.remove(allergen) } else { draft.allergens.insert(allergen) }
                    }
                }
            }
            Eyebrow("Dislikes")
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
            TargetScoreboard(macros: preview.daily)
            DayTypeTargetsRow(targets: preview.byDayType, schedule: preview.schedule)
            ForEach(preview.warnings, id: \.self) { warning in
                WarningBanner(message: warning.message, serious: warning.isSerious)
            }
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("The math")
                MathBreakdownView(steps: preview.steps)
            }
            .card()
            Text("Everything here is editable later in Targets.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(Theme.textPrimary)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func rateText(_ rate: RatePlan) -> String {
        if draft.mode.ratePolicy.fixedDailyAdjustment != nil { return "Hold weight" }
        let value = draft.unitSystem == .imperial ? rate.weeklyChangeLb : rate.weeklyChangeKg
        return "\(value >= 0 ? "+" : "−")\(Fmt.number(abs(value), maxDecimals: 2)) \(draft.unitSystem.massLabel)/week"
    }
}

/// Three compact cards: Practice Day, Game Day, Rest Day targets.
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
                            Text("\(schedule[dayType, default: 0])×/wk").font(.eyebrow).foregroundStyle(Theme.textSecondary)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(Fmt.int(macros.kcal)).font(.scoreboard(26)).foregroundStyle(Theme.textPrimary)
                            Text("kcal").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.textSecondary)
                        }
                        MacroPill(macros: macros)
                        if let onEdit {
                            HStack {
                                if overridden.contains(dayType) {
                                    Text("Custom").font(.eyebrow).foregroundStyle(Theme.scoreboard)
                                }
                                Spacer()
                                Button("Edit") { onEdit(dayType) }.buttonStyle(GhostButtonStyle(compact: true))
                            }
                        }
                    }
                    .card(padding: 14)
                }
            }
        }
    }
}
