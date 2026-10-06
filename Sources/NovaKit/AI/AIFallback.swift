import Foundation

/// Which models to try, in order, when a provider is busy. Providers are
/// identified by name so this stays independent of the app's provider type.
public enum AIFallback {
    public struct Attempt: Equatable, Sendable {
        public var provider: String
        public var model: String
        public init(provider: String, model: String) { self.provider = provider; self.model = model }
    }

    /// What to do after a failed attempt.
    public enum Failure: Equatable, Sendable {
        /// Busy or briefly unreachable (5xx, 429, timeout): try the next attempt.
        case temporary
        /// This provider can't serve the request (bad key, unknown model): skip it.
        case skip
        /// The request itself is the problem (refused, too long): stop.
        case fatal
    }

    /// Free and fast first, paid next, local models last (slow but always there).
    public static let order = ["groq", "gemini", "openRouter", "anthropic", "openAI", "ollama", "lmStudio"]
    public static let maxAttempts = 3

    /// A lighter model on the same provider that usually has spare capacity.
    public static func lighterModel(provider: String, current: String) -> String? {
        let lighter: String? = switch provider {
        case "gemini": "gemini-flash-lite-latest"
        case "groq": "openai/gpt-oss-20b"
        default: nil
        }
        return lighter == current ? nil : lighter
    }

    /// The chosen model first, then its lighter sibling, then other providers.
    /// - Parameters:
    ///   - preferred: the provider the user picked (if it is usable).
    ///   - available: every usable provider with the model set for it.
    public static func plan(preferred: Attempt?, available: [Attempt], tryOthers: Bool = true) -> [Attempt] {
        var attempts: [Attempt] = []
        if let preferred {
            attempts.append(preferred)
            if let lighter = lighterModel(provider: preferred.provider, current: preferred.model) {
                attempts.append(Attempt(provider: preferred.provider, model: lighter))
            }
        }
        if tryOthers || preferred == nil {
            let others = available
                .filter { $0.provider != preferred?.provider }
                .sorted { (order.firstIndex(of: $0.provider) ?? order.count) < (order.firstIndex(of: $1.provider) ?? order.count) }
            attempts += others
        }
        return Array(attempts.prefix(maxAttempts))
    }

    /// Sorts an error into retry / skip / stop. `status` is the HTTP status, if any.
    public static func classify(status: Int?, message: String) -> Failure {
        let text = message.lowercased()
        if let status {
            switch status {
            case 408, 409, 425, 429, 500...599: return .temporary
            case 401, 402, 403, 404: return .skip
            case 400 where text.contains("model"): return .skip
            case 400, 413, 422: return .fatal
            default: break
            }
        }
        let busy = ["overloaded", "high demand", "unavailable", "rate limit", "timed out", "timeout", "try again",
                    "network", "offline", "connection"]
        if busy.contains(where: text.contains) { return .temporary }
        return .skip
    }
}
