import Foundation

/// Built-in starter data shipped as JSON in the package: foods, meals/shakes, and the exercise library.
/// IDs are derived from each entry's stable `key`, so they survive reinstalls and exports.
public enum SeedLibrary {
    public struct FoodSeed: Codable, Sendable {
        public var key: String
        public var name: String
        public var brand: String?
        public var serving: String
        public var amount: Double
        public var unit: GroceryUnit
        public var kcal: Double
        public var p: Double
        public var c: Double
        public var f: Double
        public var section: StoreSection
        public var allergens: [Allergen]?
        public var shaker: Bool?
        /// Seeded into "My foods" so the user can edit it (e.g. their protein powder).
        public var custom: Bool?

        public var id: UUID { SeedLibrary.foodID(key) }

        public var item: FoodItem {
            FoodItem(id: id, name: name, brand: brand, servingLabel: serving, servingAmount: amount, servingUnit: unit,
                     macros: Macros(kcal: kcal, protein: p, carbs: c, fat: f), section: section,
                     allergens: Set(allergens ?? []), shakerSafe: shaker ?? false)
        }
    }

    public struct MealSeed: Codable, Sendable {
        public struct Item: Codable, Sendable {
            public var f: String
            public var s: Double
        }

        public var key: String
        public var name: String
        public var slots: [MealSlot]
        public var shake: Bool?
        public var items: [Item]

        public var id: UUID { SeedLibrary.mealID(key) }

        public var template: MealTemplate {
            MealTemplate(id: id, name: name, slots: Set(slots),
                         ingredients: items.map { Ingredient(foodID: SeedLibrary.foodID($0.f), servings: $0.s) },
                         isShake: shake ?? false)
        }
    }

    public struct ExerciseSeed: Codable, Sendable {
        public var key: String
        public var name: String
        public var muscle: MuscleGroup
        public var equipment: Equipment
        public var compound: Bool
        public var rest: Int

        public var id: UUID { SeedLibrary.exerciseID(key) }

        public var def: ExerciseDef {
            ExerciseDef(id: id, name: name, muscle: muscle, equipment: equipment, isCompound: compound, defaultRestSeconds: rest)
        }
    }

    public static func foodID(_ key: String) -> UUID { StableID.uuid("food", key) }
    public static func mealID(_ key: String) -> UUID { StableID.uuid("meal", key) }
    public static func exerciseID(_ key: String) -> UUID { StableID.uuid("exercise", key) }

    public static func foods() throws -> [FoodSeed] { try load("foods") }
    public static func meals() throws -> [MealSeed] { try load("meals") }
    public static func exercises() throws -> [ExerciseSeed] { try load("exercises") }

    private static func load<T: Decodable>(_ name: String) throws -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
