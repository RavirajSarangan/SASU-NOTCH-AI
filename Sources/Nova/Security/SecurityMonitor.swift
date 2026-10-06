import CryptoKit
import AppKit
import CoreAudio
import CoreMediaIO
import Foundation
import NovaKit
import Observation

/// Splits a byte stream into lines. Only used from the pipe's serial
/// readability handler, so unsynchronized state is safe.
private final class LineBuffer: @unchecked Sendable {
    private var data = Data()

    func append(_ chunk: Data) -> [String] {
        data.append(chunk)
        var lines: [String] = []
        while let newline = data.firstIndex(of: 0x0A) {
            lines.append(String(decoding: data[..<newline], as: UTF8.self))
            data.removeSubrange(...newline)
        }
        return lines
    }
}

/// What Nova Guard has accepted as normal for this Mac.
struct SecurityBaseline: Codable {
    var accounts: AccountSnapshot?
    var startupItems: [String: Set<String>] = [:]
    var apps: Set<String> = []
    var exposedPorts: Set<Int> = []
    /// Alerts the user marked "This was me".
    var accepted: Set<String> = []
    // Added in 0.7 (optional so older baselines still load).
    var sshKeys: Set<String>?
    var profiles: Set<String>?
    var cronLines: Set<String>?
    var sudoersFiles: Set<String>?
    /// SHA-256 of each line (never the text: startup files can hold secrets).
    var shellLineHashes: [String: Set<String>]?
}

/// Nova Guard: local security monitoring. It alerts and points to the fix;
/// safe, reversible fixes (quarantining a risky startup item, stopping a
/// reverse shell) run automatically; admin fixes only run when the user
/// clicks and enters their password (see GuardActions).
@Observable
@MainActor
final class SecurityMonitor {
    private(set) var checks: [SecurityCheck] = []
    private(set) var score: Int?
    private(set) var alerts: [SecurityAlert] = []
    private(set) var lastScan: Date?
    private(set) var isScanning = false
    private(set) var cameraOn = false
    private(set) var microphoneOn = false

    /// Called for every new alert (the coordinator decides how to surface it).
    @ObservationIgnored var onAlert: ((SecurityAlert) -> Void)?
    @ObservationIgnored let prefs: NovaPreferences
    let actions = GuardActions()

    @ObservationIgnored private var baseline = SecurityBaseline()
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var logProcess: Process?
    @ObservationIgnored private var watchers: [DispatchSourceFileSystemObject] = []
    @ObservationIgnored private var failedLogins = FailedLoginWindow()
    @ObservationIgnored private var seenSessions: Set<String> = []
    @ObservationIgnored private var reportedShellPids: Set<Int32> = []
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    /// Restart delay for the log stream; doubles on quick deaths (max 60 s).
    @ObservationIgnored private var logRestartDelay: Double = 2
    @ObservationIgnored private var logStartedAt = Date.distantPast

    static let startupDirectories = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents").path,
        "/Library/LaunchAgents", "/Library/LaunchDaemons",
    ]

    private static var baselineURL: URL { NovaPathsApp.support.appendingPathComponent("security-baseline.json") }
    private static var alertsURL: URL { NovaPathsApp.support.appendingPathComponent("security-alerts.json") }

    init(prefs: NovaPreferences) {
        self.prefs = prefs
        baseline = (try? Data(contentsOf: Self.baselineURL)).flatMap { try? JSONDecoder().decode(SecurityBaseline.self, from: $0) } ?? SecurityBaseline()
        alerts = (try? Data(contentsOf: Self.alertsURL)).flatMap { try? JSONDecoder().decode([SecurityAlert].self, from: $0) } ?? []
    }

    // MARK: - Lifecycle

    func start() {
        guard prefs.securityEnabled else { return }
        failedLogins = FailedLoginWindow(window: 300, threshold: prefs.failedLoginThreshold)
        tasks.append(Task { [weak self] in
            await self?.establishBaselineIfNeeded()
            await self?.scanPosture()
        })
        // Remote sessions every 15 s; exposed ports every 60 s; accounts every 60 s; posture every 6 h.
        tasks.append(repeating(every: 15) { await $0.checkRemoteSessions() })
        tasks.append(repeating(every: 60) {
            await $0.checkAccounts(); await $0.checkExposedPorts(); await $0.checkStartupItems(); await $0.checkAccessPoints()
        })
        tasks.append(repeating(every: 6 * 3600) { await $0.scanPosture() })
        tasks.append(repeating(every: 3) { await $0.checkCameraAndMicrophone() })
        tasks.append(repeating(every: 15) { await $0.checkProcesses() })
        startAuthLogStream()
        watchDirectories()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.scanPosture(); await self?.checkAccounts() }
        }
        Log.app.info("Nova Guard started")
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        logProcess?.terminate()
        logProcess = nil
        watchers.forEach { $0.cancel() }
        watchers.removeAll()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    func restart() {
        stop()
        start()
    }

    private func repeating(every seconds: Double, _ body: @escaping @MainActor (SecurityMonitor) async -> Void) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard let self, !Task.isCancelled else { return }
                await body(self)
            }
        }
    }

    // MARK: - Posture

    func scanPosture() async {
        guard prefs.securityPosture else { return }
        isScanning = true
        defer { isScanning = false }
        async let fileVault = CommandRunner.run("/usr/bin/fdesetup", ["status"])
        async let firewall = CommandRunner.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])
        async let stealth = CommandRunner.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getstealthmode"])
        async let sip = CommandRunner.run("/usr/bin/csrutil", ["status"])
        async let gatekeeper = CommandRunner.run("/usr/sbin/spctl", ["--status"])
        async let lock = CommandRunner.run("/usr/sbin/sysadminctl", ["-screenLock", "status"])
        async let netstat = CommandRunner.run("/usr/sbin/netstat", ["-anv", "-p", "tcp"])
        let updates = UserDefaults(suiteName: "/Library/Preferences/com.apple.SoftwareUpdate")?
            .object(forKey: "AutomaticallyInstallMacOSUpdates").map { "\($0)" }

        let ports = NetstatParser.listeningPorts(NetstatParser.parse(await netstat))
        let new: [SecurityCheck] = [
            SecurityPosture.fileVault(await fileVault),
            SecurityPosture.firewall(await firewall),
            SecurityPosture.stealthMode(await stealth),
            SecurityPosture.sip(await sip),
            SecurityPosture.gatekeeper(await gatekeeper),
            SecurityPosture.automaticUpdates(updates),
            SecurityPosture.screenLock(await lock),
        ] + SecurityPosture.remoteAccess(listeningPorts: ports)

        // Alert when something got worse since the last scan (e.g. Remote Login turned on).
        for check in new {
            if let old = checks.first(where: { $0.id == check.id }), check.status > old.status, check.status >= .warning {
                raise(SecurityAlert(severity: check.status == .critical ? .critical : .high,
                                    kind: ["ssh", "screensharing", "ard", "filesharing"].contains(check.id) ? .remoteAccessEnabled : .postureChanged,
                                    title: "\(check.title) changed", detail: check.detail, fix: check.fix))
            }
        }
        checks = new
        score = SecurityPosture.score(new)
        lastScan = Date()
    }

    // MARK: - Intrusion

    func checkRemoteSessions() async {
        guard prefs.securityIntrusion else { return }
        let sessions = NetstatParser.remoteSessions(NetstatParser.parse(await CommandRunner.run("/usr/sbin/netstat", ["-anv", "-p", "tcp"])))
        let keys = Set(sessions.map { "\($0.localPort)|\($0.foreignHost)|\($0.foreignPort ?? 0)" })
        for session in sessions {
            let key = "\(session.localPort)|\(session.foreignHost)|\(session.foreignPort ?? 0)"
            guard !seenSessions.contains(key) else { continue }
            let service = NetstatParser.remoteAccessPorts[session.localPort] ?? "Remote access"
            raise(SecurityAlert(severity: .critical, kind: .remoteSession, title: "\(service) connection from \(session.foreignHost)",
                                detail: "Another computer is connected to your Mac right now. If this isn't you, turn the service off.",
                                fix: .sharing))
        }
        seenSessions = keys
    }

    private func startAuthLogStream() {
        guard prefs.securityIntrusion else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--style", "ndjson", "--predicate", AuthLogParser.predicate]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let buffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            for line in buffer.append(handle.availableData) {
                guard let event = AuthLogParser.parse(ndjsonLine: line) else { continue }
                Task { @MainActor in self?.handle(event) }
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Ran for a while: start over quickly. Died fast: back off.
                self.logRestartDelay = Date().timeIntervalSince(self.logStartedAt) > 120 ? 2 : min(self.logRestartDelay * 2, 60)
                try? await Task.sleep(for: .seconds(self.logRestartDelay))
                guard self.prefs.securityEnabled, self.logProcess != nil else { return }
                self.startAuthLogStream()   // restart if it died
            }
        }
        do {
            try process.run()
            logProcess = process
            logStartedAt = Date()
        } catch {
            Log.app.error("Couldn't start the auth log stream")
        }
    }

    func handle(_ event: AuthLogParser.Event) {
        switch event {
        case .sshAccepted(let user, let from):
            raise(SecurityAlert(severity: .critical, kind: .sshLogin, title: "SSH login as \(user) from \(from)",
                                detail: "Someone logged in to your Mac over the network. If this isn't you, turn off Remote Login now.",
                                fix: .sharing))
        case .sshFailed(let user, let from):
            failedLogin(detail: "Failed SSH login as \(user) from \(from)")
        case .screenSharingAuth(let succeeded, _):
            if succeeded {
                raise(SecurityAlert(severity: .critical, kind: .screenSharingAuth, title: "Screen Sharing session started",
                                    detail: "Someone authenticated to view or control your screen.", fix: .sharing))
            } else {
                failedLogin(detail: "Failed Screen Sharing login")
            }
        case .loginFailed(let detail):
            failedLogin(detail: detail)
        case .sudo(let user, let command):
            guard prefs.securitySudoAlerts else { return }
            raise(SecurityAlert(severity: .info, kind: .sudo, title: "Admin command run by \(user)",
                                detail: String(command.prefix(160))))
        }
    }

    private func failedLogin(detail: String) {
        if failedLogins.record(Date()) {
            raise(SecurityAlert(severity: .high, kind: .failedLogins, title: "Repeated failed login attempts",
                                detail: "\(prefs.failedLoginThreshold) failures in 5 minutes. Latest: \(detail.prefix(140))",
                                fix: .lockScreen))
        }
    }

    // MARK: - Accounts, ports, startup items, apps

    private func accountSnapshot() async -> AccountSnapshot {
        AccountSnapshot.parse(usersOutput: await CommandRunner.run("/usr/bin/dscl", [".", "-list", "/Users", "UniqueID"]),
                              adminOutput: await CommandRunner.run("/usr/bin/dscl", [".", "-read", "/Groups/admin", "GroupMembership"]))
    }

    func checkAccounts() async {
        guard prefs.securityIntrusion, let known = baseline.accounts else { return }
        let now = await accountSnapshot()
        guard !now.users.isEmpty else { return }
        for alert in now.alerts(comparedTo: known) where !baseline.accepted.contains(alert.baselineKey ?? "") {
            raise(alert)
        }
        baseline.accounts = AccountSnapshot(users: known.users.union(now.users), admins: known.admins.union(now.admins))
        saveBaseline()
    }

    /// Ports listening on all interfaces (reachable from the network).
    private func exposedPorts() async -> [NetstatParser.Socket] {
        let output = await CommandRunner.run("/usr/sbin/netstat", ["-anv", "-p", "tcp"])
        return NetstatParser.parse(output).filter { socket in
            socket.state == "LISTEN" && output.contains("*.\(socket.localPort) ")
        }
    }

    func checkExposedPorts() async {
        guard prefs.securityPortAlerts else { return }
        let listening = await exposedPorts()
        for socket in listening where !baseline.exposedPorts.contains(socket.localPort) {
            raise(SecurityAlert(severity: .info, kind: .newListeningPort,
                                title: "\(socket.processName ?? "An app") is accepting connections on port \(socket.localPort)",
                                detail: "Other devices on your network can reach this port.", fix: .firewall,
                                baselineKey: "port:\(socket.localPort)"))
        }
        baseline.exposedPorts.formUnion(listening.map(\.localPort))
        saveBaseline()
    }

    private func currentStartupItems() -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for directory in Self.startupDirectories {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory))?.filter { $0.hasSuffix(".plist") } ?? []
            result[directory] = Set(names)
        }
        return result
    }

    private func currentApps() -> Set<String> {
        Set(((try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []).filter { $0.hasSuffix(".app") })
    }

    func checkStartupItems() async {
        guard prefs.securityPersistence else { return }
        let current = currentStartupItems()
        for item in PersistenceDiff.newItems(current: current, baseline: baseline.startupItems) {
            let path = "\(item.directory)/\(item.name)"
            let program = (try? Data(contentsOf: URL(fileURLWithPath: path))).flatMap(PersistenceDiff.program(fromPlist:)) ?? "unknown program"
            let isDaemon = item.directory.hasSuffix("LaunchDaemons")
            if prefs.securityAutoFix, await isRiskyStartupProgram(program),
               let action = await actions.quarantineLaunchAgent(at: path, reason: "Runs \(program.prefix(120))") {
                raise(SecurityAlert(severity: .high, kind: .newStartupItem, title: "Blocked a risky startup item: \(item.name)",
                                    detail: "It would run \(program) every time you log in. Nova unloaded it and moved it to quarantine. Undo in Nova Guard if it was yours.",
                                    fix: .loginItems, path: action.undo == .none ? nil : Self.quarantinePath(of: action), baselineKey: nil))
                continue
            }
            raise(SecurityAlert(severity: isDaemon ? .high : .info, kind: .newStartupItem,
                                title: "New startup item: \(item.name)",
                                detail: "Runs \(program) \(isDaemon ? "as root at boot" : "when you log in"). If you don't recognize it, remove it.",
                                fix: .loginItems, path: path, baselineKey: "startup:\(path)"))
        }
        for (directory, names) in current { baseline.startupItems[directory, default: []].formUnion(names) }

        let apps = currentApps()
        for app in apps.subtracting(baseline.apps).sorted() {
            let path = "/Applications/\(app)"
            let verdict = await CommandRunner.run("/usr/sbin/spctl", ["-a", "-t", "exec", "-vv", path], timeout: 20)
            if !verdict.contains("accepted") {
                raise(SecurityAlert(severity: .high, kind: .unsignedApp, title: "Unverified app installed: \(app)",
                                    detail: "macOS couldn't verify who made this app. Only open it if you trust where it came from.",
                                    fix: .privacySecurity, path: path, baselineKey: "app:\(app)"))
            }
        }
        baseline.apps.formUnion(apps)
        saveBaseline()
    }

    /// Unsigned binaries, scripts from temp/Downloads/hidden folders, or
    /// command lines that fetch and run code.
    private func isRiskyStartupProgram(_ program: String) async -> Bool {
        if TextDiff.looksRisky(program) || AutoFixPolicy.agentDenyReason(command: program) != nil { return true }
        let binary = program.split(separator: " ").first.map(String.init) ?? program
        if ["/tmp/", "/private/tmp/", "/var/folders/", "/Downloads/", "/Users/Shared/"].contains(where: binary.contains) { return true }
        if binary.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { return true }
        guard FileManager.default.fileExists(atPath: binary) else { return false }
        let verify = await CommandRunner.runWithStatus("/usr/bin/codesign", ["--verify", binary], timeout: 10)
        return verify.status != 0 && verify.output.contains("not signed")
    }

    private static func quarantinePath(of action: GuardAction) -> String? {
        if case .restoreLaunchAgent(_, let quarantined) = action.undo { return quarantined }
        return nil
    }

    // MARK: - Reverse shells

    /// Scans the user's own processes for reverse shells and stops them.
    func checkProcesses() async {
        guard prefs.securityIntrusion else { return }
        let output = await CommandRunner.run("/bin/ps", ["-U", "\(getuid())", "-o", "pid=,command="], timeout: 5)
        for process in ProcessListParser.parse(output) where AutoFixPolicy.isReverseShell(command: process.command)
            && !reportedShellPids.contains(process.pid) {
            reportedShellPids.insert(process.pid)
            let stopped = prefs.securityAutoFix ? actions.terminate(pid: process.pid, command: process.command) : nil
            raise(SecurityAlert(severity: .critical, kind: .reverseShell,
                                title: stopped != nil ? "Stopped a reverse shell" : "Reverse shell running",
                                detail: "A process was giving remote control of this Mac to another computer: \(process.command.prefix(140))\(stopped != nil ? ". Nova stopped it." : ". Stop it in Activity Monitor (pid \(process.pid)).")",
                                baselineKey: nil))
        }
    }

    // MARK: - SSH keys, profiles, cron, sudoers, shell startup files

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path
    private static let shellFiles = [".zshrc", ".zprofile", ".zshenv", ".bash_profile", ".bashrc"].map { "\(home)/\($0)" }
    private static let authorizedKeysPath = "\(home)/.ssh/authorized_keys"

    private struct AccessPoints {
        var sshKeys: [String: AuthorizedKeys.Key]
        var profiles: Set<String>
        var cronLines: Set<String>
        var sudoersFiles: Set<String>
        var shellFiles: [String: [String]]   // meaningful lines, kept in memory only
    }

    private static func hash(_ line: String) -> String {
        SHA256.hash(data: Data(line.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func currentAccessPoints() async -> AccessPoints {
        let keysText = (try? String(contentsOfFile: Self.authorizedKeysPath, encoding: .utf8)) ?? ""
        let keys = Dictionary(AuthorizedKeys.parse(keysText).map { (AuthorizedKeys.identity($0), $0) }, uniquingKeysWith: { a, _ in a })
        let profiles = ProfilesParser.identifiers(from: await CommandRunner.run("/usr/bin/profiles", ["list"]))
        let cron = await CommandRunner.run("/usr/bin/crontab", ["-l"])
        let cronLines = cron.contains("no crontab") ? [] : Set(TextDiff.addedLines(old: "", new: cron))
        let sudoers = Set((try? FileManager.default.contentsOfDirectory(atPath: "/etc/sudoers.d")) ?? [])
        var shell: [String: [String]] = [:]
        for path in Self.shellFiles {
            shell[path] = TextDiff.addedLines(old: "", new: (try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
        }
        return AccessPoints(sshKeys: keys, profiles: profiles, cronLines: cronLines, sudoersFiles: sudoers, shellFiles: shell)
    }

    func checkAccessPoints() async {
        guard prefs.securityPersistence || prefs.securityIntrusion else { return }
        let now = await currentAccessPoints()
        guard let knownKeys = baseline.sshKeys, let knownProfiles = baseline.profiles, let knownCron = baseline.cronLines,
              let knownSudoers = baseline.sudoersFiles, let knownShell = baseline.shellLineHashes else {
            remember(now)
            return
        }
        for (id, key) in now.sshKeys where !knownKeys.contains(id) {
            raise(SecurityAlert(severity: .critical, kind: .newSSHKey, title: "New SSH key can log in to your Mac",
                                detail: "A \(key.type) key\(key.comment.isEmpty ? "" : " (\(key.comment))") was added to ~/.ssh/authorized_keys. If you didn't add it, remove it and turn off Remote Login.",
                                fix: .sharing, path: Self.authorizedKeysPath, baselineKey: "ssh:\(id)"))
        }
        for profile in now.profiles.subtracting(knownProfiles).sorted() {
            raise(SecurityAlert(severity: .high, kind: .newProfile, title: "New configuration profile: \(profile)",
                                detail: "Profiles can change network, certificate and security settings. Remove it in System Settings → General → Device Management unless you installed it.",
                                fix: .deviceManagement, baselineKey: "profile:\(profile)"))
        }
        let newCron = now.cronLines.subtracting(knownCron)
        if let first = newCron.sorted().first {
            raise(SecurityAlert(severity: .high, kind: .newScheduledJob, title: "New scheduled job (cron)",
                                detail: "\(newCron.count) new line\(newCron.count == 1 ? "" : "s") in your crontab, e.g. “\(first.prefix(80))”. Check it with `crontab -l`.",
                                baselineKey: "cron:\(first)"))
        }
        for file in now.sudoersFiles.subtracting(knownSudoers).sorted() {
            raise(SecurityAlert(severity: .high, kind: .newScheduledJob, title: "New admin rule: /etc/sudoers.d/\(file)",
                                detail: "This can let a user or program run commands as root without a password.",
                                path: "/etc/sudoers.d/\(file)", baselineKey: "sudoers:\(file)"))
        }
        for (path, lines) in now.shellFiles {
            let known = knownShell[path] ?? []
            let added = lines.filter { !known.contains(Self.hash($0)) }
            guard let first = added.first else { continue }
            let risky = added.contains(where: TextDiff.looksRisky)
            let name = (path as NSString).lastPathComponent
            raise(SecurityAlert(severity: risky ? .high : .info, kind: .shellStartupChanged,
                                title: risky ? "Suspicious line added to \(name)" : "\(name) changed",
                                detail: "\(added.count) new line\(added.count == 1 ? "" : "s"): “\((added.first(where: TextDiff.looksRisky) ?? first).prefix(90))”. It runs every time you open a terminal.",
                                path: path, baselineKey: nil))
        }
        remember(now)
    }

    private func remember(_ points: AccessPoints) {
        // Keys and profiles stay "known" once seen; removed ones don't matter.
        baseline.sshKeys = (baseline.sshKeys ?? []).union(points.sshKeys.keys)
        baseline.profiles = (baseline.profiles ?? []).union(points.profiles)
        baseline.cronLines = points.cronLines
        baseline.sudoersFiles = (baseline.sudoersFiles ?? []).union(points.sudoersFiles)
        baseline.shellLineHashes = points.shellFiles.mapValues { Set($0.map(Self.hash)) }
        saveBaseline()
    }

    private func watchDirectories() {
        for path in Self.startupDirectories + ["/Applications"] {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .rename], queue: .main)
            source.setEventHandler { [weak self] in
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))   // let the copy/installer finish
                    await self?.checkStartupItems()
                }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            watchers.append(source)
        }
    }

    // MARK: - Camera & microphone

    func checkCameraAndMicrophone() async {
        guard prefs.securityCameraMic else { return }
        // Device queries run off the main thread (see `HardwareRunLoops`).
        let (camera, micPIDs) = await withCheckedContinuation { continuation in
            HardwareRunLoops.queue.async { continuation.resume(returning: (Self.isCameraRunning(), Self.microphoneUsers())) }
        }
        let microphone = !micPIDs.isEmpty
        // Only report a change that lasts two checks (~6 s): apps and macOS
        // services open the mic for a moment all the time.
        if camera != cameraOn {
            cameraSeen += 1
            if cameraSeen >= 2 {
                cameraOn = camera
                cameraSeen = 0
                if camera { raise(SecurityAlert(severity: .info, kind: .camera, title: "Camera turned on", detail: "An app started using your camera.")) }
            }
        } else {
            cameraSeen = 0
        }
        if microphone != microphoneOn {
            micSeen += 1
            if micSeen >= 2 {
                microphoneOn = microphone
                micSeen = 0
                if microphone { announceMicrophone(pids: micPIDs) }
            }
        } else {
            micSeen = 0
        }
    }

    @ObservationIgnored private var cameraSeen = 0
    @ObservationIgnored private var micSeen = 0
    /// When each app was last announced, so a call app isn't announced again and again.
    @ObservationIgnored private var micAnnounced: [String: Date] = [:]

    /// "Zoom started using your microphone." Each app at most once every 10 minutes;
    /// "turned off" is never announced.
    private func announceMicrophone(pids: [pid_t]) {
        let names = Array(Set(pids.map { NSRunningApplication(processIdentifier: $0)?.localizedName ?? "An app" })).sorted()
        let now = Date()
        let fresh = names.filter { now.timeIntervalSince(micAnnounced[$0] ?? .distantPast) > 600 }
        guard !fresh.isEmpty else { return }
        for name in fresh { micAnnounced[name] = now }
        let who = fresh.count == 1 ? fresh[0] : fresh.dropLast().joined(separator: ", ") + " and " + fresh.last!
        raise(SecurityAlert(severity: .info, kind: .microphone, title: "Microphone turned on",
                            detail: "\(who) started using your microphone."))
    }

    /// True when another process is recording audio input. Asks CoreAudio per
    /// process (macOS 14+), so audio output — including Nova's own sounds on a
    /// headset that is both mic and speaker — never counts as the microphone.
    nonisolated static func isMicrophoneRunning() -> Bool { !microphoneUsers().isEmpty }

    /// macOS speech services ("Hey Siri", dictation, and the on-device
    /// recognizer Nova's own voice uses). They switch the mic on and off by
    /// themselves, so they never count as another app recording.
    nonisolated static let systemSpeechBundles: Set<String> = [
        "com.apple.CoreSpeech", "com.apple.corespeechd", "com.apple.assistantd", "com.apple.Siri", "com.apple.siri",
        "com.apple.SiriNCService", "com.apple.voicetrigger", "com.apple.speech.speechrecognitiond",
        "com.apple.SpeechRecognitionCore.speechrecognitiond", "com.apple.localspeechrecognition", "com.apple.DictationIM",
        "com.apple.accessibility.heard",
    ]

    /// Processes other than Nova (and macOS speech services) recording audio input.
    nonisolated static func microphoneUsers() -> [pid_t] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &processes) == noErr else { return [] }
        let me = getpid()
        var users: [pid_t] = []
        for process in processes {
            var pidAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                                        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            if AudioObjectGetPropertyData(process, &pidAddress, 0, nil, &pidSize, &pid) == noErr, pid == me { continue }
            var inputAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput,
                                                          mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(process, &inputAddress, 0, nil, &runningSize, &running) == noErr, running != 0 else { continue }
            var bundleAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var bundle: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(process, &bundleAddress, 0, nil, &bundleSize, &bundle) == noErr,
               let id = bundle?.takeRetainedValue() as String?,
               systemSpeechBundles.contains(id) || id.lowercased().hasPrefix("com.apple.siri") { continue }
            users.append(pid)
        }
        return users
    }

    nonisolated static func isCameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0, size > 0 else { return false }
        var devices = [CMIODeviceID](repeating: 0, count: Int(size) / MemoryLayout<CMIODeviceID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == 0 else { return false }
        address.mSelector = CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
        for device in devices {
            var running: UInt32 = 0
            var got: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &running) == 0, running != 0 {
                return true
            }
        }
        return false
    }

    // MARK: - Alerts & baseline

    private func raise(_ alert: SecurityAlert) {
        if let key = alert.baselineKey, baseline.accepted.contains(key) { return }
        alerts.insert(alert, at: 0)
        alerts = Array(alerts.prefix(50))
        saveAlerts()
        Log.app.notice("Security alert: \(alert.title, privacy: .public)")
        onAlert?(alert)
    }

    /// "This was me": stop alerting about this item.
    func accept(_ alert: SecurityAlert) {
        if let key = alert.baselineKey { baseline.accepted.insert(key) }
        alerts.removeAll { $0.id == alert.id }
        saveAlerts()
        saveBaseline()
    }

    func clearAlerts() {
        alerts.removeAll()
        saveAlerts()
    }

    /// Re-learns what's normal (accounts, startup items, apps, open ports).
    func resetBaseline() async {
        baseline = SecurityBaseline()
        await establishBaselineIfNeeded()
    }

    private func establishBaselineIfNeeded() async {
        if baseline.accounts == nil { baseline.accounts = await accountSnapshot() }
        if baseline.startupItems.isEmpty { baseline.startupItems = currentStartupItems() }
        if baseline.apps.isEmpty { baseline.apps = currentApps() }
        if baseline.exposedPorts.isEmpty { baseline.exposedPorts = Set(await exposedPorts().map(\.localPort)) }
        saveBaseline()
    }

    private func saveBaseline() {
        try? FileManager.default.createDirectory(at: NovaPathsApp.support, withIntermediateDirectories: true)
        try? JSONEncoder().encode(baseline).write(to: Self.baselineURL, options: .atomic)
    }

    private func saveAlerts() {
        try? FileManager.default.createDirectory(at: NovaPathsApp.support, withIntermediateDirectories: true)
        try? JSONEncoder().encode(alerts).write(to: Self.alertsURL, options: .atomic)
    }

    #if DEBUG
    func loadPreview() {
        checks = [
            SecurityPosture.fileVault("FileVault is On."), SecurityPosture.firewall("Firewall is enabled. (State = 1)"),
            SecurityPosture.stealthMode("Firewall stealth mode is off"), SecurityPosture.sip("System Integrity Protection status: enabled."),
            SecurityPosture.gatekeeper("assessments enabled"), SecurityPosture.automaticUpdates("1"),
            SecurityPosture.screenLock("screenLock delay is 300 seconds"),
        ] + SecurityPosture.remoteAccess(listeningPorts: [])
        score = SecurityPosture.score(checks)
        lastScan = Date()
        alerts = [
            SecurityAlert(severity: .critical, kind: .remoteSession, title: "Remote Login (SSH) connection from 203.0.113.9",
                          detail: "Another computer is connected to your Mac right now.", fix: .sharing),
            SecurityAlert(severity: .info, kind: .camera, title: "Camera turned on", detail: "An app started using your camera."),
        ]
    }
    #endif
}
