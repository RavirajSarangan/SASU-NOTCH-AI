import NovaKit
import SwiftUI

extension PermissionRiskLevel {
    var color: Color {
        switch self {
        case .low: Theme.success
        case .medium: Theme.warning
        case .high: Theme.error
        }
    }

    var label: String {
        switch self {
        case .low: "Low risk"
        case .medium: "Medium risk"
        case .high: "High risk"
        }
    }
}

/// Shown the moment an agent asks for permission. Nothing is approved
/// without a click; high-risk requests can't be allowed for the whole session.
struct PermissionRequestView: View {
    let coordinator: AppCoordinator

    /// Buttons stay inactive briefly after a request appears (accidental-click guard).
    @ViewState private var armed = Self.startArmed
    #if DEBUG
    /// Landing-page screenshots show the buttons as they look once enabled.
    nonisolated(unsafe) static var startArmed = false
    #else
    static let startArmed = false
    #endif
    /// High-risk "Allow" needs a second click within a few seconds.
    @ViewState private var confirmingAllow = false

    var body: some View {
        if let request = coordinator.permissions.current {
            content(request)
                .onChange(of: request.id, initial: true) { _, id in
                    coordinator.permissionShown(id)
                    armed = Self.startArmed
                    confirmingAllow = false
                    Task {
                        try? await Task.sleep(for: .seconds(DecisionGate.armDelay))
                        if coordinator.permissions.current?.id == id { withAnimation(.easeOut(duration: 0.2)) { armed = true } }
                    }
                }
        } else {
            Color.clear
        }
    }

    private func allow(_ request: AgentPermissionRequest) {
        guard request.risk.level == .high, !confirmingAllow else {
            coordinator.decide(.allowOnce, requestId: request.id)
            return
        }
        withAnimation(.easeOut(duration: 0.15)) { confirmingAllow = true }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { confirmingAllow = false }
        }
    }

    private func content(_ request: AgentPermissionRequest) -> some View {
        let g = coordinator.state.geometry
        let wing = NotchLayout.wingWidth(for: coordinator.state.size, geometry: g)
        let count = coordinator.permissions.pending.count
        let risk = request.risk

        return VStack(spacing: 8) {
            // Top row in the notch wings.
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    LogoTile(mark: request.agent.brand, size: 20)
                    Text(request.agent.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let project = request.workingDirectory.map({ URL(fileURLWithPath: $0).lastPathComponent }) {
                        HStack(spacing: 4) {
                            Circle().fill(Theme.sessionColors[AgentSession.tag(for: request.sessionId)]).frame(width: 6, height: 6)
                            Text(project).lineLimit(1)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    }
                    if count > 1 {
                        Text("1 of \(count)")
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: g.hasNotch ? wing - 14 : nil, alignment: .leading)
                Spacer(minLength: g.hasNotch ? g.notchWidth : 0)
                if request.isQuestion {
                    Label("Question", systemImage: "questionmark.bubble.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.cyan.opacity(0.14), in: Capsule())
                } else {
                    Label(risk.level.label, systemImage: risk.level == .high ? "exclamationmark.triangle.fill" : "shield.lefthalf.filled")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(risk.level.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(risk.level.color.opacity(0.14), in: Capsule())
                }
            }
            .frame(height: g.notchHeight)

            if let questions = request.questions, !questions.isEmpty {
                HStack(alignment: .top, spacing: 14) {
                    NovaCharacterView(art: .body, expression: .thinking, cursor: coordinator.cursor, anchor: coordinator.novaAnchor)
                        .frame(width: 80, height: 80)
                        .padding(.top, 4)
                    QuestionCardView(coordinator: coordinator, request: request, questions: questions, armed: armed)
                }
            } else {
            HStack(alignment: .top, spacing: 14) {
                NovaCharacterView(art: .body, expression: .warning, cursor: coordinator.cursor, anchor: coordinator.novaAnchor)
                    .frame(width: 92, height: 92)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Wants to use")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                        Text(request.tool)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.cyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                        Spacer(minLength: 0)
                        Text(request.receivedAt, style: .time)
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if let edit = request.edit {
                        DiffView(preview: edit, maxLines: 4) {
                            DiffWindow.show(edit, title: "\(request.agent.displayName) wants to change \(edit.file.map { ($0 as NSString).lastPathComponent } ?? "a file")")
                        }
                        .overlay(alignment: .leading) {
                            Rectangle().fill(risk.level.color).frame(width: 2).padding(.vertical, 6)
                        }
                    } else {
                    Text(request.command ?? request.filePath ?? request.detail ?? request.tool)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(risk.level.color).frame(width: 2).padding(.vertical, 6)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
                    }

                    HStack(spacing: 10) {
                        if let cwd = request.workingDirectory {
                            Label((cwd as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                        Label(risk.reason, systemImage: "info.circle")
                            .foregroundStyle(risk.level.color.opacity(0.9))
                            .lineLimit(1)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(12)
            .premiumCard(glow: risk.level.color, glowCenter: .topLeading)

            HStack(spacing: 8) {
                DecisionButton(title: "Deny", hint: "esc", style: .secondary, disabled: !armed) {
                    coordinator.decide(.deny, requestId: request.id)
                }
                DecisionButton(title: "Always Allow for Session", hint: nil, style: .secondary,
                               disabled: !armed || risk.level == .high) { coordinator.decide(.allowForSession, requestId: request.id) }
                    .help(risk.level == .high ? "Not available for high-risk actions" : "Allow matching requests until this session ends")
                DecisionButton(title: confirmingAllow ? "Confirm allow" : "Allow Once",
                               hint: risk.level == .high ? nil : "⌘↩",
                               style: confirmingAllow ? .confirm : .primary, disabled: !armed) { allow(request) }
            }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

private struct DecisionButton: View {
    enum Style { case primary, secondary, confirm }
    let title: String
    let hint: String?
    let style: Style
    var disabled = false
    var action: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                if let hint {
                    Text(hint)
                        .font(.system(size: 10, weight: .medium))
                        .opacity(0.6)
                }
            }
            .foregroundStyle(style == .secondary ? Theme.textPrimary : Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background {
                if style == .primary {
                    Capsule().fill(LinearGradient(colors: [Theme.cyan, Color(hex: 0x7FB2FF)], startPoint: .leading, endPoint: .trailing))
                        .brightness(hovering ? 0.06 : 0)
                } else if style == .confirm {
                    Capsule().fill(Theme.warning).brightness(hovering ? 0.06 : 0)
                } else {
                    Capsule().fill(Color.white.opacity(hovering ? 0.12 : 0.07))
                }
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(style == .primary ? 0 : 0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .onHover { hovering = $0 }
    }
}
