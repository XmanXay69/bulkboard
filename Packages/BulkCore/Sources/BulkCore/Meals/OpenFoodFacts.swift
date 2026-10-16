import Foundation

/// Open Food Facts: a free, open product database (openfoodfacts.org). No account or key.
/// This file builds requests and reads responses; the app does the networking.
public enum OpenFoodFacts {
    public static let searchEndpoint = URL(string: "https://search.openfoodfacts.org/search")!
    public static let productEndpoint = URL(string: "https://world.openfoodfacts.org/api/v2/product")!

    static let fields = "code,product_name,product_name_en,brands,quantity,serving_size,serving_quantity,product_quantity,nutriments,countries_tags"

    /// Full-text search URLs: one filtered to the brand (precise when the brand is right) and one plain (forgiving).
    public static func searchURLs(product: String, brand: String?, pageSize: Int = 12) -> [URL] {
        let product = product.trimmingCharacters(in: .whitespaces)
        let brand = brand?.trimmingCharacters(in: .whitespaces) ?? ""
        var queries: [String] = []
        if !brand.isEmpty {
            queries.append("brands:\"\(brand.replacingOccurrences(of: "\"", with: ""))\" \(product)")
        }
        queries.append([brand, product].filter { !$0.isEmpty }.joined(separator: " "))
        return queries.compactMap { query in
            var components = URLComponents(url: searchEndpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "page_size", value: String(pageSize)),
                URLQueryItem(name: "fields", value: fields),
            ]
            return components.url
        }
    }

    /// Product details by barcode, including serving size and package weight.
    public static func productURL(code: String) -> URL? {
        let digits = code.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        var components = URLComponents(url: productEndpoint.appendingPathComponent(digits), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields", value: fields)]
        return components.url
    }

    /// True for something that looks like a barcode (EAN-8, UPC-A, EAN-13, GTIN-14).
    public static func isBarcode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return (8...14).contains(trimmed.count) && trimmed.allSatisfy(\.isNumber)
    }

    // MARK: Responses

    public struct SearchResponse: Decodable, Sendable {
        public var hits: [Product]

        enum CodingKeys: CodingKey { case hits }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hits = (try? container.decode([Lossy<Product>].self, forKey: .hits))?.compactMap(\.value) ?? []
        }
    }

    public struct ProductResponse: Decodable, Sendable {
        public var status: Int?
        public var product: Product?
    }

    public struct Product: Decodable, Hashable, Sendable, Identifiable {
        public var code: String
        public var name: String
        public var brands: [String]
        public var quantity: String?
        public var servingSize: String?
        public var servingQuantity: Double?
        public var productQuantity: Double?
        public var nutriments: [String: Double]
        public var countries: [String]

        public var id: String { code }

        enum CodingKeys: String, CodingKey {
            case code, quantity, brands, nutriments
            case productName = "product_name", productNameEN = "product_name_en"
            case servingSize = "serving_size", servingQuantity = "serving_quantity"
            case productQuantity = "product_quantity", countries = "countries_tags"
        }

        public init(code: String, name: String, brands: [String] = [], quantity: String? = nil, servingSize: String? = nil,
                    servingQuantity: Double? = nil, productQuantity: Double? = nil, nutriments: [String: Double] = [:],
                    countries: [String] = []) {
            self.code = code
            self.name = name
            self.brands = brands
            self.quantity = quantity
            self.servingSize = servingSize
            self.servingQuantity = servingQuantity
            self.productQuantity = productQuantity
            self.nutriments = nutriments
            self.countries = countries
        }

        // The database is crowd-sourced: numbers arrive as strings, brands as a string or a list, fields go missing.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(Flexible.self, forKey: .code).text ?? ""
            let english = (try? c.decodeIfPresent(String.self, forKey: .productNameEN)) ?? nil
            let local = (try? c.decodeIfPresent(String.self, forKey: .productName)) ?? nil
            name = [english, local].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
            if let list = try? c.decodeIfPresent([String].self, forKey: .brands) {
                brands = list
            } else if let text = try? c.decodeIfPresent(String.self, forKey: .brands) {
                brands = text.split(separator: ",").map(String.init)
            } else {
                brands = []
            }
            brands = brands.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            quantity = (try? c.decodeIfPresent(Flexible.self, forKey: .quantity))??.text
            servingSize = (try? c.decodeIfPresent(Flexible.self, forKey: .servingSize))??.text
            servingQuantity = (try? c.decodeIfPresent(Flexible.self, forKey: .servingQuantity))??.number
            productQuantity = (try? c.decodeIfPresent(Flexible.self, forKey: .productQuantity))??.number
            let raw = (try? c.decodeIfPresent([String: Flexible].self, forKey: .nutriments)) ?? nil
            nutriments = (raw ?? [:]).compactMapValues(\.number)
            countries = ((try? c.decodeIfPresent([String].self, forKey: .countries)) ?? nil) ?? []
        }

        public var brand: String? { brands.first }

        /// "DiGiorno · 27.5 oz"
        public var subtitle: String {
            [brands.first, quantity].compactMap { $0 }.joined(separator: " · ")
        }
    }

    // MARK: Mapping

    /// Nutrition facts from a product, or nil when it has no usable calories.
    public static func facts(for product: Product) -> NutritionFacts? {
        let n = product.nutriments
        func kcal(_ basis: String) -> Double? {
            if let value = n["energy-kcal_\(basis)"] { return value }
            if let kj = n["energy-kj_\(basis)"] ?? n["energy_\(basis)"] { return kj / 4.184 }
            return nil
        }
        func macros(_ basis: String) -> Macros? {
            guard let energy = kcal(basis) else { return nil }
            let protein = n["proteins_\(basis)"] ?? 0
            let carbs = n["carbohydrates_\(basis)"] ?? 0
            let fat = n["fat_\(basis)"] ?? 0
            guard energy > 0 || protein + carbs + fat > 0 else { return nil }
            return Macros(kcal: energy, protein: protein, carbs: carbs, fat: fat)
        }
        let per100 = macros("100g")
        let perServing = macros("serving")
        guard per100 != nil || perServing != nil else { return nil }
        let servingText = product.servingSize.map(ServingText.parse)
        let quantityText = product.quantity.map(ServingText.parse)
        let isLiquid = (servingText?.isLiquid ?? false) || (quantityText?.isLiquid ?? false) || soundsLikeDrink(product.name)
        var servingGrams = product.servingQuantity ?? servingText?.grams
        if servingGrams == nil, let perServing, let per100, per100.kcal > 0 {
            servingGrams = perServing.kcal / per100.kcal * 100
        }
        return NutritionFacts(per100: per100, perServing: perServing, servingGrams: servingGrams,
                              servingText: product.servingSize, packageGrams: product.productQuantity ?? quantityText?.grams,
                              isLiquid: isLiquid)
    }

    /// Calories per 100 g that are physically possible and roughly agree with the macros.
    /// Also catches a common data-entry slip: a whole bottle's numbers typed in as "per 100 ml".
    public static func isPlausible(_ facts: NutritionFacts) -> Bool {
        guard let m = facts.per100 ?? facts.perServing else { return false }
        if let per100 = facts.per100, per100.kcal > 920 || per100.protein + per100.carbs + per100.fat > 101 { return false }
        if facts.isLiquid, let per100 = facts.per100, per100.fat < 20, per100.protein > 14 || per100.kcal > 160 { return false }
        let implied = m.kcalFromMacros
        guard m.kcal > 0 else { return implied == 0 } // water, diet soda
        guard implied > 0 else { return m.kcal < 20 }
        return abs(m.kcal - implied) / max(m.kcal, implied) < 0.35
    }

    /// Best matches first: the right brand, the most name words in common, plausible numbers, then the user's country.
    public static func rank(_ products: [Product], product query: String, brand: String?, countryTag: String? = nil) -> [Product] {
        let queryWords = words(query)
        let brandWords = words(brand ?? "")
        var seen = Set<String>()
        let unique = products.filter { !$0.code.isEmpty && !$0.name.isEmpty && seen.insert($0.code).inserted }
        let scored: [(Product, Double)] = unique.compactMap { product in
            guard let facts = facts(for: product) else { return nil }
            let nameWords = words(product.name + " " + product.brands.joined(separator: " "))
            var score = 0.0
            if !queryWords.isEmpty {
                score += 3 * Double(queryWords.intersection(nameWords).count) / Double(queryWords.count)
            }
            if !brandWords.isEmpty {
                let productBrand = words(product.brands.joined(separator: " "))
                if !brandWords.isDisjoint(with: productBrand) || productBrand.contains(brandWords.sorted().joined()) { score += 3 }
            }
            if isPlausible(facts) { score += 1.5 } else { score -= 2 }
            if facts.servingMacros != nil { score += 0.25 }
            if let countryTag, product.countries.contains(countryTag) { score += 0.75 }
            return (product, score)
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Names that mean a ready-to-drink product (not a powder or mix).
    static func soundsLikeDrink(_ name: String) -> Bool {
        let w = words(name)
        let drinks: Set<String> = ["shake", "milk", "drink", "juice", "soda", "smoothie", "latte", "coffee", "tea", "water",
                                   "kefir", "lemonade", "beverage", "cola", "gatorade", "powerade"]
        let solids: Set<String> = ["powder", "mix", "bar", "bars", "chocolate-chip", "cookie", "cookies", "cereal", "chips"]
        return !w.isDisjoint(with: drinks) && w.isDisjoint(with: solids)
    }

    /// The Open Food Facts country tag for a region code ("US" → "en:united-states").
    public static func countryTag(region: String?) -> String? {
        switch region?.uppercased() {
        case "US": "en:united-states"
        case "CA": "en:canada"
        case "GB": "en:united-kingdom"
        case "AU": "en:australia"
        case "IE": "en:ireland"
        case "NZ": "en:new-zealand"
        case "FR": "en:france"
        case "DE": "en:germany"
        case "ES": "en:spain"
        case "IT": "en:italy"
        case "MX": "en:mexico"
        default: nil
        }
    }

    static func words(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        return Set(folded.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 1 })
    }
}

/// A JSON value that may be a number or a numeric string.
struct Flexible: Decodable, Hashable, Sendable {
    var number: Double?
    var text: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(Double.self) {
            number = value
            text = value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
        } else if let string = try? c.decode(String.self) {
            text = string
            number = Double(string.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        }
    }
}

/// Decodes what it can and skips the rest, so one malformed product doesn't sink a search.
struct Lossy<T: Decodable>: Decodable {
    var value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
