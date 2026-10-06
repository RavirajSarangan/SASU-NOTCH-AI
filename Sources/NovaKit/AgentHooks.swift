import Foundation

/// Which tool's hook system is calling `nova-hook`.
public enum HookSource: String, CaseIterable, Sendable {
    case claude, codex, cursor, gemini
}

/// What a single hook invocation should do.
public struct HookPlan: Sendable, Equatable {
    /// Activity to report (fire-and-forget).
    public var events: [AgentEvent]
    /// A permission request to wait on, if any.
    public var request: AgentEvent?
    /// Claude's PermissionRequest can approve; the others can only block.
    public var canApprove: Bool
    /// The tool's own event name (needed to format the reply).
    public var hookEvent: String

    public init(events: [AgentEvent], request: AgentEvent? = nil, canApprove: Bool = false, hookEvent: String) {
        self.events = events
        self.request = request
        self.canApprove = canApprove
        self.hookEvent = hookEvent
    }
}

/// Maps hook payloads from Claude Code, Codex, Cursor and Gemini CLI to
/// Nova events, and Nova's decisions back to each tool's output format.
///
/// Codex, Cursor and Gemini hooks can block an action but not approve it,
/// so for them Nova only guards **high-risk** commands: the user can deny
/// them from the notch; everything else follows the tool's own approvals.
public enum AgentHookRouter {
    /// How long a guarded tool waits for the user.
    public static let guardTimeout: TimeInterval = 60

    public static func plan(source: HookSource, hookJSON data: Data, agent: AgentKind? = nil,
                            requestId: String = UUID().uuidString, askMode: Bool = false,
                            environment: [String: String] = ProcessInfo.processInfo.environment) -> HookPlan? {
        switch source {
        case .claude:
            guard let mapped = ClaudeHookMapper.map(hookJSON: data, requestId: requestId, askMode: askMode,
                                                    environment: environment) else { return nil }
            let name = hookName(data) ?? ""
            return mapped.awaitsDecision
                ? HookPlan(events: [], request: mapped.event, canApprove: true, hookEvent: name)
                : HookPlan(events: [mapped.event], hookEvent: name)
        case .codex:
            return codex(data, requestId: requestId, environment: environment)
        case .cursor:
            return cursor(data, requestId: requestId)
        case .gemini:
            return gemini(data, agent: agent ?? .gemini, requestId: requestId)
        }
    }

    /// Hook stdout for the user's decision. nil means print nothing, so the
    /// tool falls back to its own behaviour.
    public static func output(source: HookSource, hookEvent: String, reply: PermissionReply, hookJSON: Data = Data()) -> Data? {
        if source == .claude {
            // Questions: only answers produce output; anything else falls
            // back to Claude asking in the terminal.
            if hookEvent == "PreToolUse" || reply.answers != nil { return ClaudeHookMapper.questionOutput(hookEvent: hookEvent, reply: reply, hookJSON: hookJSON) }
            return ClaudeHookMapper.permissionOutput(for: reply)
        }
        guard reply.decision == .deny else { return nil }   // only "deny" is meaningful for these tools
        let reason = reply.reason ?? "Denied in Nova"
        let object: [String: Any]
        switch source {
        case .codex:
            object = ["hookSpecificOutput": ["hookEventName": hookEvent, "permissionDecision": "deny", "permissionDecisionReason": reason]]
        case .cursor:
            object = ["permission": "deny", "userMessage": reason, "agentMessage": "The user denied this command in Nova."]
        case .gemini:
            object = ["decision": "deny", "reason": reason]
        case .claude:
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    // MARK: - Codex (Claude-compatible payloads)

    static func codex(_ data: Data, requestId: String, environment: [String: String]) -> HookPlan? {
        guard let name = hookName(data) else { return nil }
        if name == "PermissionRequest" {
            // Codex escalated to its own reviewer; show it, don't block.
            guard let object = json(data) else { return nil }
            let event = AgentEvent(agent: .codex, sessionId: object["session_id"] as? String ?? "codex", event: .notification,
                                   workingDirectory: object["cwd"] as? String, message: "Codex is waiting for approval in the terminal")
            return HookPlan(events: [event], hookEvent: name)
        }
        guard var mapped = ClaudeHookMapper.map(hookJSON: data, requestId: requestId, environment: environment)?.event else { return nil }
        mapped.agent = .codex
        mapped.requestId = nil
        var plan = HookPlan(events: [mapped], hookEvent: name)
        if name == "PreToolUse" { plan.request = guardRequest(for: mapped, requestId: requestId) }
        return plan
    }

    // MARK: - Cursor

    static func cursor(_ data: Data, requestId: String) -> HookPlan? {
        guard let object = json(data), let name = object["hook_event_name"] as? String else { return nil }
        let session = object["conversation_id"] as? String ?? "cursor"
        let cwd = (object["workspace_roots"] as? [String])?.first ?? object["cwd"] as? String
        func event(_ kind: AgentEvent.Kind, tool: String? = nil, description: String? = nil, command: String? = nil,
                   file: String? = nil, message: String? = nil) -> AgentEvent {
            AgentEvent(agent: .cursor, sessionId: session, event: kind, tool: tool, description: description, command: command,
                       workingDirectory: cwd, filePath: file, message: message, host: "cursor")
        }

        switch name {
        case "beforeSubmitPrompt":
            let prompt = (object["prompt"] as? String).map { String($0.prefix(140)) }
            return HookPlan(events: [event(.prompt, description: prompt)], hookEvent: name)
        case "beforeShellExecution":
            let command = object["command"] as? String ?? ""
            let start = event(.toolStart, tool: "Bash", description: ClaudeHookMapper.describe(tool: "Bash", input: ["command": command]),
                              command: command)
            return HookPlan(events: [start], request: guardRequest(for: start, requestId: requestId), hookEvent: name)
        case "afterShellExecution":
            return HookPlan(events: [event(.toolEnd, tool: "Bash")], hookEvent: name)
        case "beforeMCPExecution":
            let tool = "mcp__" + (object["tool_name"] as? String ?? "tool")
            return HookPlan(events: [event(.toolStart, tool: tool, description: ClaudeHookMapper.describe(tool: tool, input: [:]))], hookEvent: name)
        case "afterMCPExecution":
            return HookPlan(events: [event(.toolEnd, tool: "mcp__" + (object["tool_name"] as? String ?? "tool"))], hookEvent: name)
        case "afterFileEdit":
            let file = object["file_path"] as? String
            let description = ClaudeHookMapper.describe(tool: "Edit", input: file.map { ["file_path": $0] } ?? [:])
            return HookPlan(events: [event(.toolStart, tool: "Edit", description: description, file: file), event(.toolEnd, tool: "Edit")],
                            hookEvent: name)
        case "stop":
            let status = object["status"] as? String ?? "completed"
            return HookPlan(events: [status == "error" ? event(.error, message: "Cursor stopped with an error") : event(.stop)], hookEvent: name)
        default:
            return nil
        }
    }

    // MARK: - Gemini CLI / Antigravity

    static let geminiToolNames: [String: String] = [
        "run_shell_command": "Bash", "write_file": "Write", "replace": "Edit", "edit": "Edit",
        "read_file": "Read", "read_many_files": "Read", "glob": "Glob", "search_file_content": "Grep", "grep": "Grep",
        "web_fetch": "WebFetch", "google_web_search": "WebSearch", "list_directory": "LS",
    ]

    static func gemini(_ data: Data, agent: AgentKind, requestId: String) -> HookPlan? {
        guard let object = json(data), let name = object["hook_event_name"] as? String else { return nil }
        let session = object["session_id"] as? String ?? agent.rawValue
        let cwd = object["cwd"] as? String
        let rawTool = object["tool_name"] as? String
        let tool = rawTool.map { geminiToolNames[$0] ?? $0 }
        var input = object["tool_input"] as? [String: Any] ?? [:]
        if input["file_path"] == nil, let path = (input["absolute_path"] ?? input["path"]) as? String { input["file_path"] = path }
        let command = input["command"] as? String
        let file = input["file_path"] as? String
        func event(_ kind: AgentEvent.Kind, description: String? = nil, message: String? = nil) -> AgentEvent {
            AgentEvent(agent: agent, sessionId: session, event: kind, tool: tool, description: description, command: command,
                       workingDirectory: cwd, filePath: file, message: message)
        }

        switch name {
        case "SessionStart":
            return HookPlan(events: [event(.sessionStart)], hookEvent: name)
        case "SessionEnd":
            return HookPlan(events: [event(.sessionEnd)], hookEvent: name)
        case "BeforeAgent":
            return HookPlan(events: [event(.prompt, description: (object["prompt"] as? String).map { String($0.prefix(140)) })], hookEvent: name)
        case "AfterAgent":
            return HookPlan(events: [event(.stop)], hookEvent: name)
        case "BeforeTool":
            var start = event(.toolStart, description: ClaudeHookMapper.describe(tool: tool, input: input))
            start.edit = EditPreview.make(tool: rawTool, input: input)
            return HookPlan(events: [start], request: guardRequest(for: start, requestId: requestId), hookEvent: name)
        case "AfterTool":
            return HookPlan(events: [event(.toolEnd)], hookEvent: name)
        case "Notification":
            let isPermission = object["notification_type"] as? String == "ToolPermission"
            let message = isPermission ? "\(agent.displayName) needs approval in the terminal" : (object["message"] as? String ?? "")
            return HookPlan(events: [event(.notification, message: message)], hookEvent: name)
        default:
            return nil
        }
    }

    // MARK: - Helpers

    /// A permission request for high-risk shell commands only.
    static func guardRequest(for event: AgentEvent, requestId: String) -> AgentEvent? {
        let tool = event.tool ?? ""
        guard ["Bash", "bash", "shell", "Shell"].contains(tool), let command = event.command,
              PermissionRiskClassifier.classify(tool: "Bash", command: command, filePath: nil,
                                                workingDirectory: event.workingDirectory).level == .high else { return nil }
        var request = event
        request.event = .permissionRequest
        request.tool = "Bash"
        request.requestId = requestId
        return request
    }

    private static func json(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func hookName(_ data: Data) -> String? {
        json(data)?["hook_event_name"] as? String
    }
}
