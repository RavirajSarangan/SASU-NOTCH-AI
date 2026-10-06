import Foundation

/// Which part of the calendar you asked about.
public enum AgendaDay: String, Sendable { case next, today, tomorrow }

/// One calendar event, as Nova needs it.
public struct AgendaItem: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    public var allDay: Bool
    public var joinURL: URL?

    public init(title: String, start: Date, end: Date, allDay: Bool = false, joinURL: URL? = nil) {
        self.title = title; self.start = start; self.end = end; self.allDay = allDay; self.joinURL = joinURL
    }
}

public enum Agenda {
    /// What Nova says for "what's next" / "what's on today".
    public static func spoken(_ items: [AgendaItem], day: AgendaDay, now: Date, calendar: Calendar = .current) -> String {
        func time(_ d: Date) -> String {
            d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "en_US")))
                .replacingOccurrences(of: "\u{202F}", with: " ")
        }
        let timed = items.filter { !$0.allDay }.sorted { $0.start < $1.start }
        switch day {
        case .next:
            if let current = timed.first(where: { $0.start <= now && $0.end > now }) {
                let next = timed.first { $0.start > now }
                return "You're in \(current.title) until \(time(current.end))." + (next.map { " Next: \($0.title) at \(time($0.start))." } ?? "")
            }
            guard let next = timed.first(where: { $0.start > now }) else { return "Nothing else on your calendar today." }
            let minutes = Int(next.start.timeIntervalSince(now) / 60)
            let when = minutes < 60 ? "in \(max(minutes, 1)) minute\(minutes == 1 ? "" : "s")" : "at \(time(next.start))"
            return "Next: \(next.title), \(when)."
        case .today, .tomorrow:
            let label = day == .today ? "today" : "tomorrow"
            let upcoming = day == .today ? timed.filter { $0.end > now } : timed
            let allDay = items.filter(\.allDay).map(\.title)
            guard !upcoming.isEmpty || !allDay.isEmpty else { return "Nothing on your calendar \(label)." }
            var parts = upcoming.prefix(3).map { "\($0.title) at \(time($0.start))" }
            if upcoming.count > 3 { parts.append("\(upcoming.count - 3) more") }
            var sentence = upcoming.isEmpty ? "" : "\(label.capitalized) you have \(upcoming.count) event\(upcoming.count == 1 ? "" : "s"): " + list(parts) + "."
            if !allDay.isEmpty { sentence += (sentence.isEmpty ? "" : " ") + "All day: \(list(allDay.prefix(2).map { $0 }))." }
            return sentence
        }
    }

    static func list(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
    }

    /// A Zoom, Meet, Teams or Webex link in an event's URL, location or notes.
    public static func joinURL(in texts: [String?]) -> URL? {
        let pattern = #"https?://(?:[\w-]+\.)?(?:zoom\.us/j/[\w?=&./-]+|meet\.google\.com/[\w-]+|teams\.microsoft\.com/l/meetup-join/[^\s<>"]+|teams\.live\.com/meet/[^\s<>"]+|[\w-]+\.webex\.com/[^\s<>"]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        for text in texts.compactMap({ $0 }) {
            if let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let r = Range(m.range, in: text) {
                return URL(string: String(text[r]))
            }
        }
        return nil
    }
}

/// "Remind me at 5 to call Amma", "remind me in 20 minutes to stretch".
enum ReminderParser {
    static func parse(_ raw: String) -> VoiceIntent? {
        let lower = raw.lowercased()
        let prefixes = ["remind me", "set a reminder", "add a reminder", "create a reminder", "reminder"]
        guard let prefix = prefixes.first(where: { lower.hasPrefix($0) }) else { return nil }
        var rest = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,:"))
        let (withoutTime, time) = MessageParser.extractTime(rest)
        rest = withoutTime.trimmingCharacters(in: CharacterSet(charactersIn: " ,:"))
        while let lead = ["to ", "that ", "about ", "for "].first(where: { rest.lowercased().hasPrefix($0) }) {
            rest = String(rest.dropFirst(lead.count))
        }
        rest = MessageParser.clean(rest)
        guard !rest.isEmpty else { return nil }
        return .addReminder(text: rest, at: time)
    }
}
