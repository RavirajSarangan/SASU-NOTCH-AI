import AppKit
import SwiftUI

/// Your pinned apps on the left, Spotify on the right.
struct DockRow: View {
    let coordinator: AppCoordinator

    var body: some View {
        HStack(spacing: 8) {
            AppDock(coordinator: coordinator)
            if coordinator.spotify.isRunning {
                NowPlayingCard(spotify: coordinator.spotify)
                    .frame(width: 236)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: coordinator.spotify.isRunning)
    }
}

struct AppDock: View {
    let coordinator: AppCoordinator

    var body: some View {
        let launcher = coordinator.launcher
        HStack(spacing: 6) {
            ForEach(launcher.apps) { app in
                DockIcon(app: app, running: launcher.running.contains(app.bundleID)) { launcher.open(app) }
                    .contextMenu {
                        Button("Open") { launcher.open(app) }
                        if launcher.running.contains(app.bundleID) {
                            Button("Hide") { launcher.hide(app) }
                            Button("Quit") { launcher.quit(app) }
                        }
                        Divider()
                        Button("Remove from Nova") { launcher.unpin(app.bundleID) }
                    }
            }
            Button { coordinator.openSettings(.general) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            }
            .buttonStyle(.plain)
            .help("Choose apps")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .premiumCard(radius: 16)
    }
}

private struct DockIcon: View {
    let app: LauncherApp
    let running: Bool
    var open: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(spacing: 3) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.4), radius: hovering ? 6 : 2, y: hovering ? 4 : 1)
                Circle()
                    .fill(running ? Theme.textPrimary.opacity(0.85) : .clear)
                    .frame(width: 3.5, height: 3.5)
            }
            .scaleEffect(hovering ? 1.12 : 1, anchor: .bottom)
            .offset(y: hovering ? -2 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(app.name)
        .accessibilityLabel(app.name)
    }
}

struct NowPlayingCard: View {
    let spotify: SpotifyService

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: 0x1DB954).opacity(0.18))
                if let art = spotify.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(hex: 0x1DB954))
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onTapGesture { spotify.open() }

            VStack(alignment: .leading, spacing: 3) {
                Text(spotify.track?.name ?? "Spotify")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(spotify.controlError ?? spotify.track?.artist ?? "Press play")
                    .font(.system(size: 10))
                    .foregroundStyle(spotify.controlError == nil ? Theme.textSecondary : Theme.warning)
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    GeometryReader { proxy in
                        Capsule().fill(Color.white.opacity(0.1))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color(hex: 0x1DB954)).frame(width: proxy.size.width * spotify.progress)
                            }
                    }
                    .frame(height: 3)
                }
            }
            HStack(spacing: 2) {
                control("backward.fill", label: "Previous track") { spotify.previous() }
                control(spotify.isPlaying ? "pause.fill" : "play.fill", label: spotify.isPlaying ? "Pause" : "Play", big: true) { spotify.playPause() }
                control("forward.fill", label: "Next track") { spotify.next() }
            }
        }
        .padding(.horizontal, 9)
        .frame(maxHeight: .infinity)
        .premiumCard(radius: 16, glow: Color(hex: 0x1DB954))
    }

    private func control(_ symbol: String, label: String, big: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: big ? 13 : 9.5, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: big ? 26 : 20, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Tiny animated equalizer for the notch wing while music plays.
struct Equalizer: View {
    var color: Color = Color(hex: 0x1DB954)

    @Environment(\.novaStyle) private var style

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: style.paused)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 2, height: 3 + 7 * CGFloat(abs(sin(t * (3.1 + Double(i) * 0.9) + Double(i)))))
                }
            }
            .frame(width: 14, height: 11, alignment: .bottom)
        }
    }
}
