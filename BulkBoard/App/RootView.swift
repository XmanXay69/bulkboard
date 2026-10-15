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
                .frame(width: 216)
            Rectangle().fill(Theme.stroke).frame(width: 1).ignoresSafeArea()
            detail(for: appModel.section)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .pageBackground()
        }
        .overlay { ToastOverlay() }
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
        case .dashboard: DashboardView(profile: profile)
        case .meals: MealPlanView(profile: profile)
        case .grocery: GroceryView()
        case .training: TrainingView(profile: profile)
        case .body: BodyView(profile: profile)
        case .progress: ProgressScreen(profile: profile)
        case .targets: TargetsView(profile: profile)
        case .library: LibraryView()
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var appModel
    var profile: ProfileRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                AppMark(size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("BulkBoard").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 5) {
                        Text(profile.goalMode.title).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        if profile.isDemo { DemoBadge() }
                    }
                }
                .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 16)

            ForEach(AppSection.allCases) { section in
                SidebarButton(section: section, isSelected: appModel.section == section) {
                    appModel.section = section
                }
            }

            Spacer()
            Label("Data stays on this Mac", systemImage: "lock")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 8)
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
            HStack(spacing: 9) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(verbatim: "⌘\(section.shortcutKey)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if isSelected || isHovering {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Theme.surfaceRaised : Theme.surfaceRaised.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
