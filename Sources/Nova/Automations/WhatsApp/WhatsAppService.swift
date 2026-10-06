import AppKit
import Foundation
import NovaKit
import Observation

/// A drafted reply waiting for the user's approval.
struct ReplyDraft: Identifiable, Equatable {
    let id = UUID()
    var contact: WAContactSettings
    var phone: String
    var incoming: String
    var draft: String
    var sensitive: Bool
    var receivedAt: Date
}

/// Tomorrow-morning (or now) greetings waiting to go out.
struct PendingGreeting: Identifiable, Equatable {
    var id: Int64 { contact.id }
    var contact: WAContactSettings
    var phone: String
    var text: String
}

enum WhatsAppAccess: Equatable {
    case ok, notInstalled, noDataAccess(String), schemaChanged(String)

    var message: String? {
        switch self {
        case .ok: nil
        case .notInstalled: "WhatsApp for Mac isn't installed."
        case .noDataAccess: "Nova can't read WhatsApp's data. Allow it when macOS asks, or give Nova Full Disk Access in System Settings → Privacy & Security."
        case .schemaChanged(let detail): "WhatsApp's data format changed (\(detail)). Reading is paused until Nova is updated."
        }
    }
}

/// Watches selected WhatsApp chats, drafts replies with AI (sent only on the
/// user's click), and sends the scheduled good-morning messages.
@Observable
@MainActor
final class WhatsAppService {
    private(set) var access: WhatsAppAccess = .ok
    private(set) var chats: [WAChat] = []
    private(set) var drafts: [ReplyDraft] = []
    /// Why automations are paused right now (offline, locked…), if they are.
    private(set) var waitingReason: String?
    private(set) var isDrafting = false
    private(set) var lastStatus: String?

    /// Called when a new draft is ready or greetings are scheduled.
    @ObservationIgnored var onDraft: ((ReplyDraft) -> Void)?
    @ObservationIgnored var onGreetingsScheduled: ((Int) -> Void)?
    @ObservationIgnored var onStatus: ((String, Bool) -> Void)?

    @ObservationIgnored let settings: AutomationStore
    @ObservationIgnored private let ai: AIService
    @ObservationIgnored private var store: WhatsAppStore?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var walSource: DispatchSourceFileSystemObject?
    @ObservationIgnored private var isSending = false
    @ObservationIgnored private var isRunningGreetings = false
    @ObservationIgnored private var draftRetryAt: Date?
    @ObservationIgnored private var started = false
    @ObservationIgnored let connectivity: ConnectivityMonitor

    static let greetingReviewWindow: TimeInterval = 5 * 60

    init(settings: AutomationStore, ai: AIService, connectivity: ConnectivityMonitor = ConnectivityMonitor()) {
        self.settings = settings
        self.ai = ai
        self.connectivity = connectivity
    }

    /// Greetings written and waiting to go out (or to be sent by hand).
    var pendingGreetings: [PendingGreeting] {
        guard let job = settings.data.greetingJob else { return [] }
        return job.readyToSend.map { item in
            PendingGreeting(contact: settings.contact(item.id) ?? WAContactSettings(id: item.id, jid: "", name: item.name),
                            phone: item.phone, text: item.text ?? "")
        }
    }

    var greetingsSendAt: Date? {
        guard let job = settings.data.greetingJob, !job.expired, !job.readyToSend.isEmpty else { return nil }
        return job.sendAt
    }

    #if DEBUG
    func loadPreview(greetings: Bool = false) {
        let amma = WAContactSettings(id: 1, jid: "447700900123@s.whatsapp.net", name: "Amma", language: .tamil)
        if greetings {
            settings.upsert(amma)
            settings.upsert(WAContactSettings(id: 2, jid: "15550001111@s.whatsapp.net", name: "Kumar"))
            settings.data.greetingJob = GreetingJob(day: MorningSchedule.dayKey(Date()), sendAt: Date().addingTimeInterval(240), items: [
                GreetingJob.Item(id: 1, name: "Amma", phone: "447700900123", text: "காலை வணக்கம் அம்மா ☀️ சாப்பிட்டீங்களா?"),
                GreetingJob.Item(id: 2, name: "Kumar", phone: "15550001111", text: "Morning machan! Big day today, all the best"),
            ])
        } else {
            drafts = [ReplyDraft(contact: amma, phone: "447700900123", incoming: "சாப்பிட்டியா கண்ணா?",
                                 draft: "சாப்டேன் அம்மா 😊 நீங்க சாப்டீங்களா?", sensitive: false, receivedAt: Date())]
        }
    }
    #endif

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        openStore()
        // Only react to messages that arrive from now on.
        if let store, let max = try? store.maxMessageId(), settings.data.lastSeenMessageId == 0 || max < settings.data.lastSeenMessageId {
            settings.data.lastSeenMessageId = max
        }
        watchWAL()
        connectivity.onReady = { [weak self] in
            Task { @MainActor in await self?.tick() }
        }
        connectivity.start()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    /// One pass over everything the automation has to do.
    func tick(now: Date = Date()) async {
        await checkIncoming(now: now)
        await checkGreetingSchedule(now: now)
        await sendDueScheduled(now: now)
    }

    // MARK: Voice: send now or later (always after you confirmed the read-back)

    /// Sends one message now, through the same checks as greetings (awake,
    /// unlocked, online, Accessibility) and test mode.
    func sendNow(_ text: String, to chat: WAChat) async -> (ok: Bool, status: String) {
        guard let phone = chat.phone, phone.count >= 7 else {
            return (false, "I don't have a phone number for \(chat.name), so I can't open that chat.")
        }
        if case .wait(let reason) = gate() { return (false, reason) }
        let ok = await send(text, to: phone, chatId: chat.id, name: chat.name.isEmpty ? "+\(phone)" : chat.name)
        return (ok, lastStatus ?? "")
    }

    var scheduled: [ScheduledMessage] { settings.data.scheduledMessages ?? [] }
    /// Called a minute before a scheduled message goes out.
    @ObservationIgnored var onScheduledSoon: ((ScheduledMessage) -> Void)?

    func schedule(_ text: String, to chat: WAChat, at date: Date) -> Bool {
        guard let phone = chat.phone, phone.count >= 7 else { return false }
        var list = scheduled
        list.append(ScheduledMessage(chatId: chat.id, name: chat.name, phone: phone, text: text, at: date))
        settings.data.scheduledMessages = list.sorted { $0.at < $1.at }
        return true
    }

    func cancelScheduled(_ id: UUID) {
        settings.data.scheduledMessages = scheduled.filter { $0.id != id }
    }

    /// Sends what's due. If the Mac was unavailable for over an hour after the
    /// time, the message is skipped (a late "good night" is worse than none).
    private func sendDueScheduled(now: Date) async {
        for item in scheduled {
            if !item.warned, item.at.timeIntervalSince(now) <= 60, item.at > now {
                mutateScheduled(item.id) { $0.warned = true }
                onScheduledSoon?(item)
            }
            guard item.at <= now else { continue }
            if now.timeIntervalSince(item.at) > 3600 {
                cancelScheduled(item.id)
                report("Skipped the scheduled message to \(item.name): the Mac wasn't ready in time.", ok: false)
                continue
            }
            if case .wait = gate() { continue }   // try again on the next pass
            cancelScheduled(item.id)              // never sent twice, even if sending fails
            _ = await send(item.text, to: item.phone, chatId: item.chatId, name: item.name)
        }
    }

    private func mutateScheduled(_ id: UUID, _ change: (inout ScheduledMessage) -> Void) {
        var list = scheduled
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[index])
        settings.data.scheduledMessages = list
    }

    private func gate() -> AutomationGate.Decision {
        AutomationGate.check(online: connectivity.isOnline, awake: connectivity.isAwake,
                             screenLocked: connectivity.isScreenLocked, sending: true,
                             whatsAppInstalled: WhatsAppSender.isInstalled,
                             accessibility: WhatsAppSender.hasAccessibility)
    }

    func reloadChats() {
        openStore()
        chats = (try? store?.chats()) ?? []
    }

    private func openStore() {
        guard WhatsAppSender.isInstalled else { access = .notInstalled; return }
        do {
            store = try WhatsAppStore()
            access = .ok
        } catch WhatsAppStore.StoreError.schemaChanged(let detail) {
            store = nil
            access = .schemaChanged(detail)
        } catch {
            store = nil
            access = .noDataAccess("\(error)")
        }
    }

    private func watchWAL() {
        let path = WhatsAppStore.defaultPath + "-wal"
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))  // let WhatsApp finish writing
                await self?.checkIncoming()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        walSource = source
    }

    // MARK: - Reply drafts

    func checkIncoming(now: Date = Date()) async {
        guard settings.data.draftsEnabled, let store, !isDrafting else { return }
        let watched = settings.data.contacts.filter(\.draftReplies)
        guard !watched.isEmpty else { return }
        // Offline: leave new messages unread until the Mac is back online.
        guard connectivity.isOnline, draftRetryAt.map({ now >= $0 }) ?? true else { return }
        let messages: [WAMessage]
        do {
            messages = try store.incoming(after: settings.data.lastSeenMessageId, chatIds: watched.map(\.id))
        } catch {
            access = .schemaChanged("\(error)")
            return
        }
        guard let newest = messages.last else { return }

        // One draft per chat, answering its latest message.
        let latestPerChat = Dictionary(grouping: messages, by: \.chatId).compactMap { $0.value.last }
        isDrafting = true
        defer { isDrafting = false }
        var failedIds: [Int64] = []
        for message in latestPerChat {
            guard let contact = settings.contact(message.chatId),
                  let phone = phone(for: contact),
                  !drafts.contains(where: { $0.contact.id == contact.id && $0.incoming == message.text }) else { continue }
            do {
                let (text, sensitive) = try await draftReply(to: message, contact: contact)
                let draft = ReplyDraft(contact: contact, phone: phone, incoming: message.text, draft: text,
                                       sensitive: sensitive, receivedAt: message.date)
                drafts.append(draft)
                onDraft?(draft)
            } catch {
                failedIds.append(message.id)
                lastStatus = "Couldn't draft a reply: \(error.localizedDescription)"
            }
        }
        // Retry failed drafts on a later pass instead of losing the message.
        if let firstFailed = failedIds.min() {
            settings.data.lastSeenMessageId = max(settings.data.lastSeenMessageId, firstFailed - 1)
            draftRetryAt = now.addingTimeInterval(60)
        } else {
            settings.data.lastSeenMessageId = newest.id
            draftRetryAt = nil
        }
    }

    func regenerate(_ draftID: UUID) async {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        let draft = drafts[index]
        let message = WAMessage(id: 0, chatId: draft.contact.id, isFromMe: false, text: draft.incoming, date: draft.receivedAt)
        if let (text, sensitive) = try? await draftReply(to: message, contact: draft.contact, avoid: draft.draft),
           let i = drafts.firstIndex(where: { $0.id == draftID }) {
            drafts[i].draft = text
            drafts[i].sensitive = sensitive
        }
    }

    func updateDraft(_ draftID: UUID, text: String) {
        if let i = drafts.firstIndex(where: { $0.id == draftID }) { drafts[i].draft = text }
    }

    func dismiss(_ draftID: UUID) {
        drafts.removeAll { $0.id == draftID }
    }

    func sendDraft(_ draftID: UUID) async {
        guard let draft = drafts.first(where: { $0.id == draftID }) else { return }
        if case .wait(let reason) = sendGate() {
            report("\(reason). The reply to \(draft.contact.name) wasn't sent.", ok: false)
            return
        }
        let ok = await send(draft.draft, to: draft.phone, chatId: draft.contact.id, name: draft.contact.name)
        if ok { drafts.removeAll { $0.id == draftID } }
    }

    private func draftReply(to message: WAMessage, contact: WAContactSettings, avoid: String? = nil) async throws -> (String, Bool) {
        let history = (try? store?.messages(chatId: contact.id, limit: 20)) ?? []
        let transcript = history.map { "\($0.isFromMe ? "Me" : contact.name): \($0.text)" }.joined(separator: "\n")
        let myStyle = history.filter(\.isFromMe).suffix(12).map(\.text).joined(separator: " | ")
        let system = """
        You draft WhatsApp replies that the user will review and send as themselves to \(contact.name).
        Write exactly like the user writes in this chat: same language, length, slang, emoji habits and warmth.
        Language: \(contact.language.label)\(contact.language == .tanglish ? " (Tamil written in English letters)" : "").
        \(contact.toneNote.isEmpty ? "" : "Notes about this person: \(contact.toneNote)")
        Keep it short and natural, like a real text message. Never mention AI. Don't invent facts, plans or promises.
        If the message involves money, health, emergencies, serious news, commitments or anything the user should decide personally,
        start your reply with [SENSITIVE] and keep the draft neutral.
        Output only the reply text.
        """
        var prompt = "Recent chat:\n\(transcript)\n\nThe user's own recent messages (style examples): \(myStyle)\n\nWrite the user's reply to: \"\(message.text)\""
        if let avoid { prompt += "\n\nWrite something different from: \"\(avoid)\"" }
        var text = try await ai.complete(system: system, prompt: prompt, effort: "low", maxTokens: 600)
        let sensitive = text.hasPrefix("[SENSITIVE]")
        if sensitive { text = String(text.dropFirst("[SENSITIVE]".count)).trimmingCharacters(in: .whitespaces) }
        return (text.trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespacesAndNewlines)), sensitive)
    }

    // MARK: - Morning greetings

    /// Runs every pass: starts today's job when it's due, writes greetings
    /// when online, and sends them after the review window when the Mac is
    /// online and unlocked. Failures retry with backoff until the cutoff.
    func checkGreetingSchedule(now: Date = Date()) async {
        guard !isRunningGreetings else { return }
        isRunningGreetings = true
        defer { isRunningGreetings = false }

        let data = settings.data
        let today = MorningSchedule.dayKey(now)
        if data.greetingsEnabled, data.greetingJob?.day != today,
           data.greetingSchedule.isDue(now: now, lastRunDay: data.lastGreetingDay) {
            startJob(day: today, now: now)
        }
        guard let job = settings.data.greetingJob, !job.isComplete, !job.expired else {
            if settings.data.greetingJob?.expired != true { waitingReason = nil }
            return
        }
        if job.isExpired(now: now, schedule: data.greetingSchedule) {
            mutateJob { $0.expired = true }
            settings.data.lastGreetingDay = job.day
            waitingReason = nil
            if job.day == today {
                report("Today's good-morning messages weren't sent (\(job.unsent.map(\.name).joined(separator: ", "))). Open Brief to send them now.", ok: false)
            }
            return
        }
        guard job.canAttempt(now: now) else { return }

        // 1. Write the greetings (needs internet).
        if !job.needsText.isEmpty {
            if case .wait(let reason) = AutomationGate.check(online: connectivity.isOnline, awake: connectivity.isAwake,
                                                              screenLocked: false, sending: false) {
                waitingReason = "\(reason). Good-morning messages will go out when you're back."
                return
            }
            await writeGreetings(job.needsText, now: now)
        }

        // 2. Send after the review window.
        guard let ready = settings.data.greetingJob, ready.isSendTime(now: now), !ready.readyToSend.isEmpty,
              ready.canAttempt(now: now) else { return }
        await sendReadyGreetings(now: now)
    }

    private func startJob(day: String, now: Date) {
        var items: [GreetingJob.Item] = []
        var missing: [String] = []
        for contact in settings.data.contacts where contact.morningGreeting {
            if let phone = phone(for: contact) {
                items.append(GreetingJob.Item(id: contact.id, name: contact.name, phone: phone))
            } else {
                missing.append(contact.name)
            }
        }
        if !missing.isEmpty { report("No phone number saved for \(missing.joined(separator: ", ")). Add it in Settings → Automations.", ok: false) }
        guard !items.isEmpty else {
            settings.data.lastGreetingDay = day
            return
        }
        settings.data.greetingJob = GreetingJob(day: day, sendAt: now.addingTimeInterval(Self.greetingReviewWindow), items: items)
    }

    private func writeGreetings(_ items: [GreetingJob.Item], now: Date) async {
        var failed = false
        for item in items {
            guard let contact = settings.contact(item.id) else { mutateJob { $0.remove(item.id) }; continue }
            do {
                let text = try await greeting(for: contact)
                mutateJob { $0.setText(text, for: item.id) }
            } catch {
                failed = true
                Log.automations.error("WhatsApp greeting for a contact failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if failed { mutateJob { $0.recordFailure(now: now) } }
        guard let job = settings.data.greetingJob, !job.announced, !job.readyToSend.isEmpty else { return }
        // Always give the user the full review window once texts are ready.
        let sendAt = max(job.sendAt, Date().addingTimeInterval(Self.greetingReviewWindow))
        mutateJob {
            $0.announced = true
            $0.sendAt = sendAt
        }
        waitingReason = nil
        onGreetingsScheduled?(job.readyToSend.count)
    }

    private func sendReadyGreetings(now: Date) async {
        if case .wait(let reason) = sendGate() {
            waitingReason = "\(reason). Good-morning messages will go out after that."
            return
        }
        waitingReason = nil
        guard let job = settings.data.greetingJob else { return }
        let batch = job.readyToSend
        for (i, item) in batch.enumerated() {
            // The user may have edited or removed it during the last send.
            guard let current = settings.data.greetingJob?.readyToSend.first(where: { $0.id == item.id }),
                  let text = current.text, !text.isEmpty else { continue }
            if await send(text, to: current.phone, chatId: current.id, name: current.name) {
                if !settings.data.testMode, let jid = settings.contact(current.id)?.jid { settings.rememberGreeting(text, for: jid) }
                mutateJob { $0.markSent(current.id) }
            } else {
                mutateJob { $0.recordFailure(for: current.id, now: Date()) }
                break  // retry the rest after the backoff
            }
            if i < batch.count - 1 { try? await Task.sleep(for: .seconds(Double.random(in: 3...8))) }
        }
        if let job = settings.data.greetingJob, job.isComplete {
            settings.data.lastGreetingDay = job.day
        }
    }

    private func sendGate() -> AutomationGate.Decision {
        AutomationGate.check(online: connectivity.isOnline, awake: connectivity.isAwake,
                             screenLocked: connectivity.isScreenLocked, sending: true,
                             whatsAppInstalled: WhatsAppSender.isInstalled,
                             accessibility: WhatsAppSender.hasAccessibility, testMode: settings.data.testMode)
    }

    private func mutateJob(_ change: (inout GreetingJob) -> Void) {
        guard var job = settings.data.greetingJob else { return }
        change(&job)
        settings.data.greetingJob = job
    }

    func updateGreeting(_ id: Int64, text: String) {
        mutateJob { $0.setText(text, for: id) }
    }

    func removeGreeting(_ id: Int64) {
        mutateJob { $0.remove(id) }
        if let job = settings.data.greetingJob, job.isComplete {
            settings.data.lastGreetingDay = job.day
            settings.data.greetingJob = nil
        }
    }

    func skipGreetingsToday() {
        settings.data.lastGreetingDay = settings.data.greetingJob?.day ?? MorningSchedule.dayKey(Date())
        settings.data.greetingJob = nil
        waitingReason = nil
        lastStatus = "Skipped today's greetings"
    }

    /// Sends now, skipping the review wait (also works after the cutoff).
    func sendGreetingsNow() async {
        guard !isRunningGreetings else { return }
        isRunningGreetings = true
        defer { isRunningGreetings = false }
        mutateJob {
            $0.sendAt = Date()
            $0.retryAt = nil
        }
        await sendReadyGreetings(now: Date())
    }

    private func greeting(for contact: WAContactSettings) async throws -> String {
        let recent = settings.data.recentGreetings[contact.jid] ?? []
        let myStyle = ((try? store?.messages(chatId: contact.id, limit: 40)) ?? []).filter(\.isFromMe).suffix(15).map(\.text)
        let weekday = Date().formatted(.dateTime.weekday(.wide).day().month(.wide))
        let system = """
        Write a short good-morning WhatsApp message the user will send to \(contact.name).
        Sound exactly like the user (style examples below): natural, warm, not cheesy, no hashtags. 1–2 short lines, max one emoji.
        Language: \(contact.language.label)\(contact.language == .tanglish ? " (Tamil in English letters)" : "").
        \(contact.toneNote.isEmpty ? "" : "About them: \(contact.toneNote)")
        Vary it every day. Never mention AI. Output only the message.
        """
        let prompt = "Today is \(weekday). User's style examples: \(myStyle.joined(separator: " | "))\nDon't repeat these recent greetings: \(recent.joined(separator: " | "))"
        for _ in 0..<3 {
            let text = try await ai.complete(system: system, prompt: prompt, effort: "low", maxTokens: 200)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespacesAndNewlines))
            if !GreetingDeduper.isTooSimilar(text, to: recent) { return text }
        }
        throw AIError.invalidResponse
    }

    // MARK: - Sending

    /// Sends one real test message to the chosen number (best: your own,
    /// the "Message yourself" chat), even in test mode, to prove sending
    /// works end to end. The Settings button asks for a second click first.
    func sendSelfTest() async {
        let digits = settings.data.selfPhone?.filter(\.isNumber) ?? ""
        guard digits.count >= 7 else { report("Enter or choose a WhatsApp number first.", ok: false); return }
        if case .wait(let reason) = AutomationGate.check(online: connectivity.isOnline, awake: connectivity.isAwake,
                                                         screenLocked: connectivity.isScreenLocked, sending: true,
                                                         whatsAppInstalled: WhatsAppSender.isInstalled,
                                                         accessibility: WhatsAppSender.hasAccessibility) {
            report(reason, ok: false)
            return
        }
        if chats.isEmpty { reloadChats() }
        let chat = chats.first { $0.phone == digits }
        let text = "Nova test ✓ \(Date().formatted(date: .omitted, time: .shortened))"
        let name = chat.map { $0.name.isEmpty ? "+\(digits)" : $0.name } ?? "+\(digits)"
        _ = await send(text, to: digits, chatId: chat?.id, name: name, live: true)
    }

    private func send(_ text: String, to phone: String, chatId: Int64?, name: String, live: Bool = false) async -> Bool {
        while isSending { try? await Task.sleep(for: .milliseconds(300)) }
        isSending = true
        defer { isSending = false }
        let testMode = live ? false : settings.data.testMode
        let startedAt = Date()
        do {
            let pressed = try await WhatsAppSender.send(text, toPhone: phone, testMode: testMode)
            guard pressed else {
                report("Test mode: filled the message to \(name) in WhatsApp without sending", ok: true)
                return true
            }
            // Confirm WhatsApp actually recorded the outgoing message.
            if await confirmSent(chatId: chatId, text: text, after: startedAt) {
                report("Sent to \(name)", ok: true)
                return true
            }
            // Not in WhatsApp's database yet. Press Send again only if the
            // message is provably still sitting in the chat box.
            if await WhatsAppSender.resendIfStillFilled(text), await confirmSent(chatId: chatId, text: text, after: startedAt) {
                report("Sent to \(name)", ok: true)
                return true
            }
            report("Couldn't confirm the message to \(name) was sent. Check WhatsApp.", ok: false)
            return false
        } catch {
            report(error.localizedDescription, ok: false)
            return false
        }
    }

    private func confirmSent(chatId: Int64?, text: String, after date: Date) async -> Bool {
        guard let store, let chatId else { return true }  // can't verify without data access
        for _ in 0..<8 {
            try? await Task.sleep(for: .seconds(1))
            if (try? store.hasOutgoing(chatId: chatId, text: text, after: date)) == true { return true }
        }
        return false
    }

    private func report(_ message: String, ok: Bool) {
        if !ok { Log.automations.error("WhatsApp: \(message, privacy: .public)") }
        lastStatus = message
        onStatus?(message, ok)
    }

    private func phone(for contact: WAContactSettings) -> String? {
        let digits = contact.phone?.filter(\.isNumber) ?? ""
        return digits.count >= 7 ? digits : WAChat.digits(ofPhoneJID: contact.jid)
    }
}
