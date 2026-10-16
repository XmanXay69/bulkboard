import AppKit
import BulkCore
import CryptoKit
import Foundation
import Observation
import OSLog
import SwiftData

private let log = Logger(subsystem: "com.xmanxay.BulkBoard", category: "updater")

/// Checks GitHub for a newer BulkBoard and installs it in place.
///
/// Your data lives in Application Support, outside BulkBoard.app, so swapping the app never touches it.
/// Before installing, the updater still saves a JSON backup and a copy of the store. The download is
/// checked against GitHub's SHA-256 digest, the bundle ID and version are verified, and its code
/// signature must be valid before it replaces the running copy.
@Observable
final class Updater {
    static let shared = Updater()
    static let repository = "XmanXay69/bulkboard"
    static let checkInterval: TimeInterval = 6 * 3600

    // End-to-end test switches, honored only together with `--update-feed=<url>`:
    // `--update-test-apps=<folder>` stands in for /Applications, `--update-auto` acts without clicks.
    private static func argument(_ name: String) -> String? {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix(name + "=") }.map { String($0.dropFirst(name.count + 1)) }
    }

    static var isTestFeed: Bool { argument("--update-feed") != nil }
    static var testApplicationsFolder: URL? { isTestFeed ? argument("--update-test-apps").map { URL(fileURLWithPath: $0, isDirectory: true) } : nil }
    static var actsAutomatically: Bool { isTestFeed && ProcessInfo.processInfo.arguments.contains("--update-auto") }

    static var feedURL: URL {
        if let custom = argument("--update-feed"), let url = URL(string: custom) { return url }
        return URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    enum Phase: Equatable {
        case idle
        case checking
        case downloading(Double)
        case installing
        case failed(String)
    }

    /// Where the running copy lives, which decides whether it can replace itself.
    enum Location: Equatable {
        case installable
        /// Opened straight from the downloaded disk image.
        case diskImage
        /// macOS is running a temporary copy because the app hasn't been moved since downloading.
        case translocated
        /// The folder isn't writable for this user.
        case readOnly
    }

    private(set) var phase: Phase = .idle
    private(set) var latest: AppRelease?
    private(set) var lastChecked: Date?
    /// The result of the last check the user asked for, for the toolbar popover.
    private(set) var lastMessage: String?
    var showSheet = false

    let currentVersion = SemanticVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") ?? SemanticVersion("0.0.0")!

    var autoCheck: Bool {
        get { access(keyPath: \.autoCheck); return UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true }
        set {
            withMutation(keyPath: \.autoCheck) { UserDefaults.standard.set(newValue, forKey: "autoCheckUpdates") }
            if newValue { Task { await checkIfDue() } }
        }
    }

    var isUpdateAvailable: Bool { latest?.isNewer(than: currentVersion) ?? false }
    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    private var timer: Timer?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["User-Agent": NutritionLookup.userAgent]
        return URLSession(configuration: config)
    }()

    private init() {
        guard !Self.isTestFeed else { return } // a test feed never reads or writes the real app's settings
        lastChecked = (UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Double).map { Date(timeIntervalSince1970: $0) }
        if let data = UserDefaults.standard.data(forKey: "latestReleaseJSON") {
            latest = try? AppRelease.parse(githubJSON: data)
        }
    }

    /// Call once at launch: checks if a check is due, then every few hours while the app runs.
    func start(context: ModelContext) {
        guard timer == nil, !Persistence.usesInMemoryStore || Self.isTestFeed else { return }
        Task {
            if Self.isTestFeed { await check(userInitiated: false) } else { await checkIfDue() }
            if Self.actsAutomatically { await actAutomatically(context: context) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkIfDue() }
        }
    }

    private func actAutomatically(context: ModelContext) async {
        switch location {
        case .diskImage, .translocated:
            log.info("Auto: moving to \(Self.testApplicationsFolder?.path ?? "Applications", privacy: .public)")
            moveToApplications()
        case .installable where isUpdateAvailable:
            log.info("Auto: installing \(self.latest?.version.description ?? "", privacy: .public)")
            await install(context: context)
        default:
            log.info("Auto: nothing to do (version \(self.currentVersion.description, privacy: .public))")
        }
    }

    func checkIfDue() async {
        guard autoCheck else { return }
        if let lastChecked, Date.now.timeIntervalSince(lastChecked) < Self.checkInterval { return }
        await check(userInitiated: false)
    }

    func check(userInitiated: Bool) async {
        guard !isBusy else { return }
        phase = .checking
        defer { if phase == .checking { phase = .idle } }
        var request = URLRequest(url: Self.feedURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UpdateError.unreachable }
            if http.statusCode == 403 || http.statusCode == 429 { throw UpdateError.rateLimited }
            if http.statusCode == 404 { throw UpdateError.noRelease }
            guard http.statusCode == 200 else { throw UpdateError.unreachable }
            let release = try AppRelease.parse(githubJSON: data)
            latest = release
            lastChecked = .now
            if !Self.isTestFeed {
                UserDefaults.standard.set(data, forKey: "latestReleaseJSON")
                UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastUpdateCheck")
            }
            log.info("Latest release \(release.version.description, privacy: .public), running \(self.currentVersion.description, privacy: .public)")
            lastMessage = release.isNewer(than: currentVersion)
                ? "BulkBoard \(release.version) is available."
                : "You're on the latest version (\(currentVersion))."
            if userInitiated && release.isNewer(than: currentVersion) { showSheet = true }
        } catch {
            log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            lastMessage = (error as? UpdateError)?.errorDescription ?? UpdateError.unreachable.errorDescription
            if userInitiated { phase = .failed(lastMessage ?? "") }
        }
    }

    // MARK: Location

    var location: Location {
        let url = Bundle.main.bundleURL
        if url.path.contains("/AppTranslocation/") { return .translocated }
        if url.path.hasPrefix("/Volumes/"), (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true {
            return .diskImage
        }
        let parent = url.deletingLastPathComponent().path
        return FileManager.default.isWritableFile(atPath: parent) ? .installable : .readOnly
    }

    /// Copies the running app into Applications (or ~/Applications) and relaunches from there,
    /// so it can update itself. Afterwards you can eject the disk image.
    func moveToApplications() {
        let fm = FileManager.default
        let systemApps = Self.testApplicationsFolder ?? URL(fileURLWithPath: "/Applications", isDirectory: true)
        let folder = fm.isWritableFile(atPath: systemApps.path) ? systemApps
            : fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        let destination = folder.appendingPathComponent("BulkBoard.app")
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: folder, create: true)
            let copy = staging.appendingPathComponent("BulkBoard.app")
            try fm.copyItem(at: Bundle.main.bundleURL, to: copy)
            Self.clearQuarantine(copy)
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: copy)
            } else {
                try fm.moveItem(at: copy, to: destination)
            }
            try? fm.removeItem(at: staging)
            relaunch(at: destination)
        } catch {
            log.error("Move failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed("Couldn't copy BulkBoard to \(folder.path): \(error.localizedDescription). Drag it into Applications yourself, then open it from there.")
        }
    }

    // MARK: Install

    /// Downloads, verifies and installs the latest release, then relaunches.
    func install(context: ModelContext) async {
        guard let release = latest, release.isNewer(than: currentVersion) else { return }
        guard let asset = release.asset else {
            phase = .failed("This release has no app download attached. Get it from the release page.")
            return
        }
        guard location == .installable else {
            phase = .failed("Move BulkBoard to Applications first, then update.")
            return
        }
        #if DEBUG
        if !Self.isTestFeed {
            phase = .failed("This is a development build. Pull and rebuild instead.")
            return
        }
        #endif
        let fm = FileManager.default
        var staging: URL?
        do {
            phase = .downloading(0)
            let zip = try await download(asset)
            if let expected = asset.sha256 {
                let actual = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
                guard actual == expected else { throw UpdateError.checksumMismatch }
            }

            phase = .installing
            let target = Bundle.main.bundleURL
            let stage = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
            staging = stage
            let newApp = stage.appendingPathComponent("BulkBoard.app")
            let bundleID = Bundle.main.bundleIdentifier
            try await Task.detached {
                try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, stage.path])
                try? FileManager.default.removeItem(at: zip)
                try Self.validate(newApp, expected: release.version, bundleID: bundleID)
                Self.clearQuarantine(newApp)
            }.value

            // Belt and braces: your data isn't in the app, but keep a copy before anything changes.
            if context.profile != nil { try BackupService.writeBackup(context) }
            try StoreSafety.snapshot(reason: "before-update-to-\(release.version)")

            _ = try fm.replaceItemAt(target, withItemAt: newApp)
            try? fm.removeItem(at: stage)
            log.info("Installed \(release.version.description, privacy: .public) at \(target.path, privacy: .public)")
            relaunch(at: target)
        } catch {
            if let staging { try? fm.removeItem(at: staging) }
            log.error("Install failed: \(error.localizedDescription, privacy: .public)")
            let message = (error as? UpdateError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message)
        }
    }

    private func download(_ asset: AppRelease.Asset) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(asset.name)")
        let tracker = DownloadTracker()
        let expected = Double(max(asset.size, 1))
        let progress = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.phase = .downloading(min(1, Double(tracker.task?.countOfBytesReceived ?? 0) / expected))
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        defer { progress.cancel() }
        let (file, response) = try await session.download(from: asset.url, delegate: tracker)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.downloadFailed }
        try FileManager.default.moveItem(at: file, to: destination)
        phase = .downloading(1)
        return destination
    }

    /// The new app must be BulkBoard, the version the release says, and validly signed.
    private nonisolated static func validate(_ app: URL, expected: SemanticVersion, bundleID: String?) throws {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              info["CFBundleIdentifier"] as? String == bundleID else { throw UpdateError.notBulkBoard }
        guard let version = (info["CFBundleShortVersionString"] as? String).flatMap(SemanticVersion.init), version == expected else {
            throw UpdateError.wrongVersion
        }
        do { try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) } catch { throw UpdateError.badSignature }
    }

    private nonisolated static func clearQuarantine(_ app: URL) {
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
    }

    /// Opens the app at `url` once this process has quit, then quits.
    private func relaunch(at url: URL) {
        // Keep test-only arguments so an end-to-end update test stays on its scratch store.
        let keep = ProcessInfo.processInfo.arguments.filter {
            $0.hasPrefix("--store=") || $0.hasPrefix("--update-feed=") || $0.hasPrefix("--update-test-apps=") || $0 == "--update-auto"
        }
        let script = #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; shift; /usr/bin/open "$@""#
        var arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), url.path]
        if !keep.isEmpty { arguments += ["--args"] + keep }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            phase = .failed("Installed, but couldn't relaunch. Quit and open BulkBoard again.")
        }
    }

    @discardableResult
    private nonisolated static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else { throw UpdateError.tool(tool, output) }
        return output
    }

    func dismissError() {
        if case .failed = phase { phase = .idle }
    }
}

/// Hands back the download task so its byte count can drive the progress bar.
private nonisolated final class DownloadTracker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _task: URLSessionTask?

    var task: URLSessionTask? { lock.withLock { _task } }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        lock.withLock { _task = task }
    }
}

nonisolated enum UpdateError: LocalizedError {
    case unreachable, rateLimited, noRelease, downloadFailed, checksumMismatch, notBulkBoard, wrongVersion, badSignature
    case tool(String, String)

    var errorDescription: String? {
        switch self {
        case .unreachable: "Couldn't reach GitHub to check for updates."
        case .rateLimited: "GitHub is limiting update checks right now. Try again in an hour."
        case .noRelease: "No releases found on GitHub yet."
        case .downloadFailed: "The download didn't finish. Try again."
        case .checksumMismatch: "The download didn't match GitHub's checksum, so it wasn't installed."
        case .notBulkBoard: "The download wasn't a BulkBoard app, so it wasn't installed."
        case .wrongVersion: "The download's version didn't match the release, so it wasn't installed."
        case .badSignature: "The download's code signature didn't check out, so it wasn't installed."
        case let .tool(tool, output): "\((tool as NSString).lastPathComponent) failed: \(output.prefix(200))"
        }
    }
}
