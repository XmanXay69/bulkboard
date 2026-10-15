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
        .task {
            SeedService.ensureBuiltIns(context)
            await OllamaClient.shared.refresh()
            await ScreenshotDirector.run(appModel: appModel, context: context)
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var appModel
    var profile: ProfileRecord

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(profile: profile)
                .frame(width: 224)
            Rectangle().fill(Theme.stroke).frame(width: 1).ignoresSafeArea()
            detail(for: appModel.section)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .pageBackground()
        }
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .targets: TargetsView(profile: profile)
        case .meals: MealPlanView(profile: profile)
        case .library: LibraryView()
        case .grocery: GroceryView()
        default:
            EmptyStateView(symbol: section.symbol, title: section.title, message: "Coming up next.")
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

/// Placeholder footer until progress stats land; shows local-only reassurance.
struct SidebarFooter: View {
    var body: some View {
        Label("All data stays on this Mac", systemImage: "lock.fill")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
    }
}
