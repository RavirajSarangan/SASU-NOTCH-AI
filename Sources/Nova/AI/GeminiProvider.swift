import Foundation

/// Google Gemini via the Generative Language API with SSE streaming.
struct GeminiProvider: AIProvider {
    let kind = AIProviderKind.gemini
    let apiKey: String

    private static let base = "https://generativelanguage.googleapis.com/v1beta/"

    private func request(_ path: String, body: [String: Any]? = nil) throws -> URLRequest {
        guard let url = URL(string: Self.base + path) else { throw AIError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    func streamMessage(_ input: AIRequest) -> AsyncThrowingStream<String, Error> {
        var body: [String: Any] = [
            "contents": input.messages.map { ["role": $0.role == .user ? "user" : "model", "parts": [["text": $0.text]]] },
            "generationConfig": ["maxOutputTokens": input.maxTokens],
        ]
        if let system = input.system { body["systemInstruction"] = ["parts": [["text": system]]] }
        let model = input.model.hasPrefix("models/") ? String(input.model.dropFirst(7)) : input.model

        let urlRequest: URLRequest
        do { urlRequest = try request("models/\(model):streamGenerateContent?alt=sse", body: body) } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await (_, data) in AIHTTP.events(urlRequest) {
                        guard let object = AIHTTP.parse(data),
                              let candidate = (object["candidates"] as? [[String: Any]])?.first else { continue }
                        let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
                        for part in parts { if let text = part["text"] as? String { continuation.yield(text) } }
                        if candidate["finishReason"] as? String == "SAFETY" { throw AIError.refused("safety") }
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
        let object = try await AIHTTP.json(try request("models?pageSize=200"))
        let models = object["models"] as? [[String: Any]] ?? []
        return models.compactMap { model -> String? in
            let methods = model["supportedGenerationMethods"] as? [String] ?? []
            guard methods.contains("generateContent"), let name = model["name"] as? String else { return nil }
            return name.replacingOccurrences(of: "models/", with: "")
        }
    }
}
