import Foundation
import Security

/// Every secret Nova stores. Values live only in the macOS Keychain, never in
/// UserDefaults, plists, JSON or .env files.
public enum SecretKey: String, CaseIterable, Sendable {
    case openAIKey = "openai-api-key"
    case anthropicKey = "anthropic-api-key"
    case geminiKey = "gemini-api-key"
    case groqKey = "groq-api-key"
    case openRouterKey = "openrouter-api-key"
    case githubToken = "github-token"
    case vercelToken = "vercel-token"
    case stripeKey = "stripe-key"
    case n8nKey = "n8n-api-key"
    case supabaseKey = "supabase-key"
    case googleClientID = "google-oauth-client-id"
    case googleClientSecret = "google-oauth-client-secret"
    case googleRefreshToken = "google-refresh-token"

    public var label: String {
        switch self {
        case .openAIKey: "OpenAI API Key"
        case .anthropicKey: "Anthropic API Key"
        case .geminiKey: "Gemini API Key"
        case .groqKey: "Groq API Key"
        case .openRouterKey: "OpenRouter API Key"
        case .githubToken: "GitHub Token"
        case .vercelToken: "Vercel Token"
        case .stripeKey: "Stripe Key"
        case .n8nKey: "n8n API Key"
        case .supabaseKey: "Supabase Key"
        case .googleClientID: "Google OAuth Client ID"
        case .googleClientSecret: "Google OAuth Client Secret"
        case .googleRefreshToken: "Google Refresh Token"
        }
    }
}

public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidData
}

/// In-memory copy of secrets already read, so the Keychain dialog appears
/// at most once per secret per launch. `.some(nil)` means "known to be absent".
final class SecretCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String?] = [:]

    func get(_ service: String, _ account: String) -> String?? {
        lock.lock(); defer { lock.unlock() }
        return values[service + "/" + account]
    }

    func set(_ service: String, _ account: String, _ value: String?) {
        lock.lock(); values[service + "/" + account] = .some(value); lock.unlock()
    }

    func clear() { lock.lock(); values.removeAll(); lock.unlock() }
}

/// Thin wrapper over generic-password Keychain items.
public struct KeychainManager: Sendable {
    public static let shared = KeychainManager()

    public let service: String

    public init(service: String = "app.nova.companion") {
        self.service = service
    }

    public func saveSecret(_ value: String, for key: SecretKey) throws {
        try save(value, account: key.rawValue)
        Self.cache.set(service, key.rawValue, value)
    }

    /// Reads a secret. Blocks while macOS shows its "allow access" dialog, so
    /// call it only off the main thread; UI code should use `secret(_:)`.
    public func readSecret(_ key: SecretKey) -> String? {
        if let hit = Self.cache.get(service, key.rawValue) { return hit }
        guard let value = try? read(account: key.rawValue) else { return nil }
        Self.cache.set(service, key.rawValue, value)
        return value
    }

    /// Reads a secret on Nova's own Keychain queue, one dialog at a time,
    /// never on the main thread or Swift's shared threads. Cached after the
    /// first read, so macOS asks at most once per secret per launch.
    public func secret(_ key: SecretKey) async -> String? {
        if let hit = Self.cache.get(service, key.rawValue) { return hit }
        return await withCheckedContinuation { continuation in
            Self.queue.async { continuation.resume(returning: readSecret(key)) }
        }
    }

    public func deleteSecret(_ key: SecretKey) throws {
        try delete(account: key.rawValue)
        Self.cache.set(service, key.rawValue, nil)
    }

    private static let queue = DispatchQueue(label: "nova.keychain", qos: .userInitiated)
    private static let cache = SecretCache()

    public func secretExists(_ key: SecretKey) -> Bool {
        var query = baseQuery(account: key.rawValue)
        query[kSecReturnData as String] = false
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Account-level primitives (also used by tests)

    public func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unexpectedStatus(status) }
    }

    /// Removes every item for this service. The file-based keychain deletes
    /// one match per call, so repeat until nothing is left.
    public func deleteAll() {
        Self.cache.clear()
        let query = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary
        for _ in 0..<(SecretKey.allCases.count * 4) where SecItemDelete(query) == errSecSuccess {}
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
