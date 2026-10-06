import Foundation
import Observation

/// Chat state: streaming, stop, regenerate, and local history (no secrets).
@Observable
@MainActor
final class ChatViewModel {
    var messages: [AIMessage] = []
    var input = ""
    private(set) var isStreaming = false
    private(set) var error: String?
    /// Set when another provider answered because the chosen one was busy.
    private(set) var answeredBy: AIProviderKind?
    var providerKind: AIProviderKind

    @ObservationIgnored private let ai: AIService
    @ObservationIgnored private var streamTask: Task<Void, Never>?

    static let system = """
    You are Nova, a friendly AI companion living in the user's MacBook notch. \
    Be concise and practical. Use Markdown, and fenced code blocks for code.
    """

    private static var historyURL: URL {
        NovaPathsApp.support.appendingPathComponent("chat-history.json")
    }

    init(ai: AIService) {
        self.ai = ai
        providerKind = ai.defaultProvider
        loadHistory()
    }

    var model: String { ai.model(for: providerKind) }
    var canSend: Bool { !isStreaming && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        input = ""
        messages.append(AIMessage(role: .user, text: text))
        stream()
    }

    func regenerate() {
        guard !isStreaming else { return }
        if messages.last?.role == .assistant { messages.removeLast() }
        guard messages.last?.role == .user else { return }
        stream()
    }

    func stop() {
        streamTask?.cancel()
    }

    func clear() {
        stop()
        messages.removeAll()
        error = nil
        saveHistory()
    }

    private func stream() {
        error = nil
        let kind = providerKind
        let request = AIRequest(model: model, system: Self.system, messages: messages, maxTokens: 16_000, effort: "medium")
        messages.append(AIMessage(role: .assistant, text: ""))
        let index = messages.count - 1
        isStreaming = true

        answeredBy = nil
        streamTask = Task { [weak self] in
            guard let ai = self?.ai else { return }
            do {
                // If the chosen provider is busy before the first word arrives,
                // the next one answers instead; once text is streaming, no switching.
                // Reading a key may wait for the Keychain dialog, off the main thread.
                let (_, used) = try await ai.withFallback(preferring: kind) { provider, model in
                    var request = request
                    request.model = model
                    var started = false
                    do {
                        for try await chunk in provider.streamMessage(request) {
                            guard let self, !Task.isCancelled else { break }
                            started = true
                            self.messages[index].text += chunk
                        }
                    } catch where started {
                        throw AIStreamBroke(underlying: error)
                    }
                }
                if used != kind { self?.answeredBy = used }
            } catch let broke as AIStreamBroke {
                self?.error = broke.underlying.localizedDescription
            } catch is CancellationError {
            } catch {
                self?.error = error.localizedDescription
                Log.ai.error("Chat stream failed: \(error.localizedDescription, privacy: .public)")
            }
            guard let self else { return }
            if self.messages.indices.contains(index), self.messages[index].text.isEmpty {
                self.messages.remove(at: index)
            }
            self.isStreaming = false
            self.saveHistory()
        }
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: Self.historyURL),
              let saved = try? JSONDecoder().decode([AIMessage].self, from: data) else { return }
        messages = saved
    }

    private func saveHistory() {
        try? FileManager.default.createDirectory(at: NovaPathsApp.support, withIntermediateDirectories: true)
        let recent = Array(messages.suffix(100))
        try? JSONEncoder().encode(recent).write(to: Self.historyURL, options: .atomic)
    }
}

/// App-side storage locations (Application Support/Nova).
enum NovaPathsApp {
    static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Nova", isDirectory: true)
    }
}
