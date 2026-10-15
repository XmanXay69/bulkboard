import Foundation

/// A meal the planner can choose from, flattened from a `MealTemplate`.
public struct PlannerCandidate: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var slots: Set<MealSlot>
    /// Per serving.
    public var macros: Macros
    public var allergens: Set<Allergen>
    /// Lowercased meal and ingredient names, matched against dislikes.
    public var searchText: String

    public init(id: UUID, name: String, slots: Set<MealSlot>, macros: Macros,
                allergens: Set<Allergen> = [], searchText: String? = nil) {
        self.id = id
        self.name = name
        self.slots = slots
        self.macros = macros
        self.allergens = allergens
        self.searchText = (searchText ?? name).lowercased()
    }

    public init(template: MealTemplate, foods: [UUID: FoodItem]) {
        let ingredientFoods = template.ingredients.compactMap { foods[$0.foodID] }
        self.init(id: template.id, name: template.name, slots: template.slots,
                  macros: template.macros(foods: foods),
                  allergens: ingredientFoods.reduce(into: Set<Allergen>()) { $0.formUnion($1.allergens) },
                  searchText: ([template.name] + ingredientFoods.map(\.name)).joined(separator: " "))
    }
}

public struct PlannedMeal: Hashable, Sendable, Codable {
    public var candidateID: UUID
    public var servings: Double

    public init(candidateID: UUID, servings: Double) {
        self.candidateID = candidateID
        self.servings = servings
    }
}

public struct DayRequest: Sendable {
    public var target: Macros
    public var slots: [MealSlot]
    /// Slot index → meal that must stay put.
    public var locked: [Int: PlannedMeal]

    public init(target: Macros, slots: [MealSlot], locked: [Int: PlannedMeal] = [:]) {
        self.target = target
        self.slots = slots
        self.locked = locked
    }
}

public struct DayPlan: Sendable, Equatable {
    /// Aligned with the request's slots; nil when nothing fits a slot.
    public var meals: [PlannedMeal?]
    public var totals: Macros
    public var score: Double
}

/// How much the planner spreads meals across the week.
public enum MealVariety: String, Codable, CaseIterable, Sendable {
    /// Repeat the same few meals: shortest grocery list, easiest to batch-cook.
    case prep
    case balanced
    case mixItUp

    public var title: String {
        switch self {
        case .prep: "Meal prep"
        case .balanced: "Balanced"
        case .mixItUp: "Mix it up"
        }
    }

    var maxRepeatsPerWeek: Int {
        switch self {
        case .prep: 7
        case .balanced: 3
        case .mixItUp: 2
        }
    }

    /// Cost per extra use of a meal within the week. Negative rewards repeats.
    var repeatPenalty: Double {
        switch self {
        case .prep: -0.01
        case .balanced: 0.015
        case .mixItUp: 0.04
        }
    }
}

public struct PlannerOptions: Sendable {
    public var servingSteps: [Double]
    public var restarts: Int
    public var maxRepeatsPerWeek: Int
    public var repeatPenalty: Double
    public var dislikes: [String]
    public var avoidAllergens: Set<Allergen>

    public init(servingSteps: [Double] = [0.75, 1, 1.25, 1.5, 2], restarts: Int = 6, variety: MealVariety = .balanced,
                dislikes: [String] = [], avoidAllergens: Set<Allergen> = []) {
        self.servingSteps = servingSteps
        self.restarts = restarts
        self.maxRepeatsPerWeek = variety.maxRepeatsPerWeek
        self.repeatPenalty = variety.repeatPenalty
        self.dislikes = dislikes
        self.avoidAllergens = avoidAllergens
    }
}

/// Proposes meals for each slot of each day so daily totals land on target.
///
/// Per day: random start, then coordinate descent (swap one slot's meal and serving size at a time
/// while it improves), with several restarts. Days run in order so a variety penalty spreads meals
/// across the week. Seeded, so the same seed gives the same plan.
public enum MealPlanner {
    public static func eligible(_ candidates: [PlannerCandidate], options: PlannerOptions) -> [PlannerCandidate] {
        let dislikes = options.dislikes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return candidates.filter { candidate in
            candidate.allergens.isDisjoint(with: options.avoidAllergens)
                && !dislikes.contains(where: { candidate.searchText.contains($0) })
        }
    }

    /// Lower is better. Calories and protein dominate; going over on protein is cheap.
    public static func score(_ totals: Macros, target: Macros) -> Double {
        func rel(_ value: Double, _ goal: Double) -> Double { goal > 0 ? (value - goal) / goal : 0 }
        let k = rel(totals.kcal, target.kcal)
        let p = rel(totals.protein, target.protein)
        let c = rel(totals.carbs, target.carbs)
        let f = rel(totals.fat, target.fat)
        return 4 * k * k + (p < 0 ? 4 : 0.5) * p * p + c * c + f * f
    }

    public static func planWeek(_ days: [DayRequest], candidates: [PlannerCandidate],
                                options: PlannerOptions = PlannerOptions(), seed: UInt64) -> [DayPlan] {
        var rng = SplitMix64(seed: seed)
        let pool = eligible(candidates, options: options)
        let byID = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .merging(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var usage: [UUID: Int] = [:]
        for day in days {
            for meal in day.locked.values { usage[meal.candidateID, default: 0] += 1 }
        }

        var plans: [DayPlan] = []
        for day in days {
            let plan = planDay(day, pool: pool, byID: byID, usage: usage, options: options, rng: &rng)
            for (index, meal) in plan.meals.enumerated() where day.locked[index] == nil {
                if let meal { usage[meal.candidateID, default: 0] += 1 }
            }
            plans.append(plan)
        }
        return plans
    }

    static func planDay(_ day: DayRequest, pool: [PlannerCandidate], byID: [UUID: PlannerCandidate],
                        usage: [UUID: Int], options: PlannerOptions, rng: inout SplitMix64) -> DayPlan {
        let slotOptions: [[PlannerCandidate]] = day.slots.map { slot in pool.filter { $0.slots.contains(slot) } }

        func totals(_ meals: [PlannedMeal?]) -> Macros {
            meals.compactMap { $0 }.reduce(Macros.zero) { sum, meal in
                sum + (byID[meal.candidateID]?.macros ?? .zero) * meal.servings
            }
        }

        func penalty(_ meals: [PlannedMeal?]) -> Double {
            var counts: [UUID: Int] = [:]
            var cost = 0.0
            for (index, meal) in meals.enumerated() {
                guard let meal, day.locked[index] == nil else { continue }
                counts[meal.candidateID, default: 0] += 1
                let used = usage[meal.candidateID, default: 0] + counts[meal.candidateID, default: 0]
                if used > options.maxRepeatsPerWeek { cost += 0.5 }
                cost += options.repeatPenalty * Double(used - 1)
                if counts[meal.candidateID, default: 0] > 1 { cost += 0.3 } // same meal twice in a day
                cost += 0.004 * abs(meal.servings - 1)
            }
            return cost
        }

        func evaluate(_ meals: [PlannedMeal?]) -> Double { score(totals(meals), target: day.target) + penalty(meals) }

        var best: [PlannedMeal?] = []
        var bestScore = Double.infinity

        for _ in 0..<max(1, options.restarts) {
            var meals: [PlannedMeal?] = day.slots.indices.map { index in
                if let locked = day.locked[index] { return locked }
                guard let pick = slotOptions[index].randomElement(using: &rng) else { return nil }
                return PlannedMeal(candidateID: pick.id, servings: 1)
            }
            var current = evaluate(meals)

            for _ in 0..<8 {
                var improved = false
                for index in day.slots.indices.shuffled(using: &rng) where day.locked[index] == nil {
                    for candidate in slotOptions[index] {
                        for servings in options.servingSteps {
                            let previous = meals[index]
                            meals[index] = PlannedMeal(candidateID: candidate.id, servings: servings)
                            let value = evaluate(meals)
                            if value + 1e-12 < current {
                                current = value
                                improved = true
                            } else {
                                meals[index] = previous
                            }
                        }
                    }
                }
                if !improved { break }
            }

            if current < bestScore {
                bestScore = current
                best = meals
            }
        }

        return DayPlan(meals: best, totals: totals(best), score: score(totals(best), target: day.target))
    }
}
