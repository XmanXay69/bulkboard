import BulkCore
import SwiftUI

// MARK: - Containers

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.stroke))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }

    /// Standard page background.
    func pageBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}

/// A card used for the main figure on a screen.
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content.card(padding: 20)
    }
}

/// Small secondary label above a group of content.
struct SectionLabel: View {
    var text: String
    var color: Color = Theme.textSecondary

    init(_ text: String, color: Color = Theme.textSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
    }
}

struct PageHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Stats

/// A number with a label underneath.
struct StatView: View {
    var value: String
    var label: String
    var unit: String?
    var size: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.stat(size))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.system(size: max(11, size * 0.42), weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Progress

enum TargetStatus {
    case under, onTarget, over

    /// Within ±5% counts as on target.
    init(value: Double, target: Double, tolerance: Double = 0.05) {
        guard target > 0 else { self = .onTarget; return }
        let ratio = value / target
        if ratio < 1 - tolerance { self = .under } else if ratio > 1 + tolerance { self = .over } else { self = .onTarget }
    }

    var color: Color {
        switch self {
        case .under: Theme.textSecondary
        case .onTarget: Theme.positive
        case .over: Theme.negative
        }
    }

    var symbol: String {
        switch self {
        case .under: "arrow.down"
        case .onTarget: "checkmark"
        case .over: "arrow.up"
        }
    }
}

/// Thin progress bar with a value / target readout.
struct MacroBar: View {
    var label: String
    var value: Double
    var target: Double
    var unit: String = "g"
    var compact = false

    private var status: TargetStatus { TargetStatus(value: value, target: target) }
    private var fraction: Double { target > 0 ? min(value / target, 1.25) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: compact ? 11 : 13))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                HStack(spacing: 0) {
                    Text("\(Fmt.int(value))")
                        .font(.system(size: compact ? 11 : 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text(" / \(Fmt.int(target)) \(unit)")
                        .font(.system(size: compact ? 11 : 13).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                if !compact && status == .onTarget {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.positive)
                }
            }
            ProgressBar(progress: fraction, height: compact ? 4 : 6)
        }
    }
}

struct ProgressBar: View {
    var progress: Double
    var height: CGFloat = 6
    var color: Color = Theme.accent

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceRaised)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, proxy.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: progress)
    }
}

/// Ring gauge for a single number vs target.
struct RingGauge: View {
    var value: Double
    var target: Double
    var lineWidth: CGFloat = 10

    var body: some View {
        let fraction = target > 0 ? value / target : 0
        ZStack {
            Circle().stroke(Theme.surfaceRaised, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(fraction, 1))
                .stroke(Theme.accent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

// MARK: - Badges, banners

struct DayTypeBadge: View {
    var dayType: DayType
    var large = false

    var body: some View {
        Label(dayType.title, systemImage: dayType.symbol)
            .font(.system(size: large ? 12 : 11, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, large ? 10 : 7)
            .padding(.vertical, large ? 4 : 3)
            .foregroundStyle(Theme.textSecondary)
            .background(Theme.surfaceRaised, in: Capsule())
    }
}

struct WarningBanner: View {
    var message: String
    var serious: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: serious ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(serious ? Theme.negative : Theme.textSecondary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(serious ? Theme.negative.opacity(0.08) : Theme.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity)
    }
}

/// Calories and macros as one quiet line of text.
struct MacroPill: View {
    var macros: Macros

    var body: some View {
        HStack(spacing: 6) {
            Text("\(Fmt.int(macros.kcal)) kcal").foregroundStyle(Theme.textPrimary)
            Text("\(Fmt.int(macros.protein))P · \(Fmt.int(macros.carbs))C · \(Fmt.int(macros.fat))F")
                .foregroundStyle(Theme.textSecondary)
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
    }
}

struct AIEstimateBadge: View {
    var body: some View {
        Label("AI estimate", systemImage: "sparkles")
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(Theme.accent)
            .background(Theme.accent.opacity(0.1), in: Capsule())
    }
}
