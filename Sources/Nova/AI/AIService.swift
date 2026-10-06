import NovaKit
import Foundation
import Observation

/// Chooses the provider/model and builds providers from Keychain keys.
/// Only non-secret preferences (provider + model names) go to UserDefaults.
@Observable
@MainActor
final class AIService {
    private let defaults = UserDefaults.standard
    private let keychain: KeychainManager

    var defaultProvider: AIProviderKind {
        didSet { defaults.set(defaultProvider.rawValue, forKey: "ai.defaultProvider") }
    }

    private(set) var models: [AIProviderKind: [String]] = [:]
    /// Local servers (Ollama, LM Studio) found running on this Mac.
    private(set) var localAvailable: Set<AIProviderKind> = []
    /// Bumped when keys change so views re-read `hasKey`.
    private(set) var keysVersion = 0

    init(keychain: KeychainManager = .shared) {
        self.keychain = keychain
        defaultProvider = AIProviderKind(rawValue: UserDefaults.standard.string(forKey: "ai.defaultProvider") ?? "") ?? .anthropic
    }

    func model(for kind: AIProviderKind) -> String {
        defaults.string(forKey: "ai.model.\(kind.rawValue)") ?? kind.defaultModel
    }

    func setModel(_ model: String, for kind: AIProviderKind) {
        defaults.set(model, forKey: "ai.model.\(kind.rawValue)")
        keysVersion += 1
    }

    /// Usable: a saved key, or (for local models) the server is running.
    func hasKey(_ kind: AIProviderKind) -> Bool {
        _ = keysVersion
        if kind.isLocal { return localAvailable.contains(kind) }
        return keychain.secretExists(kind.secretKey)
    }

    /// Looks for local model servers (quick, localhost only).
    func probeLocalServers() async {
        var found: Set<AIProviderKind> = []
        for kind in AIProviderKind.allCases where kind.isLocal {
            guard let url = kind.localBaseURL?.appendingPathComponent("models") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 1.5
            if let (_, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 { found.insert(kind) }
        }
        localAvailable = found
    }

    var configuredProviders: [AIProviderKind] { AIProviderKind.allCases.filter(hasKey) }

    func provider(_ kind: AIProviderKind) async throws -> any AIProvider {
        if kind.isLocal, let base = kind.localBaseURL {
            guard localAvailable.contains(kind) else { throw AIError.network("\(kind.displayName) isn't running. Start it, then try again.") }
            return OpenAIProvider(kind: kind, apiKey: "", base: base)
        }
        guard let key = await keychain.secret(kind.secretKey), !key.isEmpty else { throw AIError.missingAPIKey(kind) }
        return switch kind {
        case .anthropic: AnthropicProvider(apiKey: key)
        case .openAI: OpenAIProvider(apiKey: key)
        case .gemini: GeminiProvider(apiKey: key)
        case .groq, .openRouter: OpenAIProvider(kind: kind, apiKey: key, base: kind.hostedBaseURL!)
        case .ollama, .lmStudio: throw AIError.invalidResponse   // handled above
        }
    }

    /// The default provider if it has a key, else the first configured one.
    func preferredProvider() async throws -> any AIProvider {
        if hasKey(defaultProvider) { return try await provider(defaultProvider) }
        guard let first = configuredProviders.first else { throw AIError.missingAPIKey(defaultProvider) }
        return try await provider(first)
    }

    func saveKey(_ value: String, for kind: AIProviderKind) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try keychain.deleteSecret(kind.secretKey)
        } else {
            try keychain.saveSecret(trimmed, for: kind.secretKey)
        }
        keysVersion += 1
    }

    func keysChanged() { keysVersion += 1 }

    func refreshModels(for kind: AIProviderKind) async throws -> [String] {
        let list = try await provider(kind).listModels()
        models[kind] = list
        return list
    }

    /// When the chosen provider is busy, try other providers you set up.
    var tryOtherProviders: Bool {
        get { _ = keysVersion; return defaults.object(forKey: "ai.tryOthers") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ai.tryOthers"); keysVersion += 1 }
    }

    /// What to try, in order: the chosen provider (or the default), its lighter
    /// model, then other usable providers. See `AIFallback`.
    func attempts(preferring kind: AIProviderKind? = nil) -> [AIFallback.Attempt] {
        let chosen = kind ?? defaultProvider
        let preferred = hasKey(chosen) ? AIFallback.Attempt(provider: chosen.rawValue, model: model(for: chosen)) : nil
        let available = configuredProviders.map { AIFallback.Attempt(provider: $0.rawValue, model: model(for: $0)) }
        return AIFallback.plan(preferred: preferred, available: available, tryOthers: tryOtherProviders)
    }

    /// Runs `body` against each attempt until one works. Busy providers are
    /// skipped quietly; the raw server message only goes to the log.
    func withFallback<T>(preferring kind: AIProviderKind? = nil,
                         _ body: (any AIProvider, String) async throws -> T) async throws -> (T, AIProviderKind) {
        let plan = attempts(preferring: kind)
        guard !plan.isEmpty else { throw AIUnavailable.noneConfigured }
        var sawBusy = false
        var lastProvider: String?
        for (index, attempt) in plan.enumerated() {
            guard let kind = AIProviderKind(rawValue: attempt.provider) else { continue }
            // A short pause before asking the same provider again.
            if lastProvider == attempt.provider { try await Task.sleep(for: .seconds(1)) }
            lastProvider = attempt.provider
            do {
                #if DEBUG
                if index == 0, CommandLine.arguments.contains("--ai-fail-first") {
                    throw AIError.http(503, "Simulated: this model is currently experiencing high demand.")
                }
                #endif
                let provider = try await provider(kind)
                return (try await body(provider, attempt.model), kind)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let failure = Self.classify(error)
                Log.ai.error("AI \(attempt.provider, privacy: .public)/\(attempt.model, privacy: .public) failed (\(String(describing: failure), privacy: .public)): \(error.localizedDescription, privacy: .public)")
                switch failure {
                case .fatal: throw error
                case .temporary: sawBusy = true
                case .skip: break
                }
            }
        }
        throw sawBusy ? AIUnavailable.allBusy : AIUnavailable.noneWorked
    }

    static func classify(_ error: Error) -> AIFallback.Failure {
        switch error {
        case AIError.http(let code, let message): AIFallback.classify(status: code, message: message)
        case AIError.network: .temporary
        case AIError.refused, is AIStreamBroke: .fatal
        case AIError.missingAPIKey, AIError.invalidResponse: .skip
        default: AIFallback.classify(status: nil, message: error.localizedDescription)
        }
    }

    /// One-shot completion used by automations (drafts, summaries) and voice.
    func complete(system: String, prompt: String, effort: String = "low", maxTokens: Int = 4000) async throws -> String {
        try await completeWithSource(system: system, prompt: prompt, effort: effort, maxTokens: maxTokens).text
    }

    /// Like `complete`, and also says which provider answered.
    func completeWithSource(system: String, prompt: String, effort: String = "low", maxTokens: Int = 4000) async throws -> (text: String, provider: AIProviderKind) {
        let (text, kind) = try await withFallback { provider, model in
            let request = AIRequest(model: model, system: system,
                                    messages: [AIMessage(role: .user, text: prompt)], maxTokens: maxTokens, effort: effort)
            return try await provider.sendMessage(request).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (text, kind)
    }
}

/// A stream that failed after text arrived: shown as is, never retried elsewhere.
struct AIStreamBroke: Error { let underlying: Error }

/// Plain-language reasons no answer came back.
enum AIUnavailable: LocalizedError {
    case noneConfigured, allBusy, noneWorked

    var errorDescription: String? {
        switch self {
        case .noneConfigured: "No AI is set up yet. Add a free Groq or Gemini key in Settings → AI Providers."
        case .allBusy: "The AI providers are busy right now. Try again in a minute, or add a free Groq key as a backup in Settings."
        case .noneWorked: "None of your AI providers answered. Check the keys in Settings → AI Providers."
        }
    }
}
