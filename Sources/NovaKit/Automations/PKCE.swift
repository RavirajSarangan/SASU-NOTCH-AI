import CryptoKit
import Foundation

/// Proof Key for Code Exchange (RFC 7636) for the Google sign-in flow.
public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String = PKCE.randomVerifier()) {
        self.verifier = verifier
        challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public static func randomVerifier(length: Int = 64) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int(generator.next() % UInt64(alphabet.count))] })
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
