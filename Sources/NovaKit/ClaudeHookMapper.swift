import Foundation

/// Translates Claude Code hook input (JSON on stdin) into Nova events, and
/// Nova's decisions back into hook output.
/// Reference: https://code.claude.com/docs/en/hooks.md
public enum ClaudeHookMapper {
    public struct Mapped: Sendable, Equatable {
        public var event: AgentEvent
        /// True when the hook must wait for Nova's decision.
        public var awaitsDecision: Bool
    }

    /// Where Claude Code is running, from the environment it gives hooks.
    public static func detectHost(_ env: [String: String]) -> String? {
        if env["CURSOR_TRACE_ID"] != nil { return "cursor" }
        if env["CLAUDE_CODE_ENTRYPOINT"]?.contains("vscode") == true || env["TERM_PROGRAM"] == "vscode" { return "vscode" }
        switch env["TERM_PROGRAM"] {
        case "Apple_Terminal": return "terminal"
        case "iTerm.app": return "iterm"
        case "WarpTerminal": return "warp"
        case "ghostty": return "ghostty"
        default: return nil
        }
    }

    /// `askMode`: this hook was installed only for AskUserQuestion
    /// (`nova-hook --ask`), so it waits for the user's answers.
    public static func map(hookJSON data: Data, requestId: String = UUID().uuidString, askMode: Bool = false,
                           environment: [String: String] = ProcessInfo.processInfo.environment) -> Mapped? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hookName = object["hook_event_name"] as? String else { return nil }

        let sessionId = object["session_id"] as? String ?? "unknown"
        let cwd = object["cwd"] as? String
        let tool = object["tool_name"] as? String
        let input = object["tool_input"] as? [String: Any] ?? [:]
        let command = input["command"] as? String
        let filePath = (input["file_path"] ?? input["notebook_path"] ?? input["path"]) as? String

        var event = AgentEvent(agent: .claude, sessionId: sessionId, event: .unknown, tool: tool,
                               command: command.map(SecretMasker.mask), workingDirectory: cwd, filePath: filePath,
                               host: detectHost(environment))
        if hookName == "PreToolUse" || hookName == "PermissionRequest" { event.edit = EditPreview.make(tool: tool, input: input) }
        var awaits = false

        // Questions: answered in the notch (PreToolUse via --ask, or a
        // PermissionRequest for AskUserQuestion).
        if tool == "AskUserQuestion", askMode ? hookName == "PreToolUse" : hookName == "PermissionRequest" {
            guard let questions = AgentQuestion.parse(toolInput: input) else { return nil }
            event.event = .permissionRequest
            event.questions = questions
            event.description = questions.count == 1 ? questions[0].question : "\(questions.count) questions for you"
            event.requestId = requestId
            return Mapped(event: event, awaitsDecision: true)
        }
        if askMode { return nil }   // the --ask hook ignores everything else

        switch hookName {
        case "SessionStart":
            event.event = .sessionStart
        case "UserPromptSubmit":
            event.event = .prompt
            event.description = (object["prompt"] as? String).map { String($0.prefix(140)) }
        case "PreToolUse":
            event.event = .toolStart
            event.description = describe(tool: tool, input: input)
        case "PostToolUse":
            event.event = .toolEnd
            event.description = describe(tool: tool, input: input)
        case "PostToolUseFailure":
            event.event = .toolFailed
            event.description = describe(tool: tool, input: input)
        case "PermissionRequest":
            event.event = .permissionRequest
            event.description = describe(tool: tool, input: input)
            event.requestId = requestId
            awaits = true
        case "Notification":
            event.event = .notification
            event.message = object["message"] as? String
        case "Stop", "SubagentStop":
            guard hookName == "Stop" else { return nil }
            event.event = .stop
        case "StopFailure":
            event.event = .error
            event.message = object["error"] as? String ?? object["message"] as? String
        case "SessionEnd":
            event.event = .sessionEnd
        default:
            return nil
        }
        return Mapped(event: event, awaitsDecision: awaits)
    }

    /// Human-readable one-liner for a tool call.
    public static func describe(tool: String?, input: [String: Any]) -> String {
        let file = ((input["file_path"] ?? input["notebook_path"]) as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        switch tool {
        case "Bash": return "Running \((input["command"] as? String).map { String($0.prefix(80)) } ?? "a command")"
        case "Read": return "Reading \(file ?? "a file")"
        case "Edit", "MultiEdit": return "Editing \(file ?? "a file")"
        case "Write": return "Writing \(file ?? "a file")"
        case "NotebookEdit": return "Editing notebook \(file ?? "")"
        case "Grep": return "Searching for “\(input["pattern"] as? String ?? "")”"
        case "Glob": return "Finding \(input["pattern"] as? String ?? "files")"
        case "WebFetch": return "Fetching \(input["url"] as? String ?? "a page")"
        case "WebSearch": return "Searching the web for “\(input["query"] as? String ?? "")”"
        case "Task", "Agent": return (input["description"] as? String) ?? "Running a subagent"
        case let name?: return name.hasPrefix("mcp__") ? "Calling \(name.replacingOccurrences(of: "mcp__", with: ""))" : "Using \(name)"
        case nil: return "Working"
        }
    }

    /// Hook stdout for a decision. `nil` means print nothing, which lets
    /// Claude Code show its normal permission prompt.
    /// Hook stdout for answered questions: allow the tool with the answers
    /// filled in. `nil` (terminal fallback) when there's nothing to send.
    public static func questionOutput(hookEvent: String, reply: PermissionReply, hookJSON: Data) -> Data? {
        guard reply.decision == .allow, let answers = reply.answers,
              let object = try? JSONSerialization.jsonObject(with: hookJSON) as? [String: Any],
              let input = object["tool_input"] as? [String: Any],
              let questions = AgentQuestion.parse(toolInput: input),
              AgentQuestion.isComplete(answers, for: questions) else { return nil }
        var updated = input
        updated["answers"] = AgentQuestion.answersJSON(answers, for: questions)
        let specific: [String: Any] = hookEvent == "PreToolUse"
            ? ["hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": updated]
            : ["hookEventName": "PermissionRequest", "decision": ["behavior": "allow", "updatedInput": updated]]
        return try? JSONSerialization.data(withJSONObject: ["hookSpecificOutput": specific], options: [.sortedKeys])
    }

    public static func permissionOutput(for reply: PermissionReply) -> Data? {
        var decision: [String: Any]
        switch reply.decision {
        case .allow:
            decision = ["behavior": "allow"]
        case .deny:
            decision = ["behavior": "deny", "message": reply.reason ?? "Denied from Nova."]
        case .ask:
            return nil
        }
        let output: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    }
}
