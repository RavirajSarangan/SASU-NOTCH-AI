import NovaKit
import SwiftUI

extension AgentStatus {
    var label: String {
        switch self {
        case .idle: "Idle"
        case .working: "Working"
        case .thinking: "Thinking"
        case .waiting: "Waiting"
        case .completed: "Completed"
        case .error: "Error"
        case .needsApproval: "Needs Approval"
        }
    }

    var color: Color {
        switch self {
        case .idle: Theme.textSecondary
        case .working: Theme.cyan
        case .thinking: Theme.violet
        case .waiting: Theme.blue
        case .completed: Theme.success
        case .error: Theme.error
        case .needsApproval: Theme.warning
        }
    }

    /// Whether the status dot should pulse.
    var isLive: Bool {
        switch self {
        case .working, .thinking, .needsApproval: true
        default: false
        }
    }

    /// Nova's reaction when the user focuses an agent in this state.
    var expression: NovaExpression {
        switch self {
        case .working: .coding
        case .thinking: .thinking
        case .needsApproval: .warning
        case .completed: .success
        case .error: .error
        case .idle, .waiting: .happy
        }
    }
}

extension AgentKind {
    var brand: BrandMark {
        switch self {
        case .claude: .claude
        case .codex: .openAI
        case .cursor: .cursor
        case .gemini: .gemini
        case .antigravity: .antigravity
        case .vscode: .vscode
        }
    }
}

/// View model for one agent row/chip on Home.
struct AgentSummary: Identifiable, Sendable, Equatable {
    let kind: AgentKind
    var status: AgentStatus
    var detail: String
    var preview: SessionPreview
    /// Live session id, if any.
    var sessionId: String?
    var projectName: String? = nil
    /// Live sessions of this same agent (2 = "Claude ×2").
    var siblingCount = 1
    var terminalApp: String? = nil
    var subagents = 0

    /// One entry per live session (several per agent are fine).
    var id: String { sessionId ?? kind.rawValue }
    var name: String { kind.displayName }
    /// "Claude · portfolio" when the same agent runs in several projects.
    var title: String {
        guard siblingCount > 1, let projectName else { return name }
        return "\(name) · \(projectName)"
    }
    /// The session's color (several sessions of one agent stay distinguishable).
    var tagColor: Color? { sessionId.map { Theme.sessionColors[AgentSession.tag(for: $0)] } }
    var brand: BrandMark { kind.brand }
    var isConnected: Bool { sessionId != nil }
}

extension AgentSummary {
    /// Summary for an agent from its most recent live session (or "not connected").
    static func live(_ kind: AgentKind, session: AgentSession?, siblings: Int = 1, now: Date = Date()) -> AgentSummary {
        guard let session else {
            return AgentSummary(kind: kind, status: .idle, detail: "Not connected", preview: .idle)
        }
        let detail: String = switch session.status {
        case .working: session.actions.last?.detail ?? "Working"
        case .thinking: session.currentTask ?? "Thinking"
        case .needsApproval: "Waiting for your approval"
        case .completed: "Finished · \(Self.format(session.elapsed(now: now)))"
        case .error: "Stopped with an error"
        case .waiting: "Waiting for input"
        case .idle: session.projectName ?? "Idle"
        }
        return AgentSummary(kind: kind, status: session.status, detail: detail,
                            preview: SessionPreview(session: session, now: now), sessionId: session.id,
                            projectName: session.projectName, siblingCount: siblings,
                            terminalApp: session.terminalApp, subagents: session.subagents)
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = max(Int(interval), 0)
        let m = total / 60, s = total % 60
        if m >= 60 { return "\(m / 60)h \(m % 60)m" }
        return m > 0 ? "\(m)m \(String(format: "%02d", s))s" : "\(s)s"
    }

    // Mock data for snapshots and previews.
    static let mocks: [AgentSummary] = [
        .init(kind: .claude, status: .working, detail: "Editing APIClient.swift", preview: .swiftEdit, sessionId: "mock-1"),
        .init(kind: .codex, status: .thinking, detail: "Planning refactor", preview: .planning, sessionId: "mock-2"),
        .init(kind: .cursor, status: .idle, detail: "Not connected", preview: .idle),
        .init(kind: .gemini, status: .needsApproval, detail: "Wants to run npm run build", preview: .approval, sessionId: "mock-3"),
        .init(kind: .antigravity, status: .completed, detail: "Finished 4m ago", preview: .finished, sessionId: "mock-4"),
    ]
}

extension SessionPreview {
    init(session: AgentSession, now: Date) {
        let file = session.filePath.map { URL(fileURLWithPath: $0) }
        var path = session.filePath ?? session.cwd ?? ""
        if let cwd = session.cwd, path.hasPrefix(cwd + "/") { path = String(path.dropFirst(cwd.count + 1)) }

        let recent = session.actions.suffix(4)
        var steps = recent.map { action in
            Step(title: action.tool, symbol: Self.symbol(for: action.tool), state: action.state == .running ? .active : .done)
        }
        if session.status == .completed {
            steps.append(Step(title: "Done", symbol: "checkmark", state: .done))
        }
        if steps.isEmpty {
            steps = [Step(title: session.status == .thinking ? "Thinking" : "Ready", symbol: "sparkles",
                          state: session.status == .thinking ? .active : .done)]
        }

        self.init(
            fileName: file?.lastPathComponent ?? session.projectName ?? "Session",
            path: path,
            languageBadge: Self.badge(for: file?.pathExtension),
            elapsed: AgentSummary.format(session.elapsed(now: now)),
            steps: Array(steps.suffix(4)),
            lines: [],
            notes: session.actions.suffix(5).map { action in
                let state: Note.State = switch action.state {
                case .running: .running
                case .done: .done
                case .failed: .failed
                }
                return Note(text: action.detail.isEmpty ? action.tool : action.detail, state: state, edit: action.edit)
            }
        )
    }

    static func symbol(for tool: String) -> String {
        switch tool {
        case "Read", "Grep", "Glob": "doc.text.magnifyingglass"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": "pencil"
        case "Bash": "terminal"
        case "WebFetch", "WebSearch": "globe"
        case "Task", "Agent": "person.2"
        default: "wrench.and.screwdriver"
        }
    }

    static func badge(for ext: String?) -> String {
        switch ext?.lowercased() {
        case "swift": "SW"
        case "ts", "tsx": "TS"
        case "js", "jsx", "json": "JS"
        case "py": "PY"
        case "md": "MD"
        case "rs": "RS"
        case "go": "GO"
        case nil, "": "··"
        case let e?: String(e.prefix(2)).uppercased()
        }
    }
}

extension AgentSummary {
    /// Equal when everything shown on screen is equal. Ignores the preview's
    /// random step/note ids and its ticking `elapsed` text (timers update on
    /// their own), so an unchanged session doesn't re-render the notch.
    static func == (a: AgentSummary, b: AgentSummary) -> Bool {
        a.kind == b.kind && a.status == b.status && a.detail == b.detail && a.sessionId == b.sessionId
            && a.projectName == b.projectName && a.siblingCount == b.siblingCount && a.terminalApp == b.terminalApp
            && a.subagents == b.subagents && a.preview.signature == b.preview.signature
    }
}

extension SessionPreview {
    /// What the preview shows, as comparable text.
    var signature: String {
        let steps = self.steps.map { "\($0.title)|\($0.symbol)|\($0.state)" }.joined(separator: ";")
        let notes = self.notes.map { "\($0.text)|\($0.state)|\($0.edit?.summary ?? "")" }.joined(separator: ";")
        let lines = self.lines.map { "\($0.number)|\($0.kind)|\($0.text)" }.joined(separator: ";")
        return [fileName, path, languageBadge, steps, notes, lines].joined(separator: "\u{1F}")
    }
}
