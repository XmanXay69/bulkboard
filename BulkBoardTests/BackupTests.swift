import BulkCore
import Foundation
import SwiftData
import Testing
@testable import BulkBoard

@Suite("Backup, export and import")
@MainActor
struct BackupTests {
    @Test func jsonRoundTripRestoresEverything() throws {
        let source = try makeContext()
        SeedService.ensureBuiltIns(source)
        DemoData.load(into: source)
        let custom = FoodRecord(name: "Grandma's lasagna")
        custom.macros = Macros(kcal: 610, protein: 34, carbs: 52, fat: 28)
        source.insert(custom)
        try source.save()

        let data = try BackupService.encode(BackupService.snapshot(source))
        let restored = try makeContext()
        BackupService.restore(try BackupService.decode(data), into: restored)

        func counts(_ c: ModelContext) -> [Int] {
            [c.fetchAll(ProfileRecord.self).count, c.fetchAll(FoodRecord.self).count, c.fetchAll(RecipeRecord.self).count,
             c.fetchAll(PlanEntryRecord.self).count, c.fetchAll(IntakeRecord.self).count, c.fetchAll(GroceryItemRecord.self).count,
             c.fetchAll(ExerciseRecord.self).count, c.fetchAll(WorkoutPlanRecord.self).count, c.fetchAll(WorkoutSessionRecord.self).count,
             c.fetchAll(CourtSessionRecord.self).count, c.fetchAll(WeightRecord.self).count]
        }
        #expect(counts(restored) == counts(source))
        #expect(restored.fetchAll(FoodRecord.self).contains { $0.name == "Grandma's lasagna" && $0.kcal == 610 })
        let originalSets = TrainingActions.completedSessions(source).flatMap(\.sets).count
        #expect(TrainingActions.completedSessions(restored).flatMap(\.sets).count == originalSets)
        #expect(restored.profile?.targets().result.daily == source.profile?.targets().result.daily)
    }

    @Test func rejectsFilesThatArentBackups() {
        #expect(throws: BackupError.self) {
            try BackupService.decode(Data(#"{"format":"something-else","version":1,"exportedAt":"2026-01-01T00:00:00Z","appVersion":"1"}"#.utf8))
        }
    }

    @Test func csvExportHasHeadersAndRows() throws {
        let context = try makeContext()
        SeedService.ensureBuiltIns(context)
        DemoData.load(into: context)
        let files = BackupService.csvFiles(context)
        #expect(Set(files.keys) == ["weights.csv", "lifts.csv", "court-sessions.csv", "intake.csv"])
        #expect(files["weights.csv"]!.hasPrefix("date,weight_kg,weight_lb,note\n"))
        #expect(files["lifts.csv"]!.split(separator: "\n").count > 100)
        #expect(files["lifts.csv"]!.contains("Barbell Bench Press"))
    }

    @Test func csvEscaping() {
        #expect(BackupService.csvEscape("plain") == "plain")
        #expect(BackupService.csvEscape("a, b") == "\"a, b\"")
        #expect(BackupService.csvEscape("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }

    @Test func backupsArePrunedToTheNewest() throws {
        let context = try makeContext()
        onboard(context)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bulkboard-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for day in 1...5 {
            try Data("{}".utf8).write(to: folder.appendingPathComponent("BulkBoard-2026-01-0\(day)-120000.json"))
        }
        let newest = try BackupService.writeBackup(context, to: folder, keep: 3)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(remaining.count == 3)
        #expect(remaining.contains(newest.lastPathComponent))
        #expect(!remaining.contains("BulkBoard-2026-01-01-120000.json"))
    }

    @Test func deleteAllEmptiesTheStore() throws {
        let context = try makeContext()
        onboard(context)
        BackupService.deleteAll(context)
        #expect(context.profile == nil)
        #expect(context.fetchAll(FoodRecord.self).isEmpty)
        #expect(context.fetchAll(PlanEntryRecord.self).isEmpty)
    }
}
