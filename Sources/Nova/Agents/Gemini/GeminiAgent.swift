import NovaKit

/// Gemini CLI. No official hook integration yet: any tool or script can report
/// to Nova by sending `{"agent":"gemini",...}` events to the local socket.
@MainActor
final class GeminiAgent: SocketAgentProvider {
    init() { super.init(kind: .gemini) }
}
