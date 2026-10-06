import NovaKit

/// Cursor. No official hook integration yet: any tool or script can report
/// to Nova by sending `{"agent":"cursor",...}` events to the local socket.
@MainActor
final class CursorAgent: SocketAgentProvider {
    init() { super.init(kind: .cursor) }
}
