import SwiftUI

/// Review panel for WhatsApp reply drafts and the morning greetings.
/// Nothing is sent without a click here (greetings send automatically only
/// after their review window, which is what the user asked for).
struct AutomationReviewView: View {
    let coordinator: AppCoordinator

    private var wa: WhatsAppService { coordinator.whatsapp }

    var body: some View {
        let g = coordinator.state.geometry
        let wing = NotchLayout.wingWidth(for: coordinator.state.size, geometry: g)
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    IconButton(systemName: "chevron.left", label: "Back") { coordinator.backToHome() }
                    Text(wa.drafts.isEmpty ? "Good morning" : "Reply draft")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                }
                .frame(width: g.hasNotch ? wing - 14 : nil, alignment: .leading)
                Spacer(minLength: g.hasNotch ? g.notchWidth : 0)
                if coordinator.automations.data.testMode {
                    Text("TEST MODE").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.warning)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(Theme.warning.opacity(0.14), in: Capsule())
                        .help("Messages are filled in WhatsApp but not sent. Turn off in Settings → Automations.")
                }
            }
            .frame(height: g.notchHeight)

            if let draft = wa.drafts.first {
                DraftCard(coordinator: coordinator, draft: draft, remaining: wa.drafts.count)
            } else if !wa.pendingGreetings.isEmpty {
                GreetingList(coordinator: coordinator)
            } else {
                EmptyStateView(coordinator: coordinator, expression: .success, title: "All caught up",
                               message: "No drafts or greetings waiting.")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

private struct DraftCard: View {
    let coordinator: AppCoordinator
    let draft: ReplyDraft
    let remaining: Int

    @ViewState private var text = ""
    @ViewState private var sending = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NovaCharacterView(art: .body, expression: .typing, cursor: coordinator.cursor, anchor: coordinator.novaAnchor)
                .frame(width: 84, height: 80)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(draft.contact.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(draft.receivedAt, style: .time).font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                    if remaining > 1 { Text("· \(remaining - 1) more").font(.system(size: 10)).foregroundStyle(Theme.textSecondary) }
                    Spacer()
                    if draft.sensitive {
                        Label("Reply yourself?", systemImage: "hand.raised.fill")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.warning)
                            .help("This looks like something you should answer personally.")
                    }
                }
                Text("“\(draft.incoming)”")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                TextField("Reply", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(2...4)
                    .padding(9)
                    .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(hex: 0x25D366).opacity(0.4)))
                    .onChange(of: text) { _, new in coordinator.whatsapp.updateDraft(draft.id, text: new) }
                HStack(spacing: 8) {
                    PillButton(title: "Ignore", style: .quiet) {
                        coordinator.whatsapp.dismiss(draft.id)
                        coordinator.automationReviewed()
                    }
                    PillButton(title: "Regenerate", systemImage: "arrow.clockwise", style: .quiet) {
                        Task {
                            await coordinator.whatsapp.regenerate(draft.id)
                            text = coordinator.whatsapp.drafts.first?.draft ?? text
                        }
                    }
                    Spacer()
                    PillButton(title: sending ? "Sending…" : "Send", systemImage: "paperplane.fill", hint: "⌘↩",
                               style: .primary, tint: Color(hex: 0x25D366)) {
                        sending = true
                        Task {
                            await coordinator.whatsapp.sendDraft(draft.id)
                            sending = false
                            coordinator.automationReviewed()
                        }
                    }
                    .frame(width: 130)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(sending || text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(glow: Color(hex: 0x25D366))
        .onAppear { text = draft.draft }
        .onChange(of: draft.id) { text = draft.draft }
    }
}

private struct GreetingList: View {
    let coordinator: AppCoordinator

    var body: some View {
        let wa = coordinator.whatsapp
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let waiting = wa.waitingReason {
                    Label(waiting, systemImage: "pause.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(Theme.warning).lineLimit(1)
                } else if let sendAt = wa.greetingsSendAt {
                    Label { Text("Sends in \(sendAt, style: .relative)") } icon: { Image(systemName: "clock") }
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                PillButton(title: "Skip today", style: .quiet) { wa.skipGreetingsToday(); coordinator.automationReviewed() }
                PillButton(title: "Send now", systemImage: "paperplane.fill", style: .primary, tint: Color(hex: 0x25D366)) {
                    Task { await wa.sendGreetingsNow(); coordinator.automationReviewed() }
                }
                .frame(width: 120)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(wa.pendingGreetings) { item in
                        HStack(spacing: 8) {
                            Text(item.contact.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                                .frame(width: 90, alignment: .leading).lineLimit(1)
                            TextField("", text: Binding(get: { item.text }, set: { wa.updateGreeting(item.id, text: $0) }))
                                .textFieldStyle(.plain).font(.system(size: 12))
                            Button { wa.removeGreeting(item.id) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(glow: Theme.warning)
    }
}
