import AppKit
import NovaKit

/// What Nova does for each spoken request. Safe by design: voice can deny an
/// agent request but never approve one, and nothing destructive (deleting,
/// sending messages, shutting down) is available by voice.
extension AppCoordinator {
    func handleVoice(_ text: String) async {
        // Answering "Send?" (only messages and plan steps accept a spoken answer).
        if let pending = pendingVoiceAction, pending.voiceConfirm {
            switch VoiceSafety.confirmation(text) {
            case true?:
                voice.say(pending.confirm == "Send" ? "Sending." : "OK.")
                confirmVoiceAction()
            case false?:
                dismissPendingVoiceAction()
                voice.say("Cancelled. Nothing was sent.")
            case nil:
                voice.say("Say “send” to send it, or “cancel”.")
            }
            logAction(text, result: "confirmation")
            return
        }
        // One of your routines ("start my work day").
        if let routine = RoutineMatcher.match(text, in: routines.routines) {
            let reply = await runPlan(routine.intents, request: routine.name)
            logAction(text, result: "routine \(routine.name)")
            voice.say(reply)
            return
        }
        await perform(VoiceIntentRouter.route(text), fromAI: false)
        logAction(text, result: voice.reply)
    }

    /// Runs one intent and speaks the result. `fromAI` is set when the AI
    /// picked the action, so a question is never sent back to the AI in a loop.
    func perform(_ intent: VoiceIntent, fromAI: Bool) async {
        let reply = await result(of: intent, fromAI: fromAI)
        guard !reply.isEmpty else { return }
        // A follow-up makes sense after an answer, not after "stop", a lock or a dance.
        followUpAllowed = switch intent {
        case .stopSpeaking, .lockScreen, .screenshot, .dance, .highFive: false
        default: pendingVoiceAction == nil
        }
        voice.say(reply)
    }

    /// Does what the intent asks and returns what Nova should say.
    func result(of intent: VoiceIntent, fromAI: Bool) async -> String {
        let reply: String
        switch intent {
        case .wakeOnly:
            reply = "Yes? I'm listening."
        case .status:
            reply = voiceStatus()
        case .deny:
            if let request = permissions.pending.first(where: { !$0.isQuestion }) {
                permissions.decide(.deny, for: request.id)
                flash(.annoyed, for: .milliseconds(700))
                reply = "Denied. \(request.agent.displayName) won't run that."
            } else {
                reply = "There's nothing waiting for approval."
            }
        case .refuseAllow:
            reply = permissions.pending.contains { !$0.isQuestion }
                ? "For your safety I can only deny by voice. Please approve it on screen."
                : "For your safety I never approve anything by voice."
        case .readBrief:
            if let overview = brief.mail?.overview, !overview.isEmpty {
                reply = overview
            } else {
                reply = "Your brief isn't ready yet. I'll open it for you."
                state.selectedTab = .brief
            }
        case .music(let command):
            reply = voiceMusic(command)
        case .scanSecurity:
            await security.scanPosture()
            reply = voiceSecuritySummary()
        case .openApp(let name):
            reply = voiceOpen(app: name)
        case .quitApp(let name):
            reply = await MacActions.quit(name)
        case .switchTo(let name):
            if let app = MacActions.runningApp(named: name) {
                app.activate()
                reply = "Here's \(app.localizedName ?? name)."
            } else {
                reply = voiceOpen(app: name)
            }
        case .openWebsite(let site):
            reply = MacActions.openWebsite(site)
        case .webSearch(let engine, let query):
            reply = MacActions.search(query, on: engine)
        case .playSong(let query):
            reply = MacActions.spotifySearch(query)
        case .browser(let command):
            reply = await MacActions.browser(command)
        case .typeText(let text):
            reply = await MacActions.type(text)
        case .click(let label):
            reply = await voiceClick(label)
        case .mute(let on):
            _ = await CommandRunner.run("/usr/bin/osascript", ["-e", "set volume output muted \(on)"])
            reply = on ? "Muted." : "Sound's back on."
        case .timer(let seconds):
            startTimer(seconds: seconds)
            reply = "Timer set for \(Self.spoken(seconds: seconds))."
        case .screenshot:
            reply = await voiceScreenshot()
        case .lockScreen:
            voice.cancel()
            closeVoice()
            try? await Task.sleep(for: .milliseconds(300))
            MacActions.lockScreen()
            return ""
        case .sendMessage(let contact, let text):
            reply = voicePrepareMessage(contact: contact, text: text, at: nil)
        case .scheduleMessage(let contact, let text, let time):
            reply = voicePrepareMessage(contact: contact, text: text, at: time.resolve(now: Date()))
        case .systemCheck:
            reply = await voiceSystemCheck()
        case .findFile(let query):
            reply = await voiceFindFiles(query)
        case .openResult(let n):
            reply = voiceOpenResult(n)
        case .revealResult:
            if let url = lastFileResults.first {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                reply = "Here it is in Finder."
            } else {
                reply = "Ask me to find a file first."
            }
        case .clipboard(let task):
            reply = await voiceClipboard(task)
        case .agenda(let day):
            reply = await voiceAgenda(day)
        case .usage:
            await usage.scan()
            reply = usage.spokenSummary()
        case .runShortcut(let name):
            reply = await voiceRunShortcut(name)
        case .makeRoutine(let name, let description):
            reply = await voiceMakeRoutine(name: name, description: description)
        case .addReminder(let text, let time):
            reply = await voiceReminder(text, at: time?.resolve(now: Date()))
        case .volume(let up):
            _ = await CommandRunner.run("/usr/bin/osascript", ["-e", "set volume output volume ((output volume of (get volume settings)) \(up ? "+" : "-") 12)"])
            reply = up ? "Turned it up." : "Turned it down."
        case .time:
            reply = "It's \(Date().formatted(date: .omitted, time: .shortened))."
        case .date:
            reply = "Today is \(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))."
        case .stopSpeaking:
            if activePlan != nil { activePlan?.stopped = true }
            voice.cancel()
            return ""
        case .dance:
            music.partyUntil = Date().addingTimeInterval(10)
            flash(.excited, for: .milliseconds(900))
            reply = ["Let's dance!", "Party time! 🎶", "Watch these moves!", "Aadalaam! 🎶"].randomElement()!
            // Show the whole Nova dancing on Home, not just the head in the voice strip.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                self?.open()
            }
        case .joke:
            reply = Self.jokes.randomElement()!
            flash(.happy, for: .seconds(2))
        case .coinFlip:
            let heads = Bool.random()
            flash(.success, for: .seconds(1))
            reply = heads ? "Heads!" : "Tails!"
        case .rollDie:
            flash(.excited, for: .seconds(1))
            reply = "You rolled a \(Int.random(in: 1...6))."
        case .highFive:
            flash(.excited, for: .seconds(1.2))
            reply = ["High five! ✋", "Up top! ✋", "Yes! Nice one ✋"].randomElement()!
        case .ask(let question):
            if fromAI {
                reply = question
            } else {
                reply = await voiceAsk(question)
            }
        }
        return reply
    }

    static let jokes = [
        "Why do programmers prefer dark mode? Because light attracts bugs.",
        "I told my computer I needed a break. It said: no problem, I'll go to sleep.",
        "There are 10 kinds of people: those who understand binary and those who don't.",
        "A SQL query walks into a bar, walks up to two tables and asks: can I join you?",
        "Why did the developer go broke? He used up all his cache.",
        "My code doesn't have bugs. It has surprise features.",
        "Why was the JavaScript developer sad? Because he didn't Node how to Express himself.",
        "I would tell you a UDP joke, but you might not get it.",
        "Debugging: being the detective in a crime movie where you are also the murderer.",
        "Why do Java developers wear glasses? Because they don't C sharp.",
        "It works on my machine. Then we'll ship your machine.",
        "Git commit, git push, git out of the office.",
    ]

    private func voiceStatus() -> String {
        let live = state.agents.filter { $0.isConnected && $0.status.isLive }
        guard !live.isEmpty else { return "No agents are running right now." }
        let parts = live.prefix(3).map { agent -> String in
            let name = agent.siblingCount > 1 ? agent.title : agent.name
            switch agent.status {
            case .needsApproval: return "\(name) needs your approval"
            case .error: return "\(name) hit an error"
            default: return "\(name) is \(agent.status.label.lowercased()): \(agent.detail)"
            }
        }
        let more = live.count > 3 ? " And \(live.count - 3) more." : ""
        return parts.joined(separator: ". ") + "." + more
    }

    private func voiceMusic(_ command: VoiceIntent.MusicCommand) -> String {
        guard spotify.isRunning else {
            spotify.open()
            return "Opening Spotify."
        }
        switch command {
        case .play:
            if !spotify.isPlaying { spotify.playPause() }
            return spotify.track.map { "Playing \($0.name)." } ?? "Playing."
        case .pause:
            if spotify.isPlaying { spotify.playPause() }
            return "Paused."
        case .next:
            spotify.next()
            return "Next song."
        case .previous:
            spotify.previous()
            return "Previous song."
        }
    }

    private func voiceSecuritySummary() -> String {
        let issues = security.checks.filter { $0.status == .warning || $0.status == .critical }
        let score = security.score.map { "Your security score is \($0)." } ?? "Scan finished."
        guard !issues.isEmpty else { return score + " Everything I check looks good." }
        let names = issues.prefix(3).map(\.title).joined(separator: ", ")
        return score + " To fix: \(names). Open Nova Guard for one-click fixes."
    }

    private func voiceOpen(app name: String) -> String {
        let wanted = name.lowercased().replacingOccurrences(of: " ", with: "")
        let aliases = ["vscode": "visual studio code", "code": "visual studio code", "chrome": "google chrome", "settings": "system settings"]
        let target = (aliases[wanted] ?? name).lowercased()
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        for folder in folders {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            if let match = items.first(where: { $0.lowercased() == target + ".app" })
                ?? items.first(where: { $0.lowercased().hasSuffix(".app") && $0.lowercased().replacingOccurrences(of: " ", with: "").hasPrefix(target.replacingOccurrences(of: " ", with: "")) }) {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: folder).appendingPathComponent(match), configuration: .init())
                return "Opening \(match.replacingOccurrences(of: ".app", with: ""))."
            }
        }
        if MacActions.knownSites[name.lowercased()] != nil { return MacActions.openWebsite(name) }
        return "I couldn't find an app called \(name). Say “find \(name)” to look for a file."
    }

    /// Presses a button by name. Risky ones (Send, Delete, Buy…) wait for a
    /// mouse click on Nova's confirm button: voice alone never does them.
    private func voiceClick(_ label: String) async -> String {
        switch await MacActions.findButton(label) {
        case .none(let message):
            return message
        case .several(let names):
            return "I found \(names.count): \(names.joined(separator: ", ")). Say the full name."
        case .found(let button):
            if button.risky {
                pendingVoiceAction = PendingVoiceAction(title: "Click “\(button.title)” in \(button.appName)?", confirm: "Click it") {
                    _ = await MacActions.press(button)
                }
                return "“\(button.title)” can't be undone, so please click the button to confirm."
            }
            return await MacActions.press(button) ? "Clicked \(button.title)." : "\(button.appName) didn't respond to the click."
        }
    }

    private func voiceScreenshot() async -> String {
        // Hide the voice panel first so it isn't in the picture.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let path = NSHomeDirectory() + "/Desktop/Nova Screenshot \(formatter.string(from: Date())).png"
        closeVoice()
        try? await Task.sleep(for: .milliseconds(500))
        let result = await CommandRunner.runWithStatus("/usr/sbin/screencapture", ["-x", path])
        return result.status == 0 ? "Saved a screenshot to your Desktop." : "I couldn't take a screenshot. Nova may need Screen Recording access."
    }

    static func spoken(seconds: Int) -> String {
        if seconds % 3600 == 0 { return seconds == 3600 ? "1 hour" : "\(seconds / 3600) hours" }
        if seconds % 60 == 0 { return seconds == 60 ? "1 minute" : "\(seconds / 60) minutes" }
        if seconds > 60 { return "\(seconds / 60) minutes \(seconds % 60) seconds" }
        return "\(seconds) seconds"
    }

    /// Anything the rules didn't catch: the AI either answers or picks one
    /// of the typed actions above (never approving or denying anything).
    private func voiceAsk(_ question: String) async -> String {
        lastVoiceProvider = nil
        do {
            // The last few exchanges, so "and tomorrow?" makes sense.
            let recent = voiceHistory.filter { Date().timeIntervalSince($0.at) < 600 }.suffix(3)
            let prompt = recent.isEmpty ? question
                : "Earlier in this conversation:\n" + recent.map { "User: \($0.question)\nNova: \($0.answer)" }.joined(separator: "\n")
                    + "\n\nNow the user says: \(question)"
            let (raw, provider) = try await ai.completeWithSource(system: VoiceAIAction.instructions, prompt: prompt,
                                                                  effort: "low", maxTokens: 600)
            switch VoiceAIAction.parse(raw) {
            case .action(let intent):
                Log.ai.info("Voice AI picked an action via \(provider.rawValue, privacy: .public)")
                return await result(of: intent, fromAI: true)
            case .plan(let steps):
                Log.ai.info("Voice AI made a \(steps.count)-step plan via \(provider.rawValue, privacy: .public)")
                return await runPlan(steps, request: question)
            case .answer(let answer):
                chat.messages.append(AIMessage(role: .user, text: question))
                chat.messages.append(AIMessage(role: .assistant, text: answer))
                voiceHistory.append((question, answer, Date()))
                voiceHistory = Array(voiceHistory.suffix(6))
                lastVoiceProvider = provider
                return answer
            }
        } catch {
            return error.localizedDescription
        }
    }
}

/// Something that waits for you before it runs: a risky click (mouse only),
/// or a message / plan step (mouse, or saying "send" / "go").
struct PendingVoiceAction: Identifiable {
    let id = UUID()
    let title: String
    let confirm: String
    var voiceConfirm = false
    var expiresAfter: Double = 20
    var onCancel: (@MainActor () -> Void)? = nil
    let run: @MainActor () async -> Void

    init(title: String, confirm: String, voiceConfirm: Bool = false, expiresAfter: Double = 20,
         onCancel: (@MainActor () -> Void)? = nil, run: @escaping @MainActor () async -> Void) {
        self.title = title
        self.confirm = confirm
        self.voiceConfirm = voiceConfirm
        self.expiresAfter = expiresAfter
        self.onCancel = onCancel
        self.run = run
    }
}

/// A multi-step job ("get my work day ready").
struct VoicePlan {
    var request: String
    var steps: [VoiceIntent]
    var done: [String] = []
    var current = 0
    var stopped = false
}