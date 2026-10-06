import Foundation
import NovaKit

/// One coding agent Nova can monitor. Providers normalise incoming events
/// and route approvals; they hold no UI logic.
@MainActor
protocol AgentProvider: AnyObject {
    var kind: AgentKind { get }
    var isMonitoring: Bool { get }

    func startMonitoring()
    func stopMonitoring()
    /// Normalises an event for this agent; return nil to ignore it.
    func handleEvent(_ event: AgentEvent) -> AgentEvent?
    /// Asks the user (via PermissionManager) to approve a request.
    func requestApproval(_ request: AgentPermissionRequest)
    /// Sends the user's answer back to the waiting agent.
    func sendApprovalResponse(_ request: AgentPermissionRequest, _ reply: PermissionReply)
    func getStatus() -> AgentStatus
}

/// Shared behaviour: socket-fed providers differ only in how they describe
/// events, so concrete agents subclass this.
@MainActor
class SocketAgentProvider: AgentProvider {
    let kind: AgentKind
    private(set) var isMonitoring = false
    private(set) var lastStatus: AgentStatus = .idle

    /// Set by AgentSessionManager.
    var approvalHandler: ((AgentPermissionRequest) -> Void)?
    var responder: ((String, PermissionReply) -> Void)?

    init(kind: AgentKind) {
        self.kind = kind
    }

    func startMonitoring() { isMonitoring = true }
    func stopMonitoring() { isMonitoring = false }

    func handleEvent(_ event: AgentEvent) -> AgentEvent? {
        guard isMonitoring, event.agent == kind else { return nil }
        return normalize(event)
    }

    /// Override to enrich events (e.g. fill a description).
    func normalize(_ event: AgentEvent) -> AgentEvent { event }

    func requestApproval(_ request: AgentPermissionRequest) {
        approvalHandler?(request)
    }

    func sendApprovalResponse(_ request: AgentPermissionRequest, _ reply: PermissionReply) {
        responder?(request.id, reply)
    }

    func getStatus() -> AgentStatus { lastStatus }

    func record(_ status: AgentStatus) { lastStatus = status }
}
