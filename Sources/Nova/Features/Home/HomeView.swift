import NovaKit
import SwiftUI

/// Home tab: the focused agent (hero + live session), your apps and music,
/// and connected services.
struct HomeView: View {
    let coordinator: AppCoordinator

    @Environment(\.novaStyle) private var style

    @ViewState private var appeared = false

    var body: some View {
        let agent = coordinator.state.focusedAgent
        let session = coordinator.sessions.session(id: agent.sessionId)
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HeroCard(coordinator: coordinator, agent: agent, session: session)
                    .frame(width: 204)
                LiveSessionCard(coordinator: coordinator, focused: agent, session: session)
            }
            .frame(height: 176)
            .rise(appeared, delay: 0)

            DockRow(coordinator: coordinator)
                .frame(height: 56)
                .rise(appeared, delay: 0.05)

            ServicesStrip(coordinator: coordinator)
                .frame(height: 40)
                .rise(appeared, delay: 0.1)
        }
        .frame(maxWidth: .infinity)
        .onAppear { appeared = true }
        .transaction { if !style.animations { $0.animation = nil } }
        .onDisappear { appeared = false }
    }
}

private extension View {
    /// Staggered fade-and-rise when the panel opens.
    func rise(_ visible: Bool, delay: Double) -> some View {
        opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 8)
            .blur(radius: visible ? 0 : 3)
            .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(delay), value: visible)
    }
}

// MARK: - Hero

private struct HeroCard: View {
    let coordinator: AppCoordinator
    let agent: AgentSummary
    let session: AgentSession?

    @Environment(\.novaStyle) private var style
    @ViewState private var celebrate = 0
    @Environment(\.novaLive) private var live

    private var scene: RigScene {
        let mood = RigMood(rawValue: coordinator.state.expression.rawValue) ?? .idle
        let dancing = live.music?.sample() != nil && live.approvalSince == nil && !live.guardAlert
        return RigScene.scene(for: mood, dancing: dancing, guardAlert: live.guardAlert)
    }

    var body: some View {
        VStack(spacing: 7) {
            NovaCharacterView(art: .body, expression: coordinator.state.expression,
                              cursor: coordinator.cursor, anchor: coordinator.novaAnchor)
                .overlay { ParticleBurst(trigger: celebrate, style: .sparkles, count: 16).frame(width: 160, height: 120) }
                .contentShape(Rectangle())
                .onTapGesture { coordinator.poke() }
                .help("Poke Nova")
                .onChange(of: agent.status) { _, status in if status == .completed, style.animations { celebrate += 1 } }
                .frame(width: (style.nova2 ? 104 : 86) * style.characterScale, height: (style.nova2 ? 74 : 62) * style.characterScale)
                .background {
                    if !(style.nova2 && style.scenes) {
                        Circle()
                            .fill(agent.status.color.opacity(0.14))
                            .frame(width: 70, height: 70)
                            .blur(radius: 18)
                    }
                }
                .frame(maxWidth: .infinity)
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Text(agent.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    StatusPill(status: agent.isConnected ? agent.status : nil)
                }
                if let host = session?.host {
                    HostBadge(host: host)
                }
            }
            HStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Stat(value: session.map { AgentSummary.format($0.elapsed(now: timeline.date)) } ?? "–", label: "time")
                }
                Stat(value: session.map { "\($0.actions.count)" } ?? "–", label: "tools")
                Stat(value: session.map { "\(Set($0.actions.filter { ["Edit", "Write", "MultiEdit"].contains($0.tool) }.map(\.detail)).count)" } ?? "–",
                     label: "edits")
            }
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            // Nova 2: the mood's animated scene fills the card; a soft fade keeps the text readable.
            if style.nova2 && style.scenes {
                SceneBackgroundView(scene: scene, music: live.music, paused: style.paused)
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
        }
        .premiumCard(glow: agent.brand.tint)
    }
}

struct StatusPill: View {
    /// nil = not connected.
    let status: AgentStatus?

    var body: some View {
        let color = status?.color ?? Theme.textSecondary
        HStack(spacing: 4) {
            StatusDot(color: color, live: status?.isLive ?? false, size: 5)
            Text(status?.label ?? "Not connected")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(color.opacity(0.13), in: Capsule())
    }
}

private struct HostBadge: View {
    let host: String

    var body: some View {
        HStack(spacing: 4) {
            if host == "vscode" {
                BrandLogo(mark: .vscode, size: 9)
            } else {
                Image(systemName: host == "cursor" ? "cursorarrow.rays" : "terminal").font(.system(size: 9, weight: .bold))
            }
            Text("in " + label)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(Theme.textSecondary)
    }

    private var label: String {
        switch host {
        case "vscode": "VS Code"
        case "cursor": "Cursor"
        case "iterm": "iTerm"
        case "warp": "Warp"
        case "ghostty": "Ghostty"
        default: "Terminal"
        }
    }
}

private struct Stat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Live session

private struct LiveSessionCard: View {
    let coordinator: AppCoordinator
    let focused: AgentSummary
    let session: AgentSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                // Live sessions first; drop the least relevant chips into "+N" when space runs out.
                ViewThatFits(in: .horizontal) {
                    ForEach(chipLimits, id: \.self) { limit in chipRow(limit: limit) }
                }
                .frame(minWidth: 0, alignment: .leading)
                Spacer(minLength: 4)
                if session != nil {
                    IconButton(systemName: "macwindow", label: "Show where it runs") { coordinator.jumpToTerminal(focused) }
                    IconButton(systemName: "arrow.up.left.and.arrow.down.right", label: "Open session") {
                        coordinator.openSession(for: focused.id)
                    }
                }
            }
            if let session {
                SessionBody(session: session, preview: focused.preview)
            } else {
                NotConnected(agent: focused) { coordinator.openSettings(.agents) }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .premiumCard(glow: Theme.blue, glowCenter: .topTrailing)
    }

    /// Agents ordered by relevance: the focused one, live sessions (most urgent first), connected, the rest.
    private var orderedAgents: [AgentSummary] {
        let agents = coordinator.state.agents
        func rank(_ a: AgentSummary) -> Int {
            if a.id == focused.id { return 1000 }
            if a.isConnected && a.status.isLive { return 500 + AgentSessionState.priority(a.status) }
            return a.isConnected ? 100 : 0
        }
        return agents.enumerated().sorted { (rank($0.element), -$0.offset) > (rank($1.element), -$1.offset) }.map(\.element)
    }

    /// How many chips to try showing, widest first.
    private var chipLimits: [Int] {
        let count = orderedAgents.count
        let live = coordinator.state.agents.filter { $0.isConnected && $0.status.isLive }.count
        return Array(Set([count, max(live + 1, 4), max(live + 1, 2), 1])).filter { $0 <= count }.sorted(by: >)
    }

    private func chipRow(limit: Int) -> some View {
        let shown = Array(orderedAgents.prefix(limit)), hidden = Array(orderedAgents.dropFirst(limit))
        return HStack(spacing: 5) {
            ForEach(shown) { agent in
                AgentChip(agent: agent, selected: agent.id == focused.id) { coordinator.focus(agent: agent.id) }
            }
            if !hidden.isEmpty, !IsolatedHostSwitch.enabled {
                // Snapshots can't draw AppKit menus: a plain label.
                Text("+\(hidden.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 7)
                    .frame(height: 28)
                    .background(Color.white.opacity(0.06), in: Capsule())
            } else if !hidden.isEmpty {
                Menu {
                    ForEach(hidden) { agent in
                        Button(agent.isConnected ? "\(agent.title) · \(agent.status.label)" : agent.title) { coordinator.focus(agent: agent.id) }
                    }
                } label: {
                    Text("+\(hidden.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 7)
                        .frame(height: 28)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More agents")
            }
        }
        .fixedSize()
    }
}

private struct SessionBody: View {
    let session: AgentSession
    let preview: SessionPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            ViewThatFits(in: .horizontal) {
                StepTrack(actions: Array(session.actions.suffix(6)), finished: session.status == .completed)
                StepTrack(actions: Array(session.actions.suffix(4)), finished: session.status == .completed)
                StepTrack(actions: Array(session.actions.suffix(2)), finished: session.status == .completed)
            }
            if !preview.lines.isEmpty {
                CodePreview(preview: preview, accent: session.agent.brand.tint)
            } else {
                ActivityList(notes: Array(preview.notes.suffix(3)))
            }
            Spacer(minLength: 0)
        }
    }

    private var title: String {
        switch session.status {
        case .waiting where session.actions.isEmpty: "Waiting for a prompt"
        case .waiting, .completed: session.currentTask ?? "Waiting for your next prompt"
        default: session.currentTask ?? session.actions.last?.detail ?? "Working"
        }
    }

    private var subtitle: String {
        var parts = [session.projectName ?? "Session"]
        switch session.status {
        case .completed: parts.append("finished in \(AgentSummary.format(session.elapsed(now: Date())))")
        case .waiting: parts.append("waiting for you")
        case .needsApproval: parts.append("needs your approval")
        default: if let tool = session.currentTool { parts.append("using \(tool)") }
        }
        return parts.joined(separator: " · ")
    }
}

/// Horizontal timeline of the latest tool steps.
private struct StepTrack: View {
    let actions: [AgentAction]
    let finished: Bool

    var body: some View {
        track
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Steps")
            .accessibilityValue(actions.isEmpty ? "none yet" : actions.map { "\($0.tool) \($0.state == .running ? "running" : $0.state == .done ? "done" : "failed")" }.joined(separator: ", "))
    }

    private var track: some View {
        HStack(spacing: 0) {
            if actions.isEmpty {
                Text("No tool activity yet")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                if index > 0 {
                    Rectangle()
                        .fill(color(for: actions[index - 1]).opacity(0.5))
                        .frame(height: 1.5)
                        .frame(maxWidth: 26)
                }
                VStack(spacing: 3) {
                    ZStack {
                        Circle().fill(color(for: action).opacity(0.18)).frame(width: 18, height: 18)
                        switch action.state {
                        case .running: Spinner(size: 10, lineWidth: 1.5)
                        case .done: Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.success)
                        case .failed: Image(systemName: "xmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.error)
                        }
                    }
                    Text(action.tool)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(action.state == .running ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                }
                .fixedSize()
                .help(action.detail)
            }
            if finished, !actions.isEmpty {
                Rectangle().fill(Theme.success.opacity(0.5)).frame(height: 1.5).frame(maxWidth: 26)
                Image(systemName: "flag.checkered").font(.system(size: 10)).foregroundStyle(Theme.success)
            }
        }
        .fixedSize()
    }

    private func color(for action: AgentAction) -> Color {
        switch action.state {
        case .running: Theme.cyan
        case .done: Theme.success
        case .failed: Theme.error
        }
    }
}

private struct NotConnected: View {
    let agent: AgentSummary
    var connect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            LogoTile(mark: agent.brand, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(agent.name) isn't connected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(agent.kind == .claude ? "Install the Nova hook to see sessions and approve commands here."
                     : agent.kind == .vscode ? "Install the Nova VS Code extension to see tasks, debugging and errors."
                     : "Any tool can report to Nova's local socket.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PillButton(title: "How to connect", systemImage: "arrow.right", style: .secondary, action: connect)
                    .frame(width: 150)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Logo tile that expands to show the name when selected.
private struct AgentChip: View {
    let agent: AgentSummary
    let selected: Bool
    var action: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                LogoTile(mark: agent.brand, size: 22, status: agent.isConnected ? agent.status.color : nil)
                    .opacity(agent.isConnected || selected ? 1 : 0.45)
                    .overlay(alignment: .bottomLeading) {
                        if agent.siblingCount > 1, let tag = agent.tagColor {
                            Circle().fill(tag).frame(width: 7, height: 7)
                                .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
                                .offset(x: -1, y: 1)
                        }
                    }
                if selected {
                    Text(agent.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 140, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(3)
            .padding(.trailing, selected ? 6 : 0)
            .background(Color.white.opacity(selected ? 0.09 : (hovering ? 0.05 : 0)), in: Capsule())
            .scaleEffect(hovering && !selected ? 1.06 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(agent.title) · \(agent.isConnected ? agent.status.label : "Not connected")")
    }
}
