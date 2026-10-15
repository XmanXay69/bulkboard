import BulkCore
import Foundation
import Observation

/// Optional local AI via Ollama. Talks only to the loopback interface; no cloud, no keys.
/// The app works fully without it; UI checks `isAvailable` and hides or disables AI features.
@Observable
final class OllamaClient {
    static let shared = OllamaClient()

    /// Loopback only, on purpose.
    static let baseURL = URL(string: "http://127.0.0.1:11434")!

    private(set) var isAvailable = false
    private(set) var models: [String] = []
    private(set) var isChecking = false

    var isEnabled: Bool {
        get { access(keyPath: \.isEnabled); return UserDefaults.standard.object(forKey: "ollamaEnabled") as? Bool ?? true }
        set {
            withMutation(keyPath: \.isEnabled) { UserDefaults.standard.set(newValue, forKey: "ollamaEnabled") }
            Task { await refresh() }
        }
    }

    var model: String {
        get { access(keyPath: \.model); return UserDefaults.standard.string(forKey: "ollamaModel") ?? "" }
        set { withMutation(keyPath: \.model) { UserDefaults.standard.set(newValue, forKey: "ollamaModel") } }
    }

    /// Name fragments of Ollama models that accept images.
    static let visionHints = ["vision", "llava", "bakllava", "gemma3", "qwen2.5vl", "qwen2.5-vl", "qwen3-vl", "qwen3vl",
                              "minicpm-v", "moondream", "llama4", "mistral-small3", "granite3.2-vision"]

    var visionModels: [String] {
        models.filter { name in Self.visionHints.contains { name.lowercased().contains($0) } }
    }

    var visionModel: String {
        get {
            access(keyPath: \.visionModel)
            let saved = UserDefaults.standard.string(forKey: "ollamaVisionModel") ?? ""
            return visionModels.contains(saved) ? saved : visionModels.first ?? ""
        }
        set { withMutation(keyPath: \.visionModel) { UserDefaults.standard.set(newValue, forKey: "ollamaVisionModel") } }
    }

    var canSeeImages: Bool { isAvailable && !visionModel.isEmpty }

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Probes Ollama and lists installed models. Fails fast when it isn't running.
    func refresh() async {
        guard isEnabled, !ProcessInfo.processInfo.arguments.contains("--no-ai") else {
            isAvailable = false
            return
        }
        isChecking = true
        defer { isChecking = false }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 1.5
        do {
            let (data, _) = try await session.data(for: request)
            let tags = try JSONDecoder().decode(TagsResponse.self, from: data)
            models = tags.models.map(\.name).sorted()
            if model.isEmpty || !models.contains(model) {
                model = models.first { $0.contains("llama") || $0.contains("qwen") || $0.contains("mistral") || $0.contains("gemma") }
                    ?? models.first ?? ""
            }
            isAvailable = !models.isEmpty
        } catch {
            models = []
            isAvailable = false
        }
    }

    func chat(system: String, prompt: String, json: Bool = false, images: [Data]? = nil, model chosenModel: String? = nil) async throws -> String {
        let useModel = chosenModel ?? model
        guard isAvailable, !useModel.isEmpty else { throw OllamaError.unavailable }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ChatRequest(model: useModel,
                               messages: [.init(role: "system", content: system),
                                          .init(role: "user", content: prompt, images: images?.map { $0.base64EncodedString() })],
                               stream: false, format: json ? "json" : nil, options: .init(temperature: json ? 0.1 : 0.6))
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw OllamaError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(ChatResponse.self, from: data).message.content
    }

    // MARK: Tasks

    func estimateMacros(for food: String) async throws -> MacroEstimate {
        let system = """
        You estimate nutrition facts. Reply with JSON only: \
        {"name": string, "serving": string, "kcal": number, "protein": number, "carbs": number, "fat": number}. \
        Use grams for macros. If the user gives a serving size, use it; otherwise pick a common one and name it in "serving".
        """
        let text = try await chat(system: system, prompt: food, json: true)
        guard let data = text.data(using: .utf8) else { throw OllamaError.unreadable }
        do {
            return try JSONDecoder().decode(MacroEstimate.self, from: data)
        } catch {
            throw OllamaError.unreadable
        }
    }

    func mealIdeas(_ request: String, targets: Macros, dislikes: [String]) async throws -> String {
        let system = """
        You're a sports nutrition helper for someone bulking who plays basketball. Be concise: bullet points, \
        each idea with rough kcal and protein. Shakes must mix in a shaker bottle with no blender (powders and liquids only). \
        Avoid: \(dislikes.isEmpty ? "nothing in particular" : dislikes.joined(separator: ", ")). \
        Daily targets: \(Fmt.int(targets.kcal)) kcal, \(Fmt.int(targets.protein)) g protein, \(Fmt.int(targets.carbs)) g carbs, \(Fmt.int(targets.fat)) g fat. \
        All numbers are estimates.
        """
        return try await chat(system: system, prompt: request)
    }

    func higherProteinSwap(_ meal: String) async throws -> String {
        let system = """
        Rewrite the meal to be higher in protein while keeping calories similar or higher (the user is bulking). \
        List the swaps, then the new ingredient list with rough macros. Keep it short. Numbers are estimates.
        """
        return try await chat(system: system, prompt: meal)
    }

    /// Reviews a physique photo with a local vision model. The photo goes only to 127.0.0.1.
    func reviewPhysique(photo: Data, context: String) async throws -> PhysiqueReview {
        guard canSeeImages else { throw OllamaError.noVisionModel }
        let system = """
        You are a strength coach reviewing a physique photo for muscle balance, to decide what to train harder. \
        Be direct and respectful. Don't comment on attractiveness, skin, face or anything other than muscle development. \
        If the photo doesn't clearly show a person's physique, say so in observations and leave the lists empty. \
        Reply with JSON only: {"lagging": [up to 3 of: chest, shoulders, back, arms, forearms, legs, calves, core], \
        "strengths": [same names], "observations": [2-4 short sentences]}.
        """
        let text = try await chat(system: system, prompt: "Measurements and analysis so far:\n\(context)\nWhat looks underdeveloped relative to the rest?",
                                  json: true, images: [photo], model: visionModel)
        guard let data = text.data(using: .utf8), let review = try? JSONDecoder().decode(PhysiqueReview.self, from: data) else {
            throw OllamaError.unreadable
        }
        return review
    }

    // MARK: Wire types

    private struct TagsResponse: Decodable {
        struct Model: Decodable { var name: String }
        var models: [Model]
    }

    private struct ChatRequest: Encodable {
        struct Message: Codable {
            var role: String
            var content: String
            var images: [String]?
        }
        struct Options: Encodable { var temperature: Double }
        var model: String
        var messages: [Message]
        var stream: Bool
        var format: String?
        var options: Options
    }

    private struct ChatResponse: Decodable {
        var message: ChatRequest.Message
    }
}

nonisolated struct MacroEstimate: Codable, Equatable {
    var name: String
    var serving: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
}

/// What a vision model said about a photo. Always shown as an AI opinion, never as fact.
nonisolated struct PhysiqueReview: Codable, Equatable {
    var lagging: [String]
    var strengths: [String]
    var observations: [String]

    var laggingParts: [BodyPart] { lagging.compactMap(BodyPart.matching) }
    var mentionsCore: Bool { lagging.contains { $0.lowercased().contains("core") || $0.lowercased().contains("abs") } }
}

enum OllamaError: LocalizedError {
    case unavailable
    case noVisionModel
    case badStatus(Int, String)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unavailable: "Ollama isn't running. Start it (ollama serve) and pull a model, e.g. ollama pull llama3.2."
        case .noVisionModel: "No vision model installed. Run: ollama pull llama3.2-vision (or gemma3)."
        case let .badStatus(code, body): "Ollama returned \(code). \(body.prefix(200))"
        case .unreadable: "The model's answer wasn't usable. Try again or rephrase."
        }
    }
}
