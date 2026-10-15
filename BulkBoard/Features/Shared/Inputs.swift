import BulkCore
import SwiftUI

/// Labeled numeric field with a unit suffix.
struct NumberField: View {
    var label: String
    @Binding var value: Double
    var unit: String = ""
    var decimals = 1
    var width: CGFloat = 90

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                TextField(label, value: $value, format: .number.precision(.fractionLength(0...decimals)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: width)
                    .labelsHidden()
                if !unit.isEmpty {
                    Text(unit).foregroundStyle(Theme.textSecondary).frame(minWidth: 24, alignment: .leading)
                }
            }
        }
    }
}

struct IntStepperField: View {
    var label: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var unit: String = ""

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Text("\(value)")
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .frame(minWidth: 28, alignment: .trailing)
                if !unit.isEmpty { Text(unit).foregroundStyle(Theme.textSecondary) }
                Stepper(label, value: $value, in: range).labelsHidden()
            }
        }
    }
}

/// Selectable card used for goal modes and activity levels.
struct ChoiceCard: View {
    var title: String
    var detail: String
    var symbol: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.accent.opacity(0.08) : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : Theme.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Toggleable capsule chip.
struct Chip: View {
    var title: String
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isOn { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .foregroundStyle(isOn ? Theme.accent : Theme.textPrimary)
            .background(isOn ? Theme.accent.opacity(0.1) : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Theme.accent.opacity(0.6) : Theme.stroke))
        }
        .buttonStyle(.plain)
    }
}

extension GoalMode {
    var symbol: String {
        switch self {
        case .bulk: "arrow.up.circle"
        case .bulkPerformance: "bolt.circle"
        case .recomp: "arrow.triangle.2.circlepath"
        case .cut: "arrow.down.circle"
        case .maintain: "equal.circle"
        }
    }
}

extension ActivityLevel {
    var symbol: String {
        switch self {
        case .sedentary: "chair.fill"
        case .light: "figure.walk"
        case .moderate: "figure.run"
        case .active: "figure.basketball"
        case .veryActive: "bolt.heart.fill"
        }
    }
}

/// "Show the math" list.
struct MathBreakdownView: View {
    var steps: [MathStep]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text(step.formula).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Text(step.result)
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 9)
                if index < steps.count - 1 { Divider().opacity(0.5) }
            }
        }
    }
}

/// Calories and macros as four plain figures.
struct MacroSummary: View {
    var macros: Macros
    var size: CGFloat = 30

    var body: some View {
        Panel {
            HStack(spacing: 28) {
                StatView(value: Fmt.int(macros.kcal), label: "Calories", unit: "kcal", size: size)
                StatView(value: Fmt.int(macros.protein), label: "Protein", unit: "g", size: size)
                StatView(value: Fmt.int(macros.carbs), label: "Carbs", unit: "g", size: size)
                StatView(value: Fmt.int(macros.fat), label: "Fat", unit: "g", size: size)
                Spacer(minLength: 0)
            }
        }
    }
}
