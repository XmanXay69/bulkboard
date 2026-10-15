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
        .frame(minWidth: 1000, minHeight: 680)
        .tint(Theme.hardwood)
        .task {
            SeedService.ensureBuiltIns(context)
            await ScreenshotDirector.run(appModel: appModel, context: context)
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var appModel
    var profile: ProfileRecord

    var body: some View {
        @Bindable var appModel = appModel
        NavigationSplitView {
            Sidebar(profile: profile)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            detail(for: appModel.section)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .pageBackground()
        }
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .targets: TargetsView(profile: profile)
        default:
            EmptyStateView(symbol: section.symbol, title: section.title, message: "Coming up next.")
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var appModel
    var profile: ProfileRecord

    var body: some View {
        @Bindable var appModel = appModel
        List(selection: $appModel.section) {
            Section {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            } header: {
                HStack(spacing: 10) {
                    AppMark(size: 26)
                    Text("BulkBoard").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Theme.textPrimary)
                    if profile.isDemo { DemoBadge() }
                }
                .padding(.bottom, 10)
            }
            .collapsible(false)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar.ignoresSafeArea())
    }
}
