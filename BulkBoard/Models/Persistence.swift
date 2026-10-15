import Foundation
import SwiftData

nonisolated enum BulkBoardSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            ProfileRecord.self, FoodRecord.self, RecipeRecord.self, PlanEntryRecord.self,
            IntakeRecord.self, GroceryItemRecord.self, ExerciseRecord.self, WorkoutPlanRecord.self,
            WorkoutSessionRecord.self, CourtSessionRecord.self, WeightRecord.self,
        ]
    }
}

nonisolated enum BulkBoardMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [BulkBoardSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum Persistence {
    /// `~/Library/Application Support/BulkBoard`. Created on first access.
    static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("BulkBoard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var storeURL: URL { appSupportDirectory.appendingPathComponent("BulkBoard.store") }

    /// True when running under XCTest or a launch argument asks for a throwaway store.
    static var usesInMemoryStore: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("--in-memory")
    }

    static func makeContainer(inMemory: Bool = usesInMemoryStore) throws -> ModelContainer {
        let schema = Schema(versionedSchema: BulkBoardSchemaV1.self)
        let configuration = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, migrationPlan: BulkBoardMigrationPlan.self,
                                  configurations: configuration)
    }
}
