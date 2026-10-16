import AppKit
import BulkCore
import Foundation
import Observation

/// Optional local AI via Ollama. Talks only to the loopback interface; no cloud, no keys.
/// If Ollama is installed but not running, BulkBoard starts it (and stops it again on quit), and it can
/// download the recommended model with one click, so the AI features work without a terminal.
@Observable
final class OllamaClient {
    static let shared = OllamaClient()

    /// Loopback only, on purpose.
    static let baseURL = URL(string: "http://127.0.0.1:11434")!

    /// Reads photos and handles text, small enough for a 16 GB Mac.
    static let recommendedModel = "qwen3-vl:4b-instruct"
    static let recommendedModelSize = "3.3 GB"

    private(set) var isAvailable = false
    private(set) var models: [String] = []
    private(set) var isChecking = false
    private(set) var isStarting = false
    /// Model download in progress.
    private(set) var pull: PullProgress?
    private(set) var pullError: String?
    private var capabilities: [String: Set<String>] = [:]
    private var serverProcess: Process?

    struct PullProgress: Equatable {
        var model: String
        var status: String
        var fraction: Double?
    }

    var isEnabled: Bool {
        get { access(keyPath: \.isEnabled); return UserDefaults.standard.object(forKey: "ollamaEnabled") as? Bool ?? true }
        set {
            withMutation(keyPath: \.isEnabled) { UserDefaults.standard.set(newValue, forKey: "ollamaEnabled") }
            Task { await refresh() }
        }
    }

    /// Start Ollama automatically when it's installed but not running.
    var autoStart: Bool {
        get { access(keyPath: \.autoStart); return UserDefaults.standard.object(forKey: "ollamaAutoStart") as? Bool ?? true }
        set { withMutation(keyPath: \.autoStart) { UserDefaults.standard.set(newValue, forKey: "ollamaAutoStart") } }
    }

    var model: String {
        get { access(keyPath: \.model); return UserDefaults.standard.string(forKey: "ollamaModel") ?? "" }
        set { withMutation(keyPath: \.model) { UserDefaults.standard.set(newValue, forKey: "ollamaModel") } }
    }

    /// Name fragments of models that accept images, for Ollama versions that don't report capabilities.
    static let visionHints = ["vision", "llava", "bakllava", "gemma3", "qwen2.5vl", "qwen2.5-vl", "qwen3-vl", "qwen3vl",
                              "minicpm-v", "moondream", "llama4", "mistral-small3", "granite3.2-vision"]

    var visionModels: [String] {
        models.filter { name in
            if let caps = capabilities[name], !caps.isEmpty { return caps.contains("vision") }
            return Self.visionHints.contains { name.lowercased().contains($0) }
        }
    }

    var visionModel: String {
        get {
            access(keyPath: \.visionModel)
            let saved = UserDefaults.standard.string(forKey: "ollamaVisionModel") ?? ""
            if visionModels.contains(saved) { return saved }
            return visionModels.first { $0 == Self.recommendedModel } ?? visionModels.first ?? ""
        }
        set { withMutation(keyPath: \.visionModel) { UserDefaults.standard.set(newValue, forKey: "ollamaVisionModel") } }
    }

    var canSeeImages: Bool { isAvailable && !visionModel.isEmpty }

    // MARK: Install state

    /// The Ollama command-line binary, or the app bundle, if either is installed.
    static var installedBinary: URL? {
        ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/Applications/Ollama.app/Contents/Resources/ollama"]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var appBundle: URL? {
        let url = URL(fileURLWithPath: "/Applications/Ollama.app")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var isInstalled: Bool { Self.installedBinary != nil || Self.appBundle != nil }

    private var aiDisabledByArgument: Bool { ProcessInfo.processInfo.arguments.contains("--no-ai") }

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 180
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { OllamaClient.shared.stopServerIfStarted() }
        }
    }

    // MARK: Connection

    /// Probes Ollama and lists installed models. Fails fast when it isn't running.
    func refresh() async {
        guard isEnabled, !aiDisabledByArgument else {
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
            capabilities = Dictionary(tags.models.map { ($0.name, Set($0.capabilities ?? [])) }, uniquingKeysWith: { a, _ in a })
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

    /// True when the Ollama server answers, even with no models installed yet.
    private func serverResponds() async -> Bool {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/version"))
        request.timeoutInterval = 1
        return (try? await session.data(for: request)) != nil
    }

    var isServerRunning = false

    /// Connects, starting Ollama first if it's installed and not running.
    func connect() async {
        await refresh()
        isServerRunning = isAvailable ? true : await serverResponds()
        guard !isServerRunning, isEnabled, autoStart, !aiDisabledByArgument, !Persistence.usesInMemoryStore else { return }
        await startServer()
    }

    /// Starts Ollama: opens Ollama.app if that's how it's installed, otherwise runs `ollama serve` on loopback.
    func startServer() async {
        guard !isStarting, isInstalled else { return }
        isStarting = true
        defer { isStarting = false }
        if let app = Self.appBundle {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.addsToRecentItems = false
            _ = try? await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        } else if let binary = Self.installedBinary, serverProcess == nil {
            let process = Process()
            process.executableURL = binary
            process.arguments = ["serve"]
            var environment = ProcessInfo.processInfo.environment
            environment["OLLAMA_HOST"] = "127.0.0.1:11434"
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                serverProcess = process
            } catch { return }
        }
        for _ in 0..<40 {
            if await serverResponds() { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        isServerRunning = await serverResponds()
        await refresh()
    }

    /// Stops the server only if BulkBoard started it.
    func stopServerIfStarted() {
        serverProcess?.terminate()
        serverProcess = nil
    }

    // MARK: Models

    /// Downloads a model through Ollama (Ollama does the download; BulkBoard only talks to 127.0.0.1).
    func pullModel(_ name: String = OllamaClient.recommendedModel) async {
        guard pull == nil else { return }
        pullError = nil
        if !(await serverResponds()) { await startServer() }
        guard await serverResponds() else {
            pullError = isInstalled ? "Ollama didn't start. Open it, then try again." : OllamaError.notInstalled.localizedDescription
            return
        }
        pull = PullProgress(model: name, status: "Starting download…", fraction: nil)
        defer { pull = nil }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": name, "stream": true])
        do {
            let (bytes, _) = try await session.bytes(for: request)
            for try await line in bytes.lines {
                guard let data = line.data(using: .utf8), let event = try? JSONDecoder().decode(PullEvent.self, from: data) else { continue }
                if let error = event.error { throw OllamaError.badStatus(0, error) }
                let fraction = event.total.flatMap { total in total > 0 ? Double(event.completed ?? 0) / Double(total) : nil }
                pull = PullProgress(model: name, status: Self.describe(event.status ?? ""), fraction: fraction)
                if event.status == "success" { break }
            }
            await refresh()
            if visionModels.contains(name) { visionModel = name }
            if model.isEmpty { model = name }
        } catch {
            pullError = "Download stopped: \(error.localizedDescription)"
        }
    }

    private static func describe(_ status: String) -> String {
        if status.hasPrefix("pulling") && status != "pulling manifest" { return "Downloading" }
        switch status {
        case "pulling manifest": return "Starting download…"
        case "verifying sha256 digest": return "Verifying…"
        case "writing manifest", "removing any unused layers": return "Finishing…"
        case "success": return "Done"
        default: return status.capitalized
        }
    }

    // MARK: Chat

    func chat(system: String, prompt: String, json: Bool = false, schema: JSONValue? = nil, images: [Data]? = nil,
              model chosenModel: String? = nil, temperature: Double? = nil) async throws -> String {
        let useModel = chosenModel ?? model
        guard isAvailable, !useModel.isEmpty else { throw OllamaError.unavailable }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let format: JSONValue? = schema ?? (json ? .string("json") : nil)
        let body = ChatRequest(model: useModel,
                               messages: [.init(role: "system", content: system),
                                          .init(role: "user", content: prompt, images: images?.map { $0.base64EncodedString() })],
                               stream: false, format: format, think: false,
                               options: .init(temperature: temperature ?? (format != nil ? 0.1 : 0.6)))
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw OllamaError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(ChatResponse.self, from: data).message.content
    }

    private func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let data = text.data(using: .utf8), let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw OllamaError.unreadable
        }
        return value
    }

    // MARK: Tasks

    func estimateMacros(for food: String) async throws -> MacroEstimate {
        let system = """
        You estimate nutrition facts. Reply with JSON only: \
        {"name": string, "serving": string, "kcal": number, "protein": number, "carbs": number, "fat": number}. \
        Use grams for macros. If the user gives a serving size, use it; otherwise pick a common one and name it in "serving".
        """
        return try decode(MacroEstimate.self, from: try await chat(system: system, prompt: food, schema: MacroEstimate.schema))
    }

    /// Nutrition for exactly one unit of an item ("1 slice", "100 g"), so amounts can scale it.
    func estimateItem(product: String, brand: String, unit: String) async throws -> MacroEstimate {
        let what = [brand, product].filter { !$0.isEmpty }.joined(separator: " ")
        return try await estimateMacros(for: "Nutrition for exactly \(unit) of \(what). Set \"serving\" to \"\(unit)\".")
    }

    /// What a meal photo shows, as items to confirm and look up.
    func identifyMeal(photo: Data) async throws -> [MealPhotoItem] {
        guard canSeeImages else { throw OllamaError.noVisionModel }
        let system = """
        You list the foods and drinks in a meal photo so someone can log them. For each item give a short product name, \
        the brand only if you can read it on packaging (otherwise an empty string), and your best guess of the amount as a \
        number plus a unit such as serving, slice, piece, cup, g, oz, can, bottle or package. Don't invent brands. \
        Reply with JSON only.
        """
        let text = try await chat(system: system, prompt: "What's in this meal?", schema: MealPhotoItem.schema,
                                  images: [photo], model: visionModel)
        return try decode(MealPhotoItem.Response.self, from: text).items.filter { !$0.name.isEmpty }
    }

    func mealIdeas(_ request: String, context: String) async throws -> String {
        let system = """
        You're a sports nutrition helper for someone bulking who plays basketball. Be concise: bullet points, \
        each idea with rough kcal and protein. Shakes must mix in a shaker bottle with no blender (powders and liquids only). \
        All numbers are estimates. What you know about them:
        \(context)
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

    /// Reviews a check-in with everything BulkBoard knows: measurements, history, goals, plan, intake.
    /// Uses the photo when there is one and a model that can see it. Photos go only to 127.0.0.1.
    /// The prompt is short on purpose: small local models contradict themselves when given a long list of rules.
    func reviewPhysique(photo: Data?, context: String, teen: Bool = false) async throws -> PhysiqueReview {
        let usePhoto = photo != nil && canSeeImages
        let useModel = usePhoto ? visionModel : (model.isEmpty ? visionModel : model)
        guard isAvailable, !useModel.isEmpty else { throw OllamaError.unavailable }
        let age = teen ? "Keep advice age-appropriate for a teen (food, sleep, technique; no extreme diets). " : ""
        let groups = "Use only: chest, shoulders, back, arms, forearms, legs, calves, core. "
        let rest = "observations: 2-4 short sentences. training: 2-4 specific changes. nutrition: 1-3 specific changes with numbers. " +
            "dunk: 1-2 tips if a dunk goal is mentioned."
        let system = usePhoto
            ? "You are a strength coach reviewing a physique photo for muscle balance, to decide what to train harder. " +
              "Be direct and respectful. Only comment on muscle development. \(age)" +
              "lagging: the 1-3 groups that look least developed compared with the rest. strengths: the 1-3 that look most developed. " +
              "A group can't be in both. \(groups)\(rest)"
            : "You are a strength coach reviewing someone's measurements and training to decide what to train harder. " +
              "Be direct and respectful. \(age)" +
              "lagging and strengths: only groups the tape numbers support (up to 3 each); with no tape numbers, leave both empty " +
              "and say in observations which measurements to take. \(groups)\(rest)"
        let text = try await chat(system: system, prompt: "Here's my data:\n\(context)\n\nWhere am I lacking and what should I change?",
                                  schema: PhysiqueReview.schema(requireGroups: usePhoto), images: usePhoto ? photo.map { [$0] } : nil,
                                  model: useModel, temperature: 0.2)
        var review = try decode(PhysiqueReview.self, from: text)
        review.usedPhoto = usePhoto
        return review
    }

    // MARK: Wire types

    private struct TagsResponse: Decodable {
        struct Model: Decodable {
            var name: String
            var capabilities: [String]?
        }
        var models: [Model]
    }

    private struct PullEvent: Decodable {
        var status: String?
        var total: Int64?
        var completed: Int64?
        var error: String?
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
        var format: JSONValue?
        var think: Bool
        var options: Options
    }

    private struct ChatResponse: Decodable {
        var message: ChatRequest.Message
    }
}

/// A small JSON value, for Ollama's structured-output schemas.
nonisolated indirect enum JSONValue: Encodable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    static func objectSchema(_ properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map(JSONValue.string))])
    }

    static let stringType = JSONValue.object(["type": .string("string")])
    static let numberType = JSONValue.object(["type": .string("number")])
    static let stringList = JSONValue.object(["type": .string("array"), "items": stringType])

    static func stringList(min: Int, max: Int) -> JSONValue {
        .object(["type": .string("array"), "items": stringType, "minItems": .number(Double(min)), "maxItems": .number(Double(max))])
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

    static let schema = JSONValue.objectSchema(
        ["name": .stringType, "serving": .stringType, "kcal": .numberType, "protein": .numberType, "carbs": .numberType, "fat": .numberType],
        required: ["name", "serving", "kcal", "protein", "carbs", "fat"])
}

/// One thing a vision model spotted in a meal photo. A guess to confirm, never logged as-is.
nonisolated struct MealPhotoItem: Codable, Equatable {
    var name: String
    var brand: String
    var amount: Double
    var unit: String

    struct Response: Codable { var items: [MealPhotoItem] }

    static let schema = JSONValue.objectSchema(
        ["items": .object(["type": .string("array"), "items": .objectSchema(
            ["name": .stringType, "brand": .stringType, "amount": .numberType, "unit": .stringType],
            required: ["name", "brand", "amount", "unit"])])],
        required: ["items"])
}

/// What the coach model said about a check-in. Always shown as an AI opinion, never as fact.
nonisolated struct PhysiqueReview: Codable, Equatable {
    var lagging: [String]
    var strengths: [String]
    var observations: [String]
    var training: [String]
    var nutrition: [String]
    var dunk: [String]
    var usedPhoto: Bool?
    /// When the photo used was taken (it may come from an earlier check-in).
    var photoDate: Date?

    init(lagging: [String] = [], strengths: [String] = [], observations: [String] = [], training: [String] = [],
         nutrition: [String] = [], dunk: [String] = [], usedPhoto: Bool? = nil) {
        self.lagging = lagging
        self.strengths = strengths
        self.observations = observations
        self.training = training
        self.nutrition = nutrition
        self.dunk = dunk
        self.usedPhoto = usedPhoto
    }

    enum CodingKeys: String, CodingKey { case lagging, strengths, observations, training, nutrition, dunk, usedPhoto, photoDate }

    // Models sometimes answer a list with one string; older saved reviews lack the newer fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func list(_ key: CodingKeys) -> [String] {
            if let values = try? c.decode([String].self, forKey: key) { return values.filter { !$0.isEmpty } }
            if let text = try? c.decode(String.self, forKey: key), !text.isEmpty { return [text] }
            return []
        }
        lagging = list(.lagging)
        strengths = list(.strengths)
        observations = list(.observations)
        training = list(.training)
        nutrition = list(.nutrition)
        dunk = list(.dunk)
        usedPhoto = try? c.decodeIfPresent(Bool.self, forKey: .usedPhoto)
        photoDate = try? c.decodeIfPresent(Date.self, forKey: .photoDate)
        lagging = Array(lagging.prefix(3))
        strengths = Array(strengths.prefix(3))
    }

    var laggingParts: [BodyPart] { lagging.compactMap(BodyPart.matching) }
    var mentionsCore: Bool { lagging.contains { $0.lowercased().contains("core") || $0.lowercased().contains("abs") } }

    /// With a photo there's always a weakest and strongest group to name; from numbers alone only if the tape supports it.
    static func schema(requireGroups: Bool) -> JSONValue {
        let groups = JSONValue.stringList(min: requireGroups ? 1 : 0, max: 3)
        return .objectSchema(
            ["lagging": groups, "strengths": groups, "observations": .stringList(min: 2, max: 4),
             "training": .stringList(min: 2, max: 4), "nutrition": .stringList(min: 1, max: 3), "dunk": .stringList(min: 0, max: 2)],
            required: ["lagging", "strengths", "observations", "training", "nutrition", "dunk"])
    }
}

enum OllamaError: LocalizedError {
    case unavailable
    case notInstalled
    case noVisionModel
    case badStatus(Int, String)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unavailable: "The local AI isn't ready yet."
        case .notInstalled: "Ollama isn't installed. Get it free from ollama.com, then come back."
        case .noVisionModel: "No photo model installed yet. Download one in Settings → Local AI."
        case let .badStatus(code, body): code == 0 ? body : "Ollama returned \(code). \(body.prefix(200))"
        case .unreadable: "The model's answer wasn't usable. Try again."
        }
    }
}
