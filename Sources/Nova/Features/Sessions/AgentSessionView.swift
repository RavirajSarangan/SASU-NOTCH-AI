import NovaKit
import SwiftUI

/// Detail panel for the focused agent's live session.
struct AgentSessionView: View {
    let coordinator: AppCoordinator

    @Environment(\.novaStyle) private var style
    @Environment(\.novaLive) private var live

    var body: some View {
        let agent = coordinator.state.focusedAgent
        if let session = coordinator.sessions.session(id: agent.sessionId) {
            content(agent: agent, session: session)
        } else {
            EmptyStateView(coordinator: coordinator, expression: .confused, title: "Session ended",
                           message: "This session isn't active anymore.")
                .padding(12)
        }
    }

    private func content(agent: AgentSummary, session: AgentSession) -> some View {
        let g = coordinator.state.geometry
        let wing = NotchLayout.wingWidth(for: coordinator.state.size, geometry: g)

        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    IconButton(systemName: "chevron.left", label: "Back") { coordinator.backToHome() }
                    LogoTile(mark: agent.brand, size: 20)
                    Text(agent.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if coordinator.state.agents.filter(\.isConnected).count > 1 {
                        IconButton(systemName: "chevron.left.chevron.right", label: "Next session") { coordinator.focusNextSession() }
                    }
                }
                .frame(width: g.hasNotch ? wing - 14 : nil, alignment: .leading)
                Spacer(minLength: g.hasNotch ? g.notchWidth : 0)
                HStack(spacing: 6) {
                    IconButton(systemName: "macwindow", label: "Show where it runs") { coordinator.jumpToTerminal(agent) }
                    StatusDot(color: session.status.color, live: session.status.isLive, size: 6)
                    Text(session.status.label)
                        .foregroundStyle(session.status.color)
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text("· " + AgentSummary.format(session.elapsed(now: timeline.date)))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .font(.system(size: 11, weight: .medium))
            }
            .frame(height: g.notchHeight)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 10) {
                    NovaCharacterView(art: .body, expression: session.status.expression,
                                      cursor: coordinator.cursor, anchor: coordinator.novaAnchor)
                        .frame(width: 80, height: 70)
                    StepTimeline(steps: agent.preview.steps)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(width: 168)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .background {
                    if style.nova2 && style.scenes {
                        SceneBackgroundView(scene: RigScene.scene(for: RigMood(rawValue: session.status.expression.rawValue) ?? .idle,
                                                                  dancing: false, guardAlert: live.guardAlert),
                                            music: live.music, paused: style.paused)
                            .overlay(LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }
                }
                .premiumCard(glow: agent.brand.tint)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.currentTask ?? session.projectName ?? "Session")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        if let tool = session.currentTool {
                            Label("Using \(tool)", systemImage: "wrench.and.screwdriver")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.cyan)
                        }
                    }
                    Text("RECENT")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.textSecondary)
                    ActivityList(notes: agent.preview.notes)
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        SessionButton(title: "Open Folder", symbol: "folder") { coordinator.revealSessionFolder(session) }
                            .disabled(session.cwd == nil)
                        SessionButton(title: "Stop", symbol: "stop.fill", tint: Theme.error) { coordinator.stopSession(session.id) }
                            .disabled(!session.isActive)
                        SessionButton(title: "Collapse", symbol: "chevron.up") { coordinator.collapse() }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .premiumCard(glow: Theme.blue, glowCenter: .topTrailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

/// Recent actions with ✓ / spinner / ✕.
struct ActivityList: View {
    let notes: [SessionPreview.Note]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if notes.isEmpty {
                Text("No tool activity yet")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(notes) { note in
                HStack(spacing: 7) {
                    Group {
                        switch note.state {
                        case .done: Image(systemName: "checkmark").foregroundStyle(Theme.success)
                        case .running: Spinner(size: 9, lineWidth: 1.4)
                        case .failed: Image(systemName: "xmark").foregroundStyle(Theme.error)
                        }
                    }
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 11)
                    Text(note.text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(note.state == .running ? Theme.textPrimary : Theme.textPrimary.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let edit = note.edit {
                        Spacer(minLength: 4)
                        Button { DiffWindow.show(edit, title: note.text) } label: { DiffCounts(preview: edit) }
                            .buttonStyle(PressableStyle())
                            .help("Show the change")
                    }
                }
            }
        }
    }
}

private struct SessionButton: View {
    let title: String
    let symbol: String
    var tint: Color = Theme.textPrimary
    var action: () -> Void

    @ViewState private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(Color.white.opacity(hovering ? 0.1 : 0.05), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 }
    }
}
