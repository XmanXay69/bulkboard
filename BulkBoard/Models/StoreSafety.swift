import Foundation
import SwiftData

/// Keeps your data safe across updates.
///
/// Your data never lives inside the app: it's in `~/Library/Application Support/BulkBoard`, so replacing
/// BulkBoard.app leaves it alone. On top of that, the first launch of a new version copies the store
/// files aside before migrating them, and the updater takes a backup before installing.
enum StoreSafety {
    static var snapshotsFolder: URL {
        Persistence.dataDirectory.appendingPathComponent("Snapshots", isDirectory: true)
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "dev")-\(info?["CFBundleVersion"] as? String ?? "0")"
    }

    private static var isRealStore: Bool { !Persistence.usesInMemoryStore && !Persistence.usesCustomStore }

    /// Call before opening the container. Copies the store if this version hasn't opened it before.
    static func snapshotIfVersionChanged() {
        guard isRealStore else { return }
        let last = UserDefaults.standard.string(forKey: "lastRunVersion")
        guard last != appVersion, FileManager.default.fileExists(atPath: Persistence.storeURL.path) else { return }
        _ = try? snapshot(reason: "before-\(appVersion)")
    }

    /// Call after the container opened, so a failed migration snapshots again next launch.
    static func markVersionOpened() {
        guard isRealStore else { return }
        UserDefaults.standard.set(appVersion, forKey: "lastRunVersion")
    }

    /// Copies the store and its write-ahead log into a dated folder. Keeps the newest few.
    @discardableResult
    static func snapshot(reason: String, keep: Int = 5) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let folder = snapshotsFolder.appendingPathComponent("\(formatter.string(from: .now))-\(reason)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = Persistence.storeURL
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: store.path + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
        }
        let all = (try? FileManager.default.contentsOfDirectory(at: snapshotsFolder, includingPropertiesForKeys: nil)) ?? []
        for old in all.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).dropFirst(keep) {
            try? FileManager.default.removeItem(at: old)
        }
        return folder
    }

    /// v0.1–0.2 could load sample data. Remove anything that's left of it (your own records are never marked).
    static func removeLegacyDemoData(_ context: ModelContext) {
        func purge<T: PersistentModel>(_ type: T.Type, _ predicate: Predicate<T>) -> Int {
            let records = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
            records.forEach(context.delete)
            return records.count
        }
        let photos = ((try? context.fetch(FetchDescriptor<BodyCheckInRecord>(predicate: #Predicate { $0.isDemo }))) ?? [])
            .compactMap(\.photoFilename)
        var removed = 0
        removed += purge(ProfileRecord.self, #Predicate { $0.isDemo })
        removed += purge(FoodRecord.self, #Predicate { $0.isDemo })
        removed += purge(RecipeRecord.self, #Predicate { $0.isDemo })
        removed += purge(PlanEntryRecord.self, #Predicate { $0.isDemo })
        removed += purge(IntakeRecord.self, #Predicate { $0.isDemo })
        removed += purge(GroceryItemRecord.self, #Predicate { $0.isDemo })
        removed += purge(WorkoutPlanRecord.self, #Predicate { $0.isDemo })
        removed += purge(WorkoutSessionRecord.self, #Predicate { $0.isDemo })
        removed += purge(CourtSessionRecord.self, #Predicate { $0.isDemo })
        removed += purge(WeightRecord.self, #Predicate { $0.isDemo })
        removed += purge(BodyCheckInRecord.self, #Predicate { $0.isDemo })
        guard removed > 0 else { return }
        photos.forEach { PhotoStore.delete($0) }
        try? context.save()
    }
}
