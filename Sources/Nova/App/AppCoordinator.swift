import AppKit
import NovaKit
import SwiftUI

/// Wires services, the notch window and app state together, and owns all
/// hover / click / sleep behaviour and reactions to agent events.
@Observable
@MainActor
final class AppCoordinator {
    let state = AppState()
    let cursor = CursorTrackingService()
    let sound = SoundService()
    let sessions = AgentSessionManager()
    let permissions = PermissionManager()
    let ai: AIService
    let chat: ChatViewModel
    let google: GoogleAuth
    let automations: AutomationStore
    let brief: BriefService
    let whatsapp: WhatsAppService
    let integrations: IntegrationManager
    let launcher = AppLauncherService()
    let spotify = SpotifyService()
    let music = MusicTapService()
    let voice = VoiceService()
    let calendar = CalendarService()
    let routines = RoutineStore()
    let shortcuts = ShortcutsService()
    let usage = UsageService()
    @ObservationIgnored private var nudged: Set<String> = []
    @ObservationIgnored private var talkKey: GlobalHotKey?
    @ObservationIgnored private var wakeGate: Task<Void, Never>?
    let prefs: NovaPreferences
    let notifications = NotificationService()
    let security: SecurityMonitor
    var settingsSection: SettingsSection = .ai
    /// Non-nil when Nova couldn't start listening for agents.
    var agentSocketError: String?
    /// A risky voice action (pressing "Send", "Delete"…) waiting for a mouse click.
    var pendingVoiceAction: PendingVoiceAction? {
        didSet { if let id = pendingVoiceAction?.id { expirePendingVoiceAction(id) } }
    }
    /// Set when another AI provider answered a voice question because the default one was busy.
    var lastVoiceProvider: AIProviderKind?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored var confirmListens = 0
    /// The last "check my system" result, shown at the top of Nova Guard.
    var lastSystemReport: SystemReport?
    /// The plan Nova is working through ("get my work day ready").
    var activePlan: VoicePlan?
    /// Files from the last search ("open the second one").
    @ObservationIgnored var lastFileResults: [URL] = []
    /// Recent voice questions and answers, sent with the next question.
    @ObservationIgnored var voiceHistory: [(question: String, answer: String, at: Date)] = []
    /// Follow-ups asked in a row (at most 3), and whether the last reply allows one.
    @ObservationIgnored var followUps = 0
    @ObservationIgnored var followUpAllowed = false

    @ObservationIgnored private(set) var window: NotchWindowController?
    @ObservationIgnored private let settingsWindow = SettingsWindowController()
    @ObservationIgnored private let onboardingWindow = OnboardingWindowController()
    @ObservationIgnored private var server: AgentEventServer?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var promoteTask: Task<Void, Never>?
    @ObservationIgnored private var expressionTask: Task<Void, Never>?
    @ObservationIgnored private var tapCounter = RapidTapCounter()
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var sleepWatch: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var briefWatch: Task<Void, Never>?
    @ObservationIgnored private var lastActivity = Date()
    /// Activity-triggered compact strips stay up at least until this time.
    @ObservationIgnored private var compactPinnedUntil = Date.distantPast
    @ObservationIgnored private var keyMonitor: Any?
    /// A banner that arrived while you were talking to Nova; shown afterwards.
    @ObservationIgnored private var deferredBanner: (NotchBanner, Duration)?
    @ObservationIgnored private var mouseDownMonitor: Any?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var powerObservers: [NSObjectProtocol] = []

    /// Preferences-derived style plus the global pause state.
    // MARK: - Voice

    private func startVoice() {
        applyVoicePrefs()
        voice.onCommand = { [weak self] text in Task { await self?.handleVoice(text) } }
        voice.onFinished = { [weak self] in self?.voiceFinished() }
        voice.onWake = { [weak self] in self?.showVoicePanel() }
        wakeGate = Task { [weak self] in await self?.gateWakeWord() }
        // Hold ⌥ Space to talk; release to send.
        talkKey = GlobalHotKey(onPress: { [weak self] in self?.beginTalking() },
                               onRelease: { [weak self] in self?.voice.finishListening() })
        // "Hey Safari" works for apps installed on this Mac (list refreshed every 10 min).
        Task { [weak self] in
            while !Task.isCancelled {
                let apps = await Task.detached(priority: .utility) { MacActions.installedApps() }.value
                self?.voice.appNames = apps
                try? await Task.sleep(for: .seconds(600))
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            self?.voicePreflight()
        }
    }

    /// Every minute: a banner 5 minutes before a meeting, with its join link.
    /// Only once Calendar access was given (Nova never asks on its own here).
    private func startMeetingNudges() {
        Task { [weak self] in
            while !Task.isCancelled {
                if let self, self.prefs.meetingNudges, self.calendar.eventsAllowed {
                    let now = Date()
                    let soon = await self.calendar.events(from: now, to: now.addingTimeInterval(6 * 60))
                    for event in soon where !event.allDay && event.start > now {
                        let key = "\(event.title)|\(event.start.timeIntervalSince1970)"
                        guard !self.nudged.contains(key) else { continue }
                        self.nudged.insert(key)
                        let minutes = max(1, Int(event.start.timeIntervalSince(now) / 60))
                        self.sound.play(.notification)
                        self.showBanner(NotchBanner(title: "\(event.title) in \(minutes) min",
                                                    subtitle: event.joinURL != nil ? "Click to join." : "Starts at \(event.start.formatted(date: .omitted, time: .shortened)).",
                                                    expression: .notification, action: event.joinURL.map { .openURL($0) }), for: .seconds(15))
                    }
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Once: offer "Hey Nova" (an always-on mic needs your OK). And if it's on
    /// but macOS hasn't allowed the mic yet, say how to fix that.
    private func voicePreflight() {
        guard prefs.voiceEnabled, prefs.onboardingDone else { return }
        let asked = "pref.wakeWordOffered"
        if !prefs.voiceWakeWord, !UserDefaults.standard.bool(forKey: asked) {
            UserDefaults.standard.set(true, forKey: asked)
            showBanner(NotchBanner(title: "Turn on “Hey Nova”?", subtitle: "Click here. Nova listens on your Mac only; nothing is recorded.",
                                   expression: .listening, action: .enableWakeWord), for: .seconds(12))
        } else if prefs.voiceWakeWord, !VoiceService.permissionsGranted {
            showBanner(NotchBanner(title: "“Hey Nova” needs the microphone", subtitle: "Click here, then click Allow for Microphone and Speech Recognition.",
                                   expression: .listening, action: .openVoiceSettings), for: .seconds(12))
        }
    }

    /// Pauses "Hey Nova" while the screen is locked/asleep, Nova is hidden, or
    /// another app is using the microphone (a call or recording).
    private func gateWakeWord() async {
        while !Task.isCancelled {
            if prefs.voiceEnabled && prefs.voiceWakeWord {
                let othersRecording = await withCheckedContinuation { c in
                    HardwareRunLoops.queue.async { c.resume(returning: SecurityMonitor.isMicrophoneRunning()) }
                }
                voice.setWakeAllowed(state.isOnScreen && state.isVisible && !othersRecording)
            }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    func applyVoicePrefs() {
        voice.speakReplies = prefs.voiceSpeakReplies
        voice.rate = Float(prefs.voiceRate)
        voice.language = prefs.voiceLanguage
        voice.setWakeWord(enabled: prefs.voiceEnabled && prefs.voiceWakeWord)
    }

    /// Mic button or ⌥ Space.
    func beginTalking(autoStop: Bool = false) {
        guard prefs.voiceEnabled else { return }
        showVoicePanel()
        voice.startListening(autoStop: autoStop)
    }

    /// Mic button: click to start (it stops by itself after a pause), click again to send now.
    func toggleTalking() {
        if voice.phase == .listening, state.notchState == .voice {
            voice.finishListening()
        } else {
            beginTalking(autoStop: true)
        }
    }

    func showVoicePanel() {
        if !state.isVisible { toggleVisibility() }
        if state.notchState == .voice { return }
        if state.notchState == .permissionRequest { return }
        if state.notchState != .idle { transition(to: .idle, animated: false) }
        transition(to: .voice)
    }

    /// A reply finished. Keep listening a few seconds for a follow-up (no
    /// "Hey Nova" needed), up to 3 in a row; silence closes the panel.
    func voiceFinished() {
        if pendingVoiceAction != nil || activePlan != nil { closeVoice(); return }
        if voice.lastDeliveredEmpty || !followUpAllowed || !prefs.voiceFollowUps || followUps >= 3 || state.notchState != .voice {
            followUps = 0
            followUpAllowed = false
            closeVoice()
            return
        }
        followUps += 1
        followUpAllowed = false
        voice.startListening(autoStop: true, quietLimit: 6)
    }

    /// Runs the waiting action (a click on its button, or "send" for messages).
    func confirmVoiceAction() {
        guard let action = pendingVoiceAction else { return }
        pendingVoiceAction = nil
        confirmListens = 0
        Task {
            await action.run()
            closeVoice()
        }
    }

    /// The × button: stop everything.
    func cancelVoiceAction() {
        followUps = 0
        followUpAllowed = false
        dismissPendingVoiceAction()
        voice.cancel()
        closeVoice()
    }

    /// Drops the waiting action without running it.
    func dismissPendingVoiceAction() {
        guard let action = pendingVoiceAction else { return }
        pendingVoiceAction = nil
        confirmListens = 0
        action.onCancel?()
    }

    private func expirePendingVoiceAction(_ id: UUID) {
        let seconds = pendingVoiceAction?.expiresAfter ?? 20
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.pendingVoiceAction?.id == id else { return }
            self.dismissPendingVoiceAction()
            if self.voice.phase == .listening { self.voice.cancel() }
            self.closeVoice()
        }
    }

    /// One timer at a time; a new one replaces the old.
    func startTimer(seconds: Int) {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            let label = AppCoordinator.spoken(seconds: seconds)
            self.sound.play(.taskDone)
            self.showBanner(NotchBanner(title: "Timer done", subtitle: "Your \(label) timer is done.", expression: .excited), for: .seconds(8))
            if self.prefs.voiceSpeakReplies, self.voice.phase == .idle { self.voice.announce("Your \(label) timer is done.") }
        }
    }

    func closeVoice() {
        // Keep the panel open while something waits for confirmation. For a
        // message, listen for "send" or "cancel" once the read-back is spoken.
        if let pending = pendingVoiceAction {
            if pending.voiceConfirm, confirmListens < 2, voice.phase == .idle {
                confirmListens += 1
                voice.startListening(autoStop: true)
            }
            return
        }
        state.voiceExpression = nil
        if state.notchState == .voice { transition(to: hasActivity ? .compact : .idle) }
        if let (banner, duration) = deferredBanner {
            deferredBanner = nil
            showBanner(banner, for: duration)
        }
    }

    /// What Nova 2 reacts to: agent work, waiting approvals, Guard alerts and music.
    var liveContext: NovaLiveContext {
        var context = NovaLiveContext()
        let now = Date()
        if let latest = sessions.state.sessions.values.map(\.lastEventAt).max() {
            // Busy agents send events every few seconds; activity fades over 8 s of quiet.
            context.agentActivity = min(max(1 - now.timeIntervalSince(latest) / 8, 0.1), 1)
        }
        context.approvalSince = permissions.pending.filter { !$0.isQuestion }.map(\.receivedAt).min()
        context.guardAlert = security.alerts.contains { $0.severity >= .high && now.timeIntervalSince($0.date) < 90 }
        context.music = music
        return context
    }

    var style: NovaStyle {
        var style = prefs.style
        style.paused = !state.isVisible || !state.isOnScreen
        return style
    }

    private static let hoverToCompactDelay: Duration = .milliseconds(350)
    private static let collapseDelay: Duration = .milliseconds(250)
    private static let expandedCollapseDelay: Duration = .milliseconds(700)
    private static let activityStripDuration: TimeInterval = 3
    private static let sleepAfter: TimeInterval = 90

    init() {
        let prefs = NovaPreferences()
        self.prefs = prefs
        security = SecurityMonitor(prefs: prefs)
        ai = AIService()
        chat = ChatViewModel(ai: ai)
        google = GoogleAuth()
        automations = AutomationStore()
        brief = BriefService(google: google, ai: ai)
        whatsapp = WhatsAppService(settings: automations, ai: ai)
        integrations = IntegrationManager(google: google)
    }

    var hasActivity: Bool { state.agents.contains { $0.status.isLive } }

    var compactSummary: String {
        let agent = state.focusedAgent
        return "\(agent.name) · \(agent.detail)"
    }

    // MARK: - Lifecycle

    #if DEBUG
    /// Landing-video demo: only the notch window. No socket, automations,
    /// security monitor, notifications, music, Spotify control or microphone.
    func startDemo() {
        let controller = NotchWindowController(rootView: NotchRootView(coordinator: self))
        window = controller
        controller.reposition()
        state.geometry = controller.geometry
        state.panelScale = prefs.panelSize.scale
        controller.setInteractive(false)
        controller.show()
        transition(to: .idle, animated: false)
    }
    #endif

    func start() {
        let controller = NotchWindowController(rootView: NotchRootView(coordinator: self))
        window = controller
        controller.screenChoice = prefs.screen
        controller.reposition()
        state.geometry = controller.geometry
        state.panelScale = prefs.panelSize.scale

        cursor.onMove = { [weak self] point in self?.mouseMoved(to: point) }
        cursor.onOutsideClick = { [weak self] point in self?.outsideClick(at: point) }
        cursor.start()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screenChanged() }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) == true ? nil : event
        }
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.lastMouseDownAt = event.timestamp
            return event
        }

        HardwareRunLoops.configure()
        observePower()
        startSecurity()
        Task { await ai.probeLocalServers() }
        startAgents()
        startAutomations()
        startIntegrations()
        startNotifications()
        launcher.start()
        spotify.onPlayingChanged = { [weak self] playing in self?.music.spotifyPlaying = playing }
        spotify.start()
        music.enabled = prefs.danceToMusic && prefs.characterStyle == "nova2"
        music.start()
        startVoice()
        startMeetingNudges()
        usage.onAlert = { [weak self] source, level, summary in
            let name = UsageService.name(source)
            let reset = summary.blockEnd?.formatted(date: .omitted, time: .shortened) ?? "soon"
            let body = "\(Int((summary.blockFraction ?? level) * 100))% of your 5-hour window. Resets at \(reset)."
            self?.sound.play(.notification)
            self?.showBanner(NotchBanner(title: "\(name) usage: \(Int(level * 100))%", subtitle: body, expression: level >= 0.95 ? .warning : .notification), for: .seconds(10))
            self?.notify(.integrationAlert, title: "\(name) usage \(Int(level * 100))%", body: body)
        }
        usage.start()
        transition(to: .idle, animated: false)
        if !prefs.onboardingDone {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                self?.showOnboarding()
            }
        }
        if prefs.startHidden {
            state.isVisible = false
            transition(to: .hidden, animated: false)
        } else {
            controller.show()
        }
        startSleepWatch()
    }

    private func startAgents() {
        sessions.onEvent = { [weak self] event, session in self?.agentEvent(event, session) }
        permissions.onResolved = { [weak self] request in self?.permissionResolved(request) }
        permissions.guardCheck = { [weak self] request in self?.guardDenyReason(for: request) }
        permissions.onGuardDenied = { [weak self] request, reason in
            guard let self else { return }
            self.sessions.approvalResolved(request)
            let project = request.workingDirectory.map { " in \(URL(fileURLWithPath: $0).lastPathComponent)" } ?? ""
            self.securityAlert(SecurityAlert(severity: .high, kind: .agentBlocked,
                                             title: "Blocked: \(request.agent.displayName) tried something risky",
                                             detail: "\(request.command ?? request.tool)\(project). Reason: \(reason)."))
        }
        let server = AgentEventServer(sessions: sessions, permissions: permissions)
        sessions.start()
        for kind in prefs.disabledAgents { sessions.setEnabled(kind, false) }
        server.start()
        self.server = server
        agentSocketError = server.lastError
        if let error = server.lastError {
            showBanner(NotchBanner(title: "Agent connection unavailable", subtitle: error, expression: .error), for: .seconds(8))
        }
        refreshAgents()

        // Keeps elapsed times fresh while something is running.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.hasActivity || self.state.notchState.isExpanded else { continue }
                self.refreshAgents()
            }
        }
    }

    private func startAutomations() {
        whatsapp.onDraft = { [weak self] draft in
            self?.notify(.whatsappDraft, title: "New message from \(draft.contact.name)", body: "Suggested reply: \(draft.draft)")
            self?.showBanner(NotchBanner(title: "New message from \(draft.contact.name)",
                                         subtitle: "“\(draft.incoming.prefix(60))” · Suggested reply ready",
                                         expression: .typing, action: .reviewAutomations), for: .seconds(8))
        }
        whatsapp.onGreetingsScheduled = { [weak self] count in
            self?.showBanner(NotchBanner(title: "Morning messages scheduled",
                                         subtitle: "\(count) \(count == 1 ? "message sends" : "messages send") in 5 minutes. Click to review.",
                                         expression: .happy, action: .reviewAutomations), for: .seconds(10))
        }
        whatsapp.onStatus = { [weak self] message, ok in
            if ok, message.hasPrefix("Sent") { self?.sound.play(.sent) }
            self?.showBanner(NotchBanner(title: ok ? "WhatsApp" : "WhatsApp problem", subtitle: message,
                                         expression: ok ? .success : .error))
        }
        whatsapp.onScheduledSoon = { [weak self] item in
            self?.showBanner(NotchBanner(title: "Sending to \(item.name) in a minute", subtitle: "“\(item.text.prefix(60))” · Click to review or cancel.",
                                         expression: .typing, action: .reviewAutomations), for: .seconds(12))
        }
        whatsapp.start()

        briefWatch = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkMorningBrief()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func checkMorningBrief() async {
        let data = automations.data
        guard data.briefEnabled, google.isSignedIn,
              data.briefSchedule.isDue(now: Date(), lastRunDay: data.lastBriefDay) else { return }
        automations.data.lastBriefDay = MorningSchedule.dayKey(Date())
        await brief.refresh()
        let overview = brief.mail?.overview ?? "Your mail, LinkedIn and YouTube are ready."
        notify(.morningBrief, title: "Morning brief ready", body: overview)
        showBanner(NotchBanner(title: "Morning brief ready", subtitle: overview,
                               expression: .happy, action: .openBrief), for: .seconds(10))
    }

    /// Pauses all animation while the display sleeps or the Mac is locked.
    private func observePower() {
        let center = NSWorkspace.shared.notificationCenter
        let off: [Notification.Name] = [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification]
        let on: [Notification.Name] = [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification]
        for (names, value) in [(off, false), (on, true)] {
            for name in names {
                powerObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.state.isOnScreen = value }
                })
            }
        }
        let locked = DistributedNotificationCenter.default()
        for (name, value) in [("com.apple.screenIsLocked", false), ("com.apple.screenIsUnlocked", true)] {
            powerObservers.append(locked.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.state.isOnScreen = value }
            })
        }
    }

    // MARK: - Onboarding, demo, reset

    func showOnboarding() {
        onboardingWindow.show(coordinator: self)
    }

    func finishOnboarding() {
        prefs.onboardingDone = true
        onboardingWindow.close()
        if !state.isVisible { toggleVisibility() }
        open()
    }

    /// Plays a short fake Claude Code session so the user can see what Nova does.
    func runDemoSession() {
        let id = "demo-\(Int(Date().timeIntervalSince1970))"
        let cwd = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects/demo").path
        let steps: [(Double, AgentEvent.Kind, String?, String?)] = [
            (0, .sessionStart, nil, nil),
            (0.8, .prompt, nil, "Add a dark mode toggle to the settings page"),
            (2.0, .toolStart, "Read", "Reading SettingsView.swift"),
            (3.2, .toolEnd, "Read", nil),
            (3.6, .toolStart, "Edit", "Editing SettingsView.swift"),
            (5.4, .toolEnd, "Edit", nil),
            (5.8, .toolStart, "Bash", "Running swift test"),
            (8.5, .toolEnd, "Bash", nil),
            (9.0, .stop, nil, nil),
        ]
        for (delay, kind, tool, text) in steps {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.sessions.ingest(AgentEvent(agent: .claude, sessionId: id, event: kind, tool: tool, description: text,
                                                 workingDirectory: cwd, host: "terminal"))
            }
        }
    }

    /// Removes all Nova data (settings, history, automations, secrets) and relaunches.
    func resetAppData() {
        KeychainManager.shared.deleteAll()
        prefs.resetAll()
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("ai.") || key.hasPrefix("launcher.") || key.hasPrefix("integrations.")
            || ["soundsMuted", "soundVolume", "interfaceSounds", "reactionSounds"].contains(key) {
            defaults.removeObject(forKey: key)
        }
        for file in ["chat-history.json", "automations.json"] {
            try? FileManager.default.removeItem(at: NovaPathsApp.support.appendingPathComponent(file))
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"\(Bundle.main.bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: - Preferences & notifications

    /// Re-applies preferences that need more than a view refresh.
    func applyPreferences() {
        state.panelScale = prefs.panelSize.scale
        if window?.screenChoice != prefs.screen {
            window?.screenChoice = prefs.screen
            screenChanged()
        }
        for kind in AgentKind.allCases { sessions.setEnabled(kind, !prefs.disabledAgents.contains(kind)) }
    }

    private func startNotifications() {
        notifications.start()
        notifications.onPermissionAction = { [weak self] requestId, allow in
            guard let self else { return }
            self.permissions.decide(allow ? .allowOnce : .deny, for: requestId)
        }
        notifications.onOpen = { [weak self] kind in
            guard let self else { return }
            switch kind {
            case .whatsappDraft?: self.reviewAutomations()
            case .morningBrief?: self.select(.brief)
            case .securityCritical?, .securityWarning?, .cameraMic?: self.openSecurity()
            case .permissionRequest?: break  // the panel is already open if a request is pending
            default: self.open()
            }
        }
    }

    /// Posts a macOS notification if the user wants this kind of notification.
    private func notify(_ kind: NovaNotificationKind, title: String, body: String, requestId: String? = nil, highRisk: Bool = false) {
        let idle = Date().timeIntervalSince(lastActivity) > 60
        guard NotificationPolicy.shouldPost(kind, enabled: prefs.notifications, notchVisible: state.isVisible,
                                            onlyWhenAway: prefs.notifyOnlyWhenAway, userIdle: idle) else { return }
        notifications.post(kind, title: title, body: body, id: requestId.map { "perm-\($0)" } ?? UUID().uuidString,
                           requestId: requestId, highRisk: highRisk)
    }

    private func startIntegrations() {
        integrations.shouldAutoRefresh = { [weak self] in self?.state.isVisible ?? false }
        integrations.onHealthWorsened = { [weak self] snapshot in
            self?.notify(NotificationPolicy.kind(for: snapshot.kind), title: "\(snapshot.kind.displayName): \(snapshot.headline)",
                         body: snapshot.detail)
            self?.showBanner(NotchBanner(title: "\(snapshot.kind.displayName): \(snapshot.headline)", subtitle: snapshot.detail,
                                         expression: .error), for: .seconds(6))
        }
        integrations.start()
    }

    /// Nova Guard for coding agents: deny-listed commands are always denied;
    /// other high-risk requests are denied while the Mac is locked or idle.
    private func guardDenyReason(for request: AgentPermissionRequest) -> String? {
        if prefs.securityAgentDenyList, let reason = AutoFixPolicy.agentDenyReason(command: request.command) {
            return reason
        }
        if prefs.securityAwayGuard, request.risk.level == .high {
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            if ConnectivityMonitor.screenIsLockedNow() || idle > 300 { return "high-risk command while you were away" }
        }
        return nil
    }

    private func startSecurity() {
        security.onAlert = { [weak self] alert in self?.securityAlert(alert) }
        security.start()
    }

    private func securityAlert(_ alert: SecurityAlert) {
        switch alert.severity {
        case .critical:
            sound.play(.security)
            notify(.securityCritical, title: alert.title, body: alert.detail)
            showBanner(NotchBanner(title: alert.title, subtitle: alert.detail, expression: .warning, action: .openSecurity), for: .seconds(10))
        case .high:
            notify(.securityWarning, title: alert.title, body: alert.detail)
            showBanner(NotchBanner(title: alert.title, subtitle: alert.detail, expression: .warning, action: .openSecurity), for: .seconds(8))
        case .info:
            if alert.kind == .camera || alert.kind == .microphone {
                notify(.cameraMic, title: alert.title, body: alert.detail)
            }
            showBanner(NotchBanner(title: alert.title, subtitle: alert.detail, expression: .notification, action: .openSecurity), for: .seconds(4))
        }
    }

    func openSecurity() {
        if state.notchState == .sleep { transition(to: .idle, animated: false) }
        state.integrationFocus = .security
        transition(to: .integrationView)
    }

    func openIntegration(_ kind: IntegrationKind) {
        state.integrationFocus = .service(kind)
        transition(to: .integrationView)
        Task { await integrations.refresh(kind) }
    }

    func reviewAutomations() {
        state.integrationFocus = .automationReview
        if state.notchState == .sleep { transition(to: .idle, animated: false) }
        if state.notchState == .notification { bannerTask?.cancel() }
        transition(to: .integrationView)
    }

    /// After a draft/greeting is handled: stay if more are waiting, else close.
    func automationReviewed() {
        guard whatsapp.drafts.isEmpty, whatsapp.pendingGreetings.isEmpty else { return }
        transition(to: .idle)
    }

    func shutdown() {
        server?.stop()
        sessions.stop()
    }

    // MARK: - Public actions

    func notchTapped() {
        guard !state.notchState.isExpanded, state.notchState != .voice else { return }
        if state.notchState == .notification {
            bannerTask?.cancel()
            switch state.banner?.action {
            case .reviewAutomations?: reviewAutomations(); return
            case .openBrief?: select(.brief); return
            case .openSecurity?: openSecurity(); return
            case .enableWakeWord?:
                prefs.voiceWakeWord = true
                applyVoicePrefs()
                transition(to: .idle)
                beginTalking(autoStop: true)   // asks macOS for the mic once, now
                return
            case .openVoiceSettings?:
                transition(to: .idle)
                beginTalking(autoStop: true)
                return
            case .openURL(let url)?:
                NSWorkspace.shared.open(url)
                transition(to: .idle)
                return
            case nil: break
            }
        }
        if state.notchState == .compact, state.focusedAgent.isConnected, state.focusedAgent.status.isLive {
            transition(to: .agentSession)
        } else {
            transition(to: .expandedHome)
        }
        flash(.surprised, for: .milliseconds(450))
    }

    func select(_ tab: NovaTab) {
        let target: NotchState = tab == .chat ? .aiChat : .expandedHome
        if state.notchState != target { transition(to: target) }
        guard tab != state.selectedTab else { return }
        withAnimation(Theme.Motion.current) { state.selectedTab = tab }
        flash(tab == .chat ? .listening : .happy, for: .milliseconds(500))
    }

    func openSettings(_ section: SettingsSection = .ai) {
        settingsWindow.show(coordinator: self, section: section)
    }

    func focus(agent id: String) {
        guard id != state.focusedAgentID else { return }
        withAnimation(Theme.Motion.current) { state.focusedAgentID = id }
        flash(state.focusedAgent.status.expression, for: .milliseconds(900))
    }

    /// Brings the app the session runs in (Terminal, iTerm, VS Code…) forward.
    func jumpToTerminal(_ agent: AgentSummary) {
        let session = sessions.session(id: agent.sessionId)
        let appPath = session?.terminalApp ?? agent.terminalApp
        if let path = appPath {
            let url = URL(fileURLWithPath: path)
            if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL == url }) {
                running.activate()
            } else if let pid = session?.terminalPid, let app = NSRunningApplication(processIdentifier: pid) {
                app.activate()
            } else {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
            return
        }
        // No host recorded (older hook): open the project folder in Finder.
        if let cwd = session?.cwd { NSWorkspace.shared.open(URL(fileURLWithPath: cwd)) }
    }

    /// Cycles the focused session among live ones (compact strip, ‹ › keys).
    func focusNextSession(_ step: Int = 1) {
        let live = state.agents.filter(\.isConnected)
        guard live.count > 1, let i = live.firstIndex(where: { $0.id == state.focusedAgent.id }) else { return }
        focus(agent: live[(i + step + live.count) % live.count].id)
    }

    func openSession(for agentID: String? = nil) {
        if let agentID { state.focusedAgentID = agentID }
        guard state.focusedAgent.isConnected else { return }
        transition(to: .agentSession)
    }

    func backToHome() {
        transition(to: .expandedHome)
    }

    /// Shows a banner below the notch, then returns to idle.
    func showBanner(_ banner: NotchBanner, for duration: Duration = .seconds(4)) {
        guard state.notchState != .permissionRequest else { return }
        // Don't cover the voice panel mid-sentence.
        if state.notchState == .voice { deferredBanner = (banner, duration); return }
        if state.notchState.isExpanded || state.notchState == .notification { transition(to: .idle, animated: false) }
        if state.notchState == .sleep { transition(to: .idle, animated: false) }
        state.banner = banner
        transition(to: .notification)
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.state.notchState == .notification else { return }
            self.transition(to: .idle)
        }
    }

    func showTestBanner() {
        showBanner(NotchBanner(title: "Rate limit reached",
                               subtitle: "Retrying in a few seconds.",
                               expression: .dizzy))
    }

    func open() {
        if !state.isVisible { toggleVisibility() }
        if state.notchState == .sleep { transition(to: .idle) }
        transition(to: .expandedHome)
    }

    func collapse() {
        guard state.notchState != .permissionRequest else { return }
        cancelPending()
        transition(to: .idle)
        window?.setInteractive(isMouseInsideShape(NSEvent.mouseLocation))
    }

    func toggleVisibility() {
        state.isVisible.toggle()
        if state.isVisible {
            window?.show()
            transition(to: .idle)
        } else {
            cancelPending()
            transition(to: .hidden)
            window?.hide()
        }
    }

    func perform(_ action: QuickAction) {
        if action == .chat { select(.chat); return }
        if action == .settings { openSettings(); return }
        // Destinations arrive in later phases; acknowledge the tap for now.
        flash(.happy, for: .milliseconds(600))
    }

    // MARK: - Agents & permissions

    /// Tracks when the shown permission request appeared, and the last
    /// mouse-down, so accidental clicks can't answer it (see DecisionGate).
    @ObservationIgnored private var decisionGate: DecisionGate?
    @ObservationIgnored private var lastMouseDownAt: TimeInterval?

    /// Called by the permission view whenever a request becomes visible.
    func permissionShown(_ requestId: String) {
        guard decisionGate?.requestId != requestId else { return }
        decisionGate = DecisionGate(requestId: requestId, presentedAt: ProcessInfo.processInfo.systemUptime)
    }

    /// Answers the request the user is looking at. Ignored unless the panel
    /// has been visible long enough and the click began after it appeared.
    @discardableResult
    func decide(_ decision: PermissionDecision, requestId: String, viaKeyboard: Bool = false) -> Bool {
        guard let gate = decisionGate,
              gate.accepts(requestId: requestId, now: ProcessInfo.processInfo.systemUptime,
                           mouseDownAt: viaKeyboard ? nil : lastMouseDownAt) else { return false }
        guard let request = permissions.pending.first(where: { $0.id == requestId }) else { return false }
        if decision != .deny, request.risk.level == .high, viaKeyboard { return false }   // high risk: click twice, no shortcut
        permissions.decide(decision, for: requestId)
        flash(decision == .deny ? .annoyed : .success, for: .milliseconds(700))
        return true
    }

    /// Clicking Nova: a little annoyed squish; three quick clicks make it dizzy.
    func poke() {
        switch tapCounter.tap(at: ProcessInfo.processInfo.systemUptime) {
        case .poke: flash(.annoyed, for: .milliseconds(650))
        case .dizzy: flash(.dizzy, for: .milliseconds(1600))
        }
    }

    /// Sends answers for a question request (same click-safety as decisions).
    @discardableResult
    func answer(_ answers: [String: [String]], requestId: String) -> Bool {
        guard let gate = decisionGate,
              gate.accepts(requestId: requestId, now: ProcessInfo.processInfo.systemUptime, mouseDownAt: lastMouseDownAt),
              permissions.pending.contains(where: { $0.id == requestId }) else { return false }
        permissions.answer(answers, for: requestId)
        flash(.happy, for: .milliseconds(700))
        return true
    }

    func replyInTerminal(requestId: String) {
        let sessionId = permissions.pending.first { $0.id == requestId }?.sessionId
        permissions.replyInTerminal(requestId)
        if let agent = state.agents.first(where: { $0.sessionId == sessionId }) { jumpToTerminal(agent) }
    }

    /// Stops tracking a session locally and denies anything it's waiting on.
    func stopSession(_ sessionId: String) {
        permissions.denyAll(sessionId: sessionId)
        permissions.clearRules(for: sessionId)
        sessions.markStopped(sessionId)
        refreshAgents()
    }

    func revealSessionFolder(_ session: AgentSession) {
        guard let cwd = session.cwd else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
    }

    private func refreshAgents() {
        let before = state.expression
        let summaries = sessions.summaries()
        // Only publish real changes: replacing an identical list re-renders the whole notch.
        if summaries != state.agents { state.agents = summaries }
        if state.expression != before { playCue(for: state.expression) }
    }

    private func agentEvent(_ event: AgentEvent, _ session: AgentSession) {
        lastActivity = Date()
        refreshAgents()
        if permissions.current == nil || event.event == .permissionRequest {
            state.focusedAgentID = event.sessionId
        }
        let name = event.agent.displayName

        switch event.event {
        case .permissionRequest:
            presentPermissions()
            if let request = permissions.current, request.id == event.requestId,
               ProcessInfo.processInfo.environment["NOVA_TEST_AUTODENY"] != "1" {
                let project = session.projectName.map { " · \($0)" } ?? ""
                if request.isQuestion {
                    // No Allow/Deny actions: answers are chosen in the notch.
                    notify(.permissionRequest, title: "\(name)\(project) has a question", body: request.detail ?? "Answer in the notch")
                } else {
                    notify(.permissionRequest, title: "\(name)\(project) wants to use \(request.tool)",
                           body: request.command ?? request.filePath ?? request.detail ?? request.tool, requestId: request.id,
                           highRisk: request.risk.level == .high)
                }
            }
        case .toolStart:
            flash(session.actions.last?.tool == "Bash" ? .typing : .coding, for: .milliseconds(1200))
            showActivityStrip()
        case .prompt:
            flash(.thinking, for: .milliseconds(1500))
            showActivityStrip()
        case .stop:
            notify(.agentCompleted, title: "\(name) finished", body: session.currentTask ?? session.projectName ?? "Session complete.")
            sound.play(.taskDone)
            showBanner(NotchBanner(title: "\(name) finished",
                                   subtitle: "\(session.projectName ?? "Session") · \(AgentSummary.format(session.elapsed(now: Date())))",
                                   expression: .success))
        case .error:
            notify(.agentFailed, title: "\(name) stopped with an error", body: event.message ?? "Check the session for details.")
            showBanner(NotchBanner(title: "\(name) stopped with an error",
                                   subtitle: event.message ?? "Check the session for details.",
                                   expression: .error))
        case .notification:
            if let message = event.message, !state.notchState.isExpanded {
                showBanner(NotchBanner(title: name, subtitle: message, expression: .listening))
            }
        default:
            break
        }
    }

    private func presentPermissions() {
        #if DEBUG
        // Automated tests must never pop a panel under the user's cursor.
        if ProcessInfo.processInfo.environment["NOVA_TEST_AUTODENY"] == "1" { return }
        #endif
        guard state.isVisible, let request = permissions.current else { return }
        // VoiceOver users hear the request right away.
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: "\(request.agent.displayName) wants to use \(request.tool). \(request.risk.level.label).",
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
        if state.notchState == .sleep { transition(to: .idle, animated: false) }
        updatePermissionLayout()
        bannerTask?.cancel()
        cancelPending()
        transition(to: .permissionRequest)
    }

    /// Sizes the permission panel to the current request: taller for a
    /// diff or for questions with many options, compact for a command.
    func updatePermissionLayout() {
        let extra: CGFloat
        if let request = permissions.current {
            if request.edit != nil {
                extra = 54
            } else if let questions = request.questions {
                extra = CGFloat(max(0, (questions.map(\.options.count).max() ?? 0) - 3)) * 34
            } else {
                extra = 0
            }
        } else {
            extra = 0
        }
        guard extra != state.permissionExtraHeight else { return }
        withAnimation(prefs.effectiveReduceMotion ? Theme.Motion.reduced : Theme.Motion.spring) { state.permissionExtraHeight = extra }
    }

    private func permissionResolved(_ request: AgentPermissionRequest) {
        notifications.remove(id: "perm-\(request.id)")
        updatePermissionLayout()
        sessions.approvalResolved(request)
        refreshAgents()
        if permissions.pending.isEmpty, state.notchState == .permissionRequest {
            transition(to: .idle)
            window?.setInteractive(isMouseInsideShape(NSEvent.mouseLocation))
        }
    }

    /// Briefly shows the compact strip for background activity.
    private func showActivityStrip() {
        guard state.isVisible, state.notchState == .idle || state.notchState == .sleep || state.notchState == .hover else { return }
        if state.notchState == .sleep { transition(to: .idle, animated: false) }
        compactPinnedUntil = Date().addingTimeInterval(Self.activityStripDuration)
        transition(to: .compact)
        cancelCollapse()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.activityStripDuration))
            guard !Task.isCancelled, let self else { return }
            self.collapseTask = nil
            if self.state.notchState == .compact, !self.isMouseInsideShape(NSEvent.mouseLocation) {
                self.collapse()
            }
        }
    }

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        let escape: UInt16 = 53, enter: UInt16 = 36
        if state.notchState == .permissionRequest, let request = permissions.current {
            if event.keyCode == escape { decide(.deny, requestId: request.id, viaKeyboard: true); return true }
            if event.keyCode == enter, event.modifierFlags.contains(.command) {
                decide(.allowOnce, requestId: request.id, viaKeyboard: true)
                return true
            }
            return false
        }
        if event.keyCode == escape, state.notchState.isExpanded {
            collapse()
            return true
        }
        return false
    }

    /// Screen point Nova's eyes look from, for cursor tracking.
    var novaAnchor: CGPoint {
        guard let window else { return .zero }
        let g = state.geometry
        let rect = window.visibleRect(for: state.displaySize)
        let y = rect.maxY - g.notchHeight / 2
        if state.notchState.isExpanded {
            return CGPoint(x: rect.minX + 100, y: rect.maxY - g.notchHeight - 60)
        }
        if state.notchState == .compact || state.notchState == .notification {
            return CGPoint(x: rect.minX + 46, y: rect.maxY - g.notchHeight - 22)
        }
        let wing = NotchLayout.wingWidth(for: state.size, geometry: g)
        return CGPoint(x: rect.minX + (g.hasNotch ? wing / 2 : 17), y: y)
    }

    // MARK: - State machine

    #if DEBUG
    /// Debug: opens Home in the live panel and saves what the window draws (no Screen Recording needed).
    func debugCaptureHome(to path: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            self.state.selectedTab = .home
            self.transition(to: .expandedHome)
            for step in [1, 3] {
                try? await Task.sleep(for: .seconds(step == 1 ? 1 : 2))
                guard let view = self.window?.panel.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    FileHandle.standardError.write("capture: no view/rep \(self.window?.panel.contentView?.bounds ?? .zero)\n".data(using: .utf8)!)
                    continue
                }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + "-\(step)s.png"))
                FileHandle.standardError.write("captured \(path)-\(step)s.png notchState=\(self.state.notchState)\n".data(using: .utf8)!)
            }
            exit(0)
        }
    }
    #endif

    func transition(to next: NotchState, animated: Bool = true) {
        let previous = state.notchState
        guard previous.canTransition(to: next) else { return }
        let previousExpression = state.expression
        if next == .expandedHome, state.selectedTab == .chat { state.selectedTab = .home }
        if animated, prefs.animations {
            withAnimation(prefs.effectiveReduceMotion ? Theme.Motion.reduced : Theme.Motion.spring) { state.notchState = next }
        } else {
            state.notchState = next
        }
        window?.setKeyable(next.isExpanded)
        // The voice panel was replaced while the mic was on: stop listening
        // rather than keep the microphone running with nothing on screen.
        if previous == .voice, voice.phase == .listening { voice.cancel() }

        if next.isExpanded && !previous.isExpanded {
            sound.play(next == .permissionRequest ? .permission : .open)
        } else if previous.isExpanded && !next.isExpanded {
            sound.play(.close)
        } else if state.expression != previousExpression {
            playCue(for: state.expression)
        }
    }

    /// Temporarily overrides Nova's expression (with its sound).
    func flash(_ expression: NovaExpression, for duration: Duration) {
        expressionTask?.cancel()
        let previous = state.expression
        state.expressionOverride = expression
        if expression != previous { playCue(for: expression) }
        expressionTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.state.expressionOverride = nil
        }
    }

    private func playCue(for expression: NovaExpression) {
        guard let cue = expression.soundCue else { return }
        // Frequent reactions get long cooldowns so Nova isn't noisy.
        let cooldown: TimeInterval = switch expression {
        case .happy: 3
        case .coding, .typing: 20
        case .thinking, .listening: 10
        default: 0
        }
        sound.play(cue, cooldown: cooldown)
    }

    // MARK: - Mouse

    private func isMouseInsideShape(_ point: CGPoint) -> Bool {
        guard let window else { return false }
        // Small slop so the very top pixel row (behind the notch) counts.
        return window.visibleRect(for: state.displaySize).insetBy(dx: -4, dy: -4).contains(point)
    }

    private func mouseMoved(to point: CGPoint) {
        lastActivity = Date()
        guard state.isVisible else { return }
        if state.notchState == .sleep { transition(to: .idle) }

        let inside = isMouseInsideShape(point)
        window?.setInteractive(inside)

        switch (state.notchState, inside) {
        case (.permissionRequest, _), (.aiChat, false), (.integrationView, false):
            break  // never auto-dismiss a pending request or a chat mid-typing
        case (.idle, true):
            cancelCollapse()
            transition(to: .hover)
            schedulePromotion()
        case (.hover, true), (.compact, true):
            cancelCollapse()
            compactPinnedUntil = .distantPast
        case (.hover, false), (.compact, false):
            guard Date() >= compactPinnedUntil else { break }
            promoteTask?.cancel()
            scheduleCollapse(after: Self.collapseDelay)
        case (let s, true) where s.isExpanded:
            cancelCollapse()
        case (let s, false) where s.isExpanded:
            scheduleCollapse(after: Self.expandedCollapseDelay)
        default:
            break
        }
    }

    private func outsideClick(at point: CGPoint) {
        lastActivity = Date()
        if state.notchState.isExpanded, state.notchState != .permissionRequest, !isMouseInsideShape(point) {
            collapse()
        }
    }

    private func schedulePromotion() {
        promoteTask?.cancel()
        promoteTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hoverToCompactDelay)
            guard !Task.isCancelled, let self, self.state.notchState == .hover else { return }
            self.transition(to: .compact)
        }
    }

    private func scheduleCollapse(after delay: Duration) {
        guard collapseTask == nil else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.collapseTask = nil
            self.collapse()
        }
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    private func cancelPending() {
        cancelCollapse()
        promoteTask?.cancel()
        promoteTask = nil
    }

    // MARK: - Sleep & screens

    private func startSleepWatch() {
        sleepWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                if self.state.notchState == .idle, !self.hasActivity,
                   Date().timeIntervalSince(self.lastActivity) > Self.sleepAfter {
                    self.transition(to: .sleep)
                }
            }
        }
    }

    private func screenChanged() {
        window?.reposition()
        if let geometry = window?.geometry { state.geometry = geometry }
    }
}
