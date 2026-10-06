import Foundation

/// Claude via the Messages API (raw HTTP: there is no official Swift SDK).
/// Streams by default and opts into server-side refusal fallbacks.
struct AnthropicProvider: AIProvider {
    let kind = AIProviderKind.anthropic
    let apiKey: String

    private static let base = URL(string: "https://api.anthropic.com/v1/")!

    private func request(_ path: String, body: [String: Any]? = nil) throws -> URLRequest {
        var request = URLRequest(url: Self.base.appendingPathComponent(path))
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            // `fallbacks: "default"` re-runs a declined request on Anthropic's
            // recommended fallback model instead of returning a refusal.
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    func streamMessage(_ input: AIRequest) -> AsyncThrowingStream<String, Error> {
        var body: [String: Any] = [
            "model": input.model,
            "max_tokens": max(input.maxTokens, 1024),
            "stream": true,
            "fallbacks": "default",
            "messages": input.messages.map { ["role": $0.role.rawValue, "content": $0.text] },
        ]
        if let system = input.system { body["system"] = system }
        // Thinking stays at the model's default (adaptive); effort sets its depth.
        if let effort = input.effort { body["output_config"] = ["effort": effort] }

        let urlRequest: URLRequest
        do { urlRequest = try request("messages", body: body) } catch { return AsyncThrowingStream { $0.finish(throwing: error) } }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await (event, data) in AIHTTP.events(urlRequest) {
                        guard let object = AIHTTP.parse(data) else { continue }
                        switch event ?? (object["type"] as? String) {
                        case "content_block_delta":
                            let delta = object["delta"] as? [String: Any]
                            if delta?["type"] as? String == "text_delta", let text = delta?["text"] as? String {
                                continuation.yield(text)
                            }
                        case "message_delta":
                            let delta = object["delta"] as? [String: Any]
                            if delta?["stop_reason"] as? String == "refusal" {
                                let details = delta?["stop_details"] as? [String: Any]
                                throw AIError.refused(details?["category"] as? String)
                            }
                        case "error":
                            let error = object["error"] as? [String: Any]
                            throw AIError.http(529, error?["message"] as? String ?? "Stream error")
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func listModels() async throws -> [String] {
        let object = try await AIHTTP.json(try request("models?limit=100"))
        let data = object["data"] as? [[String: Any]] ?? []
        return data.compactMap { $0["id"] as? String }
    }
}
