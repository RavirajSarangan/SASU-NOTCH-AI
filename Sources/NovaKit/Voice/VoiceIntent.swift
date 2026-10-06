import Foundation

/// What a spoken request means. Built-in commands run locally; anything else
/// goes to the AI chat provider as a question.
public enum VoiceIntent: Equatable, Sendable {
    case status
    /// Deny the pending agent request.
    case deny
    /// The user tried to approve by voice. Voice can never approve; Nova explains.
    case refuseAllow
    case readBrief
    case music(MusicCommand)
    case scanSecurity
    case openApp(String)
    case quitApp(String)
    case switchTo(String)
    case openWebsite(String)
    case webSearch(engine: SearchEngine, query: String)
    case playSong(String)
    case browser(BrowserCommand)
    /// Type text into the focused field (never a password field).
    case typeText(String)
    /// Press a button by its name in the front app.
    case click(String)
    case mute(Bool)
    case timer(seconds: Int)
    case screenshot
    case lockScreen
    /// WhatsApp message. An empty `contact` means "the name is at the start of
    /// `text`" (split later against your chat names with `ContactMatcher`).
    case sendMessage(contact: String, text: String)
    case scheduleMessage(contact: String, text: String, at: MessageTime)
    /// Security plus health: threats, CPU, memory, disk, battery.
    case systemCheck
    case findFile(FileQuery)
    /// "Open the second one" (1-based) after a file search.
    case openResult(Int)
    /// "Show it in Finder."
    case revealResult
    case clipboard(ClipboardTask)
    case agenda(AgendaDay)
    /// "How much usage do I have left?"
    case usage
    /// Run one of your Apple Shortcuts by name.
    case runShortcut(String)
    /// "Make a routine called gym: open Spotify, timer 45 minutes."
    case makeRoutine(name: String, description: String)
    case addReminder(text: String, at: MessageTime?)
    case volume(up: Bool)
    case time
    case date
    case stopSpeaking
    // Fun
    case dance
    case joke
    case coinFlip
    case rollDie
    case highFive
    /// Only the wake word was heard; wait for the request.
    case wakeOnly
    case ask(String)

    public enum MusicCommand: String, Sendable { case play, pause, next, previous }
    public enum SearchEngine: String, Sendable { case google, youtube }
    public enum BrowserCommand: String, Sendable { case newTab, closeTab, back, forward, reload, nextTab, previousTab }
}

/// When a scheduled message goes out.
public enum MessageTime: Equatable, Sendable {
    case inMinutes(Int)
    /// A clock time; `dayOffset` nil means "the next time it's this time".
    case at(hour: Int, minute: Int, dayOffset: Int?)

    public func resolve(now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .inMinutes(let minutes):
            return now.addingTimeInterval(Double(minutes) * 60)
        case .at(let hour, let minute, let dayOffset):
            let day = calendar.date(byAdding: .day, value: dayOffset ?? 0, to: calendar.startOfDay(for: now)) ?? now
            let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? now
            if dayOffset == nil, date <= now { return calendar.date(byAdding: .day, value: 1, to: date) ?? date }
            return date
        }
    }
}

/// Maps a transcript to an intent with simple, predictable rules (English,
/// Tamil script and Tanglish). Rules are checked from most to least
/// specific; the approve family is checked before everything else so a
/// sentence like "allow it" can never fall through to an action.
public enum VoiceIntentRouter {
    public static let wakeWords = ["hey nova", "hi nova", "ok nova", "okay nova", "hello nova", "ஹே நோவா", "நோவா", "nova"]

    public static func route(_ transcript: String) -> VoiceIntent {
        let text = normalize(stripWakeWord(transcript))
        if text.isEmpty { return .wakeOnly }
        let words = Set(text.split(separator: " ").map(String.init))
        func has(_ phrases: [String]) -> Bool {
            phrases.contains { phrase in
                phrase.contains(" ") || phrase.unicodeScalars.contains(where: { $0.value > 0x7F }) ? text.contains(phrase) : words.contains(phrase)
            }
        }

        // WhatsApp messages come first: their text may contain any words
        // ("go ahead", "don't allow"), and they're only sent after you confirm.
        if let message = MessageParser.parse(stripWakeWord(transcript).trimmingCharacters(in: .whitespacesAndNewlines)) { return message }

        // Denials first ("don't allow" is a denial), then approvals, which voice never does.
        if has(["deny", "reject", "block it", "dont allow", "don't allow", "do not allow", "decline", "cancel that", "vendam", "venam", "வேண்டாம்", "maruthu", "மறு"]) {
            return .deny
        }
        // Approvals: never by voice.
        if has(["allow", "approve", "approved", "accept", "permit", "go ahead", "yes do it", "do it", "run it", "anumathi", "அனுமதி", "sari pannu", "ok pannu"]) {
            return .refuseAllow
        }

        let raw = stripWakeWord(transcript).trimmingCharacters(in: .whitespacesAndNewlines)

        // Agent usage and plan limits.
        if has(["usage", "my limit", "rate limit", "how many tokens", "tokens left", "token usage", "near my limit", "hit the limit"]) {
            return .usage
        }

        // Routines you create by voice, and Apple Shortcuts.
        if let made = Self.routineRequest(raw) { return made }
        if let shortcut = Self.shortcutName(text) { return .runShortcut(shortcut) }

        // Calendar and reminders (before music, so "what's next" isn't a song).
        if let reminder = ReminderParser.parse(raw) { return reminder }
        if has(["what's next", "whats next", "what is next", "next meeting", "my next meeting", "what's my next", "whats my next"]) {
            return .agenda(.next)
        }
        if has(["calendar", "schedule", "meetings", "agenda", "events"]) && (has(["what", "what's", "whats", "my", "any", "enna", "show", "read"])) {
            return .agenda(has(["tomorrow", "naalai", "nalaikku"]) ? .tomorrow : .today)
        }

        // Files: "find my resume", "open the invoice PDF from last week", then "open the second one".
        if let n = Self.resultIndex(text) { return .openResult(n) }
        if has(["show it in finder", "show that in finder", "reveal it", "in finder"]) && words.count <= 5 { return .revealResult }
        if let query = FileQuery.parse(text) { return .findFile(query) }

        // Clipboard: "summarise what I copied", "translate this to Tamil", "fix the grammar in my clipboard".
        if let task = ClipboardTask.parse(text) { return .clipboard(task) }

        // Whole-system check (threats and health).
        if has(["check my system", "check the system", "check my mac", "system check", "full check", "full system check", "any threats",
                "any threat", "any issues", "system health", "health check", "is my system ok", "is my mac ok", "system safe ah",
                "en system safe ah", "system check pannu", "சிஸ்டம் செக்"]) {
            return .systemCheck
        }

        // Browser: before music, so "next tab" and "go back" aren't songs.
        if has(["new tab", "open a new tab", "puthu tab"]) { return .browser(.newTab) }
        if has(["close tab", "close this tab", "close the tab", "tab close pannu", "tab moodu"]) { return .browser(.closeTab) }
        if has(["next tab"]) { return .browser(.nextTab) }
        if has(["previous tab", "last tab"]) { return .browser(.previousTab) }
        if has(["reload", "refresh", "refresh the page", "reload the page"]) { return .browser(.reload) }
        if has(["go forward"]) { return .browser(.forward) }
        if has(["go back", "back page", "previous page"]) && !has(["song", "track", "music"]) { return .browser(.back) }

        // Typing and clicking keep the original wording (names, capitals).
        if let text = Self.rest(of: raw, after: ["type", "dictate"]), !text.isEmpty { return .typeText(text) }
        if let label = Self.rest(of: raw, after: ["click on", "click", "press", "tap on", "tap"]), !label.isEmpty {
            return .click(Self.cleanLabel(label))
        }
        if words.count >= 2, has(["click pannu", "press pannu", "button click"]) {
            let label = text.replacingOccurrences(of: " click pannu", with: "").replacingOccurrences(of: " press pannu", with: "")
                .replacingOccurrences(of: " button click", with: "")
            return .click(Self.cleanLabel(label))
        }

        // Searches: "google swift actors", "search for …", "youtube lo-fi", "google la … thedu".
        if let query = Self.searchQuery(text) { return query }

        // Music.
        let music = has(["music", "song", "songs", "track", "spotify", "paattu", "pattu", "பாட்டு", "song ah"])
        if let song = Self.songRequest(text) { return .playSong(song) }
        if has(["next", "skip", "adutha", "அடுத்த"]) && (music || words.count <= 3) { return .music(.next) }
        if has(["previous", "last song", "munthaiya", "முந்தைய"]) && (music || words.count <= 3) { return .music(.previous) }
        if has(["pause", "niruthu", "நிறுத்து"]) || (music && has(["stop", "off"])) { return .music(.pause) }
        if (music && has(["play", "start", "resume", "podu", "போடு", "on"])) || has(["paattu podu", "பாட்டு போடு", "play some music", "play music"]) {
            return .music(.play)
        }

        // Fun.
        if has(["dance", "dancing", "let's dance", "lets dance", "aadu", "dance aadu", "ஆடு", "நடனம்"]) { return .dance }
        if has(["joke", "jokes", "make me laugh", "something funny", "joke sollu", "jokes sollu", "ஜோக்"]) { return .joke }
        if has(["flip a coin", "coin flip", "toss a coin", "heads or tails", "toss"]) { return .coinFlip }
        if has(["roll a die", "roll a dice", "roll the dice", "roll dice", "dice"]) { return .rollDie }
        if has(["high five", "high-five", "hi five", "give me five"]) { return .highFive }

        // Stop talking.
        if text == "stop" || has(["be quiet", "shut up", "stop talking", "quiet", "silence", "pesaathe", "பேசாதே", "nirutthu pesa"]) {
            return .stopSpeaking
        }

        // Status of agents.
        if has(["what are my agents", "agents doing", "agent status", "status", "whats happening", "what's happening", "what is happening",
                "what's going on", "whats going on", "how is claude", "enna nadakkuthu", "enna nadakuthu", "என்ன நடக்குது", "என்ன நடக்கிறது"]) {
            return .status
        }

        // Security.
        if has(["scan security", "security scan", "am i safe", "is my mac safe", "check security", "run a scan", "security check",
                "safe ah", "பாதுகாப்பு"]) {
            return .scanSecurity
        }

        // Brief.
        if has(["brief", "my mail", "my email", "my emails", "inbox", "read my mail", "mail check"]) { return .readBrief }

        // Mute.
        if has(["unmute", "sound on", "unmute sound"]) { return .mute(false) }
        if has(["mute", "mute sound", "sound off", "sound mute"]) { return .mute(true) }

        // Volume.
        if has(["volume up", "louder", "turn it up", "increase volume", "sound up", "sound athigam", "சத்தம் அதிகம்"]) { return .volume(up: true) }
        if has(["volume athigam", "volume ethu"]) { return .volume(up: true) }
        if has(["volume down", "volume koraiyu", "volume korai", "quieter", "turn it down", "lower the volume", "decrease volume", "sound down", "sound kammi", "சத்தம் குறை"]) {
            return .volume(up: false)
        }

        // Time and date.
        if has(["what time", "the time", "time now", "time enna", "மணி என்ன", "mani enna"]) { return .time }
        if has(["what date", "what day", "today's date", "todays date", "date enna", "தேதி"]) { return .date }

        // Timer, screenshot, lock.
        if has(["timer", "countdown"]), let seconds = Self.duration(in: text) { return .timer(seconds: seconds) }
        if has(["screenshot", "screen shot", "screenshot edu", "capture the screen"]) { return .screenshot }
        if has(["lock my mac", "lock the mac", "lock screen", "lock the screen", "lock my screen", "lock pannu"]) { return .lockScreen }

        // Quit or switch apps.
        if let app = Self.target(of: text, after: ["quit", "close", "exit", "kill"]) ?? Self.target(before: text, of: ["close pannu", "moodu"]) {
            return .quitApp(app)
        }
        if let app = Self.target(of: text, after: ["switch to", "go to", "bring up", "show me"]) { return .switchTo(app) }

        // Open an app or a site: "open safari", "launch notes", "open github.com", "safari open pannu", "safari thira".
        if let app = appName(in: text) {
            if let site = Self.website(app) { return .openWebsite(site) }
            return .openApp(app)
        }

        return .ask(stripWakeWord(transcript).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The wake word with punctuation and common mishearings: speech
    /// recognition often writes "Hello, Nova." or hears "Noah", "Nover" or
    /// "No va". Those only count after a greeting; a bare "Nova" counts alone.
    /// Never matches inside a word ("supernova").
    static let wakePattern: NSRegularExpression = {
        let edgeL = "(?<![\\p{L}\\p{M}\\p{N}])", edgeR = "(?![\\p{L}\\p{M}\\p{N}])"
        let greeting = "(?:hey|hay|hi|hello|hallo|ok|okay)"
        let name = "(?:nova|noah|nover|novah|novaa|nava|no va|nowa)"
        let pattern = "\(edgeL)(?:\(greeting)[\\s,.!]+\(name)|nova|ஹே\\s*நோவா|நோவா)\(edgeR)[\\s,.!?:;-]*"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static func wakeMatches(_ text: String) -> [NSTextCheckingResult] {
        wakePattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// Removes a leading wake word ("hey nova, …").
    public static func stripWakeWord(_ transcript: String) -> String {
        guard let first = wakeMatches(transcript).first, let range = Range(first.range, in: transcript),
              transcript[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return transcript }
        return String(transcript[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?:"))
    }

    /// What was said after the last wake word, or the whole text if there is none.
    public static func textAfterWakeWord(_ transcript: String) -> String {
        guard let last = wakeMatches(transcript).last, let range = Range(last.range, in: transcript) else { return transcript }
        return String(transcript[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?:"))
    }

    /// True when the transcript contains a wake word anywhere.
    public static func containsWakeWord(_ transcript: String) -> Bool {
        !wakeMatches(transcript).isEmpty
    }

    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased().replacingOccurrences(of: "’", with: "'")
        let kept = lowered.unicodeScalars.map { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
            || CharacterSet.nonBaseCharacters.contains($0) || $0 == "'" ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    public enum Interruption: Equatable, Sendable { case wake, stop }

    /// While Nova speaks: did you say "Hey Nova" or "stop"? Only the last few
    /// words count, and words that are in Nova's own reply are ignored (the
    /// microphone can hear the speaker).
    public static func interruption(in heard: String, reply: String) -> Interruption? {
        let tail = normalize(heard).split(separator: " ").suffix(4).joined(separator: " ")
        let said = normalize(reply)
        for wake in ["hey nova", "hi nova", "ok nova", "okay nova", "hello nova"] where tail.contains(wake) && !said.contains(wake) {
            return .wake
        }
        let words = Set(tail.split(separator: " ").map(String.init))
        for stop in ["stop", "wait", "enough", "niruthu", "podhum"] where words.contains(stop) && !said.split(separator: " ").contains(Substring(stop)) {
            return .stop
        }
        return nil
    }

    /// "make a routine called gym: open Spotify, timer 45 minutes".
    static func routineRequest(_ raw: String) -> VoiceIntent? {
        let pattern = #"(?i)^(?:make|create|save|new)\s+(?:a\s+)?routine\s+(?:called|named)?\s*(.+?)\s*(?::|,|\bthat\b|\bto\b|\bwhich\b)\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let n = Range(m.range(at: 1), in: raw), let d = Range(m.range(at: 2), in: raw) else { return nil }
        let name = raw[n].trimmingCharacters(in: .whitespaces), description = raw[d].trimmingCharacters(in: .whitespaces)
        return name.isEmpty || description.isEmpty ? nil : .makeRoutine(name: name, description: description)
    }

    /// "run the log water shortcut", "shortcut log water", "log water shortcut run pannu".
    static func shortcutName(_ text: String) -> String? {
        let patterns = [#"^run\s+(?:the\s+|my\s+)?(.+?)\s+shortcut$"#, #"^(?:run\s+)?(?:the\s+)?shortcut\s+(.+)$"#,
                        #"^(.+?)\s+shortcut\s+(?:run\s+pannu|podu|run)$"#]
        for pattern in patterns {
            if let r = text.range(of: pattern, options: .regularExpression),
               let regex = try? NSRegularExpression(pattern: pattern),
               let m = regex.firstMatch(in: text, range: NSRange(r, in: text)),
               let name = Range(m.range(at: 1), in: text) {
                return String(text[name])
            }
        }
        return nil
    }

    /// "open the second one" → 2.
    static func resultIndex(_ text: String) -> Int? {
        guard text.hasPrefix("open the ") || text.hasPrefix("open ") || text.hasPrefix("the "), text.hasSuffix(" one") || text.hasSuffix(" file") else { return nil }
        let ordinals = ["first": 1, "1st": 1, "second": 2, "2nd": 2, "third": 3, "3rd": 3, "fourth": 4, "4th": 4, "fifth": 5, "5th": 5, "last": 5, "next": 2]
        return text.split(separator: " ").compactMap { ordinals[String($0)] }.first
    }

    /// The words after a leading command word, in the original text: "type Hello Team." → "Hello Team".
    static func rest(of raw: String, after commands: [String]) -> String? {
        let lower = raw.lowercased()
        for command in commands where lower.hasPrefix(command + " ") || lower.hasPrefix(command + ",") {
            let rest = raw.dropFirst(command.count).trimmingCharacters(in: CharacterSet(charactersIn: " ,:"))
            return rest.hasSuffix(".") ? String(rest.dropLast()) : rest
        }
        return nil
    }

    /// "the Continue button" → "Continue".
    static func cleanLabel(_ label: String) -> String {
        var words = label.trimmingCharacters(in: CharacterSet(charactersIn: " .,!?")).split(separator: " ").map(String.init)
        if words.first?.lowercased() == "the" { words.removeFirst() }
        if let last = words.last?.lowercased(), ["button", "link", "tab", "menu"].contains(last), words.count > 1 { words.removeLast() }
        return words.joined(separator: " ")
    }

    static func searchQuery(_ text: String) -> VoiceIntent? {
        let youtube: [String] = ["search youtube for", "youtube search", "search on youtube for", "youtube"]
        let google: [String] = ["search google for", "google search", "search the web for", "search for", "look up", "google", "search"]
        // "play lo-fi on youtube"
        if text.hasPrefix("play "), text.hasSuffix(" on youtube") {
            let query = String(text.dropFirst(5).dropLast(11))
            return query.isEmpty ? nil : .webSearch(engine: .youtube, query: query)
        }
        // Tanglish: "google la swift actors thedu", "youtube la lofi paru".
        let words = text.split(separator: " ").map(String.init)
        if words.count >= 3, ["google", "youtube"].contains(words[0]), ["la", "le", "il"].contains(words[1]) {
            let query = words.dropFirst(2).filter { !["thedu", "thedungo", "paru", "search", "pannu"].contains($0) }.joined(separator: " ")
            if !query.isEmpty { return .webSearch(engine: words[0] == "youtube" ? .youtube : .google, query: query) }
        }
        for (engine, prefixes) in [(VoiceIntent.SearchEngine.youtube, youtube), (.google, google)] {
            for prefix in prefixes where text.hasPrefix(prefix + " ") {
                let query = String(text.dropFirst(prefix.count + 1)).trimmingCharacters(in: .whitespaces)
                if !query.isEmpty { return .webSearch(engine: engine, query: query) }
            }
        }
        return nil
    }

    /// "play anirudh", "play believer on spotify" → a song search. "play some music" isn't one.
    static func songRequest(_ text: String) -> String? {
        guard text.hasPrefix("play ") else { return nil }
        let words = text.dropFirst(5).split(separator: " ").map(String.init)
        if words.contains("some") { return nil }
        let filler: Set = ["the", "a", "me", "my", "music", "song", "songs", "track", "on", "spotify", "please", "it", "again", "something", "paattu", "pattu"]
        let query = words.filter { !filler.contains($0) }.joined(separator: " ")
        return query.isEmpty ? nil : query
    }

    /// Seconds in "timer for 10 minutes", "5 minute timer", "timer 30 seconds", "10 nimisham timer".
    static func duration(in text: String) -> Int? {
        let numbers = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
                       "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40, "forty five": 45, "fifty": 50, "sixty": 60, "a": 1, "an": 1, "half": 0]
        let words = text.split(separator: " ").map(String.init)
        for (i, word) in words.enumerated() {
            let unit = i + 1 < words.count ? words[i + 1] : ""
            guard let value = Int(word) ?? numbers[word] else { continue }
            if unit.hasPrefix("hour") || unit == "mani" { return value * 3600 }
            if unit.hasPrefix("min") || unit.hasPrefix("nimi") { return value * 60 }
            if unit.hasPrefix("sec") || unit == "vinadi" { return value }
        }
        if text.contains("half an hour") { return 1800 }
        return nil
    }

    /// "quit spotify" → "spotify". Ignores tabs and windows (browser commands).
    static func target(of text: String, after verbs: [String]) -> String? {
        for verb in verbs where text.hasPrefix(verb + " ") {
            let name = text.dropFirst(verb.count + 1).split(separator: " ").map(String.init)
                .filter { !["the", "app", "application", "please"].contains($0) }.joined(separator: " ")
            guard !name.isEmpty, !["tab", "this tab", "window", "this window", "it", "this"].contains(name) else { return nil }
            return name
        }
        return nil
    }

    /// "spotify close pannu" → "spotify".
    static func target(before text: String, of suffixes: [String]) -> String? {
        for suffix in suffixes where text.hasSuffix(" " + suffix) {
            let name = String(text.dropLast(suffix.count + 1))
            return name.isEmpty || name == "tab" ? nil : name
        }
        return nil
    }

    /// A site name: anything with a dot ("github.com", "youtube dot com").
    static func website(_ name: String) -> String? {
        // Normalizing turned "github.com" into "github com".
        var words = name.replacingOccurrences(of: " dot ", with: " ").split(separator: " ").map(String.init)
        guard words.count >= 2, let tld = words.last, topLevelDomains.contains(tld) else { return nil }
        words.removeLast()
        return words.joined() + "." + tld
    }

    static let topLevelDomains: Set = ["com", "org", "net", "io", "dev", "ai", "app", "co", "in", "lk", "uk", "me", "so", "tv"]

    /// "Hey Safari" opens Safari, but only for apps installed on this Mac, so
    /// ordinary speech ("hey mom") never triggers anything.
    public static func heyApp(_ transcript: String, apps: [String]) -> String? {
        let text = normalize(transcript)
        let padded = " " + text
        for greeting in ["hey ", "hi ", "ok ", "okay ", "hello "] {
            // Only a whole word: "took notes" isn't "ok notes".
            guard let range = padded.range(of: " " + greeting) else { continue }
            let after = padded[range.upperBound...]
            // Longest name first: "hey visual studio code" beats "hey visual".
            for app in apps.sorted(by: { $0.count > $1.count }) {
                let name = app.lowercased()
                if after == name || after.hasPrefix(name + " ") { return app }
            }
        }
        return nil
    }

    static func appName(in text: String) -> String? {
        let words = text.split(separator: " ").map(String.init)
        // Tanglish first: "safari open pannu", "notes thira".
        if words.count >= 3, words.last == "pannu", words[words.count - 2] == "open" {
            return words.dropLast(2).joined(separator: " ")
        }
        if let i = words.firstIndex(where: { ["open", "launch", "start"].contains($0) }), i + 1 < words.count {
            let name = words[(i + 1)...].filter { !["the", "app", "application", "please"].contains($0) }.joined(separator: " ")
            return name.isEmpty ? nil : name
        }
        if let i = words.firstIndex(where: { ["thira", "thirakku", "திற"].contains($0) }), i > 0 {
            return words[..<i].joined(separator: " ")
        }
        return nil
    }
}
