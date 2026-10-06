import Foundation

/// What voice may do to other apps. Voice can press ordinary buttons, but a
/// button that sends, deletes, pays or approves something needs a mouse click
/// on Nova's confirm button; some apps are never touched at all.
public enum VoiceSafety {
    /// Words that make a button risky (matched as whole words in its name).
    static let riskyWords: Set<String> = [
        "send", "delete", "remove", "erase", "trash", "buy", "pay", "purchase", "order", "checkout", "subscribe",
        "allow", "approve", "confirm", "accept", "yes", "agree", "transfer", "submit", "publish", "post", "merge",
        "deploy", "install", "uninstall", "reset", "empty", "discard", "overwrite", "replace", "format", "restart",
        "unsubscribe", "share", "invite",
    ]
    static let riskyPhrases = ["sign out", "log out", "shut down", "don't save", "dont save", "move to bin", "move to trash"]

    public static func isRisky(button label: String) -> Bool {
        let text = label.lowercased().replacingOccurrences(of: "’", with: "'")
        if riskyPhrases.contains(where: text.contains) { return true }
        let words = text.split(whereSeparator: { !$0.isLetter }).map(String.init)
        return words.contains(where: riskyWords.contains)
    }

    /// Apps voice never clicks or types into: password prompts, the login
    /// window, System Settings and password managers.
    public static let blockedBundleIDs: Set<String> = [
        "com.apple.SecurityAgent", "com.apple.loginwindow", "com.apple.UserNotificationCenter",
        "com.apple.systempreferences", "com.apple.Settings", "com.apple.keychainaccess", "com.apple.Passwords",
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.lastpass.LastPass",
    ]

    /// Steps an automatic plan must stop at for your confirmation: they send
    /// something, change what's on screen in another app, or end your work.
    /// (Risky button names are checked again when the button is found.)
    public static func needsConfirmation(_ intent: VoiceIntent) -> Bool {
        switch intent {
        case .sendMessage, .scheduleMessage, .typeText, .click, .quitApp, .lockScreen: true
        default: false
        }
    }

    /// Your spoken answer to "Send?": true = do it, false = cancel, nil = unclear.
    /// A bare "yes" or "ok" is deliberately not enough for sending.
    public static func confirmation(_ transcript: String) -> Bool? {
        let text = VoiceIntentRouter.normalize(VoiceIntentRouter.stripWakeWord(transcript))
        let words = Set(text.split(separator: " ").map(String.init))
        let cancel = ["cancel", "stop", "no", "don't", "dont", "vendam", "venam", "வேண்டாம்", "wait", "nope"]
        if cancel.contains(where: { words.contains($0) || text.contains($0 + " ") }) || text.contains("never mind") { return false }
        let go = ["send", "send it", "yes send", "go", "go ahead", "do it", "schedule", "schedule it", "anuppu", "anupu", "அனுப்பு", "confirm",
                  "save", "save it", "run", "run it"]
        if go.contains(where: { $0.contains(" ") ? text.contains($0) : words.contains($0) }) { return true }
        return nil
    }

    /// Steps an automatic plan may never contain.
    public static func allowedInPlan(_ intent: VoiceIntent) -> Bool {
        switch intent {
        case .deny, .refuseAllow, .ask, .wakeOnly, .stopSpeaking: false
        default: true
        }
    }

    /// Apps voice won't quit (Nova itself, the Finder, system processes).
    public static let unquittable: Set<String> = ["nova", "finder", "loginwindow", "dock", "systemuiserver", "window server"]
}

/// The AI turns free speech into one action: `{"action":"webSearch","query":"…"}`
/// or a plain answer `{"answer":"…"}`. Only actions in this list are accepted,
/// and none of them can approve or deny an agent request.
public enum VoiceAIAction {
    public static let instructions = """
    You are Nova, a voice assistant living in the user's Mac notch. Reply with ONE JSON object and nothing else.
    If the user wants something done on the Mac, use one action:
    {"action":"openApp","name":"Safari"} {"action":"quitApp","name":"Spotify"} {"action":"switchTo","name":"Chrome"}
    {"action":"openWebsite","url":"github.com"} {"action":"webSearch","engine":"google|youtube","query":"..."}
    {"action":"playSong","query":"..."} {"action":"browser","command":"newTab|closeTab|back|forward|reload|nextTab|previousTab"}
    {"action":"typeText","text":"..."} {"action":"click","label":"Continue"} {"action":"mute","on":true}
    {"action":"volume","up":true} {"action":"timer","seconds":600} {"action":"screenshot"} {"action":"lockScreen"}
    {"action":"music","command":"play|pause|next|previous"} {"action":"systemCheck"} {"action":"status"}
    {"action":"agenda","day":"next|today|tomorrow"} {"action":"runShortcut","name":"..."}
    {"action":"sendWhatsApp","contact":"Amma","text":"I'll be late"}
    {"action":"scheduleWhatsApp","contact":"Amma","text":"Good night","time":"22:00"} (or "inMinutes":30)
    For a request with several steps, reply {"plan":[{action},{action},...]} with at most 8 steps, in order.
    Never include approving, denying, deleting files, shell commands, payments or settings changes.
    Otherwise answer in 1-3 short spoken sentences, plain text, no markdown: {"answer":"..."}
    If the user writes in Tamil or Tanglish, answer in the same style. Never claim you did something you can't do.
    """

    public enum Parsed: Equatable, Sendable {
        case action(VoiceIntent)
        /// Several steps, already checked against `VoiceSafety.allowedInPlan`.
        case plan([VoiceIntent])
        case answer(String)
    }

    public static let maxPlanSteps = 8

    /// Reads the model's reply. Anything unknown or malformed becomes a plain answer.
    public static func parse(_ reply: String) -> Parsed {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end,
              let data = String(trimmed[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .answer(trimmed)
        }
        if let steps = object["plan"] as? [[String: Any]] {
            let intents = steps.prefix(maxPlanSteps).compactMap { step in
                (step["action"] as? String).flatMap { intent($0, step) }
            }.filter(VoiceSafety.allowedInPlan)
            if intents.count == 1 { return .action(intents[0]) }
            if !intents.isEmpty { return .plan(intents) }
        }
        if let action = object["action"] as? String, let intent = intent(action, object) { return .action(intent) }
        if let answer = object["answer"] as? String, !answer.isEmpty { return .answer(answer) }
        return .answer(trimmed.hasPrefix("{") ? "Sorry, I didn't get that." : trimmed)
    }

    static func intent(_ action: String, _ o: [String: Any]) -> VoiceIntent? {
        func text(_ key: String) -> String? {
            guard let value = (o[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        switch action {
        case "openApp": return text("name").map(VoiceIntent.openApp)
        case "quitApp": return text("name").map(VoiceIntent.quitApp)
        case "switchTo": return text("name").map(VoiceIntent.switchTo)
        case "openWebsite": return text("url").map(VoiceIntent.openWebsite)
        case "webSearch":
            guard let query = text("query") else { return nil }
            return .webSearch(engine: text("engine") == "youtube" ? .youtube : .google, query: query)
        case "playSong": return text("query").map(VoiceIntent.playSong)
        case "browser": return text("command").flatMap(VoiceIntent.BrowserCommand.init).map(VoiceIntent.browser)
        case "typeText": return text("text").map(VoiceIntent.typeText)
        case "click": return text("label").map(VoiceIntent.click)
        case "mute": return .mute(o["on"] as? Bool ?? true)
        case "volume": return .volume(up: o["up"] as? Bool ?? true)
        case "timer":
            guard let seconds = (o["seconds"] as? NSNumber)?.intValue, (1...86_400).contains(seconds) else { return nil }
            return .timer(seconds: seconds)
        case "screenshot": return .screenshot
        case "lockScreen": return .lockScreen
        case "music": return text("command").flatMap(VoiceIntent.MusicCommand.init).map(VoiceIntent.music)
        case "systemCheck": return .systemCheck
        case "status": return .status
        case "agenda": return .agenda(AgendaDay(rawValue: text("day") ?? "today") ?? .today)
        case "runShortcut": return text("name").map(VoiceIntent.runShortcut)
        case "sendWhatsApp":
            guard let contact = text("contact"), let body = text("text") else { return nil }
            return .sendMessage(contact: contact, text: body)
        case "scheduleWhatsApp":
            guard let contact = text("contact"), let body = text("text") else { return nil }
            if let minutes = (o["inMinutes"] as? NSNumber)?.intValue, (1...10_080).contains(minutes) {
                return .scheduleMessage(contact: contact, text: body, at: .inMinutes(minutes))
            }
            guard let time = text("time"), case let parts = time.split(separator: ":").compactMap({ Int($0) }), parts.count == 2,
                  (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
            return .scheduleMessage(contact: contact, text: body, at: .at(hour: parts[0], minute: parts[1], dayOffset: nil))
        // Approving, denying or anything else is never taken from the AI.
        default: return nil
        }
    }
}
