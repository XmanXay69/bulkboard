import BulkCore
import Foundation
import SwiftData

/// Inserts the built-in food list, meals and exercise library. Idempotent: anything already
/// present (matched by seed key) is left alone, so user edits survive and new app versions can add more.
enum SeedService {
    static func ensureBuiltIns(_ context: ModelContext) {
        let foodKeys = Set(context.fetchAll(FoodRecord.self).compactMap(\.seedKey))
        for seed in (try? SeedLibrary.foods()) ?? [] where !foodKeys.contains(seed.key) {
            let record = FoodRecord(id: seed.id, name: seed.name)
            record.apply(seed.item)
            record.seedKey = seed.key
            record.isBuiltIn = !(seed.custom ?? false)
            context.insert(record)
        }

        let mealKeys = Set(context.fetchAll(RecipeRecord.self).compactMap(\.seedKey))
        for seed in (try? SeedLibrary.meals()) ?? [] where !mealKeys.contains(seed.key) {
            let template = seed.template
            let record = RecipeRecord(id: template.id, name: template.name)
            record.slots = template.slots
            record.ingredients = template.ingredients
            record.isShake = template.isShake
            record.seedKey = seed.key
            record.isBuiltIn = true
            context.insert(record)
        }

        let exerciseKeys = Set(context.fetchAll(ExerciseRecord.self).compactMap(\.seedKey))
        for seed in (try? SeedLibrary.exercises()) ?? [] where !exerciseKeys.contains(seed.key) {
            let def = seed.def
            let record = ExerciseRecord(id: def.id, name: def.name)
            record.muscle = def.muscle
            record.equipment = def.equipment
            record.isCompound = def.isCompound
            record.defaultRestSeconds = def.defaultRestSeconds
            record.seedKey = seed.key
            record.isBuiltIn = true
            context.insert(record)
        }
        try? context.save()
    }
}
