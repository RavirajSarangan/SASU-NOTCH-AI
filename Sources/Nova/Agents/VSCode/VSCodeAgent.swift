import NovaKit

/// VS Code itself, fed by the Nova VS Code extension (extras/vscode-nova):
/// tasks, debugging, saves and errors. Claude Code sessions started inside
/// VS Code are separately tagged with `host == "vscode"`.
@MainActor
final class VSCodeAgent: SocketAgentProvider {
    init() { super.init(kind: .vscode) }
}
