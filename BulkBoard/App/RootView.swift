import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        NavigationSplitView {
            List(selection: $appModel.section) {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            ZStack {
                Theme.background.ignoresSafeArea()
                Text(appModel.section.title)
                    .font(.scoreboard(40))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }
}
