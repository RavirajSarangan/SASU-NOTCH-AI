import Foundation

/// Reads WhatsApp requests out of a sentence, keeping the message's own
/// words and capitals: "send Amma I'll be late on WhatsApp",
/// "message Ravi saying the build is green", "tell Amma on WhatsApp that I'm
/// home", "send good night to Amma at 10 pm", "Amma ku WhatsApp la late aagum
/// nu anuppu". Nothing is sent from here: the app reads it back first.
public enum MessageParser {
    public static func parse(_ raw: String) -> VoiceIntent? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"(?i)\bwhat'?s\s?app\b"#, with: "WhatsApp", options: .regularExpression)
        let lower = text.lowercased()
        let mentionsWhatsApp = lower.contains("whatsapp")
        let startsLikeMessage = ["message ", "text ", "send a message", "send message", "send a text", "msg "].contains { lower.hasPrefix($0) }
        guard mentionsWhatsApp || startsLikeMessage else { return nil }

        // "open WhatsApp and send …", "… on WhatsApp", "WhatsApp la".
        text = text.replacingOccurrences(of: #"(?i)^(open|launch)\s+whatsapp\s+(and\s+)?"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)\s*\b(on|in|via|using|through|over)\s+whatsapp\b"#, with: "", options: .regularExpression)
        let (withoutTime, time) = extractTime(text)
        text = withoutTime.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))

        guard let (contact, message) = split(text) else { return nil }
        let body = clean(message)
        guard !body.isEmpty else { return nil }
        let who = clean(contact)
        if let time { return .scheduleMessage(contact: who, text: body, at: time) }
        return .sendMessage(contact: who, text: body)
    }

    /// (contact, text). An empty contact means the name starts the text.
    static func split(_ text: String) -> (String, String)? {
        let patterns: [(String, (contact: Int, text: Int))] = [
            // Tanglish: "Amma ku WhatsApp la late aagum nu anuppu".
            (#"^(.+?)\s+(?:ku|kku|kitta)\s+(?:whatsapp\s+(?:la|le|il)\s+)?(.+?)\s*(?:nu|endru)?\s+(?:anuppu|anupu|send pannu|அனுப்பு)$"#, (1, 2)),
            // "send a message to Amma saying …"
            (#"^(?:send|write)\s+(?:a\s+)?(?:whatsapp\s+)?(?:message|msg|text)\s+to\s+(.+?)\s*(?:saying|that|:|,)\s*(.+)$"#, (1, 2)),
            // "message Ravi saying …", "tell Amma that …", "WhatsApp Ravi: …"
            (#"^(?:message|msg|text|whatsapp|tell|send)\s+(.+?)\s*(?:\bsaying\b|\bthat\b|:|,)\s*(.+)$"#, (1, 2)),
            // "send hello to Amma"
            (#"^(?:send|write)\s+(.+?)\s+to\s+([^\s].{0,40})$"#, (2, 1)),
        ]
        for (pattern, groups) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let c = Range(match.range(at: groups.contact), in: text),
                  let t = Range(match.range(at: groups.text), in: text) else { continue }
            let contact = String(text[c])
            // "send a message to …" without a body falls through.
            if ["a message", "message", "a text"].contains(contact.lowercased()) { continue }
            return (contact, String(text[t]))
        }
        // "send Amma I'll be late", "message Ravi hi": the name is split off later.
        if let regex = try? NSRegularExpression(pattern: #"^(?:send|message|msg|text|whatsapp)\s+(?:a\s+)?(?:message\s+)?(?:to\s+)?(.+)$"#, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let rest = Range(match.range(at: 1), in: text) {
            return ("", String(text[rest]))
        }
        return nil
    }

    /// Removes quotes and a trailing full stop the recognizer added.
    static func clean(_ text: String) -> String {
        var t = text.trimmingCharacters(in: CharacterSet(charactersIn: " \"“”'‘,"))
        if t.hasSuffix("."), !t.hasSuffix("..") { t.removeLast() }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Finds "at 10 pm", "tomorrow at 8", "tonight at 9:30", "in 30 minutes" and
    /// returns the text without it.
    static func extractTime(_ text: String) -> (String, MessageTime?) {
        var rest = text
        var dayOffset: Int?
        if let r = rest.range(of: #"(?i)\b(tomorrow|naalai|nalaikku)\b"#, options: .regularExpression) {
            dayOffset = 1
            rest.removeSubrange(r)
        } else if let r = rest.range(of: #"(?i)\btoday\b"#, options: .regularExpression) {
            dayOffset = 0
            rest.removeSubrange(r)
        }
        var evening = false
        if let r = rest.range(of: #"(?i)\btonight\b"#, options: .regularExpression) {
            dayOffset = dayOffset ?? 0
            evening = true
            rest.removeSubrange(r)
        }
        let relative = try! NSRegularExpression(pattern: #"(?i)\bin\s+(\d{1,3})\s*(minutes?|mins?|hours?|hrs?)\b"#)
        if let m = relative.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
           let n = Range(m.range(at: 1), in: rest).flatMap({ Int(rest[$0]) }),
           let unit = Range(m.range(at: 2), in: rest).map({ rest[$0].lowercased() }),
           let whole = Range(m.range, in: rest) {
            let minutes = unit.hasPrefix("h") ? n * 60 : n
            rest.removeSubrange(whole)
            return (squeeze(rest), .inMinutes(minutes))
        }
        let clock = try! NSRegularExpression(pattern: #"(?i)\bat\s+(\d{1,2})(?:[:.](\d{2}))?\s*(a\.?m\.?|p\.?m\.?|o'?clock)?(?=\s|$|[,.!?])"#)
        if let m = clock.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
           var hour = Range(m.range(at: 1), in: rest).flatMap({ Int(rest[$0]) }),
           let whole = Range(m.range, in: rest) {
            let minute = Range(m.range(at: 2), in: rest).flatMap { Int(rest[$0]) } ?? 0
            let suffix = Range(m.range(at: 3), in: rest).map { rest[$0].lowercased() } ?? ""
            if suffix.hasPrefix("p"), hour < 12 { hour += 12 }
            if suffix.hasPrefix("a"), hour == 12 { hour = 0 }
            if evening, hour < 12 { hour += 12 }
            guard (0...23).contains(hour), (0...59).contains(minute) else { return (text, nil) }
            rest.removeSubrange(whole)
            return (squeeze(rest), .at(hour: hour, minute: minute, dayOffset: dayOffset))
        }
        // A day word without a time isn't a schedule: keep the words.
        return (text, nil)
    }

    private static func squeeze(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
}

/// Finds the chat a spoken name means.
public enum ContactMatcher {
    public enum Result: Equatable, Sendable {
        case one(String)
        case several([String])
        case none
    }

    public static func match(_ spoken: String, in names: [String]) -> Result {
        let query = tokens(spoken)
        guard !query.isEmpty else { return .none }
        var scored: [(name: String, score: Int)] = []
        for name in names {
            let parts = tokens(name)
            guard !parts.isEmpty else { continue }
            if parts == query { scored.append((name, 100)); continue }
            if parts.starts(with: query) { scored.append((name, 80 - parts.count)); continue }
            if query.allSatisfy({ q in parts.contains { $0.hasPrefix(q) } }) { scored.append((name, 60 - parts.count)); continue }
            if query.count == 1, parts.contains(where: { close($0, query[0]) }) { scored.append((name, 40 - parts.count)) }
        }
        guard let best = scored.map(\.score).max() else { return .none }
        let top = scored.filter { $0.score == best }.map(\.name)
        // A clearly better match wins; otherwise ask.
        let runnerUp = scored.filter { $0.score < best }.map(\.score).max() ?? 0
        if top.count == 1, best >= 80 || best - runnerUp >= 10 || scored.count == 1 { return .one(top[0]) }
        return .several(Array(Set(scored.filter { $0.score >= best - 5 }.map(\.name))).sorted().prefix(3).map { $0 })
    }

    /// Splits "Amma I'll be late" into ("Amma", "I'll be late") using the
    /// longest chat name the sentence starts with; else the first word.
    public static func split(_ phrase: String, names: [String]) -> (contact: String, text: String)? {
        let words = phrase.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return nil }
        var best: (count: Int, name: String)?
        for name in names {
            let parts = tokens(name)
            guard !parts.isEmpty, parts.count < words.count else { continue }
            // Full name, or just its first name.
            for count in [parts.count, 1] where count <= parts.count {
                let spoken = tokens(words.prefix(count).joined(separator: " "))
                if spoken == Array(parts.prefix(count)), count > (best?.count ?? 0) { best = (count, name) }
            }
        }
        let count = best?.count ?? 1
        return (words.prefix(count).joined(separator: " "), words.dropFirst(count).joined(separator: " "))
    }

    static func tokens(_ s: String) -> [String] {
        s.lowercased().unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) || CharacterSet.nonBaseCharacters.contains($0) ? Character($0) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").map(String.init)
    }

    /// One typo allowed for names of 4+ letters ("ravee" ~ "ravi" is too far; "amma" ~ "ama" is close).
    static func close(_ a: String, _ b: String) -> Bool {
        guard min(a.count, b.count) >= 3, abs(a.count - b.count) <= 1 else { return false }
        let x = Array(a), y = Array(b)
        var row = Array(0...y.count)
        for i in 1...x.count {
            var previous = row[0]
            row[0] = i
            for j in 1...y.count {
                let saved = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (x[i - 1] == y[j - 1] ? 0 : 1))
                previous = saved
            }
        }
        return row[y.count] <= 1
    }
}

/// The "check my system" answer: what was found and a short spoken summary.
public struct SystemReport: Equatable, Sendable {
    public struct Input: Sendable {
        public var securityScore: Int?
        /// Titles of security checks that need attention (most serious first).
        public var securityIssues: [String] = []
        public var recentAlerts = 0
        public var cpuHogs: [(name: String, percent: Double)] = []
        /// 1 normal, 2 warning, 4 critical (as `memory_pressure` reports).
        public var memoryPressure = 1
        public var diskFreeGB: Double?
        public var diskTotalGB: Double?
        public var batteryHealth: Int?
        public var batteryCycles: Int?
        public var uptimeDays = 0
        public var microphoneApps: [String] = []
        public var cameraOn = false
        public init() {}
    }

    public struct Finding: Equatable, Sendable {
        public enum Level: Int, Sendable, Comparable {
            case info, warning, critical
            public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
        }
        public var title: String
        public var detail: String
        public var level: Level
    }

    public var findings: [Finding]
    public var summary: String

    public init(_ i: Input) {
        var f: [Finding] = []
        for (index, issue) in i.securityIssues.enumerated() {
            f.append(Finding(title: issue, detail: "Open Nova Guard for a one-click fix.", level: index == 0 && (i.securityScore ?? 100) < 60 ? .critical : .warning))
        }
        if i.recentAlerts > 0 {
            f.append(Finding(title: "\(i.recentAlerts) security alert\(i.recentAlerts == 1 ? "" : "s") today", detail: "Review them in Nova Guard.", level: .warning))
        }
        if let hog = i.cpuHogs.first, hog.percent >= 80 {
            f.append(Finding(title: "\(hog.name) is using \(Int(hog.percent))% CPU", detail: "Quit it if you're not using it.", level: .warning))
        }
        if i.memoryPressure >= 4 {
            f.append(Finding(title: "Memory is full", detail: "Close apps you don't need.", level: .critical))
        } else if i.memoryPressure >= 2 {
            f.append(Finding(title: "Memory is getting tight", detail: "Close a few apps or browser tabs.", level: .warning))
        }
        if let free = i.diskFreeGB {
            if free < 10 {
                f.append(Finding(title: "Only \(Int(free)) GB free on disk", detail: "Free some space soon.", level: free < 5 ? .critical : .warning))
            }
        }
        if let health = i.batteryHealth, health < 80 {
            f.append(Finding(title: "Battery health is \(health)%", detail: "Consider a battery service.", level: .info))
        }
        if i.uptimeDays >= 14 {
            f.append(Finding(title: "Running for \(i.uptimeDays) days", detail: "A restart applies updates and frees memory.", level: .info))
        }
        if !i.microphoneApps.isEmpty {
            f.append(Finding(title: "Using the microphone: \(i.microphoneApps.joined(separator: ", "))", detail: "Make sure that's expected.", level: .info))
        }
        if i.cameraOn {
            f.append(Finding(title: "The camera is on", detail: "Make sure that's expected.", level: .info))
        }
        findings = f.sorted { $0.level > $1.level }

        let serious = findings.filter { $0.level >= .warning }
        var spoken = i.securityScore.map { "Security score \($0)." } ?? ""
        if serious.isEmpty {
            spoken += " No threats or problems found. Your Mac looks healthy."
        } else {
            let top = serious.prefix(2).map(\.title).joined(separator: ", and ")
            spoken += " I found \(serious.count) thing\(serious.count == 1 ? "" : "s") to look at: \(top)."
            if serious.count > 2 { spoken += " The rest are in Nova Guard." }
        }
        if let free = i.diskFreeGB, free >= 10 { spoken += " \(Int(free)) GB free." }
        summary = spoken.trimmingCharacters(in: .whitespaces)
    }

    public static func == (a: SystemReport, b: SystemReport) -> Bool { a.findings == b.findings && a.summary == b.summary }
}

/// Parses `ps` and `ioreg` output for the system check.
public enum SystemHealthParser {
    /// `ps -Aceo pcpu=,comm= -r` → the top 3 processes over 20% CPU.
    public static func cpuHogs(_ output: String, ignoring: Set<String> = []) -> [(name: String, percent: Double)] {
        output.split(separator: "\n").compactMap { line -> (String, Double)? in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, let cpu = Double(parts[0].replacingOccurrences(of: ",", with: ".")) else { return nil }
            let name = parts[1].trimmingCharacters(in: .whitespaces)
            return ignoring.contains(name) || cpu < 20 ? nil : (name, cpu)
        }.prefix(3).map { $0 }
    }

    /// `ioreg -rn AppleSmartBattery` → (health %, cycle count). Nil on desktops.
    public static func battery(_ output: String) -> (Int?, Int?) {
        func value(_ key: String) -> Int? {
            guard let r = output.range(of: "\"\(key)\" = ") else { return nil }
            return Int(output[r.upperBound...].prefix { $0.isNumber })
        }
        let design = value("DesignCapacity")
        let max = value("AppleRawMaxCapacity") ?? value("NominalChargeCapacity")
        let health = design.flatMap { d in max.map { d > 0 ? min(100, Int((Double($0) / Double(d) * 100).rounded())) : 0 } }
        return (health, value("CycleCount"))
    }
}
