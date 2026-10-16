import Foundation

/// A release version like "0.3.0" or tag "v0.3.0". Compares numerically, so 0.10.0 > 0.9.2,
/// and a pre-release (0.3.0-beta.1) sorts before its release.
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public var components: [Int]
    public var prerelease: String?

    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.first == "v" || trimmed.first == "V" { trimmed.removeFirst() }
        let parts = trimmed.split(separator: "-", maxSplits: 1)
        guard let core = parts.first else { return nil }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.count <= 4, numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        components = numbers.map { $0! }
        prerelease = parts.count > 1 ? String(parts[1]) : nil
    }

    public var description: String {
        components.map(String.init).joined(separator: ".") + (prerelease.map { "-\($0)" } ?? "")
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let a = index < lhs.components.count ? lhs.components[index] : 0
            let b = index < rhs.components.count ? rhs.components[index] : 0
            if a != b { return a < b }
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil), (nil, _?): return false
        case (_?, nil): return true
        case let (a?, b?): return a.compare(b, options: .numeric) == .orderedAscending
        }
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public func hash(into hasher: inout Hasher) {
        var trimmed = components
        while trimmed.last == 0 { trimmed.removeLast() }
        hasher.combine(trimmed)
        hasher.combine(prerelease)
    }
}

/// A GitHub release as BulkBoard's updater sees it.
public struct AppRelease: Equatable, Sendable {
    public struct Asset: Equatable, Sendable {
        public var name: String
        public var url: URL
        public var size: Int
        /// Hex SHA-256 from GitHub's asset digest, when it publishes one.
        public var sha256: String?

        public init(name: String, url: URL, size: Int, sha256: String?) {
            self.name = name
            self.url = url
            self.size = size
            self.sha256 = sha256
        }
    }

    public var version: SemanticVersion
    public var title: String
    public var notes: String
    public var pageURL: URL
    public var publishedAt: Date?
    /// The zipped app the updater installs.
    public var asset: Asset?

    public init(version: SemanticVersion, title: String, notes: String, pageURL: URL, publishedAt: Date?, asset: Asset?) {
        self.version = version
        self.title = title
        self.notes = notes
        self.pageURL = pageURL
        self.publishedAt = publishedAt
        self.asset = asset
    }

    /// Reads GitHub's "latest release" JSON. Drafts and pre-releases are ignored.
    public static func parse(githubJSON data: Data) throws -> AppRelease {
        struct Wire: Decodable {
            struct WireAsset: Decodable {
                var name: String
                var browser_download_url: URL
                var size: Int
                var digest: String?
            }
            var tag_name: String
            var name: String?
            var body: String?
            var html_url: URL
            var published_at: Date?
            var draft: Bool?
            var prerelease: Bool?
            var assets: [WireAsset]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let wire = try decoder.decode(Wire.self, from: data)
        guard wire.draft != true, wire.prerelease != true, let version = SemanticVersion(wire.tag_name) else {
            throw ReleaseError.notARelease
        }
        let zip = wire.assets.first { $0.name.hasPrefix("BulkBoard-") && $0.name.hasSuffix("-macOS.zip") }
        let asset = zip.map { a in
            Asset(name: a.name, url: a.browser_download_url, size: a.size,
                  sha256: a.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil })
        }
        return AppRelease(version: version, title: wire.name ?? wire.tag_name, notes: wire.body ?? "",
                          pageURL: wire.html_url, publishedAt: wire.published_at, asset: asset)
    }

    public func isNewer(than current: SemanticVersion) -> Bool { version > current }
}

public enum ReleaseError: Error, Equatable {
    case notARelease
}
