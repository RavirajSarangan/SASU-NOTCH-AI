import NovaKit
import Foundation

enum AIProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case anthropic, openAI, gemini
    /// Free tiers behind OpenAI-compatible APIs.
    case groq, openRouter
    /// Models running on this Mac (OpenAI-compatible local servers).
    case ollama, lmStudio

    var id: String { rawValue }

    var isLocal: Bool { self == .ollama || self == .lmStudio }

    /// Usable without paying (free tier or on this Mac).
    var isFree: Bool { self == .groq || self == .openRouter || self == .gemini || isLocal }

    /// Uses the OpenAI Chat Completions format.
    var isOpenAICompatible: Bool { self == .openAI || self == .groq || self == .openRouter || isLocal }

    /// Hosted OpenAI-compatible endpoint (nil for OpenAI itself and native APIs).
    var hostedBaseURL: URL? {
        switch self {
        case .groq: URL(string: "https://api.groq.com/openai/v1/")
        case .openRouter: URL(string: "https://openrouter.ai/api/v1/")
        default: nil
        }
    }

    /// Where to create a (free) key.
    var keyPageURL: URL? {
        switch self {
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .groq: URL(string: "https://console.groq.com/keys")
        case .openRouter: URL(string: "https://openrouter.ai/settings/keys")
        case .ollama: URL(string: "https://ollama.com/download")
        case .lmStudio: URL(string: "https://lmstudio.ai")
        }
    }

    /// One line about the free tier, shown in Settings.
    var freeNote: String? {
        switch self {
        case .groq: "Free: about 1,000 requests a day, very fast. No card needed."
        case .openRouter: "Free models: 50 requests a day (1,000 after a one-time $10 top-up)."
        case .gemini: "Free tier: Flash-Lite allows about 1,000 requests a day."
        case .ollama, .lmStudio: "Free and private: runs on this Mac, works offline."
        default: nil
        }
    }

    /// OpenAI-compatible endpoint of a local server.
    var localBaseURL: URL? {
        switch self {
        case .ollama: URL(string: "http://127.0.0.1:11434/v1/")
        case .lmStudio: URL(string: "http://127.0.0.1:1234/v1/")
        default: nil
        }
    }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .gemini: "Google Gemini"
        case .groq: "Groq"
        case .openRouter: "OpenRouter"
        case .ollama: "Ollama (on this Mac)"
        case .lmStudio: "LM Studio (on this Mac)"
        }
    }

    var secretKey: SecretKey {
        switch self {
        case .anthropic: .anthropicKey
        case .openAI: .openAIKey
        case .gemini: .geminiKey
        case .groq: .groqKey
        case .openRouter: .openRouterKey
        case .ollama, .lmStudio: .openAIKey   // never used: local servers need no key
        }
    }

    var brand: BrandMark {
        switch self {
        case .anthropic: .claude
        case .openAI: .openAI
        case .gemini: .gemini
        case .groq: .groq
        case .openRouter: .openRouter
        case .ollama: .ollama
        case .lmStudio: .lmStudio
        }
    }

    /// Used until the user picks a model from the provider's live list.
    var defaultModel: String {
        switch self {
        case .anthropic: "claude-opus-5-5"
        case .openAI: "gpt-4.1"
        case .gemini: "gemini-3.8-flash"
        case .groq: "openai/gpt-oss-120b"
        case .openRouter: "openrouter/free"
        case .ollama: "llama3.2"
        case .lmStudio: "local-model"
        }
    }
}

struct AIMessage: Codable, Equatable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }

    var id = UUID()
    var role: Role
    var text: String
}

struct AIRequest: Sendable {
    var model: String
    var system: String?
    var messages: [AIMessage]
    var maxTokens: Int = 16_000
    /// Effort hint for providers that support it ("low", "medium", "high").
    var effort: String? = nil
}

enum AIError: LocalizedError, Equatable {
    case missingAPIKey(AIProviderKind)
    case http(Int, String)
    case refused(String?)
    case invalidResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let kind): "Add your \(kind.displayName) API key in Settings."
        case .http(let code, let message): "\(code): \(message)"
        case .refused(let detail): "The model declined this request\(detail.map { " (\($0))" } ?? "")."
        case .invalidResponse: "Unexpected response from the provider."
        case .network(let message): message
        }
    }
}

/// A chat model provider. Implementations call the REST API directly with
/// URLSession and stream server-sent events.
protocol AIProvider: Sendable {
    var kind: AIProviderKind { get }
    func sendMessage(_ request: AIRequest) async throws -> String
    func streamMessage(_ request: AIRequest) -> AsyncThrowingStream<String, Error>
    func validateAPIKey() async throws -> Bool
    func listModels() async throws -> [String]
}

extension AIProvider {
    /// Default: collect the stream.
    func sendMessage(_ request: AIRequest) async throws -> String {
        var text = ""
        for try await chunk in streamMessage(request) { text += chunk }
        return text
    }

    func validateAPIKey() async throws -> Bool {
        do {
            return try await !listModels().isEmpty
        } catch AIError.http(let code, _) where code == 401 || code == 403 {
            return false
        }
    }
}

/// Shared HTTP + SSE plumbing.
enum AIHTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    static func json(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await perform(request)
        try check(response, data: data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.invalidResponse }
        return object
    }

    /// Streams `data:` payloads of a server-sent-events response.
    static func events(_ request: URLRequest) -> AsyncThrowingStream<(event: String?, data: String), Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        try check(response, data: body)
                    }
                    var event: String?
                    for try await line in bytes.lines {
                        if line.hasPrefix("event:") {
                            event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            continuation.yield((event, line.dropFirst(5).trimmingCharacters(in: .whitespaces)))
                            event = nil
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw AIError.network(error.localizedDescription)
        }
    }

    static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let error = object?["error"] as? [String: Any]
            let message = (error?["message"] as? String) ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw AIError.http(http.statusCode, message)
        }
    }

    static func parse(_ data: String) -> [String: Any]? {
        guard let raw = data.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
    }
}
