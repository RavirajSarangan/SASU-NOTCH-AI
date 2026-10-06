import Foundation

/// OpenAI Chat Completions with streaming. Also used for local
/// OpenAI-compatible servers (Ollama, LM Studio), which need no key.
struct OpenAIProvider: AIProvider {
    var kind = AIProviderKind.openAI
    let apiKey: String
    var base = URL(string: "https://api.openai.com/v1/")!

    private func request(_ path: String, body: [String: Any]? = nil) throws -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path))
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    func streamMessage(_ input: AIRequest) -> AsyncThrowingStream<String, Error> {
        var messages: [[String: Any]] = []
        if let system = input.system { messages.append(["role": "system", "content": system]) }
        messages += input.messages.map { ["role": $0.role.rawValue, "content": $0.text] }
        var body: [String: Any] = ["model": input.model, "stream": true, "messages": messages]
        // OpenAI's newer name; Groq, OpenRouter and local servers use the classic one.
        body[kind == .openAI ? "max_completion_tokens" : "max_tokens"] = input.maxTokens

        let urlRequest: URLRequest
        do { urlRequest = try request("chat/completions", body: body) } catch { return AsyncThrowingStream { $0.finish(throwing: error) } }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await (_, data) in AIHTTP.events(urlRequest) {
                        if data == "[DONE]" { break }
                        guard let object = AIHTTP.parse(data),
                              let choice = (object["choices"] as? [[String: Any]])?.first,
                              let delta = choice["delta"] as? [String: Any] else { continue }
                        if let text = delta["content"] as? String { continuation.yield(text) }
                        if delta["refusal"] as? String != nil { throw AIError.refused(nil) }
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
        let object = try await AIHTTP.json(try request("models"))
        let ids = (object["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        // Local servers list only what's installed; OpenRouter: its free models;
        // OpenAI: chat-capable families.
        if kind.isLocal || kind == .groq { return ids.filter { !$0.contains("whisper") && !$0.contains("tts") && !$0.contains("guard") }.sorted() }
        if kind == .openRouter { return ids.filter { $0.hasSuffix(":free") || $0 == "openrouter/free" }.sorted() }
        return ids.filter { $0.hasPrefix("gpt") || $0.hasPrefix("o") || $0.hasPrefix("chatgpt") }.sorted()
    }
}
