import Foundation

/// Nutrition for one product as a label or food database states it.
public struct NutritionFacts: Codable, Hashable, Sendable {
    /// Per 100 g, or per 100 ml for drinks.
    public var per100: Macros?
    /// Per label serving.
    public var perServing: Macros?
    /// Grams (or ml) in one label serving.
    public var servingGrams: Double?
    /// The label's serving text, e.g. "2 slices (56 g)".
    public var servingText: String?
    /// Grams (or ml) in the whole package.
    public var packageGrams: Double?
    /// Measured in ml rather than g.
    public var isLiquid: Bool

    public init(per100: Macros? = nil, perServing: Macros? = nil, servingGrams: Double? = nil, servingText: String? = nil,
                packageGrams: Double? = nil, isLiquid: Bool = false) {
        self.per100 = per100
        self.perServing = perServing
        self.servingGrams = servingGrams.flatMap { $0 > 0 ? $0 : nil }
        self.servingText = servingText.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        self.packageGrams = packageGrams.flatMap { $0 > 0 ? $0 : nil }
        self.isLiquid = isLiquid
    }

    /// Macros for one label serving, from the label itself or derived from per-100 values.
    public var servingMacros: Macros? {
        if let perServing { return perServing }
        if let per100, let servingGrams { return per100 * (servingGrams / 100) }
        return nil
    }

    /// Countable pieces named by the serving text, e.g. 2 "slice"s per "2 slices (56 g)".
    public var piece: (name: String, perServing: Double)? {
        guard let text = servingText else { return nil }
        let parsed = ServingText.parse(text)
        guard let name = parsed.noun, let count = parsed.count, count > 0 else { return nil }
        return (name, count)
    }
}

/// How an amount is measured when logging food.
public enum PortionUnit: Codable, Hashable, Sendable {
    /// One label serving.
    case serving
    /// A countable piece: "slice", "cookie", "egg", "cup".
    case piece(String)
    /// The whole package.
    case package
    case grams
    case ounces

    /// "slices", "g", "fl oz"…
    public func label(quantity: Double, liquid: Bool) -> String {
        let plural = abs(quantity - 1) > 1e-9
        switch self {
        case .serving: return plural ? "servings" : "serving"
        case let .piece(name): return plural ? ServingText.pluralize(name) : name
        case .package: return plural ? "packages" : "package"
        case .grams: return liquid ? "ml" : "g"
        case .ounces: return liquid ? "fl oz" : "oz"
        }
    }

    /// Reads a unit word from free text ("slices", "g", "pack"), as typed or as an AI guessed it.
    public static func parse(_ word: String) -> PortionUnit {
        let lower = word.trimmingCharacters(in: .whitespaces).lowercased()
        switch lower {
        case "", "serving", "servings", "portion", "portions", "x": return .serving
        case "g", "gram", "grams", "gr", "ml", "milliliter", "milliliters", "millilitre", "millilitres": return .grams
        case "oz", "ounce", "ounces", "fl oz", "fl. oz", "floz": return .ounces
        case "package", "packages", "pack", "packs", "bag", "bags", "box", "boxes", "container", "containers", "pkg":
            return .package
        default: return .piece(ServingText.singularize(lower))
        }
    }
}

/// A unit choice for one product, with how much of the product it means.
public struct PortionOption: Hashable, Sendable, Identifiable {
    public var unit: PortionUnit
    /// "serving · 2 slices (56 g)", "slice · 28 g", "g".
    public var title: String

    public var id: PortionUnit { unit }
}

/// Converts "2 slices" or "150 g" of a product into macros.
public enum PortionMath {
    public static let gramsPerOunce = 28.349523125
    public static let mlPerFluidOunce = 29.5735295625

    /// The units that make sense for these facts, most natural first.
    public static func options(for facts: NutritionFacts) -> [PortionOption] {
        var options: [PortionOption] = []
        let g = facts.isLiquid ? "ml" : "g"
        if facts.servingMacros != nil {
            var title = "serving"
            if let text = facts.servingText { title += " · \(text)" } else if let grams = facts.servingGrams { title += " · \(Fmt.number(grams)) \(g)" }
            options.append(PortionOption(unit: .serving, title: title))
        }
        if facts.servingMacros != nil, let piece = facts.piece, piece.name != "serving" {
            var title = piece.name
            if let grams = facts.servingGrams { title += " · \(Fmt.number(grams / piece.perServing)) \(g)" }
            options.append(PortionOption(unit: .piece(piece.name), title: title))
        }
        if let package = facts.packageGrams, canWeigh(facts) {
            options.append(PortionOption(unit: .package, title: "package · \(Fmt.number(package)) \(g)"))
        }
        if canWeigh(facts) {
            options.append(PortionOption(unit: .grams, title: g))
            options.append(PortionOption(unit: .ounces, title: facts.isLiquid ? "fl oz" : "oz"))
        }
        return options
    }

    /// The unit to start with: the label's piece name when it has one ("slice"), else serving, else grams.
    public static func defaultUnit(for facts: NutritionFacts) -> PortionUnit {
        options(for: facts).first?.unit ?? .serving
    }

    /// Picks the closest available unit when the one asked for doesn't apply (an AI said "slices", the label has none).
    public static func resolve(_ unit: PortionUnit, for facts: NutritionFacts) -> PortionUnit {
        let available = options(for: facts).map(\.unit)
        if available.contains(unit) { return unit }
        if case .piece = unit, let piece = available.first(where: { if case .piece = $0 { true } else { false } }) { return piece }
        return available.first ?? .serving
    }

    public static func grams(_ quantity: Double, _ unit: PortionUnit, facts: NutritionFacts) -> Double? {
        let ounce = facts.isLiquid ? mlPerFluidOunce : gramsPerOunce
        switch unit {
        case .grams: return quantity
        case .ounces: return quantity * ounce
        case .package: return facts.packageGrams.map { $0 * quantity }
        case .serving: return facts.servingGrams.map { $0 * quantity }
        case .piece:
            guard let servingGrams = facts.servingGrams, let piece = facts.piece else { return nil }
            return servingGrams / piece.perServing * quantity
        }
    }

    /// The amount expressed in label servings.
    public static func servings(_ quantity: Double, _ unit: PortionUnit, facts: NutritionFacts) -> Double? {
        switch unit {
        case .serving: return quantity
        case .piece:
            guard let piece = facts.piece else { return nil }
            return quantity / piece.perServing
        default:
            guard let grams = grams(quantity, unit, facts: facts), let servingGrams = facts.servingGrams else { return nil }
            return grams / servingGrams
        }
    }

    /// Macros for the amount. Servings and pieces use the label's per-serving numbers; weights use per-100 values.
    public static func macros(_ quantity: Double, _ unit: PortionUnit, facts: NutritionFacts) -> Macros? {
        guard quantity >= 0 else { return nil }
        switch unit {
        case .serving, .piece:
            if let serving = facts.servingMacros, let servings = servings(quantity, unit, facts: facts) { return serving * servings }
            if let per100 = facts.per100, let grams = grams(quantity, unit, facts: facts) { return per100 * (grams / 100) }
            return nil
        case .package, .grams, .ounces:
            guard let grams = grams(quantity, unit, facts: facts) else { return nil }
            if let per100 = facts.per100 { return per100 * (grams / 100) }
            if let serving = facts.servingMacros, let servingGrams = facts.servingGrams { return serving * (grams / servingGrams) }
            return nil
        }
    }

    /// "2 slices (56 g)", "1 package (780 g)", "150 g".
    public static func describe(_ quantity: Double, _ unit: PortionUnit, facts: NutritionFacts) -> String {
        let amount = "\(Fmt.number(quantity, maxDecimals: 2)) \(unit.label(quantity: quantity, liquid: facts.isLiquid))"
        switch unit {
        case .grams, .ounces: return amount
        default:
            guard let grams = grams(quantity, unit, facts: facts) else { return amount }
            return "\(amount) (\(Fmt.int(grams)) \(facts.isLiquid ? "ml" : "g"))"
        }
    }

    private static func canWeigh(_ facts: NutritionFacts) -> Bool {
        facts.per100 != nil || (facts.servingMacros != nil && facts.servingGrams != nil)
    }
}

/// Parses label serving text like "2 slices (56 g)", "1/2 cup (120 ml)" or "130 g".
public struct ServingText: Equatable, Sendable {
    public var count: Double?
    /// Singular, lowercase piece name ("slice"), when the text names one.
    public var noun: String?
    /// Grams or ml stated in the text.
    public var grams: Double?
    public var isLiquid: Bool

    private static let measureWords: Set<String> = [
        "g", "gr", "gram", "grams", "kg", "mg", "ml", "cl", "l", "liter", "liters", "litre", "litres",
        "oz", "ounce", "ounces", "fl", "lb", "lbs", "serving", "servings", "portion", "portions", "x", "of",
    ]
    private static let adjectives: Set<String> = ["large", "medium", "small", "extra", "whole", "jumbo", "mini", "regular", "thin", "thick", "big"]

    public static func parse(_ text: String) -> ServingText {
        var result = ServingText(count: nil, noun: nil, grams: nil, isLiquid: false)
        let lower = text.lowercased().replacingOccurrences(of: ",", with: ".")

        // A metric or ounce measure anywhere, preferring the one in parentheses.
        let measure = #/(\d+(?:\.\d+)?)\s*(kg|mg|g|gr|grams?|ml|cl|l|fl\.?\s?oz|oz)\b/#
        let inParens = lower.firstMatch(of: #/\(([^)]*)\)/#).flatMap { $0.output.1.firstMatch(of: measure) }
        if let match = inParens ?? lower.firstMatch(of: measure), let value = Double(match.output.1) {
            let unit = String(match.output.2).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
            switch unit {
            case "kg": result.grams = value * 1000
            case "mg": result.grams = value / 1000
            case "ml": result.grams = value; result.isLiquid = true
            case "cl": result.grams = value * 10; result.isLiquid = true
            case "l": result.grams = value * 1000; result.isLiquid = true
            case "floz": result.grams = value * PortionMath.mlPerFluidOunce; result.isLiquid = true
            case "oz": result.grams = value * PortionMath.gramsPerOunce
            default: result.grams = value
            }
        }

        // A leading count and the word after it: "2 slices", "1 1/2 cups", "1/6 pizza".
        let lead = #/^\s*(\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)\s*([a-z][a-z\-]*)?(?:\s+([a-z][a-z\-]*))?/#
        if let match = lower.firstMatch(of: lead), let count = parseNumber(String(match.output.1)) {
            var word = match.output.2.map(String.init)
            if let first = word, adjectives.contains(first) { word = match.output.3.map(String.init) }
            if let word, !measureWords.contains(word) {
                result.count = count
                result.noun = singularize(word)
            }
        }
        return result
    }

    /// "1 1/2" → 1.5, "1/6" → 0.1667, "2.5" → 2.5
    static func parseNumber(_ text: String) -> Double? {
        let parts = text.split(separator: " ")
        if parts.count == 2, let whole = Double(parts[0]), let fraction = parseNumber(String(parts[1])) { return whole + fraction }
        let fraction = text.split(separator: "/")
        if fraction.count == 2, let top = Double(fraction[0]), let bottom = Double(fraction[1]), bottom > 0 { return top / bottom }
        return Double(text)
    }

    private static let ieWords: Set<String> = ["cookie", "brownie", "pie", "smoothie", "veggie", "rotisserie", "calorie", "hoagie", "lassie"]

    public static func singularize(_ word: String) -> String {
        let w = word.lowercased()
        if w.hasSuffix("ies"), w.count > 4 {
            let stem = String(w.dropLast(3))
            return ieWords.contains(stem + "ie") ? stem + "ie" : stem + "y"
        }
        for suffix in ["ches", "shes", "xes", "sses", "oes"] where w.hasSuffix(suffix) { return String(w.dropLast(2)) }
        if w.hasSuffix("s"), !w.hasSuffix("ss"), w.count > 3 { return String(w.dropLast()) }
        return w
    }

    public static func pluralize(_ word: String) -> String {
        let w = word.lowercased()
        if w.hasSuffix("y"), let before = w.dropLast().last, !"aeiou".contains(before) { return String(w.dropLast()) + "ies" }
        if ["s", "x", "ch", "sh"].contains(where: w.hasSuffix) { return w + "es" }
        return w + "s"
    }
}
