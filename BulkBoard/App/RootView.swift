import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    @Query private var profiles: [ProfileRecord]

    var body: some View {
        Group {
            if let profile = profiles.first {
                MainView(profile: profile)
            } else {
                OnboardingView()
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
        .tint(Theme.hardwood)
        .onChange(of: profiles.isEmpty, initial: true) { appModel.hasProfile = !profiles.isEmpty }
        .overlay(alignment: .top) {
            if let error = appModel.startupError {
                WarningBanner(message: error, serious: true)
                    .frame(maxWidth: 640)
                    .padding(.top, 8)
                    .onTapGesture { appModel.startupError = nil }
            }
        }
        .task {
            SeedService.ensureBuiltIns(context)
            BackupService.autoBackupIfNeeded(context)
            await OllamaClient.shared.refresh()
            await ScreenshotDirector.run(appModel: appModel, context: context)
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var context
    var profile: ProfileRecord

    var body: some View {
        @Bindable var appModel = appModel
        HStack(spacing: 0) {
            SidebarView(profile: profile)
                .frame(width: 224)
            Rectangle().fill(Theme.stroke).frame(width: 1).ignoresSafeArea()
            detail(for: appModel.section)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .pageBackground()
        }
        .overlay { CelebrationOverlay() }
        .sheet(item: $appModel.activeSheet) { sheet in
            switch sheet {
            case .weighIn: WeighInSheet(units: profile.unitSystem, last: context.latestWeightKg)
            case .quickAdd: QuickAddSheet(library: MealLibrary(context))
            case let .court(minutes, kind): CourtSessionSheet(minutes: minutes, kind: kind)
            case .coach: AskCoachSheet(profile: profile)
            }
        }
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .targets: TargetsView(profile: profile)
        case .meals: MealPlanView(profile: profile)
        case .library: LibraryView()
        case .grocery: GroceryView()
        case .training: TrainingView(profile: profile)
        case .dashboard: DashboardView(profile: profile)
        case .progress: ProgressScreen(profile: profile)
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var appModel
    var profile: ProfileRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                AppMark(size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("BulkBoard").font(.system(size: 16, weight: .black, design: .rounded)).foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 5) {
                        Text(profile.goalMode.title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        if profile.isDemo { DemoBadge() }
                    }
                }
                .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 18)

            ForEach(AppSection.allCases) { section in
                SidebarButton(section: section, isSelected: appModel.section == section) {
                    appModel.section = section
                }
            }

            Spacer()
            PlayerCard(profile: profile)
            SidebarFooter()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar.ignoresSafeArea())
    }
}

struct SidebarButton: View {
    var section: AppSection
    var isSelected: Bool
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)
                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                Spacer()
                Text(verbatim: "⌘\(section.shortcutKey)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .opacity(isSelected || isHovering ? 0.7 : 0)
            }
            .foregroundStyle(isSelected ? .white : Theme.textPrimary.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.heroGradient)
                        .shadow(color: Theme.hardwood.opacity(0.35), radius: 6, y: 2)
                } else if isHovering {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.surfaceRaised)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// Level, XP and streak at the bottom of the sidebar.
struct PlayerCard: View {
    var profile: ProfileRecord
    @Query(sort: \WeightRecord.date) private var weights: [WeightRecord]
    @Query private var intake: [IntakeRecord]
    @Query private var sessions: [WorkoutSessionRecord]
    @Query private var court: [CourtSessionRecord]
    @Query(sort: \WorkoutPlanRecord.createdAt, order: .reverse) private var plans: [WorkoutPlanRecord]

    var body: some View {
        let stats = ProgressService.stats(profile: profile, weights: weights, intake: intake, sessions: sessions,
                                          court: court, plan: plans.first)
        let level = stats.level
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LV \(level.level)").font(.scoreboard(18)).foregroundStyle(Theme.scoreboard)
                Spacer()
                Label("\(stats.currentStreak)", systemImage: "flame.fill")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.hardwood)
                    .help("Days in a row on your macros")
            }
            XPBar(progress: Double(level.into) / Double(level.needed), height: 8)
            Text("\(level.into) / \(level.needed) XP").font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
        .padding(.bottom, 8)
    }
}

/// Local-only reassurance.
struct SidebarFooter: View {
    var body: some View {
        Label("All data stays on this Mac", systemImage: "lock.fill")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
    }
}
