import Foundation

/// Pure session bookkeeping: applies agent events to session records.
/// `AgentSessionManager` wraps this for the UI.
public struct AgentSessionState: Sendable {
    public static let maxActions = 20
    public static let expiry: TimeInterval = 10 * 60

    public private(set) var sessions: [String: AgentSession] = [:]

    public init() {}

    /// Most recently active first.
    public var ordered: [AgentSession] {
        sessions.values.sorted { $0.lastEventAt > $1.lastEventAt }
    }

    public func latest(for agent: AgentKind) -> AgentSession? {
        sessions.values.filter { $0.agent == agent }.max { $0.lastEventAt < $1.lastEventAt }
    }

    /// Every session of one agent, most recently active first.
    public func sessions(for agent: AgentKind) -> [AgentSession] {
        sessions.values.filter { $0.agent == agent }.sorted { $0.lastEventAt > $1.lastEventAt }
    }

    /// How urgently a session needs the user (higher first).
    public static func priority(_ status: AgentStatus) -> Int {
        switch status {
        case .needsApproval: 6
        case .error: 5
        case .working: 4
        case .thinking: 3
        case .waiting: 2
        case .completed: 1
        case .idle: 0
        }
    }

    /// The session Nova should reflect: most urgent, then most recent.
    public var mostUrgent: AgentSession? {
        sessions.values.max {
            let a = Self.priority($0.status), b = Self.priority($1.status)
            return a != b ? a < b : $0.lastEventAt < $1.lastEventAt
        }
    }

    @discardableResult
    public mutating func apply(_ e: AgentEvent, now: Date = Date()) -> AgentSession {
        var s = sessions[e.sessionId] ?? AgentSession(id: e.sessionId, agent: e.agent, cwd: e.workingDirectory,
                                                       status: .idle, startedAt: now)
        s.lastEventAt = now
        if let cwd = e.workingDirectory { s.cwd = cwd }
        if let host = e.host { s.host = host }
        if let path = e.filePath { s.filePath = path }
        if let app = e.terminalApp { s.terminalApp = app }
        if let pid = e.terminalPid { s.terminalPid = pid }

        switch e.event {
        case .sessionStart:
            s.status = .waiting
            s.endedAt = nil
        case .prompt:
            s.status = .thinking
            s.endedAt = nil
            if let text = e.description ?? e.message { s.currentTask = String(text.prefix(140)) }
        case .toolStart:
            s.status = .working
            s.currentTool = e.tool
            if e.tool == "Task" || e.tool == "Agent" { s.subagents += 1 }
            s.actions.append(AgentAction(tool: e.tool ?? "Tool", detail: e.description ?? e.command ?? e.filePath ?? "",
                                         state: .running, startedAt: now, edit: e.edit))
        case .toolEnd, .toolFailed:
            let state: AgentAction.State = e.event == .toolFailed ? .failed : .done
            if let i = s.actions.lastIndex(where: { $0.state == .running && (e.tool == nil || $0.tool == e.tool) }) {
                s.actions[i].state = state
            }
            s.currentTool = nil
            s.status = .thinking
        case .permissionRequest:
            s.status = .needsApproval
        case .notification:
            if s.status != .needsApproval { s.status = .waiting }
        case .stop, .sessionEnd:
            s.status = .completed
            s.endedAt = now
            s.currentTool = nil
            for i in s.actions.indices where s.actions[i].state == .running { s.actions[i].state = .done }
        case .error:
            s.status = .error
            s.currentTool = nil
        case .unknown:
            break
        }

        if s.actions.count > Self.maxActions {
            s.actions.removeFirst(s.actions.count - Self.maxActions)
        }
        sessions[e.sessionId] = s
        return s
    }

    /// Clears a pending-approval status once the request is answered.
    public mutating func resolveApproval(sessionId: String, now: Date = Date()) {
        guard var s = sessions[sessionId], s.status == .needsApproval else { return }
        s.status = .working
        s.lastEventAt = now
        sessions[sessionId] = s
    }

    public mutating func markStopped(sessionId: String, now: Date = Date()) {
        guard var s = sessions[sessionId] else { return }
        s.status = .completed
        s.endedAt = now
        sessions[sessionId] = s
    }

    /// Drops sessions with no events for `expiry` seconds.
    @discardableResult
    public mutating func expire(now: Date = Date(), after expiry: TimeInterval = AgentSessionState.expiry) -> [String] {
        let stale = sessions.values.filter { now.timeIntervalSince($0.lastEventAt) > expiry }.map(\.id)
        stale.forEach { sessions[$0] = nil }
        return stale
    }
}

/// Finds the app an agent runs in from a process path.
public enum HostApp {
    /// "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/…"
    /// → "/Applications/Visual Studio Code.app" (the outermost bundle).
    public static func outermostBundle(path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }
}
