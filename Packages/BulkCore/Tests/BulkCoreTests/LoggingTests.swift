import Foundation
import Testing
@testable import BulkCore

@Suite("Serving text")
struct ServingTextTests {
    @Test func countNounAndGrams() {
        let parsed = ServingText.parse("2 slices (56 g)")
        #expect(parsed.count == 2)
        #expect(parsed.noun == "slice")
        #expect(parsed.grams == 56)
        #expect(!parsed.isLiquid)
    }

    @Test func plainWeightHasNoPiece() {
        let parsed = ServingText.parse("130 g")
        #expect(parsed.noun == nil)
        #expect(parsed.grams == 130)
    }

    @Test func fractionsAndAdjectives() {
        #expect(abs((ServingText.parse("1/6 pizza (130g)").count ?? 0) - 1.0 / 6) < 1e-9)
        #expect(ServingText.parse("1 1/2 cups (360 ml)").count == 1.5)
        #expect(ServingText.parse("1 1/2 cups (360 ml)").isLiquid)
        #expect(ServingText.parse("2 large eggs").noun == "egg")
        #expect(ServingText.parse("3 cookies (34 g)").noun == "cookie")
        #expect(ServingText.parse("1 portion (28.3 g)").noun == nil, "Generic words aren't pieces")
        #expect(ServingText.parse("1 portion (28.3 g)").grams == 28.3)
    }

    @Test func imperialMeasures() {
        #expect(abs((ServingText.parse("11.5 fl oz").grams ?? 0) - 340.1) < 0.1)
        #expect(ServingText.parse("11.5 fl oz").isLiquid)
        #expect(abs((ServingText.parse("27.5 oz").grams ?? 0) - 779.6) < 0.1)
    }

    @Test func singularAndPlural() {
        #expect(ServingText.singularize("patties") == "patty")
        #expect(ServingText.singularize("brownies") == "brownie")
        #expect(ServingText.singularize("sandwiches") == "sandwich")
        #expect(ServingText.singularize("glass") == "glass")
        #expect(ServingText.pluralize("patty") == "patties")
        #expect(ServingText.pluralize("slice") == "slices")
        #expect(ServingText.pluralize("sandwich") == "sandwiches")
    }
}

@Suite("Portion math")
struct PortionMathTests {
    /// A frozen pizza label: 1/6 pizza (130 g) = 300 kcal; the box is 780 g.
    let pizza = NutritionFacts(per100: Macros(kcal: 230.8, protein: 11.5, carbs: 28.5, fat: 8.5),
                               perServing: Macros(kcal: 300, protein: 15, carbs: 37, fat: 11),
                               servingGrams: 130, servingText: "1/6 pizza (130 g)", packageGrams: 780)

    /// Bread: 2 slices (56 g) = 140 kcal.
    let bread = NutritionFacts(perServing: Macros(kcal: 140, protein: 6, carbs: 26, fat: 2),
                               servingGrams: 56, servingText: "2 slices (56 g)")

    @Test func servingsUseTheLabel() {
        #expect(PortionMath.macros(2, .serving, facts: pizza) == Macros(kcal: 600, protein: 30, carbs: 74, fat: 22))
    }

    @Test func piecesSplitTheServing() throws {
        let one = try #require(PortionMath.macros(1, .piece("slice"), facts: bread))
        #expect(one.kcal == 70)
        #expect(PortionMath.grams(3, .piece("slice"), facts: bread) == 84)
        let wholePizza = try #require(PortionMath.macros(1, .piece("pizza"), facts: pizza))
        #expect(abs(wholePizza.kcal - 1800) < 1e-6, "1/6 pizza per serving means one pizza is six servings")
    }

    @Test func weightsUsePer100() throws {
        let box = try #require(PortionMath.macros(1, .package, facts: pizza))
        #expect(abs(box.kcal - 1800.2) < 0.1)
        let grams = try #require(PortionMath.macros(200, .grams, facts: pizza))
        #expect(abs(grams.kcal - 461.6) < 0.1)
        let ounces = try #require(PortionMath.macros(4, .ounces, facts: pizza))
        #expect(abs(ounces.kcal - 261.7) < 0.1)
    }

    @Test func weightsFallBackToServingGrams() throws {
        let macros = try #require(PortionMath.macros(112, .grams, facts: bread))
        #expect(macros.kcal == 280)
    }

    @Test func optionsMatchWhatTheLabelSupports() {
        let units = PortionMath.options(for: bread).map(\.unit)
        #expect(units == [.serving, .piece("slice"), .grams, .ounces], "No package without a package weight")
        #expect(PortionMath.options(for: pizza).map(\.unit).contains(.package))
        let servingOnly = NutritionFacts(perServing: Macros(kcal: 200, protein: 20, carbs: 10, fat: 8), servingText: "1 bar")
        #expect(PortionMath.options(for: servingOnly).map(\.unit) == [.serving, .piece("bar")], "Can't weigh without grams")
        #expect(PortionMath.macros(100, .grams, facts: servingOnly) == nil)
    }

    @Test func resolvesUnitsThatDontApply() {
        let servingOnly = NutritionFacts(perServing: Macros(kcal: 200, protein: 20, carbs: 10, fat: 8))
        #expect(PortionMath.resolve(.piece("slice"), for: servingOnly) == .serving)
        #expect(PortionMath.resolve(.piece("slices"), for: bread) == .piece("slice"))
        #expect(PortionMath.resolve(.grams, for: bread) == .grams)
    }

    @Test func describesAmounts() {
        #expect(PortionMath.describe(2, .serving, facts: pizza) == "2 servings (260 g)")
        #expect(PortionMath.describe(1, .piece("slice"), facts: bread) == "1 slice (28 g)")
        #expect(PortionMath.describe(150, .grams, facts: bread) == "150 g")
        #expect(PortionUnit.parse("Slices") == .piece("slice"))
        #expect(PortionUnit.parse("bag") == .package)
        #expect(PortionUnit.parse("grams") == .grams)
    }

    @Test func loggedItemSnapshotsMacros() {
        let item = LoggedFoodItem(name: "Rising Crust Pepperoni Pizza", brand: "DiGiorno", quantity: 2, unit: .serving,
                                  facts: pizza, source: .openFoodFacts(code: "0071921962395"))
        #expect(item.macros.kcal == 600)
        #expect(item.displayName == "DiGiorno Rising Crust Pepperoni Pizza")
        #expect(item.servingsEquivalent == 2)
        let data = try! JSONEncoder().encode(item)
        #expect(try! JSONDecoder().decode(LoggedFoodItem.self, from: data) == item)
    }

    @Test func libraryFoodsBecomeFacts() {
        let eggs = FoodItem(name: "Eggs", servingLabel: "2 large eggs", servingAmount: 2, servingUnit: .piece,
                            macros: Macros(kcal: 143, protein: 12.6, carbs: 0.7, fat: 9.5), section: .dairyEggs)
        let facts = eggs.nutritionFacts
        #expect(PortionMath.options(for: facts).map(\.unit) == [.serving, .piece("egg")])
        #expect(PortionMath.macros(3, .piece("egg"), facts: facts)?.kcal == 214.5)
        let rice = FoodItem(name: "Rice", servingLabel: "1 cup cooked", servingAmount: 50, servingUnit: .g,
                            macros: Macros(kcal: 180, protein: 4, carbs: 40, fat: 0.5), section: .grainsPasta)
        #expect(PortionMath.macros(100, .grams, facts: rice.nutritionFacts)?.kcal == 360)
    }

    @Test func factsBecomeAFoodListEntry() {
        let food = pizza.foodItem(name: "Pepperoni Pizza", brand: "DiGiorno")
        #expect(food.servingLabel == "1/6 pizza (130 g)")
        #expect(food.servingAmount == 130 && food.servingUnit == .g)
        #expect(food.macros.kcal == 300)
        let per100Only = NutritionFacts(per100: Macros(kcal: 120, protein: 23, carbs: 0, fat: 2.6))
        #expect(per100Only.foodItem(name: "Chicken", brand: nil).servingLabel == "100 g")
    }
}

@Suite("Open Food Facts")
struct OpenFoodFactsTests {
    static let productJSON = """
    {"status": 1, "product": {"code": "0071921962395", "product_name": "Rising crust pepperoni frozen pizza",
      "brands": "DiGiorno", "quantity": "27.5 oz", "serving_size": "130 g", "serving_quantity": 130,
      "product_quantity": "779.6", "nutriments": {"energy-kcal_100g": 230.77, "energy-kcal_serving": 300,
      "proteins_100g": 11.54, "proteins_serving": 15, "carbohydrates_100g": 28.46, "carbohydrates_serving": "37",
      "fat_100g": 8.46, "fat_serving": 11, "energy-kj_modifier": "~"}}}
    """

    @Test func decodesMessyProducts() throws {
        let response = try JSONDecoder().decode(OpenFoodFacts.ProductResponse.self, from: Data(Self.productJSON.utf8))
        let product = try #require(response.product)
        #expect(product.brands == ["DiGiorno"])
        #expect(product.productQuantity == 779.6, "Numbers can arrive as strings")
        #expect(product.nutriments["carbohydrates_serving"] == 37)
        let facts = try #require(OpenFoodFacts.facts(for: product))
        #expect(facts.perServing?.kcal == 300)
        #expect(facts.servingGrams == 130)
        #expect(facts.packageGrams == 779.6)
        #expect(OpenFoodFacts.isPlausible(facts))
    }

    @Test func searchSkipsBrokenHitsAndUsesKilojoules() throws {
        let json = """
        {"hits": [
          {"code": "1", "product_name": "Good", "brands": ["Lay's"], "nutriments": {"energy-kj_100g": 2389, "fat_100g": 34, "carbohydrates_100g": 53, "proteins_100g": 7}},
          {"code": 22, "product_name": "Numeric code", "nutriments": {}},
          {"product_name": 7}
        ]}
        """
        let response = try JSONDecoder().decode(OpenFoodFacts.SearchResponse.self, from: Data(json.utf8))
        #expect(response.hits.count == 2)
        #expect(response.hits[1].code == "22")
        let facts = try #require(OpenFoodFacts.facts(for: response.hits[0]))
        #expect(abs((facts.per100?.kcal ?? 0) - 571) < 1)
        #expect(OpenFoodFacts.facts(for: response.hits[1]) == nil, "No calories, no facts")
    }

    @Test func ranksBrandAndNameMatchesFirst() {
        let n = ["energy-kcal_100g": 230.0, "proteins_100g": 11, "carbohydrates_100g": 28, "fat_100g": 8.5]
        let products = [
            OpenFoodFacts.Product(code: "a", name: "Pepperoni Pizza", brands: ["Dr. Oetker"], nutriments: n),
            OpenFoodFacts.Product(code: "b", name: "Rising Crust Pepperoni Pizza", brands: ["DiGiorno"], nutriments: n),
            OpenFoodFacts.Product(code: "c", name: "Pepperoni Pizza", brands: ["Digiorno"], nutriments: ["energy-kcal_100g": 2300]),
            OpenFoodFacts.Product(code: "b", name: "Duplicate", brands: ["DiGiorno"], nutriments: n),
        ]
        let ranked = OpenFoodFacts.rank(products, product: "pepperoni pizza", brand: "digiorno")
        #expect(ranked.map(\.code) == ["b", "a", "c"], "Brand first, implausible numbers last, duplicates dropped")
    }

    @Test func flagsBottleNumbersEnteredAsPer100() {
        // A 340 ml shake whose per-bottle label (150 kcal, 30 g protein) was typed into the per-100 fields.
        let wrong = OpenFoodFacts.Product(code: "1", name: "Chocolate Protein Shake", brands: ["Fairlife"], quantity: "11.5 fl oz",
                                          servingSize: "340g", nutriments: ["energy-kcal_100g": 150, "proteins_100g": 30,
                                                                            "carbohydrates_100g": 4, "fat_100g": 2.5])
        let right = OpenFoodFacts.Product(code: "2", name: "Chocolate Protein Shake", brands: ["Fairlife"], quantity: "11.5 fl oz",
                                          nutriments: ["energy-kcal_100g": 44, "proteins_100g": 8.8, "carbohydrates_100g": 1.2, "fat_100g": 0.7])
        #expect(OpenFoodFacts.facts(for: wrong)?.isLiquid == true, "A fluid-ounce package marks it as a drink")
        #expect(!OpenFoodFacts.isPlausible(OpenFoodFacts.facts(for: wrong)!))
        #expect(OpenFoodFacts.isPlausible(OpenFoodFacts.facts(for: right)!))
        let oil = NutritionFacts(per100: Macros(kcal: 884, fat: 100), servingText: "1 tbsp (15 ml)", isLiquid: true)
        #expect(OpenFoodFacts.isPlausible(oil), "Oils are dense but real")
        #expect(OpenFoodFacts.rank([wrong, right], product: "chocolate protein shake", brand: "fairlife").first?.code == "2")
        let noQuantity = OpenFoodFacts.Product(code: "3", name: "Chocolate Protein Shake", nutriments: ["energy-kcal_100g": 150, "proteins_100g": 30])
        #expect(!OpenFoodFacts.isPlausible(OpenFoodFacts.facts(for: noQuantity)!), "The name says it's a drink")
        #expect(!OpenFoodFacts.soundsLikeDrink("Whey Protein Powder Chocolate Shake Mix"))
    }

    @Test func buildsRequests() {
        let urls = OpenFoodFacts.searchURLs(product: "classic chips", brand: "Lay's")
        #expect(urls.count == 2)
        #expect(urls[0].absoluteString.contains("brands:%22Lay's%22") || urls[0].absoluteString.contains("brands:%22Lay%27s%22"))
        #expect(OpenFoodFacts.searchURLs(product: "banana", brand: nil).count == 1)
        #expect(OpenFoodFacts.productURL(code: "0028400090858")?.path == "/api/v2/product/0028400090858")
        #expect(OpenFoodFacts.isBarcode("0028400090858"))
        #expect(!OpenFoodFacts.isBarcode("lays 2"))
        #expect(OpenFoodFacts.countryTag(region: "us") == "en:united-states")
    }
}

@Suite("Versions and releases")
struct VersionTests {
    @Test func comparesNumerically() throws {
        let v = { (text: String) in SemanticVersion(text)! }
        #expect(v("v0.3.0") > v("0.2.0"))
        #expect(v("0.10.0") > v("0.9.2"))
        #expect(v("1.0") == v("1.0.0"))
        #expect(v("0.3.0-beta.1") < v("0.3.0"))
        #expect(v("0.3.0-beta.2") < v("0.3.0-beta.10"))
        #expect(SemanticVersion("dev") == nil)
        #expect(SemanticVersion("1..2") == nil)
        #expect(v("v0.3.0").description == "0.3.0")
    }

    @Test func parsesGitHubLatestRelease() throws {
        let json = """
        {"tag_name": "v0.3.0", "name": "BulkBoard v0.3.0", "body": "Notes", "draft": false, "prerelease": false,
         "html_url": "https://github.com/XmanXay69/bulkboard/releases/tag/v0.3.0", "published_at": "2026-10-16T05:00:00Z",
         "assets": [
          {"name": "BulkBoard-0.3.0.dmg", "browser_download_url": "https://example.com/a.dmg", "size": 6000000, "digest": "sha256:aa"},
          {"name": "BulkBoard-0.3.0-macOS.zip", "browser_download_url": "https://example.com/a.zip", "size": 5000000, "digest": "sha256:ABC123"}
         ]}
        """
        let release = try AppRelease.parse(githubJSON: Data(json.utf8))
        #expect(release.version == SemanticVersion("0.3.0")!)
        #expect(release.asset?.name == "BulkBoard-0.3.0-macOS.zip")
        #expect(release.asset?.sha256 == "abc123")
        #expect(release.isNewer(than: SemanticVersion("0.2.0")!))
        #expect(!release.isNewer(than: SemanticVersion("0.3.0")!))

        let prerelease = json.replacingOccurrences(of: "\"prerelease\": false", with: "\"prerelease\": true")
        #expect(throws: ReleaseError.notARelease) { try AppRelease.parse(githubJSON: Data(prerelease.utf8)) }
    }
}
