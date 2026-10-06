import NovaKit
import SwiftUI

struct AutomationSettings: View {
    let coordinator: AppCoordinator

    var body: some View {
        SettingsHeader(title: "Automations", subtitle: "Your morning brief and WhatsApp helper. Everything runs on this Mac.")
        GoogleSection(google: coordinator.google, brief: coordinator.brief)
        BriefScheduleSection(store: coordinator.automations)
        CalendarSection(coordinator: coordinator)
        WhatsAppSection(coordinator: coordinator)
    }
}

private struct GoogleSection: View {
    let google: GoogleAuth
    let brief: BriefService

    @ViewState private var clientID = ""
    @ViewState private var clientSecret = ""

    var body: some View {
        SettingsCard(title: "Google (Gmail · YouTube · LinkedIn emails)", symbol: "g.circle.fill") {
            if google.isSignedIn {
                HStack {
                    Label("Connected (read-only)", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.success)
                    Spacer()
                    Button("Refresh brief now") { Task { await brief.refresh() } }
                    Button("Disconnect", role: .destructive) { google.signOut() }
                }
                if let error = brief.error { Text(error).font(.caption).foregroundStyle(Theme.warning) }
            } else {
                Text("One-time setup (about 5 minutes):").font(.callout)
                VStack(alignment: .leading, spacing: 3) {
                    Text("1. In Google Cloud Console, create a project and enable the Gmail API, YouTube Data API v3 and YouTube Analytics API.")
                    Text("2. OAuth consent screen → External → add yourself as a Test user.")
                    Text("3. Credentials → Create OAuth client ID → Desktop app. Paste the ID and secret below.")
                }
                .font(.caption).foregroundStyle(.secondary)
                Link("Open Google Cloud Console", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                    .font(.caption)
                if !google.hasClient {
                    TextField("Client ID", text: $clientID).textFieldStyle(.roundedBorder)
                    SecureField("Client secret", text: $clientSecret).textFieldStyle(.roundedBorder)
                    Button("Save client") { try? google.saveClient(id: clientID, secret: clientSecret); clientSecret = "" }
                        .disabled(clientID.isEmpty || clientSecret.isEmpty)
                } else {
                    HStack {
                        Button(google.isSigningIn ? "Waiting for browser…" : "Connect Google") { Task { await google.signIn() } }
                            .disabled(google.isSigningIn)
                        Button("Change client") { try? google.saveClient(id: "", secret: "") }
                    }
                }
                Text("Nova asks only for read-only scopes. Tokens stay in your Keychain.").font(.caption).foregroundStyle(.secondary)
                if let error = google.lastError { Text(error).font(.caption).foregroundStyle(Theme.warning) }
            }
        }
    }
}

private struct BriefScheduleSection: View {
    @Bindable var store: AutomationStore

    var body: some View {
        SettingsCard(title: "Morning brief", symbol: "sun.max.fill") {
            Toggle("Prepare my brief every morning", isOn: $store.data.briefEnabled)
            TimePicker(schedule: $store.data.briefSchedule).disabled(!store.data.briefEnabled)
            Text("If your Mac is asleep, the brief runs when it wakes (until \(store.data.briefSchedule.cutoffHour):00).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct WhatsAppSection: View {
    let coordinator: AppCoordinator

    @ViewState private var showPicker = false
    @ViewState private var confirmingTest = false

    /// Name of the chosen test number from your chats, or the number itself.
    private var testRecipient: String {
        let digits = coordinator.automations.data.selfPhone?.filter(\.isNumber) ?? ""
        if let chat = coordinator.whatsapp.chats.first(where: { $0.phone == digits }), !chat.name.isEmpty { return chat.name }
        return "+" + digits
    }

    var body: some View {
        let wa = coordinator.whatsapp
        @Bindable var store = coordinator.automations
        SettingsCard(title: "WhatsApp", symbol: "message.fill") {
            if let problem = wa.access.message {
                Label(problem, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(Theme.warning)
                Button("Try again") { wa.reloadChats() }
            }
            // Re-checked every 2 s: macOS doesn't announce permission changes.
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                let allowed = WhatsAppSender.hasAccessibility
                HStack {
                    Label(allowed ? "Accessibility allowed (can press Send)" : "Accessibility needed to press Send",
                          systemImage: allowed ? "checkmark.circle.fill" : "hand.raised")
                        .foregroundStyle(allowed ? Theme.success : Theme.textSecondary)
                        .font(.callout)
                    Spacer()
                    if !allowed { Button("Allow…") { WhatsAppSender.requestAccessibility() } }
                }
            }
            Toggle("Test mode: fill messages in WhatsApp but don't press Send", isOn: $store.data.testMode)
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                ReadinessRow(connectivity: wa.connectivity, testMode: store.data.testMode)
            }
            if let waiting = wa.waitingReason {
                Label(waiting, systemImage: "pause.circle.fill").font(.callout).foregroundStyle(Theme.warning)
            }
            HStack {
                TextField("WhatsApp number for the test (e.g. 447700900123)", text: Binding(
                    get: { store.data.selfPhone ?? "" }, set: { store.data.selfPhone = $0.isEmpty ? nil : $0 }))
                    .textFieldStyle(.roundedBorder)
                // Pick from your chats instead of typing the number.
                Menu("Choose…") {
                    let withPhone = wa.chats.filter { ($0.phone ?? "").count >= 7 }
                        .sorted { ($0.lastMessageDate ?? .distantPast) > ($1.lastMessageDate ?? .distantPast) }
                    if withPhone.isEmpty {
                        Button("Load my WhatsApp chats") { wa.reloadChats() }
                    } else {
                        ForEach(withPhone.prefix(40)) { chat in
                            Button("\(chat.name.isEmpty ? (chat.phone ?? "") : chat.name)  ·  +\(chat.phone ?? "")") {
                                store.data.selfPhone = chat.phone
                            }
                        }
                    }
                }
                .fixedSize()
                .help("Pick a contact from your WhatsApp chats")
                // Two clicks: the test is a real message, even in test mode.
                Button(confirmingTest ? "Send to \(testRecipient)?" : "Send a test") {
                    if confirmingTest {
                        confirmingTest = false
                        Task { await wa.sendSelfTest() }
                    } else {
                        confirmingTest = true
                        Task { try? await Task.sleep(for: .seconds(4)); confirmingTest = false }
                    }
                }
                .tint(confirmingTest ? Theme.warning : nil)
                .disabled((store.data.selfPhone?.filter(\.isNumber).count ?? 0) < 7)
            }
            Text("“Send a test” sends one real message “Nova test ✓” to this number, even in test mode. Your own number (the “Message yourself” chat) is the safest choice.")
                .font(.caption).foregroundStyle(.secondary)
            .font(.callout)
            if let status = wa.lastStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Text("Automations only run while this Mac is awake, unlocked and online. If you're offline at greeting time, they go out when you're back (until the cutoff).")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("Draft replies to my selected contacts (I approve each one)", isOn: $store.data.draftsEnabled)
            Toggle("Send good morning to selected contacts", isOn: $store.data.greetingsEnabled)
            TimePicker(schedule: $store.data.greetingSchedule).disabled(!store.data.greetingsEnabled)
            Text("You get 5 minutes to review, edit or skip before they go out. After \(store.data.greetingSchedule.cutoffHour):00 they're skipped for the day.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Text("Contacts").font(.headline)
                Spacer()
                Button("Add contacts…") { wa.reloadChats(); showPicker = true }
            }
            if store.data.contacts.isEmpty {
                Text("No contacts yet. Nova only reads chats you add here.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach($store.data.contacts) { $contact in
                ContactRow(contact: $contact) { store.remove(contact.id) }
            }
            Text("Privacy: to write drafts and greetings, the recent messages of the contacts you add are sent to your chosen AI provider. Nothing else leaves your Mac.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Scheduled messages").font(.headline)
            if wa.scheduled.isEmpty {
                Text("None. Say “Hey Nova, send good night to Amma at 10 pm on WhatsApp”: Nova reads it back and waits for “schedule”.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(wa.scheduled) { item in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(item.name) · \(item.at.formatted(date: .abbreviated, time: .shortened))").font(.callout.weight(.semibold))
                        Text(item.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Button("Cancel", role: .destructive) { wa.cancelScheduled(item.id) }.controlSize(.small)
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            ContactPicker(chats: wa.chats, selected: Set(store.data.contacts.map(\.id))) { chat in
                store.upsert(WAContactSettings(id: chat.id, jid: chat.jid,
                                               name: chat.name.isEmpty ? (chat.phone.map { "+\($0)" } ?? "Unknown") : chat.name,
                                               phone: chat.phone))
            } done: { showPicker = false }
        }
    }
}

private struct ReadinessRow: View {
    let connectivity: ConnectivityMonitor
    let testMode: Bool

    var body: some View {
        HStack(spacing: 12) {
            item("Online", connectivity.isOnline)
            item("Unlocked", !connectivity.isScreenLocked)
            item("WhatsApp", WhatsAppSender.isInstalled)
            item("Accessibility", WhatsAppSender.hasAccessibility)
            Label(testMode ? "Test mode" : "Live", systemImage: testMode ? "flask.fill" : "paperplane.fill")
                .foregroundStyle(testMode ? Theme.warning : Theme.success)
        }
        .font(.caption)
    }

    private func item(_ title: String, _ ok: Bool) -> some View {
        Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(ok ? Theme.success : Theme.error)
    }
}

private struct ContactRow: View {
    @Binding var contact: WAContactSettings
    var remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(contact.name).font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("Good morning", isOn: $contact.morningGreeting).toggleStyle(.checkbox)
                Toggle("Draft replies", isOn: $contact.draftReplies).toggleStyle(.checkbox)
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
            if (contact.phone ?? "").filter(\.isNumber).count < 7 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                    TextField("Phone with country code, e.g. +44 7700 900123 (needed to send)", text: Binding(
                        get: { contact.phone ?? "" }, set: { contact.phone = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
                .controlSize(.small)
            }
            HStack {
                Picker("Language", selection: $contact.language) {
                    ForEach(ReplyLanguage.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 220)
                TextField("About them / tone (e.g. my mum, call her Amma, caring)", text: $contact.toneNote)
                    .textFieldStyle(.roundedBorder)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ContactPicker: View {
    let chats: [WAChat]
    let selected: Set<Int64>
    var add: (WAChat) -> Void
    var done: () -> Void

    @ViewState private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add WhatsApp contacts").font(.headline)
            TextField("Search", text: $query).textFieldStyle(.roundedBorder)
            List(chats.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || ($0.phone ?? "").contains(query) }) { chat in
                HStack {
                    VStack(alignment: .leading) {
                        Text(chat.name.isEmpty ? (chat.phone ?? "Unknown") : chat.name)
                        Text(chat.phone.map { "+\($0)" } ?? "Number not saved. You can add it after")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selected.contains(chat.id) {
                        Image(systemName: "checkmark").foregroundStyle(Theme.success)
                    } else {
                        Button("Add") { add(chat) }
                    }
                }
            }
            .frame(minHeight: 300)
            if chats.isEmpty { Text("No chats found. Make sure WhatsApp for Mac is signed in.").font(.caption).foregroundStyle(.secondary) }
            HStack { Spacer(); Button("Done", action: done).keyboardShortcut(.defaultAction) }
        }
        .padding(18)
        .frame(width: 440, height: 480)
    }
}

private struct TimePicker: View {
    @Binding var schedule: MorningSchedule

    var body: some View {
        DatePicker("Time", selection: Binding(
            get: { schedule.fireDate(on: Date()) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                schedule.hour = c.hour ?? schedule.hour
                schedule.minute = c.minute ?? schedule.minute
            }), displayedComponents: .hourAndMinute)
            .frame(maxWidth: 220)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Calendar and Reminders access, and the meeting nudge.
private struct CalendarSection: View {
    let coordinator: AppCoordinator
    @ViewState private var refresh = 0

    var body: some View {
        @Bindable var prefs = coordinator.prefs
        let calendar = coordinator.calendar
        let _ = refresh
        SettingsCard(title: "Calendar & reminders", symbol: "calendar") {
            HStack(spacing: 12) {
                access("Calendar", allowed: calendar.eventsAllowed, denied: calendar.eventsDenied) {
                    Task { _ = await calendar.requestEvents(); refresh += 1 }
                }
                access("Reminders", allowed: calendar.remindersAllowed, denied: calendar.remindersDenied) {
                    Task { _ = await calendar.requestReminders(); refresh += 1 }
                }
            }
            Toggle("Remind me 5 minutes before meetings (with the join link)", isOn: $prefs.meetingNudges)
            Text("Ask “what's next?”, “what's on my calendar tomorrow?” or “remind me at 5 to call Amma”. Events stay on your Mac; only the event you ask about is spoken.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func access(_ name: String, allowed: Bool, denied: Bool, request: @escaping () -> Void) -> some View {
        if allowed {
            Label("\(name) allowed", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success).font(.callout)
        } else if denied {
            Button("Allow \(name) in System Settings…") {
                let pane = name == "Calendar" ? "Privacy_Calendars" : "Privacy_Reminders"
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
            }
        } else {
            Button("Allow \(name)", action: request)
        }
    }
}
