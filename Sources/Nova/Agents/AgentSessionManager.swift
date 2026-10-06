import Foundation
import NovaKit
import Observation

/// Owns the agent providers and live session state.
@Observable
@MainActor
final class AgentSessionManager {
    private(set) var state = AgentSessionState()

    @ObservationIgnored let providers: [AgentKind: SocketAgentProvider]
    /// Called after each accepted event, with the updated session.
    @ObservationIgnored var onEvent: ((AgentEvent, AgentSession) -> Void)?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    init() {
        let all: [SocketAgentProvider] = [ClaudeCodeAgent(), CodexAgent(), CursorAgent(), GeminiAgent(), AntigravityAgent(), VSCodeAgent()]
        providers = Dictionary(uniqueKeysWithValues: all.map { ($0.kind, $0) })
    }

    func start() {
        providers.values.forEach { $0.startMonitoring() }
        expiryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.state.expire()
            }
        }
    }

    /// Turns monitoring of one agent on or off (Settings → Agents).
    func setEnabled(_ kind: AgentKind, _ enabled: Bool) {
        guard let provider = providers[kind] else { return }
        enabled ? provider.startMonitoring() : provider.stopMonitoring()
    }

    func stop() {
        providers.values.forEach { $0.stopMonitoring() }
        expiryTask?.cancel()
    }

    /// Applies an event; returns the updated session, or nil if ignored.
    @discardableResult
    func ingest(_ raw: AgentEvent, now: Date = Date()) -> AgentSession? {
        guard let provider = providers[raw.agent], let event = provider.handleEvent(raw) else { return nil }
        let session = state.apply(event, now: now)
        provider.record(session.status)
        if event.event == .permissionRequest, let request = AgentPermissionRequest(event: event, now: now) {
            provider.requestApproval(request)
        }
        onEvent?(event, session)
        return session
    }

    func approvalResolved(_ request: AgentPermissionRequest) {
        state.resolveApproval(sessionId: request.sessionId)
    }

    func markStopped(_ sessionId: String) {
        state.markStopped(sessionId: sessionId)
    }

    func session(id: String?) -> AgentSession? {
        id.flatMap { state.sessions[$0] }
    }

    /// Max sessions shown per agent (the rest stay tracked, newest first).
    static let maxSessionsPerAgent = 4

    /// Every live session as its own summary (two Claude Code windows show
    /// as two), plus a "not connected" entry for agents with none.
    func summaries(now: Date = Date()) -> [AgentSummary] {
        AgentKind.allCases.flatMap { kind -> [AgentSummary] in
            let live = state.sessions(for: kind).prefix(Self.maxSessionsPerAgent)
            guard !live.isEmpty else { return [AgentSummary.live(kind, session: nil, now: now)] }
            return live.map { AgentSummary.live(kind, session: $0, siblings: live.count, now: now) }
        }
    }
}
