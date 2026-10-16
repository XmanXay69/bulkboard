import BulkCore
import SwiftData
import SwiftUI

/// Top-right toolbar button. Quiet when you're up to date; lights up when GitHub has a newer release.
struct UpdateToolbarButton: View {
    @State private var updater = Updater.shared
    @State private var showPopover = false

    var body: some View {
        Group {
            switch updater.phase {
            case let .downloading(fraction):
                HStack(spacing: 6) {
                    ProgressView(value: fraction).frame(width: 60)
                    Text("Updating").font(.system(size: 12))
                }
                .padding(.horizontal, 4)
            case .installing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Installing").font(.system(size: 12))
                }
            default:
                if updater.isUpdateAvailable {
                    Button { updater.showSheet = true } label: {
                        Label("Update to \(updater.latest?.version.description ?? "")", systemImage: "arrow.down.circle.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("BulkBoard \(updater.latest?.version.description ?? "") is out. Click to update.")
                } else {
                    Button {
                        showPopover = true
                        Task { await updater.check(userInitiated: true) }
                    } label: {
                        Image(systemName: updater.phase == .checking ? "arrow.triangle.2.circlepath" : "arrow.down.circle")
                            .symbolEffect(.rotate, isActive: updater.phase == .checking)
                    }
                    .help("Check for updates · you have \(updater.currentVersion.description)")
                    .popover(isPresented: $showPopover, arrowEdge: .bottom) { checkPopover }
                }
            }
        }
    }

    private var checkPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            if updater.phase == .checking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking GitHub…")
                }
            } else if case let .failed(message) = updater.phase {
                Text(message)
                Button("OK") { updater.dismissError(); showPopover = false }.controlSize(.small)
            } else {
                Text(updater.lastMessage ?? "You're on the latest version (\(updater.currentVersion)).")
                if let checked = updater.lastChecked {
                    Text("Checked \(checked.formatted(.relative(presentation: .named)))").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .font(.system(size: 13))
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }
}

/// What's new, and one button to install it.
struct UpdateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var updater = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                AppMark(size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("BulkBoard \(updater.latest?.version.description ?? "") is available")
                        .font(.system(size: 18, weight: .semibold))
                    Text("You have \(updater.currentVersion.description).\(updater.latest?.publishedAt.map { " Released \($0.formatted(date: .abbreviated, time: .omitted))." } ?? "")")
                        .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
            }
            ScrollView {
                Text(notes)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 260)
            .padding(12)
            .background(Theme.surfaceRaised.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            Label("Your meals, workouts, check-ins and photos stay where they are. A backup is saved before installing.",
                  systemImage: "lock")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)

            if updater.location != .installable {
                WarningBanner(message: locationMessage, serious: false)
            }
            switch updater.phase {
            case let .downloading(fraction):
                ProgressView(value: fraction) { Text("Downloading…").font(.system(size: 12)) }
            case .installing:
                ProgressView { Text("Installing. BulkBoard will reopen in a moment.").font(.system(size: 12)) }
            case let .failed(message):
                WarningBanner(message: message, serious: true)
            default:
                EmptyView()
            }

            HStack {
                if let page = updater.latest?.pageURL {
                    Link("View on GitHub", destination: page).font(.system(size: 12))
                }
                Spacer()
                Button("Later") { updater.dismissError(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(updater.isBusy)
                if updater.location == .installable {
                    Button("Install and relaunch") { Task { await updater.install(context: context) } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(updater.isBusy)
                } else if updater.location == .readOnly {
                    if let page = updater.latest?.pageURL { Link("Download", destination: page).buttonStyle(.borderedProminent) }
                } else {
                    Button("Move to Applications") { updater.moveToApplications() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private var notes: AttributedString {
        // Headings ("### New") read better as bold lines; the rest is inline markdown.
        let text = (updater.latest?.notes ?? "").replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = line.drop { $0 == "#" }
                return trimmed.count < line.count ? "**\(trimmed.trimmingCharacters(in: .whitespaces))**" : String(line)
            }
            .joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private var locationMessage: String {
        switch updater.location {
        case .diskImage: "BulkBoard is running from the disk image. Move it to Applications once, and from then on it updates itself."
        case .translocated: "BulkBoard is running from a temporary copy macOS made after the download. Move it to Applications once, and from then on it updates itself."
        case .readOnly: "BulkBoard can't write to the folder it's in. Download the update and replace it yourself."
        case .installable: ""
        }
    }
}

/// Shown at the top of the window when BulkBoard runs from the disk image or a temporary copy.
struct MoveToApplicationsBanner: View {
    @State private var updater = Updater.shared
    @AppStorage("hideMoveBanner") private var hidden = false

    var body: some View {
        if !hidden, updater.location == .diskImage || updater.location == .translocated {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.app").foregroundStyle(Theme.accent)
                Text("Move BulkBoard to Applications so it can update itself.")
                    .font(.system(size: 13))
                Spacer()
                Button("Move to Applications") { updater.moveToApplications() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button { hidden = true } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                    .help("Hide")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
        }
    }
}
