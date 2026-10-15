import Foundation

/// Grocery store sections, in walking order.
public enum StoreSection: String, Codable, CaseIterable, Sendable, Comparable {
    case produce
    case meatSeafood
    case dairyEggs
    case bakery
    case grainsPasta
    case pantry
    case snacks
    case frozen
    case beverages
    case supplements
    case other

    public var title: String {
        switch self {
        case .produce: "Produce"
        case .meatSeafood: "Meat & Seafood"
        case .dairyEggs: "Dairy & Eggs"
        case .bakery: "Bakery"
        case .grainsPasta: "Grains & Pasta"
        case .pantry: "Pantry"
        case .snacks: "Snacks"
        case .frozen: "Frozen"
        case .beverages: "Beverages"
        case .supplements: "Supplements"
        case .other: "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .produce: "carrot.fill"
        case .meatSeafood: "fish.fill"
        case .dairyEggs: "drop.fill"
        case .bakery: "birthday.cake.fill"
        case .grainsPasta: "takeoutbag.and.cup.and.straw.fill"
        case .pantry: "cabinet.fill"
        case .snacks: "popcorn.fill"
        case .frozen: "snowflake"
        case .beverages: "waterbottle.fill"
        case .supplements: "pills.fill"
        case .other: "bag.fill"
        }
    }

    private var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (lhs: StoreSection, rhs: StoreSection) -> Bool { lhs.order < rhs.order }
}

public enum Allergen: String, Codable, CaseIterable, Sendable {
    case dairy
    case egg
    case peanut
    case treeNut
    case gluten
    case soy
    case fish
    case shellfish

    public var title: String {
        switch self {
        case .dairy: "Dairy"
        case .egg: "Egg"
        case .peanut: "Peanut"
        case .treeNut: "Tree nut"
        case .gluten: "Gluten"
        case .soy: "Soy"
        case .fish: "Fish"
        case .shellfish: "Shellfish"
        }
    }
}

/// Units a serving can be measured in. Mass and volume convert; count-style units only merge with themselves.
public enum GroceryUnit: String, Codable, CaseIterable, Sendable {
    case g, kg, oz, lb
    case ml, l, flOz, cup, tbsp, tsp
    case piece, slice, scoop, serving, can

    public enum Dimension: Sendable, Equatable { case mass, volume, count(GroceryUnit) }

    public var dimension: Dimension {
        switch self {
        case .g, .kg, .oz, .lb: .mass
        case .ml, .l, .flOz, .cup, .tbsp, .tsp: .volume
        case .piece, .slice, .scoop, .serving, .can: .count(self)
        }
    }

    /// Multiplier to the dimension's base unit (grams for mass, millilitres for volume, 1 for counts).
    public var toBase: Double {
        switch self {
        case .g: 1
        case .kg: 1000
        case .oz: 28.349523125
        case .lb: 453.59237
        case .ml: 1
        case .l: 1000
        case .flOz: 29.5735295625
        case .cup: 236.5882365
        case .tbsp: 14.78676478125
        case .tsp: 4.92892159375
        case .piece, .slice, .scoop, .serving, .can: 1
        }
    }

    public var label: String {
        switch self {
        case .g: "g"
        case .kg: "kg"
        case .oz: "oz"
        case .lb: "lb"
        case .ml: "ml"
        case .l: "L"
        case .flOz: "fl oz"
        case .cup: "cup"
        case .tbsp: "tbsp"
        case .tsp: "tsp"
        case .piece: "pc"
        case .slice: "slice"
        case .scoop: "scoop"
        case .serving: "serving"
        case .can: "can"
        }
    }
}

public struct FoodItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var brand: String?
    /// Human-friendly serving, e.g. "1 cup cooked (50 g dry)".
    public var servingLabel: String
    /// Amount of `servingUnit` per serving, used to merge grocery quantities.
    public var servingAmount: Double
    public var servingUnit: GroceryUnit
    public var macros: Macros
    public var section: StoreSection
    public var allergens: Set<Allergen>
    /// Mixes fine in a shaker bottle with no blender.
    public var shakerSafe: Bool

    public init(id: UUID = UUID(), name: String, brand: String? = nil, servingLabel: String,
                servingAmount: Double, servingUnit: GroceryUnit, macros: Macros,
                section: StoreSection, allergens: Set<Allergen> = [], shakerSafe: Bool = false) {
        self.id = id
        self.name = name
        self.brand = brand
        self.servingLabel = servingLabel
        self.servingAmount = servingAmount
        self.servingUnit = servingUnit
        self.macros = macros
        self.section = section
        self.allergens = allergens
        self.shakerSafe = shakerSafe
    }
}

public enum MealSlot: String, Codable, CaseIterable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack
    case shake

    public var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        case .shake: "Shake"
        }
    }

    public var symbol: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "carrot.fill"
        case .shake: "cup.and.saucer.fill"
        }
    }

    /// Soft cap on how much of the day's calories one meal in this slot should carry.
    public var maxDailyShare: Double {
        switch self {
        case .breakfast: 0.30
        case .lunch: 0.35
        case .dinner: 0.38
        case .snack: 0.18
        case .shake: 0.25
        }
    }

    /// Default daily structure: three meals, a snack and a shake.
    public static let defaultDay: [MealSlot] = [.breakfast, .lunch, .snack, .dinner, .shake]
}

public struct Ingredient: Codable, Hashable, Sendable {
    public var foodID: UUID
    public var servings: Double

    public init(foodID: UUID, servings: Double) {
        self.foodID = foodID
        self.servings = servings
    }
}

/// A saved meal or recipe (shakes included) built from foods.
public struct MealTemplate: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var slots: Set<MealSlot>
    public var ingredients: [Ingredient]
    public var isShake: Bool

    public init(id: UUID = UUID(), name: String, slots: Set<MealSlot>, ingredients: [Ingredient], isShake: Bool = false) {
        self.id = id
        self.name = name
        self.slots = slots
        self.ingredients = ingredients
        self.isShake = isShake
    }

    /// Totals for one serving of the meal, given a food lookup. Unknown foods count as zero.
    public func macros(foods: [UUID: FoodItem]) -> Macros {
        ingredients.map { ingredient in
            (foods[ingredient.foodID]?.macros ?? .zero) * ingredient.servings
        }.sum()
    }
}
