import Foundation

/// Coding agents Nova knows how to display.
public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claude, codex, cursor, gemini, antigravity, vscode

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .gemini: "Gemini CLI"
        case .antigravity: "Antigravity"
        case .vscode: "VS Code"
        }
    }
}

public enum AgentStatus: String, Codable, CaseIterable, Sendable {
    case idle, working, thinking, waiting, completed, error, needsApproval
}

/// One step in a session's recent activity.
public struct AgentAction: Identifiable, Sendable, Equatable {
    public enum State: Sendable, Equatable { case running, done, failed }

    public let id: UUID
    public var tool: String
    public var detail: String
    public var state: State
    public var startedAt: Date
    /// Lines added/removed by an edit ("+N −M"), with the diff to show on tap.
    public var edit: EditPreview?

    public init(id: UUID = UUID(), tool: String, detail: String, state: State, startedAt: Date, edit: EditPreview? = nil) {
        self.edit = edit
        self.id = id
        self.tool = tool
        self.detail = detail
        self.state = state
        self.startedAt = startedAt
    }
}

public struct AgentSession: Identifiable, Sendable, Equatable {
    public let id: String
    public var agent: AgentKind
    public var cwd: String?
    /// Where the agent runs: "vscode", "cursor", "terminal", "iterm"…
    public var host: String?
    public var status: AgentStatus
    public var startedAt: Date
    public var lastEventAt: Date
    public var endedAt: Date?
    public var currentTool: String?
    public var currentTask: String?
    public var filePath: String?
    public var actions: [AgentAction] = []
    public var terminalApp: String?
    public var terminalPid: Int32?
    /// Subagents (Task tool) started in this session.
    public var subagents = 0

    public init(id: String, agent: AgentKind, cwd: String?, status: AgentStatus, startedAt: Date) {
        self.id = id
        self.agent = agent
        self.cwd = cwd
        self.status = status
        self.startedAt = startedAt
        self.lastEventAt = startedAt
    }

    public var projectName: String? {
        cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    public var isActive: Bool { endedAt == nil && status != .completed }

    /// A stable color slot (0..<6) so each session keeps its color.
    public var tag: Int { Self.tag(for: id) }

    public static func tag(for id: String) -> Int {
        var hash: UInt32 = 2_166_136_261   // FNV-1a: stable across launches
        for byte in id.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return Int(hash % 6)
    }

    public func elapsed(now: Date) -> TimeInterval {
        (endedAt ?? now).timeIntervalSince(startedAt)
    }
}

public enum PermissionRiskLevel: Int, Codable, Comparable, Sendable {
    case low, medium, high
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct PermissionRisk: Sendable, Equatable {
    public var level: PermissionRiskLevel
    public var reason: String

    public init(_ level: PermissionRiskLevel, _ reason: String) {
        self.level = level
        self.reason = reason
    }
}

public struct AgentPermissionRequest: Identifiable, Sendable, Equatable {
    public let id: String
    public var sessionId: String
    public var agent: AgentKind
    public var tool: String
    public var command: String?
    public var filePath: String?
    public var workingDirectory: String?
    public var detail: String?
    public var risk: PermissionRisk
    public var receivedAt: Date
    /// Set when the agent is asking questions rather than asking permission.
    public var questions: [AgentQuestion]?
    public var edit: EditPreview?

    public var isQuestion: Bool { !(questions ?? []).isEmpty }

    public init(id: String, sessionId: String, agent: AgentKind, tool: String, command: String?, filePath: String?,
                workingDirectory: String?, detail: String?, risk: PermissionRisk, receivedAt: Date,
                questions: [AgentQuestion]? = nil) {
        self.questions = questions
        self.id = id
        self.sessionId = sessionId
        self.agent = agent
        self.tool = tool
        self.command = command
        self.filePath = filePath
        self.workingDirectory = workingDirectory
        self.detail = detail
        self.risk = risk
        self.receivedAt = receivedAt
    }

    /// Builds a request from a `permission_request` event, classifying its risk.
    public init?(event: AgentEvent, now: Date) {
        guard event.event == .permissionRequest else { return nil }
        let tool = event.tool ?? "Unknown"
        self.init(
            id: event.requestId ?? UUID().uuidString,
            sessionId: event.sessionId,
            agent: event.agent,
            tool: tool,
            command: event.command,
            filePath: event.filePath,
            workingDirectory: event.workingDirectory,
            detail: event.description,
            risk: PermissionRiskClassifier.classify(tool: tool, command: event.command, filePath: event.filePath,
                                                    workingDirectory: event.workingDirectory),
            receivedAt: now,
            questions: event.questions
        )
        edit = event.edit
    }
}

public enum PermissionDecision: Sendable, Equatable {
    case deny, allowOnce, allowForSession
}
