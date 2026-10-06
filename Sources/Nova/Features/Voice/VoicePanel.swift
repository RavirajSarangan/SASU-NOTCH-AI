import NovaKit
import SwiftUI

/// The notch while you talk to Nova: listening (live words + level),
/// thinking, then the reply as Nova speaks it.
struct VoicePanel: View {
    let coordinator: AppCoordinator

    @Environment(\.novaStyle) private var style

    private var voice: VoiceService { coordinator.voice }

    var body: some View {
        let state = coordinator.state
        VStack(spacing: 0) {
            Color.clear.frame(height: state.geometry.notchHeight)
            HStack(alignment: .center, spacing: 12) {
                NovaCharacterView(art: .head, expression: state.expression, cursor: coordinator.cursor,
                                  anchor: coordinator.novaAnchor, maxFPS: 24)
                    .frame(width: 40, height: 37)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(bodyText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.15), value: bodyText)
                }
                if let pending = coordinator.pendingVoiceAction {
                    // Risky clicks run only from this mouse click, never from voice.
                    Button(pending.confirm) { coordinator.confirmVoiceAction() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.warning)
                        .controlSize(.small)
                        .help(pending.title)
                } else {
                    LevelBars(level: voice.level, color: accent, active: voice.phase == .listening || voice.phase == .speaking)
                        .frame(width: 34, height: 22)
                }
                Button { coordinator.cancelVoiceAction() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Stop")
            }
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity)
        }
        .background {
            if style.nova2 && style.scenes {
                SceneBackgroundView(scene: voice.phase == .thinking ? .thinking : .aurora, paused: style.paused)
                    .opacity(0.7)
                    .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .bottom))
            }
        }
        .onChange(of: voice.phase, initial: true) { _, phase in
            coordinator.state.voiceExpression = switch phase {
            case .listening: .listening
            case .thinking: .thinking
            case .speaking: .happy
            case .idle: nil
            }
        }
    }

    static let hints = ["Try “what are my agents doing?”", "Try “Nova, dance!”", "Try “tell me a joke”",
                        "Try “scan security”", "Try “paattu podu”", "Try “open Safari”",
                        "Try “google swift concurrency”", "Try “timer 10 minutes”", "Try “new tab”"]
    @ViewState private var hintIndex = Int.random(in: 0..<9)

    private var title: String {
        if let pending = coordinator.pendingVoiceAction { return pending.title }
        if voice.phase == .speaking, let other = coordinator.lastVoiceProvider, other != coordinator.ai.defaultProvider {
            return "Nova · via \(other.displayName)"
        }
        return switch voice.phase {
        case .listening: "Listening…"
        case .thinking: "Thinking…"
        case .speaking: "Nova"
        case .idle: "Nova"
        }
    }

    private var bodyText: String {
        switch voice.phase {
        case .listening: voice.transcript.isEmpty ? Self.hints[hintIndex] : voice.transcript
        case .thinking: voice.transcript
        case .speaking, .idle: voice.reply
        }
    }

    private var accent: Color {
        switch voice.phase {
        case .listening: Theme.cyan
        case .thinking: Theme.violet
        default: Theme.success
        }
    }
}

/// Five bars that follow the voice level.
private struct LevelBars: View {
    var level: Double
    var color: Color
    var active: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                let shape = [0.55, 0.85, 1, 0.8, 0.5][i]
                Capsule()
                    .fill(color.opacity(active ? 0.95 : 0.35))
                    .frame(width: 4, height: max(4, 22 * (active ? level : 0.15) * shape))
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }
}
