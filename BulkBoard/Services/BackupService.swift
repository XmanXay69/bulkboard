import AppKit
import BulkCore
import Foundation
import SwiftData

/// A complete, versioned snapshot of the user's data. Plain JSON so it's portable and diffable.
nonisolated struct BackupDocument: Codable {
    static let format = "bulkboard-backup"

    var format = BackupDocument.format
    var version = 1
    var exportedAt = Date()
    var appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    var profile: Profile?
    var foods: [Food] = []
    var recipes: [Recipe] = []
    var planEntries: [PlanEntry] = []
    var intake: [Intake] = []
    var groceries: [Grocery] = []
    var exercises: [Exercise] = []
    var workoutPlan: WorkoutPlan?
    var sessions: [Session] = []
    var courtSessions: [Court] = []
    var weights: [Weight] = []
    /// Added in 0.2. Measurements and AI notes; photos stay on disk and aren't embedded.
    var checkIns: [CheckIn]?

    struct Profile: Codable {
        var id: UUID, createdAt: Date, age: Int, sex: String, heightCm: Double, weightKg: Double, goalWeightKg: Double
        var startDate: Date, targetDate: Date, activity: String, goalMode: String, liftingDays: Int, courtDays: Int
        var dislikes: [String], allergens: [String], unitSystem: String
        var proteinPerLbOverride: Double?, fatPercentOverride: Double?, weeklyRateOverrideKg: Double?
        var dayTargetOverrides: Data?, mealSlots: [String], isDemo: Bool
        var focusMuscles: [String]?, dunkGoal: Bool?
    }

    struct Food: Codable {
        var id: UUID, seedKey: String?, name: String, brand: String?, servingLabel: String, servingAmount: Double
        var servingUnit: String, kcal: Double, protein: Double, carbs: Double, fat: Double, section: String
        var allergens: [String], shakerSafe: Bool, isBuiltIn: Bool, isAIEstimate: Bool, isFavorite: Bool
        var isArchived: Bool, isDemo: Bool, createdAt: Date
    }

    struct Recipe: Codable {
        var id: UUID, seedKey: String?, name: String, slots: [String], ingredients: [Ingredient], isShake: Bool
        var notes: String, isBuiltIn: Bool, isFavorite: Bool, isArchived: Bool, isDemo: Bool, createdAt: Date
    }

    struct PlanEntry: Codable {
        var id: UUID, day: Date, slotIndex: Int, slot: String, recipeID: UUID?, foodID: UUID?, servings: Double
        var isLocked: Bool, isDemo: Bool
    }

    struct Intake: Codable {
        var id: UUID, day: Date, timestamp: Date, slot: String, name: String, kcal: Double, protein: Double
        var carbs: Double, fat: Double, planEntryID: UUID?, isDemo: Bool
        /// Added in 0.3: what was in the meal, notes, saved meal, and the photo's file name (photos stay on disk).
        var items: [LoggedFoodItem]?, notes: String?, recipeID: UUID?, photoFilename: String?
    }

    struct Grocery: Codable {
        var id: UUID, name: String, amountText: String, section: String, isChecked: Bool, isManual: Bool
        var sortIndex: Int, isDemo: Bool, createdAt: Date
    }

    struct Exercise: Codable {
        var id: UUID, seedKey: String?, name: String, muscle: String, equipment: String, isCompound: Bool
        var defaultRestSeconds: Int, notes: String, isBuiltIn: Bool, isArchived: Bool, createdAt: Date
    }

    struct WorkoutPlan: Codable {
        var id: UUID, createdAt: Date, liftingDays: Int, courtDays: Int, days: [PlannedDay], isDemo: Bool
    }

    struct Session: Codable {
        var id: UUID, date: Date, title: String, dayType: String, sets: [SessionSet], durationSeconds: Int
        var notes: String, isCompleted: Bool, prCount: Int, isDemo: Bool
    }

    struct Court: Codable {
        var id: UUID, date: Date, kind: String, minutes: Int, rpe: Int, notes: String, isDemo: Bool
    }

    struct Weight: Codable {
        var id: UUID, date: Date, weightKg: Double, note: String, isDemo: Bool
    }

    struct CheckIn: Codable {
        var id: UUID, date: Date, measurements: BodyMeasurements?, photoFilename: String?, aiNotes: String?, aiModel: String?, isDemo: Bool
    }
}

enum BackupService {
    static var defaultBackupFolder: URL { Persistence.dataDirectory.appendingPathComponent("Backups", isDirectory: true) }

    static var backupFolder: URL {
        if !Persistence.usesCustomStore, let path = UserDefaults.standard.string(forKey: "backupFolder"), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultBackupFolder
    }

    static var autoBackupEnabled: Bool {
        UserDefaults.standard.object(forKey: "autoBackup") as? Bool ?? true
    }

    // MARK: Snapshot

    static func snapshot(_ context: ModelContext) -> BackupDocument {
        var doc = BackupDocument()
        if let p = context.profile {
            doc.profile = .init(id: p.id, createdAt: p.createdAt, age: p.age, sex: p.sexRaw, heightCm: p.heightCm, weightKg: p.weightKg,
                                goalWeightKg: p.goalWeightKg, startDate: p.startDate, targetDate: p.targetDate, activity: p.activityRaw,
                                goalMode: p.goalModeRaw, liftingDays: p.liftingDays, courtDays: p.courtDays, dislikes: p.dislikes,
                                allergens: p.allergensRaw, unitSystem: p.unitSystemRaw, proteinPerLbOverride: p.proteinPerLbOverride,
                                fatPercentOverride: p.fatPercentOverride, weeklyRateOverrideKg: p.weeklyRateOverrideKg,
                                dayTargetOverrides: p.dayTargetOverridesData, mealSlots: p.mealSlotsRaw, isDemo: p.isDemo,
                                focusMuscles: p.focusMusclesRaw, dunkGoal: p.dunkGoal)
        }
        doc.foods = context.fetchAll(FoodRecord.self).map {
            .init(id: $0.id, seedKey: $0.seedKey, name: $0.name, brand: $0.brand, servingLabel: $0.servingLabel, servingAmount: $0.servingAmount,
                  servingUnit: $0.servingUnitRaw, kcal: $0.kcal, protein: $0.protein, carbs: $0.carbs, fat: $0.fat, section: $0.sectionRaw,
                  allergens: $0.allergensRaw, shakerSafe: $0.shakerSafe, isBuiltIn: $0.isBuiltIn, isAIEstimate: $0.isAIEstimate,
                  isFavorite: $0.isFavorite, isArchived: $0.isArchived, isDemo: $0.isDemo, createdAt: $0.createdAt)
        }
        doc.recipes = context.fetchAll(RecipeRecord.self).map {
            .init(id: $0.id, seedKey: $0.seedKey, name: $0.name, slots: $0.slotsRaw, ingredients: $0.ingredients, isShake: $0.isShake,
                  notes: $0.notes, isBuiltIn: $0.isBuiltIn, isFavorite: $0.isFavorite, isArchived: $0.isArchived, isDemo: $0.isDemo,
                  createdAt: $0.createdAt)
        }
        doc.planEntries = context.fetchAll(PlanEntryRecord.self).map {
            .init(id: $0.id, day: $0.day, slotIndex: $0.slotIndex, slot: $0.slotRaw, recipeID: $0.recipeID, foodID: $0.foodID,
                  servings: $0.servings, isLocked: $0.isLocked, isDemo: $0.isDemo)
        }
        doc.intake = context.fetchAll(IntakeRecord.self).map {
            .init(id: $0.id, day: $0.day, timestamp: $0.timestamp, slot: $0.slotRaw, name: $0.name, kcal: $0.kcal, protein: $0.protein,
                  carbs: $0.carbs, fat: $0.fat, planEntryID: $0.planEntryID, isDemo: $0.isDemo,
                  items: $0.items.isEmpty ? nil : $0.items, notes: $0.notes.isEmpty ? nil : $0.notes, recipeID: $0.recipeID,
                  photoFilename: $0.photoFilename)
        }
        doc.groceries = context.fetchAll(GroceryItemRecord.self).map {
            .init(id: $0.id, name: $0.name, amountText: $0.amountText, section: $0.sectionRaw, isChecked: $0.isChecked,
                  isManual: $0.isManual, sortIndex: $0.sortIndex, isDemo: $0.isDemo, createdAt: $0.createdAt)
        }
        doc.exercises = context.fetchAll(ExerciseRecord.self).map {
            .init(id: $0.id, seedKey: $0.seedKey, name: $0.name, muscle: $0.muscleRaw, equipment: $0.equipmentRaw, isCompound: $0.isCompound,
                  defaultRestSeconds: $0.defaultRestSeconds, notes: $0.notes, isBuiltIn: $0.isBuiltIn, isArchived: $0.isArchived,
                  createdAt: $0.createdAt)
        }
        if let plan = context.workoutPlan {
            doc.workoutPlan = .init(id: plan.id, createdAt: plan.createdAt, liftingDays: plan.liftingDays, courtDays: plan.courtDays,
                                    days: plan.days, isDemo: plan.isDemo)
        }
        doc.sessions = context.fetchAll(WorkoutSessionRecord.self).map {
            .init(id: $0.id, date: $0.date, title: $0.title, dayType: $0.dayTypeRaw, sets: $0.sets, durationSeconds: $0.durationSeconds,
                  notes: $0.notes, isCompleted: $0.isCompleted, prCount: $0.prCount, isDemo: $0.isDemo)
        }
        doc.courtSessions = context.fetchAll(CourtSessionRecord.self).map {
            .init(id: $0.id, date: $0.date, kind: $0.kindRaw, minutes: $0.minutes, rpe: $0.rpe, notes: $0.notes, isDemo: $0.isDemo)
        }
        doc.weights = context.fetchAll(WeightRecord.self).map {
            .init(id: $0.id, date: $0.date, weightKg: $0.weightKg, note: $0.note, isDemo: $0.isDemo)
        }
        doc.checkIns = context.fetchAll(BodyCheckInRecord.self).map {
            .init(id: $0.id, date: $0.date, measurements: $0.measurements, photoFilename: $0.photoFilename,
                  aiNotes: $0.aiNotes, aiModel: $0.aiModel, isDemo: $0.isDemo)
        }
        return doc
    }

    static func encode(_ doc: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(doc)
    }

    static func decode(_ data: Data) throws -> BackupDocument {
        struct Header: Decodable { var format: String?; var version: Int? }
        let header = try? JSONDecoder().decode(Header.self, from: data)
        guard header?.format == BackupDocument.format else { throw BackupError.notABackup }
        if let version = header?.version, version > 1 { throw BackupError.newerVersion(version) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupDocument.self, from: data)
    }

    // MARK: Restore

    /// Replaces everything in the store with the backup's contents.
    static func restore(_ doc: BackupDocument, into context: ModelContext) {
        deleteAll(context)
        if let p = doc.profile {
            let r = ProfileRecord()
            r.id = p.id; r.createdAt = p.createdAt; r.age = p.age; r.sexRaw = p.sex; r.heightCm = p.heightCm; r.weightKg = p.weightKg
            r.goalWeightKg = p.goalWeightKg; r.startDate = p.startDate; r.targetDate = p.targetDate; r.activityRaw = p.activity
            r.goalModeRaw = p.goalMode; r.liftingDays = p.liftingDays; r.courtDays = p.courtDays; r.dislikes = p.dislikes
            r.allergensRaw = p.allergens; r.unitSystemRaw = p.unitSystem; r.proteinPerLbOverride = p.proteinPerLbOverride
            r.fatPercentOverride = p.fatPercentOverride; r.weeklyRateOverrideKg = p.weeklyRateOverrideKg
            r.dayTargetOverridesData = p.dayTargetOverrides; r.mealSlotsRaw = p.mealSlots; r.isDemo = p.isDemo
            r.focusMusclesRaw = p.focusMuscles ?? []; r.dunkGoal = p.dunkGoal ?? false
            context.insert(r)
        }
        for f in doc.foods {
            let r = FoodRecord(id: f.id, name: f.name)
            r.seedKey = f.seedKey; r.brand = f.brand; r.servingLabel = f.servingLabel; r.servingAmount = f.servingAmount
            r.servingUnitRaw = f.servingUnit; r.kcal = f.kcal; r.protein = f.protein; r.carbs = f.carbs; r.fat = f.fat
            r.sectionRaw = f.section; r.allergensRaw = f.allergens; r.shakerSafe = f.shakerSafe; r.isBuiltIn = f.isBuiltIn
            r.isAIEstimate = f.isAIEstimate; r.isFavorite = f.isFavorite; r.isArchived = f.isArchived; r.isDemo = f.isDemo
            r.createdAt = f.createdAt
            context.insert(r)
        }
        for m in doc.recipes {
            let r = RecipeRecord(id: m.id, name: m.name)
            r.seedKey = m.seedKey; r.slotsRaw = m.slots; r.ingredients = m.ingredients; r.isShake = m.isShake; r.notes = m.notes
            r.isBuiltIn = m.isBuiltIn; r.isFavorite = m.isFavorite; r.isArchived = m.isArchived; r.isDemo = m.isDemo; r.createdAt = m.createdAt
            context.insert(r)
        }
        for e in doc.planEntries {
            let r = PlanEntryRecord(day: e.day, slotIndex: e.slotIndex, slot: MealSlot(rawValue: e.slot) ?? .snack)
            r.id = e.id; r.recipeID = e.recipeID; r.foodID = e.foodID; r.servings = e.servings; r.isLocked = e.isLocked; r.isDemo = e.isDemo
            context.insert(r)
        }
        for i in doc.intake {
            let r = IntakeRecord(day: i.day, name: i.name)
            r.id = i.id; r.timestamp = i.timestamp; r.slotRaw = i.slot; r.kcal = i.kcal; r.protein = i.protein; r.carbs = i.carbs
            r.fat = i.fat; r.planEntryID = i.planEntryID; r.isDemo = i.isDemo
            r.items = i.items ?? []; r.notes = i.notes ?? ""; r.recipeID = i.recipeID
            r.photoFilename = i.photoFilename.flatMap { FileManager.default.fileExists(atPath: PhotoStore.url(for: $0).path) ? $0 : nil }
            context.insert(r)
        }
        for g in doc.groceries {
            let r = GroceryItemRecord(name: g.name)
            r.id = g.id; r.amountText = g.amountText; r.sectionRaw = g.section; r.isChecked = g.isChecked; r.isManual = g.isManual
            r.sortIndex = g.sortIndex; r.isDemo = g.isDemo; r.createdAt = g.createdAt
            context.insert(r)
        }
        for x in doc.exercises {
            let r = ExerciseRecord(id: x.id, name: x.name)
            r.seedKey = x.seedKey; r.muscleRaw = x.muscle; r.equipmentRaw = x.equipment; r.isCompound = x.isCompound
            r.defaultRestSeconds = x.defaultRestSeconds; r.notes = x.notes; r.isBuiltIn = x.isBuiltIn; r.isArchived = x.isArchived
            r.createdAt = x.createdAt
            context.insert(r)
        }
        if let w = doc.workoutPlan {
            let r = WorkoutPlanRecord()
            r.id = w.id; r.createdAt = w.createdAt; r.liftingDays = w.liftingDays; r.courtDays = w.courtDays; r.days = w.days; r.isDemo = w.isDemo
            context.insert(r)
        }
        for s in doc.sessions {
            let r = WorkoutSessionRecord(date: s.date, title: s.title)
            r.id = s.id; r.dayTypeRaw = s.dayType; r.sets = s.sets; r.durationSeconds = s.durationSeconds; r.notes = s.notes
            r.isCompleted = s.isCompleted; r.prCount = s.prCount; r.isDemo = s.isDemo
            context.insert(r)
        }
        for c in doc.courtSessions {
            let r = CourtSessionRecord(date: c.date)
            r.id = c.id; r.kindRaw = c.kind; r.minutes = c.minutes; r.rpe = c.rpe; r.notes = c.notes; r.isDemo = c.isDemo
            context.insert(r)
        }
        for w in doc.weights {
            let r = WeightRecord(date: w.date, weightKg: w.weightKg)
            r.id = w.id; r.note = w.note; r.isDemo = w.isDemo
            context.insert(r)
        }
        for c in doc.checkIns ?? [] {
            let r = BodyCheckInRecord(date: c.date)
            r.id = c.id; r.measurements = c.measurements; r.photoFilename = c.photoFilename; r.aiNotes = c.aiNotes
            r.aiModel = c.aiModel; r.isDemo = c.isDemo
            context.insert(r)
        }
        SeedService.ensureBuiltIns(context) // backfill anything a newer version ships
        try? context.save()
    }

    /// Erases every record. Built-ins are re-seeded on the next launch or restore.
    static func deleteAll(_ context: ModelContext) {
        try? context.delete(model: ProfileRecord.self)
        try? context.delete(model: FoodRecord.self)
        try? context.delete(model: RecipeRecord.self)
        try? context.delete(model: PlanEntryRecord.self)
        try? context.delete(model: IntakeRecord.self)
        try? context.delete(model: GroceryItemRecord.self)
        try? context.delete(model: ExerciseRecord.self)
        try? context.delete(model: WorkoutPlanRecord.self)
        try? context.delete(model: WorkoutSessionRecord.self)
        try? context.delete(model: CourtSessionRecord.self)
        try? context.delete(model: WeightRecord.self)
        try? context.delete(model: BodyCheckInRecord.self)
        try? context.save()
    }

    /// Removes every stored progress photo (used by Reset all data).
    static func deletePhotos() {
        let folder = PhotoStore.directory
        for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: Files

    @discardableResult
    static func writeBackup(_ context: ModelContext, to folder: URL = backupFolder, keep: Int = 14) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = formatter.string(from: .now)
        let url = folder.appendingPathComponent("BulkBoard-\(stamp).json")
        try encode(snapshot(context)).write(to: url, options: .atomic)
        if !Persistence.usesInMemoryStore && !Persistence.usesCustomStore {
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastBackup")
        }
        prune(folder, keep: keep)
        return url
    }

    static func prune(_ folder: URL, keep: Int) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let backups = files.filter { $0.lastPathComponent.hasPrefix("BulkBoard-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(keep) { try? FileManager.default.removeItem(at: old) }
    }

    /// When the newest backup file in the folder was written, judged from the files themselves.
    static func newestBackupDate(in folder: URL = backupFolder) -> Date? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("BulkBoard-") && $0.pathExtension == "json" }
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max()
    }

    /// Daily automatic backup, skipped for throwaway stores.
    static func autoBackupIfNeeded(_ context: ModelContext) {
        guard autoBackupEnabled, !Persistence.usesInMemoryStore, !Persistence.usesCustomStore, context.profile != nil else { return }
        if let newest = newestBackupDate(), Date.now.timeIntervalSince(newest) < 20 * 3600 { return }
        _ = try? writeBackup(context)
    }

    // MARK: CSV

    static func csvFiles(_ context: ModelContext) -> [String: String] {
        let exercises = Dictionary(context.fetchAll(ExerciseRecord.self).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let iso = ISO8601DateFormatter()
        func row(_ fields: [String]) -> String { fields.map(csvEscape).joined(separator: ",") }
        func num(_ value: Double, _ decimals: Int = 1) -> String { String(format: "%.\(decimals)f", value) }

        var weights = [row(["date", "weight_kg", "weight_lb", "note"])]
        for w in context.fetchAll(WeightRecord.self, sortBy: [SortDescriptor(\.date)]) {
            weights.append(row([iso.string(from: w.date), num(w.weightKg, 2), num(Units.lb(fromKg: w.weightKg), 1), w.note]))
        }

        var lifts = [row(["date", "session", "exercise", "set", "reps", "weight_kg", "weight_lb", "warmup", "pr"])]
        for session in context.fetchAll(WorkoutSessionRecord.self, sortBy: [SortDescriptor(\.date)]) where session.isCompleted {
            for (index, set) in session.sets.enumerated() {
                lifts.append(row([iso.string(from: session.date), session.title, exercises[set.exerciseID] ?? set.exerciseID.uuidString,
                                  "\(index + 1)", "\(set.reps)", num(set.weightKg, 2), num(Units.lb(fromKg: set.weightKg), 1),
                                  set.isWarmup ? "yes" : "no", set.prKinds.map(\.title).joined(separator: "; ")]))
            }
        }

        var court = [row(["date", "type", "minutes", "rpe", "load", "notes"])]
        for c in context.fetchAll(CourtSessionRecord.self, sortBy: [SortDescriptor(\.date)]) {
            court.append(row([iso.string(from: c.date), c.kind.title, "\(c.minutes)", "\(c.rpe)", "\(c.log.load)", c.notes]))
        }

        var intake = [row(["date", "meal", "name", "kcal", "protein_g", "carbs_g", "fat_g", "items"])]
        for i in context.fetchAll(IntakeRecord.self, sortBy: [SortDescriptor(\.day)]) {
            let items = i.items.map { "\($0.displayName) (\($0.amountText))" }.joined(separator: "; ")
            intake.append(row([i.day.formatted(.iso8601.year().month().day()), i.slot.title, i.name,
                               num(i.kcal, 0), num(i.protein), num(i.carbs), num(i.fat), items]))
        }

        return ["weights.csv": weights.joined(separator: "\n") + "\n",
                "lifts.csv": lifts.joined(separator: "\n") + "\n",
                "court-sessions.csv": court.joined(separator: "\n") + "\n",
                "intake.csv": intake.joined(separator: "\n") + "\n"]
    }

    static func csvEscape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: Panels

    static func exportJSON(_ context: ModelContext) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "BulkBoard Backup \(Date.now.formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try encode(snapshot(context)).write(to: url, options: .atomic) } catch { presentError(error) }
    }

    static func exportCSV(_ context: ModelContext) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export CSVs Here"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            for (name, text) in csvFiles(context) {
                try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch { presentError(error) }
    }

    /// Asks for a backup file, confirms, saves a safety backup of current data, then restores.
    static func importJSON(_ context: ModelContext) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let doc = try decode(Data(contentsOf: url))
            let alert = NSAlert()
            alert.messageText = "Replace all data with this backup?"
            alert.informativeText = "From \(doc.exportedAt.formatted(date: .abbreviated, time: .shortened)): \(doc.weights.count) weigh-ins, \(doc.sessions.count) workouts. Your current data is backed up first."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if context.profile != nil { try writeBackup(context) }
            restore(doc, into: context)
        } catch { presentError(error) }
    }

    static func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

enum BackupError: LocalizedError {
    case notABackup
    case newerVersion(Int)

    var errorDescription: String? {
        switch self {
        case .notABackup: "That file isn't a BulkBoard backup."
        case let .newerVersion(version): "This backup is from a newer BulkBoard (format v\(version)). Update the app to import it."
        }
    }
}
