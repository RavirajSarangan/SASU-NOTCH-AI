import Foundation
import NovaKit
import Observation

enum ReplyLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english, tamil, tanglish

    var id: String { rawValue }
    var label: String {
        switch self {
        case .english: "English"
        case .tamil: "Tamil (தமிழ்)"
        case .tanglish: "Tanglish"
        }
    }
}

struct WAContactSettings: Codable, Identifiable, Equatable, Sendable {
    var id: Int64             // WhatsApp chat row id
    var jid: String
    var name: String
    /// International number as digits. Needed to send; WhatsApp only knows it for saved contacts.
    var phone: String?
    var morningGreeting = true
    var draftReplies = true
    var language: ReplyLanguage = .english
    var toneNote = ""
}

/// Non-secret automation settings, persisted to automations.json in
/// Application Support. Contains no message history.
struct AutomationSettingsData: Codable, Equatable {
    var briefEnabled = true
    var briefSchedule = MorningSchedule(hour: 8, minute: 0)
    var lastBriefDay: String?

    var greetingsEnabled = false
    var greetingSchedule = MorningSchedule(hour: 7, minute: 30)
    var lastGreetingDay: String?
    /// Greetings Nova sent recently (per contact jid), so new ones don't repeat.
    var recentGreetings: [String: [String]] = [:]
    /// Today's greetings in progress (persisted so restarts and lost
    /// connections don't drop them).
    var greetingJob: GreetingJob?
    /// The user's own WhatsApp number, for "Send a test to myself".
    var selfPhone: String?

    var draftsEnabled = true
    /// Test mode: open WhatsApp and fill the message, but never press Send.
    var testMode = true
    var lastSeenMessageId: Int64 = 0
    var contacts: [WAContactSettings] = []
    /// One-off messages you scheduled by voice. Optional so older files still load.
    var scheduledMessages: [ScheduledMessage]?
}

/// "Send good night to Amma at 10 pm."
struct ScheduledMessage: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var chatId: Int64
    var name: String
    var phone: String
    var text: String
    var at: Date
    var warned = false
}

@Observable
@MainActor
final class AutomationStore {
    var data: AutomationSettingsData {
        didSet { if data != oldValue { save() } }
    }

    private static var url: URL { NovaPathsApp.support.appendingPathComponent("automations.json") }

    init() {
        if let raw = try? Data(contentsOf: Self.url), let decoded = try? JSONDecoder().decode(AutomationSettingsData.self, from: raw) {
            data = decoded
        } else {
            data = AutomationSettingsData()
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: NovaPathsApp.support, withIntermediateDirectories: true)
        try? JSONEncoder().encode(data).write(to: Self.url, options: .atomic)
    }

    func contact(_ id: Int64) -> WAContactSettings? { data.contacts.first { $0.id == id } }

    func upsert(_ contact: WAContactSettings) {
        if let i = data.contacts.firstIndex(where: { $0.id == contact.id }) {
            data.contacts[i] = contact
        } else {
            data.contacts.append(contact)
        }
    }

    func remove(_ id: Int64) {
        data.contacts.removeAll { $0.id == id }
    }

    func rememberGreeting(_ text: String, for jid: String) {
        var list = data.recentGreetings[jid] ?? []
        list.append(text)
        data.recentGreetings[jid] = Array(list.suffix(7))
    }
}
