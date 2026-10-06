import Foundation
import NovaKit
import Observation

/// Queue of permission requests waiting for the user. Nothing is approved
/// without an explicit click, except requests matching an "always allow for
/// this session" rule the user created, and those never cover high risk.
@Observable
@MainActor
final class PermissionManager {
    private(set) var pending: [AgentPermissionRequest] = []
    @ObservationIgnored private var rules = SessionRules()
    @ObservationIgnored private var timeouts: [String: Task<Void, Never>] = [:]

    /// Delivers a reply to the waiting agent.
    @ObservationIgnored var reply: ((AgentPermissionRequest, PermissionReply) -> Void)?
    /// Nova Guard: returns a reason to deny a request without asking
    /// (deny-listed command, or high risk while you're away).
    @ObservationIgnored var guardCheck: ((AgentPermissionRequest) -> String?)?
    /// Called when Nova Guard denied a request on its own.
    @ObservationIgnored var onGuardDenied: ((AgentPermissionRequest, String) -> Void)?
    /// Called when a request is resolved (answered, cancelled or timed out).
    @ObservationIgnored var onResolved: ((AgentPermissionRequest) -> Void)?

    static let timeout: Duration = .seconds(120)
    /// Questions get longer: the user may need to think.
    static let questionTimeout: Duration = .seconds(295)

    var current: AgentPermissionRequest? { pending.first }

    /// Queues a request. Returns false if a session rule answered it already.
    @discardableResult
    func enqueue(_ request: AgentPermissionRequest) -> Bool {
        if !request.isQuestion, let reason = guardCheck?(request) {
            send(request, PermissionReply(requestId: request.id, decision: .deny, reason: "Denied by Nova Guard: \(reason)"))
            onGuardDenied?(request, reason)
            return false
        }
        if !request.isQuestion, rules.allows(request) {
            send(request, PermissionReply(requestId: request.id, decision: .allow))
            return false
        }
        pending.append(request)
        #if DEBUG
        // End-to-end test hook: deny (never allow) automatically.
        if ProcessInfo.processInfo.environment["NOVA_TEST_AUTODENY"] == "1" {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.decide(.deny, for: request.id)
            }
        }
        #endif
        timeouts[request.id] = Task { [weak self] in
            try? await Task.sleep(for: request.isQuestion ? Self.questionTimeout : Self.timeout)
            guard !Task.isCancelled else { return }
            // No answer: hand the decision back to the agent's own prompt.
            self?.resolve(request.id, with: .ask, reason: "No response in Nova")
        }
        return true
    }

    /// Answers exactly `requestId`. Unknown or already-answered ids are
    /// ignored; there is deliberately no fallback to another request.
    func decide(_ decision: PermissionDecision, for requestId: String) {
        guard let request = pending.first(where: { $0.id == requestId }) else { return }
        if decision == .allowForSession, request.risk.level == .high { return }
        // Questions are answered with answers, never "allowed"; deny hands
        // the question back to the terminal.
        if request.isQuestion {
            if decision == .deny { resolve(request.id, with: .ask, reason: "Answered in the terminal") }
            return
        }
        switch decision {
        case .deny:
            resolve(request.id, with: .deny, reason: "Denied in Nova")
        case .allowOnce:
            resolve(request.id, with: .allow)
        case .allowForSession:
            let added = rules.add(for: request)
            resolve(request.id, with: .allow)
            if !added { return }
            // Answer any queued requests the new rule now covers.
            for other in pending where rules.allows(other) {
                resolve(other.id, with: .allow)
            }
        }
    }

    /// The agent stopped waiting (hook timed out or was killed).
    func cancel(_ requestId: String) {
        guard let index = pending.firstIndex(where: { $0.id == requestId }) else { return }
        let request = pending.remove(at: index)
        timeouts.removeValue(forKey: requestId)?.cancel()
        onResolved?(request)
    }

    /// Sends the user's answers to a question request. Ignored unless every
    /// question has an answer.
    func answer(_ answers: [String: [String]], for requestId: String) {
        guard let index = pending.firstIndex(where: { $0.id == requestId }),
              let questions = pending[index].questions, AgentQuestion.isComplete(answers, for: questions) else { return }
        let request = pending.remove(at: index)
        timeouts.removeValue(forKey: requestId)?.cancel()
        send(request, PermissionReply(requestId: request.id, decision: .allow, answers: answers))
        onResolved?(request)
    }

    /// "Reply in terminal": hands the question back to the agent's own prompt.
    func replyInTerminal(_ requestId: String) {
        resolve(requestId, with: .ask, reason: "Answered in the terminal")
    }

    func clearRules(for sessionId: String) {
        rules.removeAll(for: sessionId)
    }

    func denyAll(sessionId: String) {
        for request in pending where request.sessionId == sessionId {
            resolve(request.id, with: .deny, reason: "Session stopped in Nova")
        }
    }

    private func resolve(_ requestId: String, with decision: PermissionReply.Decision, reason: String? = nil) {
        guard let index = pending.firstIndex(where: { $0.id == requestId }) else { return }
        let request = pending.remove(at: index)
        timeouts.removeValue(forKey: requestId)?.cancel()
        send(request, PermissionReply(requestId: request.id, decision: decision, reason: reason))
        onResolved?(request)
    }

    private func send(_ request: AgentPermissionRequest, _ reply: PermissionReply) {
        self.reply?(request, reply)
    }
}
