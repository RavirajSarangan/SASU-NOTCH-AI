import NovaKit

/// Google Antigravity. No official hook integration yet: any tool or script can report
/// to Nova by sending `{"agent":"antigravity",...}` events to the local socket.
@MainActor
final class AntigravityAgent: SocketAgentProvider {
    init() { super.init(kind: .antigravity) }
}
