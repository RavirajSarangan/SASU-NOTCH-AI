import Foundation
import NovaKit

/// Non-secret per-service settings (secrets live in the Keychain).
struct IntegrationConfig: Codable, Equatable {
    var n8nBaseURL: String?
    var vercelTeamID: String?
    var supabaseProjectRef: String?
    var firebaseProjectID: String?
    var firebaseEnabled = false
}

enum IntegrationError: LocalizedError {
    case notConnected(IntegrationKind)
    case missingConfig(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConnected(let kind): "\(kind.displayName) isn't connected."
        case .missingConfig(let what): "Missing \(what)."
        case .http(401, _), .http(403, _): "The token was rejected (check its permissions)."
        case .http(let code, let message): "\(code): \(message)"
        }
    }
}

/// A developer service Nova can summarise (spec §14).
@MainActor
protocol IntegrationProvider: AnyObject {
    var kind: IntegrationKind { get }
    var isConnected: Bool { get }
    /// Stores credentials; the manager then calls `refresh()` to verify them.
    func connect(token: String) throws
    func disconnect()
    func refresh() async throws -> ServiceSnapshot
    func fetchSummary() -> ServiceSnapshot?
}

enum ServiceHTTP {
    static func get(_ url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (object?["message"] as? String)
                ?? ((object?["error"] as? [String: Any])?["message"] as? String)
                ?? (object?["error"] as? String) ?? "HTTP \(code)"
            throw IntegrationError.http(code, message)
        }
        return data
    }

    static func url(_ base: String, _ path: String, _ query: [(String, String)] = []) -> URL? {
        var components = URLComponents(string: base + path)
        if !query.isEmpty { components?.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        return components?.url
    }
}

/// Shared token-in-Keychain behaviour.
@MainActor
class TokenIntegration {
    let kind: IntegrationKind
    let secret: SecretKey
    let keychain: KeychainManager
    var last: ServiceSnapshot?

    init(kind: IntegrationKind, secret: SecretKey, keychain: KeychainManager = .shared) {
        self.kind = kind
        self.secret = secret
        self.keychain = keychain
    }

    var isConnected: Bool { keychain.secretExists(secret) }

    func connect(token: String) throws {
        try keychain.saveSecret(token.trimmingCharacters(in: .whitespacesAndNewlines), for: secret)
    }

    func disconnect() {
        try? keychain.deleteSecret(secret)
        last = nil
    }

    func fetchSummary() -> ServiceSnapshot? { last }

    func token() async throws -> String {
        guard let token = await keychain.secret(secret), !token.isEmpty else { throw IntegrationError.notConnected(kind) }
        return token
    }
}
