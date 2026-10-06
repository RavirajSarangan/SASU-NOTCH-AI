import Foundation

/// Turns the output of macOS security commands into checks and a score.
public enum SecurityPosture {
    public static func fileVault(_ output: String) -> SecurityCheck {
        let on = output.contains("FileVault is On")
        return SecurityCheck(id: "filevault", title: "FileVault disk encryption",
                             detail: on ? "Your disk is encrypted." : "Your disk isn't encrypted. Anyone with the Mac could read your files.",
                             status: output.isEmpty ? .unknown : (on ? .ok : .critical), fix: .fileVault)
    }

    public static func firewall(_ output: String) -> SecurityCheck {
        let on = output.contains("enabled") || output.contains("State = 1") || output.contains("State = 2")
        return SecurityCheck(id: "firewall", title: "Firewall",
                             detail: on ? "Incoming connections are filtered." : "The firewall is off. Turn it on to block unwanted incoming connections.",
                             status: output.isEmpty ? .unknown : (on ? .ok : .critical), fix: .firewall)
    }

    public static func stealthMode(_ output: String) -> SecurityCheck {
        let on = output.contains("stealth mode is on") || output.contains("Stealth mode enabled")
        return SecurityCheck(id: "stealth", title: "Firewall stealth mode",
                             detail: on ? "Your Mac doesn't answer network probes." : "Optional: stealth mode hides your Mac from network scans.",
                             status: output.isEmpty ? .unknown : (on ? .ok : .warning), fix: .firewall)
    }

    public static func sip(_ output: String) -> SecurityCheck {
        let on = output.contains("status: enabled")
        return SecurityCheck(id: "sip", title: "System Integrity Protection",
                             detail: on ? "Core system files are protected." : "SIP is disabled. Re-enable it from Recovery mode.",
                             status: output.isEmpty ? .unknown : (on ? .ok : .critical))
    }

    public static func gatekeeper(_ output: String) -> SecurityCheck {
        let on = output.contains("assessments enabled")
        return SecurityCheck(id: "gatekeeper", title: "Gatekeeper",
                             detail: on ? "Only trusted apps can open." : "Gatekeeper is off. Unverified apps can run.",
                             status: output.isEmpty ? .unknown : (on ? .ok : .critical), fix: .privacySecurity)
    }

    public static func automaticUpdates(_ value: String?) -> SecurityCheck {
        let on = value?.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        return SecurityCheck(id: "updates", title: "Automatic security updates",
                             detail: on ? "macOS updates install automatically." : "Turn on automatic updates to get security fixes quickly.",
                             status: value == nil ? .unknown : (on ? .ok : .warning), fix: .softwareUpdate)
    }

    /// `sysadminctl -screenLock status` → "screenLock delay is 300 seconds" / "immediate" / "off".
    public static func screenLock(_ output: String) -> SecurityCheck {
        let lower = output.lowercased()
        let status: SecurityStatus
        let detail: String
        if lower.contains("off") {
            status = .critical
            detail = "No password is required after sleep or the screen saver."
        } else if lower.contains("immediate") {
            status = .ok
            detail = "A password is required immediately."
        } else if let seconds = lower.range(of: #"\d+"#, options: .regularExpression).flatMap({ Int(lower[$0]) }) {
            status = seconds <= 60 ? .ok : .warning
            detail = seconds <= 60 ? "A password is required within \(seconds) s." : "A password is required only after \(seconds / 60) min. Shorter is safer."
        } else {
            status = .unknown
            detail = "Couldn't read the screen lock setting."
        }
        return SecurityCheck(id: "screenlock", title: "Screen lock password", detail: detail, status: status, fix: .lockScreen)
    }

    /// Remote-access services, from the set of listening TCP ports.
    public static func remoteAccess(listeningPorts ports: Set<Int>) -> [SecurityCheck] {
        func check(_ id: String, _ title: String, _ open: Bool, _ what: String) -> SecurityCheck {
            SecurityCheck(id: id, title: title,
                          detail: open ? "\(what) is on. Others on your network can try to connect." : "Off.",
                          status: open ? .warning : .ok, fix: .sharing)
        }
        return [
            check("ssh", "Remote Login (SSH)", ports.contains(22), "Remote Login"),
            check("screensharing", "Screen Sharing", ports.contains(5900), "Screen Sharing"),
            check("ard", "Remote Management", ports.contains(3283), "Remote Management"),
            check("filesharing", "File Sharing", ports.contains(445) || ports.contains(548), "File Sharing"),
        ]
    }

    /// 100 minus 25 per critical and 8 per warning, clamped to 0…100.
    public static func score(_ checks: [SecurityCheck]) -> Int {
        let penalty = checks.reduce(0) { total, check in
            total + (check.status == .critical ? 25 : check.status == .warning ? 8 : 0)
        }
        return max(0, min(100, 100 - penalty))
    }
}
