import NovaKit
import SwiftUI

/// Fills the whole (transparent) panel and draws the animated notch shape
/// pinned to the top center, with the content for the current state.
struct NotchRootView: View {
    let coordinator: AppCoordinator

    private var state: AppState { coordinator.state }

    var body: some View {
        let size = state.displaySize
        let layout = state.size
        let scale = state.contentScale
        let radii = NotchLayout.cornerRadii(for: state.notchState)
        let shape = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)

        ZStack(alignment: .top) {
            #if DEBUG
            if DemoDirector.active { DemoBackdrop(notchHeight: state.geometry.notchHeight) }
            #endif
            shape
                .fill(Color.black)
                .overlay(alignment: .top) {
                    content
                        .frame(width: layout.width, height: layout.height, alignment: .top)
                        .scaleEffect(scale, anchor: .top)
                        .frame(width: size.width, height: size.height, alignment: .top)
                }
                .clipShape(shape)
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(state.notchState.isExpanded ? 0.55 : 0), radius: 22, y: 10)
                .contentShape(shape)
                .onTapGesture { coordinator.notchTapped() }
        }
        .frame(width: NotchLayout.canvasSize.width, height: NotchLayout.canvasSize.height, alignment: .top)
        .opacity(state.isVisible ? 1 : 0)
        .environment(\.novaStyle, coordinator.style)
        .environment(\.novaLive, coordinator.liveContext)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch state.notchState {
        case .permissionRequest:
            PermissionRequestView(coordinator: coordinator)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        case .agentSession:
            AgentSessionView(coordinator: coordinator)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        case .integrationView:
            Group {
                if case .service(let kind) = state.integrationFocus {
                    IntegrationDetailView(coordinator: coordinator, kind: kind)
                } else if state.integrationFocus == .security {
                    SecurityDetailView(coordinator: coordinator)
                } else {
                    AutomationReviewView(coordinator: coordinator)
                }
            }
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        case .expandedHome, .aiChat, .settings:
            ExpandedView(coordinator: coordinator)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .offset(y: -8)))
        case .notification:
            if let banner = state.banner {
                NotificationBannerView(coordinator: coordinator, banner: banner)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        case .voice:
            VoicePanel(coordinator: coordinator)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
        case .compact:
            CompactView(coordinator: coordinator)
                .transition(.opacity)
        case .hidden, .idle, .hover, .sleep:
            NotchTopRow(coordinator: coordinator)
                .transition(.opacity)
        }
    }
}

/// Full panel: tab bar in the notch row, selected tab below.
struct ExpandedView: View {
    let coordinator: AppCoordinator

    var body: some View {
        let state = coordinator.state
        VStack(spacing: 8) {
            NotchTopBar(coordinator: coordinator)
                .frame(height: state.geometry.notchHeight)
            Group {
                switch state.selectedTab {
                case .home:
                    HomeView(coordinator: coordinator)
                case .chat:
                    ChatView(coordinator: coordinator, chat: coordinator.chat)
                case .brief:
                    BriefView(coordinator: coordinator)
                case .add:
                    EmptyStateView(coordinator: coordinator, expression: .excited, title: "Connect a service",
                                   message: "GitHub, Vercel, n8n, Supabase and more. Arrives in Phase 4.")
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }
}

/// The always-visible row: Nova peeking out of the left wing, activity on
/// the right. On Macs without a notch it becomes a small pill.
struct NotchTopRow: View {
    let coordinator: AppCoordinator

    var body: some View {
        let state = coordinator.state
        let g = state.geometry
        let wing = NotchLayout.wingWidth(for: state.size, geometry: g)
        let head = g.notchHeight - 6

        HStack(spacing: 0) {
            NovaCharacterView(art: .head, expression: state.expression, cursor: coordinator.cursor,
                              anchor: coordinator.novaAnchor, paused: !state.isVisible,
                              maxFPS: state.notchState == .sleep ? 10 : 20)
                .frame(width: head, height: head)
                .frame(width: g.hasNotch ? wing : head + 14)

            if g.hasNotch {
                Spacer(minLength: g.notchWidth)
            } else {
                Text(state.notchState == .sleep ? "Sleeping" : "Nova")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }

            Group {
                if !coordinator.hasActivity, coordinator.spotify.isPlaying, state.notchState != .sleep {
                    Equalizer()
                } else {
                    ActivityIndicator(active: coordinator.hasActivity, sleeping: state.notchState == .sleep)
                }
            }
            .frame(width: g.hasNotch ? wing : 26)
            .overlay(alignment: .topTrailing) {
                // Listening for "Hey Nova" (on your Mac only).
                if coordinator.voice.wakeListening {
                    Circle().fill(Theme.success).frame(width: 4, height: 4)
                        .padding(.top, 5).padding(.trailing, 4)
                        .help("Listening for “Hey Nova” on this Mac")
                }
            }
        }
        .frame(height: g.notchHeight)
    }
}

/// Hover-dwell state: a wide aurora strip under the notch with Nova inside
/// an orbit ring and the current activity.
struct CompactView: View {
    let coordinator: AppCoordinator

    @Environment(\.novaStyle) private var style
    @Environment(\.novaLive) private var live

    private var scene: RigScene {
        let mood = RigMood(rawValue: coordinator.state.expression.rawValue) ?? .idle
        let dancing = live.music?.sample() != nil && live.approvalSince == nil && !live.guardAlert
        return RigScene.scene(for: mood, dancing: dancing, guardAlert: live.guardAlert)
    }

    var body: some View {
        let state = coordinator.state
        let agent = state.focusedAgent
        VStack(spacing: 0) {
            Color.clear.frame(height: state.geometry.notchHeight)
            HStack(spacing: 12) {
                NovaCharacterView(art: .head, expression: state.expression, cursor: coordinator.cursor,
                                  anchor: coordinator.novaAnchor, maxFPS: 20)
                    .frame(width: 34, height: 32)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        LogoTile(mark: agent.brand, size: 15)
                        Text(agent.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(agent.status.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(agent.status.color)
                        if state.liveSessionCount > 1 {
                            Button { coordinator.focusNextSession() } label: {
                                Text("\(state.liveSessionCount) active")
                                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.white.opacity(0.1), in: Capsule())
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .buttonStyle(.plain)
                            .help("Show the next session")
                        }
                        if agent.subagents > 0 {
                            Label("\(agent.subagents)", systemImage: "bolt.fill")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Theme.warning)
                                .help("Subagents started")
                        }
                    }
                    Text(agent.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textPrimary.opacity(0.75))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if agent.status.isLive {
                    Spinner(color: Theme.cyan, size: 18, lineWidth: 2.2)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
        }
        .background(alignment: .bottom) {
            // Quiet surface: a soft lift under the notch and a thin status-colored hairline.
            ZStack(alignment: .bottom) {
                if style.nova2 && style.scenes {
                    // Nova 2: the mood's animated scene, fading into the black notch at the top.
                    SceneBackgroundView(scene: scene, music: live.music, paused: style.paused, fps: 6)
                        .opacity(0.75)
                        .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .bottom))
                }
                LinearGradient(colors: [.clear, Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [.clear, agent.status.color.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                    .padding(.horizontal, 40)
            }
        }
    }
}

/// Small glowing ring on the right wing that breathes while agents work.
private struct ActivityIndicator: View {
    var active: Bool
    var sleeping: Bool

    var body: some View {
        Group {
            if active && !sleeping {
                Spinner(color: Theme.cyan, size: 12, lineWidth: 2)
            } else {
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Theme.cyan, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 12, height: 12)
            }
        }
        .opacity(sleeping ? 0.25 : (active ? 1 : 0.4))
    }
}
