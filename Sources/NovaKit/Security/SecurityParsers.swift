import Foundation

/// Parses `netstat -anv -p tcp` output.
public enum NetstatParser {
    public struct Socket: Sendable, Equatable {
        public var localPort: Int
        public var foreignHost: String
        public var foreignPort: Int?
        public var state: String
        public var processName: String?
        public var pid: Int?
    }

    /// Remote-access services worth alerting about when someone connects.
    public static let remoteAccessPorts: [Int: String] = [
        22: "Remote Login (SSH)", 5900: "Screen Sharing", 3283: "Remote Management",
        445: "File Sharing (SMB)", 548: "File Sharing (AFP)", 3389: "Remote Desktop",
    ]

    public static func parse(_ output: String) -> [Socket] {
        output.split(separator: "\n").compactMap { line in
            let cols = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard cols.count >= 6, cols[0].hasPrefix("tcp"), let localPort = port(of: cols[3]) else { return nil }
            let (host, foreignPort) = split(cols[4])
            // `-v` adds "rxbytes txbytes rhiwat shiwat process:pid …"; names may contain spaces.
            let owner = AuthLogParser.capture(String(line), #"\s\d+\s+\d+\s+\d+\s+\d+\s+(.+?):(\d+)\s+[0-9a-f]+\s"#)
            return Socket(localPort: localPort, foreignHost: host, foreignPort: foreignPort, state: cols[5],
                          processName: owner?.first?.trimmingCharacters(in: .whitespaces), pid: owner.flatMap { Int($0[1]) })
        }
    }

    public static func listeningPorts(_ sockets: [Socket]) -> Set<Int> {
        Set(sockets.filter { $0.state == "LISTEN" }.map(\.localPort))
    }

    /// Established connections *into* a remote-access service from another machine.
    public static func remoteSessions(_ sockets: [Socket]) -> [Socket] {
        sockets.filter { s in
            s.state == "ESTABLISHED" && remoteAccessPorts[s.localPort] != nil && !isLoopback(s.foreignHost)
        }
    }

    static func isLoopback(_ host: String) -> Bool {
        host.hasPrefix("127.") || host == "::1" || host.hasPrefix("localhost") || host.hasPrefix("fe80::1%lo0")
    }

    /// "192.168.1.5.22" / "*.22" / "fe80::1%lo0.22" → 22
    static func port(of address: String) -> Int? {
        guard let dot = address.lastIndex(of: ".") else { return nil }
        return Int(address[address.index(after: dot)...])
    }

    static func split(_ address: String) -> (String, Int?) {
        guard let dot = address.lastIndex(of: ".") else { return (address, nil) }
        return (String(address[..<dot]), Int(address[address.index(after: dot)...]))
    }
}

/// Users and admin-group membership vs a saved baseline.
public struct AccountSnapshot: Codable, Sendable, Equatable {
    public var users: Set<String>
    public var admins: Set<String>

    public init(users: Set<String>, admins: Set<String>) {
        self.users = users
        self.admins = admins
    }

    /// `dscl . -list /Users UniqueID` + `dscl . -read /Groups/admin GroupMembership`
    public static func parse(usersOutput: String, adminOutput: String) -> AccountSnapshot {
        let users = usersOutput.split(separator: "\n").compactMap { line -> String? in
            let cols = line.split(whereSeparator: \.isWhitespace)
            guard cols.count == 2, let uid = Int(cols[1]), uid >= 501, !cols[0].hasPrefix("_") else { return nil }
            return String(cols[0])
        }
        let admins = adminOutput.replacingOccurrences(of: "GroupMembership:", with: "")
            .split(whereSeparator: \.isWhitespace).map(String.init)
        return AccountSnapshot(users: Set(users), admins: Set(admins))
    }

    public func alerts(comparedTo baseline: AccountSnapshot) -> [SecurityAlert] {
        var alerts: [SecurityAlert] = []
        for user in users.subtracting(baseline.users).sorted() {
            alerts.append(SecurityAlert(severity: .critical, kind: .newUser, title: "New user account: \(user)",
                                        detail: "A user account was added to this Mac. If you didn't do this, remove it.",
                                        fix: .users, baselineKey: "user:\(user)"))
        }
        for admin in admins.subtracting(baseline.admins).sorted() {
            alerts.append(SecurityAlert(severity: .critical, kind: .adminChanged, title: "\(admin) became an administrator",
                                        detail: "An account was given admin rights. If you didn't do this, change it now.",
                                        fix: .users, baselineKey: "admin:\(admin)"))
        }
        return alerts
    }
}

/// Startup items (LaunchAgents / LaunchDaemons) vs a saved baseline.
public enum PersistenceDiff {
    public static func newItems(current: [String: Set<String>], baseline: [String: Set<String>]) -> [(directory: String, name: String)] {
        current.flatMap { directory, names in
            names.subtracting(baseline[directory] ?? []).sorted().map { (directory, $0) }
        }
        .sorted { $0.name < $1.name }
    }

    /// The program a launchd plist runs (Program or first ProgramArguments).
    public static func program(fromPlist data: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first
    }
}

/// Classifies unified-log lines (from `log stream --style ndjson`).
public enum AuthLogParser {
    public enum Event: Sendable, Equatable {
        case sshAccepted(user: String, from: String)
        case sshFailed(user: String, from: String)
        case screenSharingAuth(succeeded: Bool, detail: String)
        case loginFailed(detail: String)
        case sudo(user: String, command: String)
    }

    public static func parse(ndjsonLine line: String) -> Event? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["eventMessage"] as? String else { return nil }
        let process = ((object["processImagePath"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }) ?? (object["process"] as? String ?? "")
        return classify(process: process, message: message)
    }

    public static func classify(process: String, message: String) -> Event? {
        switch process {
        case "sshd", "sshd-session":
            if let m = capture(message, #"Accepted \S+ for (\S+) from (\S+)"#) { return .sshAccepted(user: m[0], from: m[1]) }
            if let m = capture(message, #"Failed \S+ for (?:invalid user )?(\S+) from (\S+)"#) { return .sshFailed(user: m[0], from: m[1]) }
            if let m = capture(message, #"Invalid user (\S+) from (\S+)"#) { return .sshFailed(user: m[0], from: m[1]) }
            return nil
        case "screensharingd":
            let lower = message.lowercased()
            guard lower.contains("authentication") else { return nil }
            return .screenSharingAuth(succeeded: lower.contains("succeeded") || lower.contains("success"), detail: message)
        case "sudo":
            if let m = capture(message, #"^\s*(\S+)\s*:.*COMMAND=(.+)$"#) { return .sudo(user: m[0], command: m[1].trimmingCharacters(in: .whitespaces)) }
            return nil
        case "loginwindow", "authd", "coreauthd":
            let lower = message.lowercased()
            if lower.contains("authentication failure") || lower.contains("failed to authenticate")
                || (lower.contains("failed to authorize") && lower.contains("system.login")) {
                return .loginFailed(detail: message)
            }
            return nil
        default:
            return nil
        }
    }

    static func capture(_ text: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }

    /// The predicate for `log stream`.
    public static let predicate = """
    process == "sshd" OR process == "sshd-session" OR process == "screensharingd" OR process == "sudo" \
    OR (process == "loginwindow" AND eventMessage CONTAINS[c] "fail") \
    OR (process == "authd" AND eventMessage CONTAINS[c] "failed to authorize")
    """
}

/// Counts failed logins in a sliding window.
public struct FailedLoginWindow: Sendable {
    public var window: TimeInterval
    public var threshold: Int
    private(set) var times: [Date] = []

    public init(window: TimeInterval = 300, threshold: Int = 3) {
        self.window = window
        self.threshold = threshold
    }

    /// Records a failure; returns true exactly when the threshold is reached.
    public mutating func record(_ date: Date) -> Bool {
        times = times.filter { date.timeIntervalSince($0) < window } + [date]
        return times.count == threshold
    }
}

// MARK: - More persistence and access points

/// Keys in ~/.ssh/authorized_keys. Each one lets someone log in without a
/// password (if Remote Login is on), so a new key is critical.
public enum AuthorizedKeys {
    public struct Key: Hashable, Sendable {
        public var type: String
        /// Short, non-secret identity: the last 16 characters of the key blob.
        public var tail: String
        public var comment: String
    }

    public static func parse(_ text: String) -> [Key] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            // Options may come first: find the key type token.
            guard let typeIndex = parts.firstIndex(where: { $0.hasPrefix("ssh-") || $0.hasPrefix("ecdsa-") || $0.hasPrefix("sk-") }),
                  parts.indices.contains(typeIndex + 1) else { return nil }
            let blob = parts[typeIndex + 1]
            let comment = parts.dropFirst(typeIndex + 2).joined(separator: " ")
            return Key(type: parts[typeIndex], tail: String(blob.suffix(16)), comment: comment)
        }
    }

    public static func identity(_ key: Key) -> String { "\(key.type):\(key.tail)" }
}

/// `profiles list` output → installed configuration profile identifiers.
/// Profiles can route traffic, install certificates and change settings,
/// a common way to take over a Mac.
public enum ProfilesParser {
    public static func identifiers(from output: String) -> Set<String> {
        var result = Set<String>()
        for line in output.split(whereSeparator: \.isNewline) {
            guard let range = line.range(of: "profileIdentifier:") else { continue }
            let id = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !id.isEmpty { result.insert(id) }
        }
        return result
    }
}

/// Lines added to a text file (shell startup files, crontab), compared with
/// the lines seen last time. Only counts and the first line are reported.
public enum TextDiff {
    public static func addedLines(old: String, new: String) -> [String] {
        let before = Set(old.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
        return new.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !before.contains($0) }
    }

    /// Lines that look like code fetching or running something remote.
    public static func looksRisky(_ line: String) -> Bool {
        line.range(of: #"(curl|wget)\b.*\|\s*(sh|bash|zsh|python)|/dev/tcp/|base64\s+(-d|-D|--decode)|\bnc\b.*\s-e\b|osascript"#,
                   options: .regularExpression) != nil
    }
}
