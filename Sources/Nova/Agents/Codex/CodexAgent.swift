import NovaKit

/// Codex CLI. No official hook integration yet: any tool or script can report
/// to Nova by sending `{"agent":"codex",...}` events to the local socket.
@MainActor
final class CodexAgent: SocketAgentProvider {
    init() { super.init(kind: .codex) }
}
