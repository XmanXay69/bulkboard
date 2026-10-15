import AppKit
import SwiftUI

/// Something worth a little fanfare.
struct Celebration: Identifiable, Equatable {
    enum Kind: Equatable { case pr, dayComplete, workoutComplete }

    let id = UUID()
    var kind: Kind
    var title: String
    var detail: String

    var headline: String {
        switch kind {
        case .pr: "NEW PR"
        case .dayComplete: "DAY COMPLETE"
        case .workoutComplete: "FINAL BUZZER"
        }
    }

    var symbol: String {
        switch kind {
        case .pr: "trophy.fill"
        case .dayComplete: "checkmark.seal.fill"
        case .workoutComplete: "flag.checkered"
        }
    }

    var sound: NSSound.Name { kind == .pr ? "Hero" : "Glass" }
}

/// Confetti burst that falls under gravity. Particles are computed analytically from elapsed time.
struct ConfettiView: View {
    var startDate: Date
    var duration: Double = 2.6
    private let particles: [Particle]

    init(startDate: Date, count: Int = 90) {
        self.startDate = startDate
        var rng = SystemRandomNumberGenerator()
        particles = (0..<count).map { _ in Particle.random(using: &rng) }
    }

    struct Particle {
        var x: Double, vx: Double, vy: Double, spin: Double, size: Double, color: Color, isCircle: Bool

        static func random(using rng: inout SystemRandomNumberGenerator) -> Particle {
            let palette: [Color] = [Theme.hardwood, Theme.scoreboard, Theme.net, Theme.paint, .white, Theme.rim]
            return Particle(x: .random(in: 0.3...0.7, using: &rng), vx: .random(in: -0.55...0.55, using: &rng),
                            vy: .random(in: -1.25 ... -0.55, using: &rng), spin: .random(in: -9...9, using: &rng),
                            size: .random(in: 6...12, using: &rng), color: palette.randomElement(using: &rng)!,
                            isCircle: Bool.random(using: &rng))
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(startDate)
                guard t >= 0, t < duration else { return }
                let gravity = 1.6
                let fade = max(0, 1 - max(0, t - duration * 0.6) / (duration * 0.4))
                for particle in particles {
                    let x = (particle.x + particle.vx * t) * size.width
                    let y = (0.55 + particle.vy * t + 0.5 * gravity * t * t) * size.height
                    var piece = context
                    piece.opacity = fade
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(particle.spin * t))
                    let rect = CGRect(x: -particle.size / 2, y: -particle.size / 4, width: particle.size, height: particle.size / 2)
                    let path = particle.isCircle ? Path(ellipseIn: rect.insetBy(dx: particle.size / 4, dy: 0)) : Path(rect)
                    piece.fill(path, with: .color(particle.color))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Full-window overlay: confetti plus a scoreboard banner. Dismisses itself.
struct CelebrationOverlay: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack {
            if let celebration = appModel.celebration {
                ConfettiView(startDate: .now)
                    .ignoresSafeArea()
                VStack(spacing: 10) {
                    Image(systemName: celebration.symbol)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Theme.scoreboard)
                        .symbolEffect(.bounce, value: celebration.id)
                    Text(celebration.headline)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(Theme.heroGradient)
                    Text(celebration.title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(celebration.detail)
                        .font(.scoreboard(18))
                        .foregroundStyle(Theme.scoreboard)
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 30)
                .background(Color(hex: 0x070C18).opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.hardwood.opacity(0.8), lineWidth: 2))
                .shadow(color: Theme.hardwood.opacity(0.45), radius: 30)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .id(celebration.id)
                .onTapGesture { appModel.celebration = nil }
                .task(id: celebration.id) {
                    NSSound(named: celebration.sound)?.play()
                    try? await Task.sleep(for: .seconds(2.4))
                    withAnimation(.easeOut(duration: 0.3)) { appModel.celebration = nil }
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: appModel.celebration)
    }
}

/// Counts down between sets and chimes when it's time to go.
@Observable
final class RestTimer {
    private(set) var endDate: Date?
    private(set) var total: Double = 90
    private var task: Task<Void, Never>?

    var isRunning: Bool { endDate != nil }

    func start(seconds: Int) {
        total = Double(seconds)
        schedule(Date.now.addingTimeInterval(total))
    }

    func add(_ seconds: Int) {
        guard let endDate else { return }
        total += Double(seconds)
        schedule(endDate.addingTimeInterval(Double(seconds)))
    }

    func skip() {
        task?.cancel()
        endDate = nil
    }

    private func schedule(_ end: Date) {
        endDate = end
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            NSSound(named: "Glass")?.play()
            self?.endDate = nil
        }
    }
}

struct RestTimerBar: View {
    var timer: RestTimer

    var body: some View {
        if let end = timer.endDate {
            TimelineView(.periodic(from: .now, by: 0.2)) { context in
                let remaining = max(0, end.timeIntervalSince(context.date))
                HStack(spacing: 14) {
                    Image(systemName: "timer").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.scoreboard)
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow("Rest")
                        Text(String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60))
                            .font(.scoreboard(26))
                            .foregroundStyle(remaining < 10 ? Theme.rim : Theme.textPrimary)
                    }
                    XPBar(progress: timer.total > 0 ? 1 - remaining / timer.total : 1, height: 8, color: Theme.scoreboard)
                    Button("+15s") { timer.add(15) }.buttonStyle(GhostButtonStyle(compact: true))
                    Button("Skip") { timer.skip() }.buttonStyle(GhostButtonStyle(compact: true))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.scoreboard.opacity(0.5)))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
