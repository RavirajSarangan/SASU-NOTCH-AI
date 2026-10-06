import AppKit
import Foundation
import NovaKit
import Observation

/// Google sign-in for a "Desktop app" OAuth client: PKCE + loopback redirect.
/// The refresh token lives in the Keychain; access tokens only in memory.
@Observable
@MainActor
final class GoogleAuth {
    static let scopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/youtube.readonly",
        "https://www.googleapis.com/auth/yt-analytics.readonly",
        // Firebase status (projects, Firestore, Functions, Hosting): read-only.
        "https://www.googleapis.com/auth/firebase.readonly",
        "https://www.googleapis.com/auth/cloud-platform.read-only",
    ]

    enum AuthError: LocalizedError {
        case missingClient, notSignedIn, stateMismatch, denied(String), tokenExchange(String)

        var errorDescription: String? {
            switch self {
            case .missingClient: "Add your Google OAuth client ID and secret first."
            case .notSignedIn: "Connect Google in Settings → Automations."
            case .stateMismatch: "Sign-in response didn't match. Please try again."
            case .denied(let reason): "Google sign-in was cancelled (\(reason))."
            case .tokenExchange(let message): "Google token error: \(message)"
            }
        }
    }

    private let keychain: KeychainManager
    private var accessToken: String?
    private var accessTokenExpiry = Date.distantPast

    private(set) var isSigningIn = false
    private(set) var lastError: String?
    /// Bumped on changes so views re-read Keychain-backed properties.
    private(set) var version = 0

    init(keychain: KeychainManager = .shared) {
        self.keychain = keychain
    }

    var hasClient: Bool { _ = version; return keychain.secretExists(.googleClientID) }
    var isSignedIn: Bool {
        _ = version
        #if DEBUG
        if previewSignedIn { return true }
        #endif
        return keychain.secretExists(.googleRefreshToken)
    }

    #if DEBUG
    /// Snapshot/preview only.
    var previewSignedIn = false
    #endif

    func saveClient(id: String, secret: String) throws {
        try keychain.saveSecret(id.trimmingCharacters(in: .whitespacesAndNewlines), for: .googleClientID)
        try keychain.saveSecret(secret.trimmingCharacters(in: .whitespacesAndNewlines), for: .googleClientSecret)
        version += 1
    }

    func signIn() async {
        isSigningIn = true
        lastError = nil
        defer { isSigningIn = false; version += 1 }
        do {
            try await performSignIn()
        } catch {
            lastError = error.localizedDescription
            Log.integrations.error("Google sign-in failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func signOut() {
        let keychain = self.keychain
        Task.detached {
            guard let token = await keychain.secret(.googleRefreshToken),
                  var revoke = URLComponents(string: "https://oauth2.googleapis.com/revoke") else { return }
            revoke.queryItems = [URLQueryItem(name: "token", value: token)]
            guard let url = revoke.url else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            _ = try? await URLSession.shared.data(for: request)
        }
        try? keychain.deleteSecret(.googleRefreshToken)
        accessToken = nil
        version += 1
    }

    /// A valid access token, refreshing it when needed.
    func token() async throws -> String {
        if let accessToken, Date() < accessTokenExpiry.addingTimeInterval(-60) { return accessToken }
        guard let refresh = await keychain.secret(.googleRefreshToken) else { throw AuthError.notSignedIn }
        guard let id = await keychain.secret(.googleClientID) else { throw AuthError.missingClient }
        let clientSecret = await keychain.secret(.googleClientSecret) ?? ""
        let response = try await tokenRequest([
            "client_id": id, "client_secret": clientSecret,
            "refresh_token": refresh, "grant_type": "refresh_token",
        ])
        return try store(response)
    }

    private func performSignIn() async throws {
        guard let clientID = await keychain.secret(.googleClientID), !clientID.isEmpty else { throw AuthError.missingClient }
        let pkce = PKCE()
        let state = PKCE.randomVerifier(length: 24)
        let receiver = LoopbackReceiver()
        let port = try await receiver.start()
        defer { receiver.stop() }
        let redirect = "http://127.0.0.1:\(port)"

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        if let url = components.url { NSWorkspace.shared.open(url) }

        let params = try await receiver.waitForCallback()
        if let error = params["error"] { throw AuthError.denied(error) }
        guard params["state"] == state, let code = params["code"] else { throw AuthError.stateMismatch }

        let response = try await tokenRequest([
            "client_id": clientID, "client_secret": await keychain.secret(.googleClientSecret) ?? "",
            "code": code, "code_verifier": pkce.verifier, "grant_type": "authorization_code", "redirect_uri": redirect,
        ])
        if let refresh = response["refresh_token"] as? String {
            try keychain.saveSecret(refresh, for: .googleRefreshToken)
        }
        _ = try store(response)
        NSApp.activate()
    }

    private func tokenRequest(_ form: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let object = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            if object["error"] as? String == "invalid_grant" {
                try? keychain.deleteSecret(.googleRefreshToken)
                version += 1
            }
            throw AuthError.tokenExchange(object["error_description"] as? String ?? object["error"] as? String ?? "HTTP error")
        }
        return object
    }

    private func store(_ response: [String: Any]) throws -> String {
        guard let token = response["access_token"] as? String else { throw AuthError.tokenExchange("no access token") }
        accessToken = token
        accessTokenExpiry = Date().addingTimeInterval(response["expires_in"] as? Double ?? 3000)
        return token
    }

    /// Authorized GET returning raw data.
    func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = ((object?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            throw AIError.http((response as? HTTPURLResponse)?.statusCode ?? 0, message)
        }
        return data
    }
}
