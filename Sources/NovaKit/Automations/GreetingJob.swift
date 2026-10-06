import Foundation

/// Whether an automation may run right now. Automations only run while the
/// Mac is awake, unlocked and online.
public enum AutomationGate {
    public enum Decision: Equatable, Sendable {
        case go
        case wait(String)

        public var canRun: Bool { self == .go }
    }

    /// `sending` adds the checks needed to press Send in WhatsApp.
    public static func check(online: Bool, awake: Bool = true, screenLocked: Bool, sending: Bool,
                             whatsAppInstalled: Bool = true, accessibility: Bool = true, testMode: Bool = false) -> Decision {
        if !awake { return .wait("Waiting for the Mac to wake") }
        if !online { return .wait("Waiting for internet") }
        guard sending else { return .go }
        if !whatsAppInstalled { return .wait("WhatsApp for Mac isn't installed") }
        if screenLocked { return .wait("Waiting for you to unlock the Mac") }
        if !testMode && !accessibility { return .wait("Nova needs Accessibility permission to press Send") }
        return .go
    }
}

/// Today's good-morning greetings, persisted so a restart, sleep or lost
/// connection never drops them. The day only counts as done once every
/// greeting is sent, the user skips, or the cutoff passes.
public struct GreetingJob: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public var id: Int64          // chat id
        public var name: String
        public var phone: String
        /// nil until the AI has written it.
        public var text: String?
        public var sent = false
        public var attempts = 0

        public init(id: Int64, name: String, phone: String, text: String? = nil) {
            self.id = id
            self.name = name
            self.phone = phone
            self.text = text
        }
    }

    public var day: String
    /// When greetings go out (after the review window).
    public var sendAt: Date
    public var items: [Item]
    /// Earliest time for the next generate/send attempt after a failure.
    public var retryAt: Date?
    public var failures = 0
    /// The user has been told the greetings are ready for review.
    public var announced = false
    /// The cutoff passed before everything was sent; no more automatic sends.
    public var expired = false

    public init(day: String, sendAt: Date, items: [Item]) {
        self.day = day
        self.sendAt = sendAt
        self.items = items
    }

    /// Backoff after consecutive failures: 1, 2, 5, then every 10 minutes.
    public static let backoff: [TimeInterval] = [60, 120, 300, 600]

    public var needsText: [Item] { items.filter { $0.text == nil && !$0.sent } }
    public var readyToSend: [Item] { items.filter { $0.text != nil && !$0.sent } }
    public var unsent: [Item] { items.filter { !$0.sent } }
    public var isComplete: Bool { items.allSatisfy(\.sent) }

    public func canAttempt(now: Date) -> Bool { retryAt.map { now >= $0 } ?? true }
    public func isSendTime(now: Date) -> Bool { now >= sendAt }

    public mutating func setText(_ text: String, for id: Int64) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].text = text }
    }

    public mutating func markSent(_ id: Int64) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].sent = true }
        failures = 0
        retryAt = nil
    }

    public mutating func recordFailure(for id: Int64? = nil, now: Date) {
        if let id, let i = items.firstIndex(where: { $0.id == id }) { items[i].attempts += 1 }
        retryAt = now.addingTimeInterval(Self.backoff[min(failures, Self.backoff.count - 1)])
        failures += 1
    }

    public mutating func remove(_ id: Int64) { items.removeAll { $0.id == id } }

    /// Past the schedule's cutoff on the job's day (or a later day): stop
    /// sending automatically so nobody gets "good morning" in the afternoon.
    public func isExpired(now: Date, schedule: MorningSchedule, calendar: Calendar = .current) -> Bool {
        if MorningSchedule.dayKey(now, calendar: calendar) != day { return true }
        let cutoff = calendar.date(bySettingHour: schedule.cutoffHour, minute: 0, second: 0, of: now) ?? now
        return now >= cutoff
    }
}

/// Compares WhatsApp's chat box with the message Nova filled in, ignoring
/// whitespace differences and the invisible characters WhatsApp may add.
public enum ComposeMatch {
    public static func matches(box: String, text: String) -> Bool {
        let a = normalize(box), b = normalize(text)
        return !b.isEmpty && a == b
    }

    static func normalize(_ s: String) -> String {
        let invisible: Set<Character> = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}", "\u{2060}"]
        return s.filter { !invisible.contains($0) }
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
