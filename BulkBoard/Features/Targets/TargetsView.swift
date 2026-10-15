import BulkCore
import SwiftData
import SwiftUI

struct TargetsView: View {
    @Bindable var profile: ProfileRecord
    @Query(sort: \WeightRecord.date, order: .reverse) private var weights: [WeightRecord]
    @State private var editingDayType: DayType?

    private var latestWeight: WeightRecord? { weights.first }
    private var snapshot: TargetsSnapshot { profile.targets(latestWeightKg: latestWeight?.weightKg) }
    private var units: UnitFormatter { UnitFormatter(system: profile.unitSystem) }

    var body: some View {
        let snapshot = snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                PageHeader(title: "Targets", subtitle: "Daily calories and macros, and how they were calculated") {
                    Picker("Goal", selection: $profile.goalModeRaw) {
                        ForEach(GoalMode.allCases, id: \.self) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode.rawValue)
                        }
                    }
                    .frame(width: 220)
                }

                MacroSummary(macros: snapshot.result.daily, size: 42)

                ForEach(snapshot.result.warnings, id: \.self) { warning in
                    WarningBanner(message: warning.message, serious: warning.isSerious)
                }

                DayTypeTargetsRow(targets: snapshot.byDayType, schedule: snapshot.result.schedule,
                                  overridden: Set(snapshot.overrides.keys)) { editingDayType = $0 }

                HStack(alignment: .top, spacing: Theme.spacing) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionLabel("Show the math")
                            Spacer()
                            if let latestWeight {
                                Text("Using weigh-in \(units.weight(latestWeight.weightKg)) · \(latestWeight.date.monthDay)")
                                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        MathBreakdownView(steps: snapshot.result.steps)
                        if let date = snapshot.result.rate.projectedGoalDate {
                            Divider()
                            Label("At this rate you hit \(units.weight(profile.goalWeightKg)) around \(date.formatted(date: .abbreviated, time: .omitted)).",
                                  systemImage: "flag.checkered")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .card()
                    .frame(minWidth: 380)

                    settingsCard
                        .frame(width: 400)
                }
            }
            .padding(28)
        }
        .pageBackground()
        .sheet(item: $editingDayType) { dayType in
            DayTargetEditor(profile: profile, dayType: dayType, computed: snapshot.result.target(for: dayType))
        }
    }

    // MARK: Settings

    private var settingsCard: some View {
        Form {
            Section("Body") {
                Picker("Units", selection: $profile.unitSystemRaw) {
                    Text("lb / ft").tag(UnitSystem.imperial.rawValue)
                    Text("kg / cm").tag(UnitSystem.metric.rawValue)
                }
                Picker("Sex", selection: $profile.sexRaw) {
                    ForEach(Sex.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                IntStepperField(label: "Age", value: $profile.age, range: 13...90, unit: "yrs")
                NumberField(label: "Height", value: heightBinding, unit: profile.unitSystem == .imperial ? "in" : "cm", decimals: 0)
                if latestWeight == nil {
                    NumberField(label: "Weight", value: massBinding(\.weightKg), unit: units.massUnit)
                }
            }
            Section("Goal") {
                NumberField(label: "Goal weight", value: massBinding(\.goalWeightKg), unit: units.massUnit)
                DatePicker("Target date", selection: $profile.targetDate, displayedComponents: .date)
                Toggle("Custom weekly rate", isOn: rateOverrideEnabled)
                if profile.weeklyRateOverrideKg != nil {
                    LabeledContent("Rate") {
                        HStack {
                            Slider(value: rateOverrideBinding, in: 0.1...2, step: 0.05)
                            Text("\(Fmt.number(rateOverrideBinding.wrappedValue, maxDecimals: 2)) \(units.massUnit)/wk")
                                .font(.system(size: 12, weight: .bold).monospacedDigit()).frame(width: 78, alignment: .trailing)
                        }
                    }
                }
            }
            Section("Activity") {
                Picker("Activity level", selection: $profile.activityRaw) {
                    ForEach(ActivityLevel.allCases, id: \.self) { level in
                        Text("\(level.title) (×\(Fmt.number(level.multiplier, maxDecimals: 3)))").tag(level.rawValue)
                    }
                }
                LabeledContent("Week") {
                    Text("\(profile.liftingDays) lift · \(profile.courtDays) court · \(max(0, 7 - profile.liftingDays - profile.courtDays)) rest")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Section {
                LabeledContent("Protein") {
                    HStack {
                        Slider(value: proteinBinding, in: 0.7...1.2, step: 0.05)
                        Text("\(Fmt.number(proteinBinding.wrappedValue, maxDecimals: 2)) g/lb")
                            .font(.system(size: 12, weight: .bold).monospacedDigit()).frame(width: 64, alignment: .trailing)
                    }
                }
                LabeledContent("Fat") {
                    HStack {
                        Slider(value: fatBinding, in: 0.2...0.35, step: 0.01)
                        Text("\(Fmt.int(fatBinding.wrappedValue * 100))% kcal")
                            .font(.system(size: 12, weight: .bold).monospacedDigit()).frame(width: 64, alignment: .trailing)
                    }
                }
                if profile.proteinPerLbOverride != nil || profile.fatPercentOverride != nil {
                    Button("Reset to \(profile.goalMode.title) defaults") {
                        profile.proteinPerLbOverride = nil
                        profile.fatPercentOverride = nil
                    }
                }
            } header: {
                Text("Macro split")
            } footer: {
                Text("Carbs fill whatever calories are left.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.stroke))
    }

    private func massBinding(_ keyPath: ReferenceWritableKeyPath<ProfileRecord, Double>) -> Binding<Double> {
        Binding {
            (Units.display(kg: profile[keyPath: keyPath], in: profile.unitSystem) * 10).rounded() / 10
        } set: {
            profile[keyPath: keyPath] = Units.kg(fromDisplay: $0, in: profile.unitSystem)
        }
    }

    private var heightBinding: Binding<Double> {
        Binding {
            profile.unitSystem == .imperial ? Units.inches(fromCm: profile.heightCm).rounded() : profile.heightCm.rounded()
        } set: {
            profile.heightCm = profile.unitSystem == .imperial ? Units.cm(fromInches: $0) : $0
        }
    }

    private var proteinBinding: Binding<Double> {
        Binding { profile.macroSettings.proteinPerLb } set: { profile.proteinPerLbOverride = $0 }
    }

    private var fatBinding: Binding<Double> {
        Binding { profile.macroSettings.fatPercent } set: { profile.fatPercentOverride = $0 }
    }

    private var rateOverrideEnabled: Binding<Bool> {
        Binding {
            profile.weeklyRateOverrideKg != nil
        } set: { enabled in
            profile.weeklyRateOverrideKg = enabled ? abs(snapshot.result.rate.weeklyChangeKg) : nil
        }
    }

    private var rateOverrideBinding: Binding<Double> {
        Binding {
            Units.display(kg: profile.weeklyRateOverrideKg ?? 0, in: profile.unitSystem)
        } set: {
            profile.weeklyRateOverrideKg = Units.kg(fromDisplay: $0, in: profile.unitSystem)
        }
    }
}

extension DayType: @retroactive Identifiable {
    public var id: String { rawValue }
}

/// Manual override for one day type's targets.
struct DayTargetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var profile: ProfileRecord
    var dayType: DayType
    var computed: Macros

    @State private var draft = Macros()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                DayTypeBadge(dayType: dayType, large: true)
                Spacer()
            }
            Text("Custom targets").font(.system(size: 22, weight: .semibold))
            Form {
                NumberField(label: "Calories", value: $draft.kcal, unit: "kcal", decimals: 0)
                NumberField(label: "Protein", value: $draft.protein, unit: "g", decimals: 0)
                NumberField(label: "Carbs", value: $draft.carbs, unit: "g", decimals: 0)
                NumberField(label: "Fat", value: $draft.fat, unit: "g", decimals: 0)
                LabeledContent("Macros add up to") {
                    Text("\(Fmt.int(draft.kcalFromMacros)) kcal")
                        .foregroundStyle(abs(draft.kcalFromMacros - draft.kcal) > 50 ? Theme.negative : Theme.textSecondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Balance carbs") {
                    draft.carbs = max(0, ((draft.kcal - draft.protein * 4 - draft.fat * 9) / 4).rounded())
                }
                .buttonStyle(.bordered).controlSize(.small)
                Button("Use calculated") {
                    var overrides = profile.dayTargetOverrides
                    overrides[dayType] = nil
                    profile.dayTargetOverrides = overrides
                    dismiss()
                }
                .buttonStyle(.bordered).controlSize(.small)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    var overrides = profile.dayTargetOverrides
                    overrides[dayType] = draft.rounded
                    profile.dayTargetOverrides = overrides
                    dismiss()
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { draft = profile.dayTargetOverrides[dayType] ?? computed }
    }
}
