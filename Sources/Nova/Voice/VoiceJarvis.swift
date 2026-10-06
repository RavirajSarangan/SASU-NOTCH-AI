import AppKit
import NovaKit

/// The bigger voice jobs: WhatsApp messages (always read back first), the
/// whole-system check, and multi-step plans that pause before risky steps.
extension AppCoordinator {
    // MARK: Messages

    /// Finds the chat and waits for "send" (or a click). Nothing is sent here.
    func voicePrepareMessage(contact: String, text: String, at date: Date?) -> String {
        if whatsapp.chats.isEmpty { whatsapp.reloadChats() }
        let chats = whatsapp.chats.filter { !$0.name.isEmpty }
        guard !chats.isEmpty else {
            return "I can't see your WhatsApp chats yet. Open Settings → Automations → WhatsApp and allow access first."
        }
        var who = contact
        var body = text
        if who.isEmpty {
            guard let split = ContactMatcher.split(text, names: chats.map(\.name)) else { return "Who should I send it to?" }
            who = split.contact
            body = split.text
        }
        guard !body.isEmpty else { return "What should the message say?" }
        let chat: WAChat
        switch ContactMatcher.match(who, in: chats.map(\.name)) {
        case .none:
            return "I couldn't find \(who) in your WhatsApp chats."
        case .several(let names):
            return "Which one: \(names.joined(separator: ", "))? Say it again with the full name."
        case .one(let name):
            guard let found = chats.first(where: { $0.name == name }) else { return "I couldn't find \(who)." }
            chat = found
        }
        guard (chat.phone?.count ?? 0) >= 7 else { return "I don't have a phone number for \(chat.name), so I can't open that chat." }

        let when = date.map { $0.formatted(date: Calendar.current.isDateInToday($0) ? .omitted : .abbreviated, time: .shortened) }
        let note = whatsapp.settings.data.testMode ? " Test mode is on, so it will be typed but not sent." : ""
        pendingVoiceAction = PendingVoiceAction(
            title: when.map { "At \($0) to \(chat.name): \(body)" } ?? "To \(chat.name): \(body)",
            confirm: date == nil ? "Send" : "Schedule", voiceConfirm: true, expiresAfter: 15
        ) { [weak self] in
            guard let self else { return }
            if let date {
                let ok = self.whatsapp.schedule(body, to: chat, at: date)
                self.showBanner(NotchBanner(title: ok ? "Message scheduled" : "Couldn't schedule",
                                            subtitle: ok ? "To \(chat.name) at \(when ?? ""). Cancel any time in Settings → Automations." : "No phone number for \(chat.name).",
                                            expression: ok ? .success : .error))
                self.logAction("Scheduled message to \(chat.name)", result: ok ? "scheduled" : "failed")
            } else {
                let (ok, status) = await self.whatsapp.sendNow(body, to: chat)
                self.logAction("Message to \(chat.name)", result: ok ? status : "failed: \(status)")
            }
        }
        if let when { return "At \(when), to \(chat.name): \(body). Say schedule, or cancel.\(note)" }
        return "To \(chat.name): \(body). Say send, or cancel.\(note)"
    }

    // MARK: System check

    func voiceSystemCheck() async -> String {
        await security.scanPosture()
        await security.checkProcesses()
        await security.checkStartupItems()
        await security.checkExposedPorts()
        let health = await SystemHealthProbe.measure()

        var input = SystemReport.Input()
        input.securityScore = security.score
        input.securityIssues = security.checks.filter { $0.status == .critical }.map(\.title)
            + security.checks.filter { $0.status == .warning }.map(\.title)
        input.recentAlerts = security.alerts.filter { $0.severity >= .high && Date().timeIntervalSince($0.date) < 86_400 }.count
        input.cpuHogs = health.cpuHogs
        input.memoryPressure = health.memoryPressure
        input.diskFreeGB = health.diskFreeGB
        input.diskTotalGB = health.diskTotalGB
        input.batteryHealth = health.batteryHealth
        input.batteryCycles = health.batteryCycles
        input.uptimeDays = health.uptimeDays
        input.microphoneApps = health.microphoneApps
        input.cameraOn = health.cameraOn
        let report = SystemReport(input)
        lastSystemReport = report
        // Show the details in Nova Guard once Nova has started answering.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.openSecurity()
        }
        return report.summary
    }

    // MARK: Plans

    /// Runs steps in order. Safe steps run by themselves; risky ones wait for
    /// "go" / "send" or a click. Say "stop" (or ×) to end the plan.
    func runPlan(_ steps: [VoiceIntent], request: String) async -> String {
        activePlan = VoicePlan(request: request, steps: steps)
        defer { activePlan = nil }
        var results: [String] = []
        for (index, step) in steps.enumerated() {
            guard activePlan?.stopped != true else { results.append("Stopped."); break }
            activePlan?.current = index
            let label = Self.describe(step)
            voice.showProgress("Step \(index + 1) of \(steps.count): \(label)")
            logAction("Plan step: \(label)", result: "started")

            // Steps that don't ask for themselves get one confirmation here.
            let asksItself: Bool = switch step {
            case .sendMessage, .scheduleMessage, .click, .runShortcut: true
            default: false
            }
            if VoiceSafety.needsConfirmation(step), !asksItself {
                guard await confirmStep("Step \(index + 1): \(label)?") else { results.append("Skipped \(label.lowercased())."); continue }
                voice.showProgress("Step \(index + 1) of \(steps.count): \(label)")
            }
            let reply = await result(of: step, fromAI: true)
            if let pending = pendingVoiceAction {
                // A message read-back or a risky click: wait for your answer.
                voice.say(reply)
                await waitUntilResolved(pending.id)
                voice.showProgress("Step \(index + 1) of \(steps.count): \(label)")
            } else if !reply.isEmpty {
                results.append(reply)
            }
            try? await Task.sleep(for: .milliseconds(600))
        }
        let summary = results.suffix(3).joined(separator: " ")
        return summary.isEmpty ? "All done." : "Done. \(summary)"
    }

    private func confirmStep(_ title: String) async -> Bool {
        await withCheckedContinuation { continuation in
            pendingVoiceAction = PendingVoiceAction(title: title, confirm: "Go", voiceConfirm: true, expiresAfter: 20,
                                                    onCancel: { continuation.resume(returning: false) },
                                                    run: { continuation.resume(returning: true) })
            voice.say(title + " Say go, or cancel.")
        }
    }

    private func waitUntilResolved(_ id: UUID) async {
        for _ in 0..<160 where pendingVoiceAction?.id == id {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    static func describe(_ intent: VoiceIntent) -> String {
        switch intent {
        case .openApp(let name): "Open \(name.capitalized)"
        case .quitApp(let name): "Quit \(name.capitalized)"
        case .switchTo(let name): "Switch to \(name.capitalized)"
        case .openWebsite(let site): "Open \(site)"
        case .webSearch(let engine, let query): "Search \(engine == .youtube ? "YouTube" : "Google") for \(query)"
        case .playSong(let query): "Find \(query) in Spotify"
        case .browser(let command): "Browser: \(command.rawValue)"
        case .typeText(let text): "Type “\(text.prefix(40))”"
        case .click(let label): "Click \(label)"
        case .mute(let on): on ? "Mute" : "Unmute"
        case .volume(let up): up ? "Volume up" : "Volume down"
        case .timer(let seconds): "Timer \(spoken(seconds: seconds))"
        case .screenshot: "Take a screenshot"
        case .lockScreen: "Lock the screen"
        case .sendMessage(let contact, _): "Message \(contact.isEmpty ? "contact" : contact)"
        case .scheduleMessage(let contact, _, _): "Schedule a message to \(contact)"
        case .systemCheck: "Check the system"
        case .findFile(let query): "Find \(describe(query))"
        case .clipboard: "Help with the clipboard"
        case .runShortcut(let name): "Run the “\(name)” shortcut"
        case .agenda(let day): day == .tomorrow ? "Tomorrow's calendar" : day == .next ? "What's next" : "Today's calendar"
        case .scanSecurity: "Security scan"
        case .music(let command): "Music: \(command.rawValue)"
        case .status: "Agent status"
        case .readBrief: "Read the brief"
        case .time: "Time"
        case .date: "Date"
        case .dance: "Dance"
        case .joke: "Tell a joke"
        default: "Step"
        }
    }

    // MARK: Files

    /// Spotlight search in your home folder; opens the newest match.
    func voiceFindFiles(_ query: FileQuery) async -> String {
        let found = await MacActions.findFiles(query)
        lastFileResults = found
        guard let first = found.first else {
            return "I couldn't find \(Self.describe(query)). Try different words."
        }
        NSWorkspace.shared.open(first)
        let others = found.count - 1
        let more = others > 0 ? " I found \(others) more; say “open the second one” or “show it in Finder”." : ""
        return "Opening \(first.lastPathComponent).\(more)"
    }

    func voiceOpenResult(_ n: Int) -> String {
        guard !lastFileResults.isEmpty else { return "Ask me to find a file first." }
        let index = min(max(n, 1), lastFileResults.count) - 1
        NSWorkspace.shared.open(lastFileResults[index])
        return "Opening \(lastFileResults[index].lastPathComponent)."
    }

    static func describe(_ query: FileQuery) -> String {
        let kind = query.kind.map { " " + $0.rawValue } ?? " file"
        let name = query.words.joined(separator: " ")
        return (name.isEmpty ? "a" : "a “\(name)”") + kind
    }

    // MARK: Calendar and reminders

    func voiceAgenda(_ day: AgendaDay) async -> String {
        guard await calendar.requestEvents() else {
            return "I need Calendar access for that. Allow Nova in System Settings → Privacy & Security → Calendars."
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let from = day == .tomorrow ? cal.date(byAdding: .day, value: 1, to: start)! : start
        let to = cal.date(byAdding: .day, value: 1, to: from)!
        return Agenda.spoken(await calendar.events(from: from, to: to), day: day, now: Date())
    }

    func voiceReminder(_ text: String, at date: Date?) async -> String {
        guard await calendar.requestReminders() else {
            return "I need Reminders access for that. Allow Nova in System Settings → Privacy & Security → Reminders."
        }
        guard await calendar.addReminder(text, at: date) else { return "I couldn't add that reminder." }
        logAction("Reminder: \(text)", result: date.map { "at \($0.formatted())" } ?? "no time")
        if let date {
            let when = date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .shortened)
            return "Reminder set: \(text), \(when)."
        }
        return "Added to Reminders: \(text)."
    }

    // MARK: Shortcuts and routines

    /// The Run button in Settings: same as saying the routine's name.
    func runRoutineNow(_ routine: Routine) {
        showVoicePanel()
        Task {
            voice.showProgress("Starting \(routine.name)…")
            let reply = await runPlan(routine.intents, request: routine.name)
            logAction("Routine \(routine.name)", result: "run from Settings")
            voice.say(reply)
        }
    }

    /// Runs one of your Apple Shortcuts. The first time for each shortcut,
    /// Nova asks (shortcuts can do anything); after that it just runs.
    func voiceRunShortcut(_ spoken: String) async -> String {
        let names = await shortcuts.names()
        guard !names.isEmpty else { return "I couldn't find any shortcuts in the Shortcuts app." }
        let name: String
        switch ContactMatcher.match(spoken, in: names) {
        case .none: return "I couldn't find a shortcut called \(spoken)."
        case .several(let options): return "Which one: \(options.joined(separator: ", "))?"
        case .one(let found): name = found
        }
        let service = shortcuts
        if service.isApproved(name) {
            return await service.run(name) ? "Ran \(name)." : "\(name) didn't finish. Check the Shortcuts app."
        }
        pendingVoiceAction = PendingVoiceAction(title: "Run the “\(name)” shortcut?", confirm: "Run", voiceConfirm: true) { [weak self] in
            service.approve(name)
            let ok = await service.run(name)
            self?.logAction("Shortcut \(name)", result: ok ? "ran" : "failed")
            self?.showBanner(NotchBanner(title: ok ? "Ran \(name)" : "\(name) didn't finish", subtitle: ok ? "Shortcut finished." : "Check the Shortcuts app.",
                                         expression: ok ? .success : .error))
        }
        return "Run the \(name) shortcut? Shortcuts can do anything, so I ask the first time. Say run, or cancel."
    }

    /// "Make a routine called gym: open Spotify, timer 45 minutes." The AI
    /// turns the description into steps; Nova reads them back and saves on "save".
    func voiceMakeRoutine(name: String, description: String) async -> String {
        let prompt = "Make a plan for this routine: \(description). Reply only with {\"plan\":[...]}."
        let steps: [VoiceIntent]
        do {
            let raw = try await ai.complete(system: VoiceAIAction.instructions, prompt: prompt, effort: "low", maxTokens: 800)
            switch VoiceAIAction.parse(raw) {
            case .plan(let intents): steps = intents
            case .action(let intent): steps = [intent]
            case .answer: return "I couldn't turn that into steps. Try “make a routine called gym: open Spotify, timer 45 minutes”."
            }
        } catch {
            return error.localizedDescription
        }
        let stored = steps.compactMap(RoutineStep.init)
        guard !stored.isEmpty else { return "None of those steps are things I can do in a routine." }
        let routine = Routine(name: name, phrases: [name], steps: stored)
        let list = steps.map(Self.describe).joined(separator: ", ")
        pendingVoiceAction = PendingVoiceAction(title: "Save “\(name)”: \(list)?", confirm: "Save", voiceConfirm: true) { [weak self] in
            self?.routines.add(routine)
            self?.logAction("Routine \(name)", result: "saved, \(stored.count) steps")
        }
        return "\(name): \(list). Say save, or cancel. Then just say “\(name)” to run it."
    }

    // MARK: Clipboard

    /// Summarise, explain, fix, shorten or translate the copied text. Secrets
    /// are masked before anything is sent to the AI.
    func voiceClipboard(_ task: ClipboardTask) async -> String {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return "Your clipboard has no text. Copy something first."
        }
        let safe = SecretMasker.mask(String(text.prefix(20_000)))
        do {
            let result = try await ai.complete(system: "You help with text the user copied. " + task.instruction,
                                               prompt: safe, effort: "low", maxTokens: 1500)
            if task.replacesClipboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result, forType: .string)
                return "Done. It's on your clipboard, ready to paste."
            }
            return result
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Action log

    /// Every voice request and its result, kept on this Mac (last 200).
    func logAction(_ request: String, result: String) {
        ActionLog.shared.append(request: request, result: result)
    }
}

/// Voice action history in Application Support/Nova/actions.json.
@MainActor
final class ActionLog {
    static let shared = ActionLog()

    struct Entry: Codable, Identifiable, Equatable {
        var id = UUID()
        var date: Date
        var request: String
        var result: String
    }

    private(set) var entries: [Entry] = []
    private var url: URL { NovaPathsApp.support.appendingPathComponent("actions.json") }

    private init() {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([Entry].self, from: data) { entries = saved }
    }

    func append(request: String, result: String) {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        entries.append(Entry(date: Date(), request: String(request.prefix(200)), result: String(result.prefix(200))))
        entries = Array(entries.suffix(200))
        try? FileManager.default.createDirectory(at: NovaPathsApp.support, withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }
}

/// CPU, memory, disk, battery and uptime, measured off the main thread.
enum SystemHealthProbe {
    struct Health: Sendable {
        var cpuHogs: [(name: String, percent: Double)] = []
        var memoryPressure = 1
        var diskFreeGB: Double?
        var diskTotalGB: Double?
        var batteryHealth: Int?
        var batteryCycles: Int?
        var uptimeDays = 0
        var microphoneApps: [String] = []
        var cameraOn = false
    }

    static func measure() async -> Health {
        var health = Health()
        let ps = await CommandRunner.run("/bin/ps", ["-Aceo", "pcpu=,comm=", "-r"])
        health.cpuHogs = SystemHealthParser.cpuHogs(ps, ignoring: ["kernel_task", "WindowServer"])
        let pressure = await CommandRunner.run("/usr/sbin/sysctl", ["-n", "kern.memorystatus_vm_pressure_level"])
        health.memoryPressure = Int(pressure.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            health.diskFreeGB = values.volumeAvailableCapacityForImportantUsage.map { Double($0) / 1_000_000_000 }
            health.diskTotalGB = values.volumeTotalCapacity.map { Double($0) / 1_000_000_000 }
        }
        let battery = await CommandRunner.run("/usr/sbin/ioreg", ["-rn", "AppleSmartBattery"])
        (health.batteryHealth, health.batteryCycles) = SystemHealthParser.battery(battery)
        health.uptimeDays = Int(ProcessInfo.processInfo.systemUptime / 86_400)
        let (pids, camera) = await withCheckedContinuation { continuation in
            HardwareRunLoops.queue.async {
                continuation.resume(returning: (SecurityMonitor.microphoneUsers(), SecurityMonitor.isCameraRunning()))
            }
        }
        health.microphoneApps = Array(Set(pids.compactMap { NSRunningApplication(processIdentifier: $0)?.localizedName })).sorted()
        health.cameraOn = camera
        return health
    }
}
