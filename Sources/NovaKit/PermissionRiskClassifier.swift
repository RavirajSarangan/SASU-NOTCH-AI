import Foundation

/// Rates how dangerous a requested action is. Conservative by design: when in
/// doubt it rates higher, and high-risk actions can never be auto-approved.
public enum PermissionRiskClassifier {
    private static let readOnlyTools: Set<String> = ["Read", "Grep", "Glob", "LS", "WebSearch", "WebFetch", "TodoWrite", "NotebookRead"]
    private static let editTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]
    private static let shellTools: Set<String> = ["Bash", "bash", "shell", "Shell", "run_shell_command", "exec"]

    /// (pattern, reason) checked against shell commands; any match is high risk.
    private static let dangerousPatterns: [(String, String)] = [
        (#"\bsudo\b"#, "Uses sudo (admin privileges)"),
        (#"\brm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+"#, "Recursive or forced delete"),
        (#"\b(chmod|chown)\s+(-[a-zA-Z]*R|.*\s/)"#, "Changes permissions recursively"),
        (#"(curl|wget)[^|]*\|\s*(sudo\s+)?(sh|bash|zsh|python3?|perl|ruby|node)\b"#, "Pipes a download into a shell"),
        (#"(sh|bash|zsh)\s+(-c\s+)?["']?\$\(\s*(curl|wget)"#, "Runs a downloaded script"),
        (#"/dev/(tcp|udp)/"#, "Opens a raw network connection (reverse shell pattern)"),
        (#"\b(nc|ncat|netcat)\b[^|;&]*\s-[a-zA-Z]*[elc]\b"#, "Netcat with command execution (reverse shell pattern)"),
        (#"\bsocat\b.*\b(exec|system):"#, "socat with command execution (reverse shell pattern)"),
        (#"base64\s+(-d|-D|--decode)[^|]*\|\s*(sh|bash|zsh|python3?|perl)\b"#, "Runs base64-hidden code"),
        (#"\b(python3?|perl|ruby|php)\s+-[a-zA-Z]*[ce]\b.*\b(socket|subprocess|pty\.spawn|exec)\b"#, "Inline script that spawns shells or sockets"),
        (#"\bchmod\s+[ugoa]*\+[a-z]*s|\bchmod\s+[0-7]*[4-7][0-7]{3}\b"#, "Sets the setuid/setgid bit"),
        (#"Library/(LaunchAgents|LaunchDaemons)"#, "Touches startup items (persistence)"),
        (#"\bcrontab\b|/etc/periodic|\bat\s+now\b"#, "Schedules a background job (persistence)"),
        (#"\bosascript\b.*(do shell script|with administrator privileges|System Events)"#, "AppleScript that runs commands or controls apps"),
        (#"authorized_keys"#, "Changes who can log in over SSH"),
        (#"\b(tccutil|sqlite3\b.*TCC\.db)"#, "Changes privacy permissions"),
        (#"\bxattr\s+-[a-zA-Z]*[dc].*com\.apple\.quarantine|\bxattr\s+-c"#, "Removes the download quarantine flag"),
        (#"\b(dscl|sysadminctl|dseditgroup)\b"#, "Changes user accounts"),
        (#"\bhistory\s+-c\b|\bunset\s+HISTFILE\b"#, "Clears shell history"),
        (#"\bgit\s+push\b.*(--force|-f\b)"#, "Force-pushes git history"),
        (#"\bgit\s+reset\s+--hard\b"#, "Discards local git changes"),
        (#"\bgit\s+clean\s+-[a-zA-Z]*f"#, "Deletes untracked files"),
        (#"\b(mkfs|diskutil\s+erase|dd\s+if=)"#, "Low-level disk operation"),
        (#"\b(launchctl|csrutil|spctl|systemsetup|pmset|nvram)\b"#, "Changes system configuration"),
        (#"\bdefaults\s+(write|delete)\b"#, "Changes system preferences"),
        (#"\bsecurity\s+(delete|add|import|dump)"#, "Touches the Keychain"),
        (#"(>|>>)\s*(/etc/|~/\.ssh|~/\.zshrc|~/\.bash_profile|/System/|/usr/)"#, "Writes to a protected location"),
        (#":\(\)\s*\{"#, "Fork bomb pattern"),
        (#"\bkill(all)?\s+-9\b"#, "Force-kills processes"),
        (#"\bnpm\s+publish\b|\bcargo\s+publish\b|\btwine\s+upload\b"#, "Publishes a package"),
    ]

    private static let mediumPatterns: [(String, String)] = [
        (#"\b(npm|pnpm|yarn|bun)\s+(i|install|add)\b|\bpip3?\s+install\b|\bbrew\s+install\b"#, "Installs packages"),
        (#"\b(curl|wget|ssh|scp|rsync)\b"#, "Uses the network"),
        (#"\brm\b"#, "Deletes files"),
        (#"\bgit\s+(push|commit|merge|rebase|checkout)\b"#, "Changes git state"),
        (#"\bmv\b"#, "Moves files"),
    ]

    private static let protectedPaths = ["/etc/", "/System/", "/usr/", "/Library/", "/.ssh/", "/.zshrc", "/.bash_profile", "/.gitconfig"]

    public static func classify(tool: String, command: String?, filePath: String?, workingDirectory: String?) -> PermissionRisk {
        if tool == "AskUserQuestion" { return PermissionRisk(.low, "Asks you a question") }
        if shellTools.contains(tool) {
            guard let command, !command.trimmingCharacters(in: .whitespaces).isEmpty else {
                return PermissionRisk(.high, "Unknown shell command")
            }
            for (pattern, reason) in dangerousPatterns where matches(command, pattern) {
                return PermissionRisk(.high, reason)
            }
            for (pattern, reason) in mediumPatterns where matches(command, pattern) {
                return PermissionRisk(.medium, reason)
            }
            return PermissionRisk(.medium, "Runs a shell command")
        }

        if editTools.contains(tool) {
            if let filePath, let sensitive = sensitiveFile(filePath) { return sensitive }
            if let filePath {
                if protectedPaths.contains(where: { filePath.contains($0) }) {
                    return PermissionRisk(.high, "Edits a protected system or config file")
                }
                if let workingDirectory, !isInside(filePath, workingDirectory) {
                    return PermissionRisk(.high, "Edits a file outside the project")
                }
            }
            return PermissionRisk(.low, "Edits a file in the project")
        }

        if readOnlyTools.contains(tool) {
            if tool == "WebFetch" || tool == "WebSearch" { return PermissionRisk(.low, "Reads from the web") }
            return PermissionRisk(.low, "Read-only")
        }

        if tool.hasPrefix("mcp__") { return PermissionRisk(.medium, "Calls an MCP tool") }
        return PermissionRisk(.high, "Unrecognised tool")
    }

    /// Files whose edits deserve a closer look even inside the project.
    static func sensitiveFile(_ path: String) -> PermissionRisk? {
        let name = (path as NSString).lastPathComponent
        if name == ".env" || name.hasPrefix(".env.") && !name.hasSuffix(".example") && !name.hasSuffix(".sample") {
            return PermissionRisk(.high, "Edits a secrets file (.env)")
        }
        if path.contains("/.github/workflows/") || path.contains("/.gitlab-ci") || name == ".gitlab-ci.yml" || path.contains("/.circleci/") {
            return PermissionRisk(.high, "Edits CI configuration (runs on every push)")
        }
        if ["package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "Cargo.lock", "Podfile.lock", "Gemfile.lock", "poetry.lock"].contains(name) {
            return PermissionRisk(.medium, "Edits a lockfile (changes installed dependencies)")
        }
        if ["package.json", "Package.swift", "Cargo.toml", "requirements.txt", "pyproject.toml", "Gemfile", "Dockerfile"].contains(name) {
            return PermissionRisk(.medium, "Edits dependencies or build scripts")
        }
        return nil
    }

    static func isInside(_ path: String, _ directory: String) -> Bool {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        let d = URL(fileURLWithPath: directory).standardizedFileURL.path
        return p == d || p.hasPrefix(d.hasSuffix("/") ? d : d + "/")
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}

/// "Always allow for this session" rules. Never matches high-risk requests.
public struct SessionRules: Sendable {
    struct Rule: Hashable, Sendable {
        var sessionId: String
        var tool: String
        var commandPrefix: String?
    }

    private var rules: Set<Rule> = []

    public init() {}

    public var isEmpty: Bool { rules.isEmpty }

    /// Returns false (and adds nothing) for high-risk requests.
    @discardableResult
    public mutating func add(for request: AgentPermissionRequest) -> Bool {
        guard request.risk.level < .high else { return false }
        rules.insert(Rule(sessionId: request.sessionId, tool: request.tool, commandPrefix: Self.prefix(of: request.command)))
        return true
    }

    public func allows(_ request: AgentPermissionRequest) -> Bool {
        guard request.risk.level < .high else { return false }
        let prefix = Self.prefix(of: request.command)
        return rules.contains(Rule(sessionId: request.sessionId, tool: request.tool, commandPrefix: prefix))
    }

    public mutating func removeAll(for sessionId: String) {
        rules = rules.filter { $0.sessionId != sessionId }
    }

    /// First two words of a command ("npm run build" → "npm run").
    static func prefix(of command: String?) -> String? {
        guard let command else { return nil }
        let words = command.split(whereSeparator: \.isWhitespace).prefix(2)
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}
