import AppKit
import SwiftUI

/// A short confirmation worth surfacing: a PR, a finished workout, macros hit.
struct Celebration: Identifiable, Equatable {
    enum Kind: Equatable { case pr, dayComplete, workoutComplete }

    let id = UUID()
    var kind: Kind
    var title: String
    var detail: String

    var symbol: String {
        switch self.kind {
        case .pr: "trophy"
        case .dayComplete: "checkmark.circle"
        case .workoutComplete: "checkmark.circle"
        }
    }
}

/// Quiet toast at the top of the window. Dismisses itself.
struct ToastOverlay: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack {
            if let toast = appModel.celebration {
                HStack(spacing: 10) {
                    Image(systemName: toast.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(toast.kind == .pr ? Theme.accent : Theme.positive)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(toast.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text(toast.detail).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(toast.id)
                .onTapGesture { appModel.celebration = nil }
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.easeOut(duration: 0.25)) { appModel.celebration = nil }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: appModel.celebration)
        .allowsHitTesting(appModel.celebration != nil)
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rest").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        Text(String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60))
                            .font(.stat(22))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    ProgressBar(progress: timer.total > 0 ? 1 - remaining / timer.total : 1, height: 6)
                    Button("+15s") { timer.add(15) }.buttonStyle(.bordered).controlSize(.small)
                    Button("Skip") { timer.skip() }.buttonStyle(.bordered).controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
