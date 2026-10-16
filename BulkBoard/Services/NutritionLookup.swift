import AppKit
import BulkCore
import Foundation
import Observation
import Vision

/// Looks up exact label nutrition online in Open Food Facts (free, open data, no account or key).
/// Only the product and brand you type, or a barcode, are sent. Can be turned off in Settings.
@Observable
final class NutritionLookup {
    static let shared = NutritionLookup()

    var isEnabled: Bool {
        get { access(keyPath: \.isEnabled); return UserDefaults.standard.object(forKey: "onlineFoodLookup") as? Bool ?? true }
        set { withMutation(keyPath: \.isEnabled) { UserDefaults.standard.set(newValue, forKey: "onlineFoodLookup") } }
    }

    static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "BulkBoard/\(version) (https://github.com/\(Updater.repository))"
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": NutritionLookup.userAgent, "Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    /// Best matches for a product (and brand), or the exact product for a barcode.
    func search(product: String, brand: String?) async throws -> [OpenFoodFacts.Product] {
        guard isEnabled else { throw LookupError.disabled }
        if OpenFoodFacts.isBarcode(product) {
            return try await self.product(code: product).map { [$0] } ?? []
        }
        let urls = OpenFoodFacts.searchURLs(product: product, brand: brand)
        var hits: [OpenFoodFacts.Product] = []
        var lastError: Error?
        await withTaskGroup(of: Result<[OpenFoodFacts.Product], Error>.self) { group in
            for url in urls {
                group.addTask { [session] in
                    do {
                        let data = try await Self.fetch(url, session: session)
                        return .success(try JSONDecoder().decode(OpenFoodFacts.SearchResponse.self, from: data).hits)
                    } catch { return .failure(error) }
                }
            }
            for await result in group {
                switch result {
                case let .success(products): hits += products
                case let .failure(error): lastError = error
                }
            }
        }
        if hits.isEmpty, let lastError { throw lastError }
        let country = OpenFoodFacts.countryTag(region: Locale.current.region?.identifier)
        return Array(OpenFoodFacts.rank(hits, product: product, brand: brand, countryTag: country).prefix(8))
    }

    /// Full product details: search results don't include serving size or package weight.
    func product(code: String) async throws -> OpenFoodFacts.Product? {
        guard isEnabled else { throw LookupError.disabled }
        guard let url = OpenFoodFacts.productURL(code: code) else { return nil }
        let data = try await Self.fetch(url, session: session)
        let response = try JSONDecoder().decode(OpenFoodFacts.ProductResponse.self, from: data)
        guard response.status != 0, let product = response.product, !product.code.isEmpty || !product.name.isEmpty else { return nil }
        return product
    }

    private nonisolated static func fetch(_ url: URL, session: URLSession) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw LookupError.server(http.statusCode)
            }
            return data
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .timedOut].contains(error.code) {
            throw LookupError.offline
        }
    }

    /// Opens a web search for the label in the default browser.
    static func searchWeb(product: String, brand: String) {
        let query = [brand, product, "nutrition facts"].filter { !$0.isEmpty }.joined(separator: " ")
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
}

enum LookupError: LocalizedError {
    case disabled, offline, server(Int)

    var errorDescription: String? {
        switch self {
        case .disabled: "Online lookup is off (Settings → Online)."
        case .offline: "Couldn't reach Open Food Facts. Check your connection, or enter the numbers yourself."
        case let .server(code): "Open Food Facts didn't answer (\(code)). Try again in a moment."
        }
    }
}

/// Finds barcodes in a photo on this Mac with the Vision framework.
enum BarcodeReader {
    static func codes(in imageData: Data) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.ean13, .ean8, .upce, .itf14, .code128]
            let handler = VNImageRequestHandler(data: imageData)
            guard (try? handler.perform([request])) != nil else { return [] }
            var seen = Set<String>()
            return (request.results ?? []).compactMap(\.payloadStringValue)
                .map { $0.filter(\.isNumber) }
                .filter { OpenFoodFacts.isBarcode($0) && seen.insert($0).inserted }
        }.value
    }
}
