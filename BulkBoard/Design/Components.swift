import BulkCore
import SwiftUI

// MARK: - Containers

struct CardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.stroke))
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View { modifier(CardModifier(padding: padding)) }

    /// Standard scrolling page background.
    func pageBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}

struct Eyebrow: View {
    var text: String
    var color: Color = Theme.textSecondary

    init(_ text: String, color: Color = Theme.textSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.eyebrow)
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

struct PageHeader<Trailing: View>: View {
    var eyebrow: String
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(eyebrow, color: Theme.hardwood)
                Text(title)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String) {
        self.init(eyebrow: eyebrow, title: title) { EmptyView() }
    }
}

// MARK: - Scoreboard stats

/// A big scoreboard-style number with a label.
struct ScoreboardStat: View {
    var value: String
    var label: String
    var unit: String?
    var color: Color = Theme.scoreboard
    var size: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.scoreboard(size))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                        .foregroundStyle(color.opacity(0.7))
                }
            }
            Eyebrow(label)
        }
    }
}

/// LED-ish digital readout used for the hero numbers.
struct ScoreboardPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color(light: 0x16213A, dark: 0x070C18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Theme.hardwood.opacity(0.7), Theme.hardwood.opacity(0.1)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
            )
            .environment(\.colorScheme, .dark)
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
        case .onTarget: Theme.net
        case .over: Theme.rim
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

/// Horizontal macro progress bar with over/under readout.
struct MacroBar: View {
    var label: String
    var value: Double
    var target: Double
    var color: Color
    var unit: String = "g"
    var compact = false

    private var status: TargetStatus { TargetStatus(value: value, target: target) }
    private var fraction: Double { target > 0 ? min(value / target, 1.25) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: compact ? 11 : 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                HStack(spacing: 0) {
                    Text("\(Fmt.int(value))")
                        .font(.system(size: compact ? 12 : 14, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text(" / \(Fmt.int(target)) \(unit)")
                        .font(.system(size: compact ? 11 : 12, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                if !compact {
                    Image(systemName: status.symbol)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(status.color)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceRaised)
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, proxy.size.width * min(fraction, 1)))
                    if fraction > 1.05 {
                        Capsule()
                            .fill(Theme.rim)
                            .frame(width: 3)
                            .offset(x: proxy.size.width - 3)
                    }
                }
            }
            .frame(height: compact ? 5 : 8)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: fraction)
        }
    }
}

/// XP-style chunky progress bar.
struct XPBar: View {
    var progress: Double
    var height: CGFloat = 12
    var color: Color = Theme.hardwood

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceRaised)
                Capsule()
                    .fill(LinearGradient(colors: [Theme.scoreboard, color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, proxy.size.width * min(max(progress, 0), 1)))
                    .overlay(alignment: .top) {
                        Capsule().fill(.white.opacity(0.25)).frame(height: height * 0.35).padding(.horizontal, 4).padding(.top, 2)
                    }
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: progress)
    }
}

/// Ring gauge for a single number vs target.
struct RingGauge: View {
    var value: Double
    var target: Double
    var color: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        let fraction = target > 0 ? value / target : 0
        ZStack {
            Circle().stroke(Theme.surfaceRaised, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(fraction, 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if fraction > 1.05 {
                Circle()
                    .trim(from: 0, to: min(fraction - 1, 1))
                    .stroke(Theme.rim, style: StrokeStyle(lineWidth: lineWidth * 0.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: fraction)
    }
}

// MARK: - Badges, banners, buttons

struct DayTypeBadge: View {
    var dayType: DayType
    var large = false

    var body: some View {
        Label(dayType.title.uppercased(), systemImage: dayType.symbol)
            .font(.system(size: large ? 13 : 10, weight: .heavy, design: .rounded))
            .tracking(1)
            .padding(.horizontal, large ? 12 : 8)
            .padding(.vertical, large ? 6 : 4)
            .foregroundStyle(Theme.color(for: dayType))
            .background(Theme.color(for: dayType).opacity(0.14), in: Capsule())
    }
}

struct WarningBanner: View {
    var message: String
    var serious: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: serious ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(serious ? Theme.rim : Theme.paint)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background((serious ? Theme.rim : Theme.paint).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(Theme.hardwood)
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(HardwoodButtonStyle())
                    .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

struct HardwoodButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 14, weight: .bold, design: .rounded))
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 6 : 10)
            .foregroundStyle(.white)
            .background(Theme.heroGradient, in: Capsule())
            .shadow(color: Theme.hardwood.opacity(configuration.isPressed ? 0.1 : 0.35), radius: 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 14, weight: .semibold, design: .rounded))
            .padding(.horizontal, compact ? 10 : 16)
            .padding(.vertical, compact ? 5 : 9)
            .foregroundStyle(Theme.textPrimary)
            .background(Theme.surfaceRaised.opacity(configuration.isPressed ? 0.6 : 1), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke))
    }
}

/// Small pill showing a macro value.
struct MacroPill: View {
    var macros: Macros

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Text("\(Fmt.int(macros.kcal))").foregroundStyle(Theme.kcal)
                Text(" kcal").foregroundStyle(Theme.textSecondary)
            }
            Text("\(Fmt.int(macros.protein))P").foregroundStyle(Theme.protein)
            Text("\(Fmt.int(macros.carbs))C").foregroundStyle(Theme.carbs)
            Text("\(Fmt.int(macros.fat))F").foregroundStyle(Theme.fat)
        }
        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
    }
}

struct AIEstimateBadge: View {
    var body: some View {
        Label("AI estimate", systemImage: "sparkles")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(Theme.paint)
            .background(Theme.paint.opacity(0.14), in: Capsule())
    }
}

struct DemoBadge: View {
    var body: some View {
        Text("DEMO")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(Theme.scoreboard)
            .background(Theme.scoreboard.opacity(0.15), in: Capsule())
    }
}
