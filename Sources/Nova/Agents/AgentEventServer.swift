import Foundation
import NovaKit

/// Bridges the local socket to the session and permission managers.
/// Permission requests keep their connection open until the user answers.
@MainActor
final class AgentEventServer {
    private let sessions: AgentSessionManager
    private let permissions: PermissionManager
    private var server: LocalSocketServer?
    private var waiting: [String: SocketConnection] = [:]   // requestId → connection

    private(set) var lastError: String?

    init(sessions: AgentSessionManager, permissions: PermissionManager) {
        self.sessions = sessions
        self.permissions = permissions

        for provider in sessions.providers.values {
            provider.approvalHandler = { [weak permissions] request in permissions?.enqueue(request) }
            provider.responder = { [weak self] requestId, reply in self?.send(reply, to: requestId) }
        }
        permissions.reply = { [weak sessions] request, reply in
            sessions?.providers[request.agent]?.sendApprovalResponse(request, reply)
        }
    }

    func start() {
        let server = LocalSocketServer(
            path: NovaPaths.socketPath,
            onMessage: { [weak self] data, connection in
                // Decoding is pure; do it here on the socket queue.
                let event = try? AgentEventDecoder.decode(data)
                Task { @MainActor in self?.receive(event, on: connection) }
            },
            onClose: { [weak self] connection in
                Task { @MainActor in self?.closed(connection) }
            }
        )
        do {
            try server.start()
            self.server = server
            lastError = nil
            Log.socket.info("Listening on \(NovaPaths.socketPath, privacy: .public)")
        } catch {
            lastError = "Couldn't open \(NovaPaths.socketPath): \(error)"
            Log.socket.error("Socket failed: \(String(describing: error), privacy: .public)")
        }
    }

    func stop() {
        server?.stop()
        server = nil
    }

    private func receive(_ event: AgentEvent?, on connection: SocketConnection) {
        guard var event else {
            Log.socket.notice("Dropped an unreadable message")
            connection.close()
            return
        }
        if event.event == .permissionRequest {
            let id = event.requestId ?? UUID().uuidString
            event.requestId = id
            waiting[id] = connection
            if sessions.ingest(event) == nil {
                // Agent disabled: let it fall back to its own prompt.
                send(PermissionReply(requestId: id, decision: .ask), to: id)
            }
        } else {
            connection.close()
            sessions.ingest(event)
        }
    }

    private func send(_ reply: PermissionReply, to requestId: String) {
        guard let connection = waiting.removeValue(forKey: requestId),
              let line = try? AgentEventDecoder.encodeLine(reply) else { return }
        connection.send(line)
    }

    private func closed(_ connection: SocketConnection) {
        guard let requestId = waiting.first(where: { $0.value === connection })?.key else { return }
        waiting[requestId] = nil
        permissions.cancel(requestId)
    }
}
