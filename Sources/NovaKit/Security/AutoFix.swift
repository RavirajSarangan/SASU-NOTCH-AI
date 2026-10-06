import Foundation

/// What Nova Guard does on its own. Safe, reversible fixes that need no
/// admin rights run automatically; admin fixes run only when the user clicks
/// (macOS then asks for their password); everything else is alert-only.
public enum AutoFixPolicy {
    public enum Action: Equatable, Sendable { case auto, askAdmin, alertOnly }

    public static func action(for kind: SecurityAlert.Kind, risky: Bool) -> Action {
        switch kind {
        case .newStartupItem: risky ? .auto : .alertOnly        // quarantine the plist (undoable)
        case .reverseShell: .auto                                // terminate the process
        case .remoteAccessEnabled, .remoteSession, .postureChanged: .askAdmin
        default: .alertOnly
        }
    }

    // MARK: Coding-agent commands that are always denied

    private static let alwaysDeny: [(String, String)] = [
        (#"/dev/(tcp|udp)/"#, "opens a reverse shell"),
        (#"\b(nc|ncat|netcat)\b[^|;&]*\s-[a-zA-Z]*[ec]\b"#, "opens a reverse shell"),
        (#"\bsocat\b.*\b(exec|system):"#, "opens a reverse shell"),
        (#"(curl|wget)[^|]*\|\s*(sudo\s+)?(sh|bash|zsh|python3?|perl|ruby|node)\b"#, "runs a script straight from the internet"),
        (#"base64\s+(-d|-D|--decode)[^|]*\|\s*(sh|bash|zsh|python3?|perl)\b"#, "runs hidden (base64) code"),
        (#"\bsecurity\s+(dump-keychain|find-generic-password\s.*-w|find-internet-password\s.*-w)"#, "reads passwords from the Keychain"),
        (#"authorized_keys"#, "changes who can log in over SSH"),
        (#"\btccutil\b|TCC\.db"#, "changes privacy permissions"),
    ]

    /// A reason if this agent command must never run, else nil.
    public static func agentDenyReason(command: String?) -> String? {
        guard let command, !command.isEmpty else { return nil }
        for (pattern, reason) in alwaysDeny where command.range(of: pattern, options: .regularExpression) != nil {
            return reason
        }
        return nil
    }

    // MARK: Reverse-shell processes

    private static let shellBinaries: Set<String> = ["bash", "sh", "zsh", "dash", "nc", "ncat", "netcat", "socat",
                                                     "python", "python3", "perl", "ruby", "php"]

    /// True for running processes that look like a reverse shell. Only the
    /// interpreter / netcat itself counts, so `grep /dev/tcp` never matches.
    public static func isReverseShell(command: String) -> Bool {
        let parts = command.split(separator: " ", omittingEmptySubsequences: true)
        guard let first = parts.first else { return false }
        let binary = String(first.split(separator: "/").last ?? first).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard shellBinaries.contains(binary) || binary.hasPrefix("python") else { return false }
        let patterns = [
            // A redirection to/from a network socket, not just the text.
            #"[<>]&?\s*/dev/(tcp|udp)/[^\s/]+/\d+"#,
            #"\b(nc|ncat|netcat)\b.*\s-[a-zA-Z]*e\s+\S*(sh|bash|zsh)\b"#,
            #"\bsocat\b.*\b(exec|system):"#,
            #"socket\..*(pty\.spawn|subprocess|os\.dup2)|(pty\.spawn|os\.dup2).*socket"#,
        ]
        return patterns.contains { command.range(of: $0, options: .regularExpression) != nil }
    }
}

/// `ps -U <uid> -o pid=,command=` output.
public enum ProcessListParser {
    public struct Process: Equatable, Sendable {
        public var pid: Int32
        public var command: String
    }

    public static func parse(_ output: String) -> [Process] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "), let pid = Int32(trimmed[..<space]) else { return nil }
            return Process(pid: pid, command: trimmed[space...].trimmingCharacters(in: .whitespaces))
        }
    }
}

/// Admin fixes Nova can apply after the user clicks and enters their
/// password. The exact command is shown to the user first.
public enum AdminFix: String, CaseIterable, Sendable {
    case firewallOn, stealthOn, remoteLoginOff, screenSharingOff, securityUpdatesOn

    public var title: String {
        switch self {
        case .firewallOn: "Turn on the Firewall"
        case .stealthOn: "Turn on stealth mode"
        case .remoteLoginOff: "Turn off Remote Login (SSH)"
        case .screenSharingOff: "Turn off Screen Sharing"
        case .securityUpdatesOn: "Turn on automatic security updates"
        }
    }

    public var command: String {
        let fw = "/usr/libexec/ApplicationFirewall/socketfilterfw"
        let su = "/Library/Preferences/com.apple.SoftwareUpdate"
        return switch self {
        case .firewallOn: "\(fw) --setglobalstate on"
        case .stealthOn: "\(fw) --setstealthmode on"
        case .remoteLoginOff: "/usr/sbin/systemsetup -f -setremotelogin off"
        case .screenSharingOff: "/bin/launchctl bootout system/com.apple.screensharing; /bin/launchctl disable system/com.apple.screensharing"
        case .securityUpdatesOn: "/usr/bin/defaults write \(su) CriticalUpdateInstall -bool true; /usr/bin/defaults write \(su) ConfigDataInstall -bool true; /usr/bin/defaults write \(su) AutomaticDownload -bool true"
        }
    }

    /// The fix for a posture check or remote-access check id, if Nova has one.
    public static func fix(forCheck id: String) -> AdminFix? {
        switch id {
        case "firewall": .firewallOn
        case "stealth": .stealthOn
        case "updates": .securityUpdatesOn
        case "ssh": .remoteLoginOff
        case "screensharing": .screenSharingOff
        default: nil
        }
    }

    /// AppleScript that runs the command with the macOS password prompt.
    public var appleScript: String {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges with prompt \"Nova Guard wants to: \(title).\""
    }
}

/// Where a quarantined file goes, so it can be restored exactly.
public enum QuarantinePath {
    /// "<dir>/<timestamp>-<name>" plus a sidecar recording the original path.
    public static func destination(for original: String, in directory: String, date: Date) -> String {
        let name = (original as NSString).lastPathComponent
        return (directory as NSString).appendingPathComponent("\(Int(date.timeIntervalSince1970))-\(name)")
    }
}
