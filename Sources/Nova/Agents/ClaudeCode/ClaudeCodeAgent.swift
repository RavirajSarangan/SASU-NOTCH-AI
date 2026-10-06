import NovaKit

/// Claude Code, fed by the `nova-hook` helper installed into Claude Code's
/// hooks (see scripts/install_claude_hook.sh).
@MainActor
final class ClaudeCodeAgent: SocketAgentProvider {
    init() { super.init(kind: .claude) }

    override func normalize(_ event: AgentEvent) -> AgentEvent {
        guard event.description == nil, event.event == .toolStart || event.event == .permissionRequest else { return event }
        var input: [String: Any] = [:]
        if let command = event.command { input["command"] = command }
        if let path = event.filePath { input["file_path"] = path }
        var event = event
        event.description = ClaudeHookMapper.describe(tool: event.tool, input: input)
        return event
    }
}
