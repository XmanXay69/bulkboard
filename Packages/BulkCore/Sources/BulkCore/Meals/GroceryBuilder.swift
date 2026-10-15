import Foundation

/// One food's use somewhere in the plan.
public struct FoodUse: Sendable {
    public var food: FoodItem
    public var servings: Double

    public init(food: FoodItem, servings: Double) {
        self.food = food
        self.servings = servings
    }
}

public struct GroceryLine: Hashable, Sendable, Identifiable {
    public var name: String
    public var section: StoreSection
    /// Grams of everything measured by mass.
    public var grams: Double
    /// Millilitres of everything measured by volume.
    public var milliliters: Double
    /// Count-style units (pieces, slices, scoops…) that only merge with themselves.
    public var counts: [GroceryUnit: Double]
    public var amountText: String

    public var id: String { name.lowercased() }
}

public struct GrocerySection: Hashable, Sendable, Identifiable {
    public var section: StoreSection
    public var lines: [GroceryLine]

    public var id: StoreSection { section }
}

public enum GroceryBuilder {
    /// Expands planned meals (and stand-alone foods) into individual food uses.
    public static func uses(meals: [PlannedMeal], templates: [UUID: MealTemplate], foods: [UUID: FoodItem]) -> [FoodUse] {
        meals.flatMap { meal -> [FoodUse] in
            if let template = templates[meal.candidateID] {
                return template.ingredients.compactMap { ingredient in
                    foods[ingredient.foodID].map { FoodUse(food: $0, servings: ingredient.servings * meal.servings) }
                }
            }
            if let food = foods[meal.candidateID] {
                return [FoodUse(food: food, servings: meal.servings)]
            }
            return []
        }
    }

    /// Merges uses by food name, converting compatible units, then groups by store section in walking order.
    public static func build(_ uses: [FoodUse], unitSystem: UnitSystem) -> [GrocerySection] {
        var lines: [String: GroceryLine] = [:]
        var order: [String] = []

        for use in uses where use.servings > 0 {
            let key = use.food.name.trimmingCharacters(in: .whitespaces).lowercased()
            if lines[key] == nil {
                lines[key] = GroceryLine(name: use.food.name, section: use.food.section, grams: 0,
                                         milliliters: 0, counts: [:], amountText: "")
                order.append(key)
            }
            let amount = use.food.servingAmount * use.servings
            switch use.food.servingUnit.dimension {
            case .mass: lines[key]!.grams += amount * use.food.servingUnit.toBase
            case .volume: lines[key]!.milliliters += amount * use.food.servingUnit.toBase
            case let .count(unit): lines[key]!.counts[unit, default: 0] += amount
            }
        }

        for key in order {
            lines[key]!.amountText = amountText(for: lines[key]!, unitSystem: unitSystem)
        }

        let grouped = Dictionary(grouping: order.compactMap { lines[$0] }, by: \.section)
        return grouped.keys.sorted().map { section in
            GrocerySection(section: section,
                           lines: grouped[section]!.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    static func amountText(for line: GroceryLine, unitSystem: UnitSystem) -> String {
        var parts: [String] = []
        if line.grams > 0 { parts.append(massText(grams: line.grams, unitSystem: unitSystem)) }
        if line.milliliters > 0 { parts.append(volumeText(ml: line.milliliters, unitSystem: unitSystem)) }
        for unit in GroceryUnit.allCases {
            guard let count = line.counts[unit], count > 0 else { continue }
            let whole = (count - 0.05).rounded(.up) // you buy whole items; ignore float dust
            parts.append("\(Fmt.int(whole)) \(countLabel(unit, count: whole))")
        }
        return parts.joined(separator: " + ")
    }

    public static func massText(grams: Double, unitSystem: UnitSystem) -> String {
        switch unitSystem {
        case .imperial:
            let ounces = grams / GroceryUnit.oz.toBase
            return ounces >= 16 ? "\(Fmt.number(ounces / 16)) lb" : "\(Fmt.int(max(1, ounces.rounded()))) oz"
        case .metric:
            return grams >= 1000 ? "\(Fmt.number(grams / 1000)) kg" : "\(Fmt.int(max(10, (grams / 10).rounded() * 10))) g"
        }
    }

    public static func volumeText(ml: Double, unitSystem: UnitSystem) -> String {
        switch unitSystem {
        case .imperial:
            let gallon = 3785.411784
            let quart = gallon / 4
            if ml >= gallon { return "\(Fmt.number(ml / gallon)) gal" }
            if ml >= quart { return "\(Fmt.number(ml / quart)) qt" }
            if ml >= GroceryUnit.cup.toBase { return "\(Fmt.number(ml / GroceryUnit.cup.toBase)) cups" }
            return "\(Fmt.int(max(1, (ml / GroceryUnit.tbsp.toBase).rounded()))) tbsp"
        case .metric:
            return ml >= 1000 ? "\(Fmt.number(ml / 1000)) L" : "\(Fmt.int(max(10, (ml / 10).rounded() * 10))) ml"
        }
    }

    static func countLabel(_ unit: GroceryUnit, count: Double) -> String {
        let plural = count != 1
        switch unit {
        case .piece: return "pc"
        case .slice: return plural ? "slices" : "slice"
        case .scoop: return plural ? "scoops" : "scoop"
        case .serving: return plural ? "servings" : "serving"
        case .can: return plural ? "cans" : "can"
        default: return unit.label
        }
    }

    /// Plain-text list for copying into Notes or a text message.
    public static func plainText(title: String, sections: [(section: StoreSection, items: [(name: String, amount: String, checked: Bool)])]) -> String {
        var out = [title, ""]
        for group in sections where !group.items.isEmpty {
            out.append(group.section.title.uppercased())
            for item in group.items {
                let box = item.checked ? "[x]" : "[ ]"
                out.append(item.amount.isEmpty ? "\(box) \(item.name)" : "\(box) \(item.name) — \(item.amount)")
            }
            out.append("")
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
