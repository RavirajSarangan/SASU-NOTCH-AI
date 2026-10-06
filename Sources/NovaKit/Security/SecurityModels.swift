import Foundation

public enum SecurityStatus: String, Codable, Sendable, Comparable {
    case ok, warning, critical, unknown

    private var rank: Int { switch self { case .ok: 0; case .unknown: 1; case .warning: 2; case .critical: 3 } }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

/// System Settings panes used by "Fix" buttons. Nova only opens them; it
/// never changes system settings itself.
public enum SettingsPane: String, Codable, Sendable {
    case fileVault = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?FileVault"
    case privacySecurity = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
    case firewall = "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall"
    case sharing = "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
    case users = "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension"
    case loginItems = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    case softwareUpdate = "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
    case lockScreen = "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension"
    case deviceManagement = "x-apple.systempreferences:com.apple.Profiles-Settings.extension"
}

public struct SecurityCheck: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var detail: String
    public var status: SecurityStatus
    public var fix: SettingsPane?

    public init(id: String, title: String, detail: String, status: SecurityStatus, fix: SettingsPane? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.fix = fix
    }
}

public enum AlertSeverity: String, Codable, Sendable, Comparable {
    case info, high, critical

    private var rank: Int { switch self { case .info: 0; case .high: 1; case .critical: 2 } }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

public struct SecurityAlert: Identifiable, Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case remoteSession, sshLogin, failedLogins, screenSharingAuth, newUser, adminChanged, sudo
        case newStartupItem, unsignedApp, newListeningPort, remoteAccessEnabled, postureChanged, camera, microphone
        case newSSHKey, newProfile, newScheduledJob, shellStartupChanged
        case reverseShell, agentBlocked
    }

    public var id: UUID
    public var date: Date
    public var severity: AlertSeverity
    public var kind: Kind
    public var title: String
    public var detail: String
    public var fix: SettingsPane?
    /// A file to reveal in Finder (startup item, app).
    public var path: String?
    /// Key used to accept this as expected ("This was me").
    public var baselineKey: String?

    public init(severity: AlertSeverity, kind: Kind, title: String, detail: String, fix: SettingsPane? = nil,
                path: String? = nil, baselineKey: String? = nil, date: Date = Date()) {
        id = UUID()
        self.date = date
        self.severity = severity
        self.kind = kind
        self.title = title
        self.detail = detail
        self.fix = fix
        self.path = path
        self.baselineKey = baselineKey
    }
}
