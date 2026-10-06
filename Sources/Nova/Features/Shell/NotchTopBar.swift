import SwiftUI

/// Expanded-state top row. The tabs sit in the left wing and the controls
/// in the right wing, leaving the camera housing clear.
struct NotchTopBar: View {
    let coordinator: AppCoordinator

    @Namespace private var tabSelection

    var body: some View {
        let state = coordinator.state
        let g = state.geometry
        let wing = NotchLayout.wingWidth(for: state.size, geometry: g)

        HStack(spacing: 0) {
            tabs
                .frame(width: g.hasNotch ? wing - 14 : nil, alignment: .leading)
            Spacer(minLength: g.hasNotch ? g.notchWidth : 0)
            HStack(spacing: 6) {
                if coordinator.prefs.voiceEnabled {
                    IconButton(systemName: coordinator.voice.phase == .listening ? "mic.fill" : "mic",
                               label: "Talk to Nova (hold ⌥ Space)") { coordinator.toggleTalking() }
                }
                UsageRing(coordinator: coordinator)
                SecurityBadge(coordinator: coordinator)
                IconButton(
                    systemName: coordinator.sound.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    label: coordinator.sound.isMuted ? "Unmute sounds" : "Mute sounds"
                ) { coordinator.sound.isMuted.toggle() }
                IconButton(systemName: "gearshape.fill", label: "Settings") { coordinator.perform(.settings) }
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(NovaTab.allCases, id: \.self) { tab in
                let selected = coordinator.state.selectedTab == tab
                Button {
                    coordinator.select(tab)
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                        .frame(width: 34, height: 24)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Color.white.opacity(0.12))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
                                    .matchedGeometryEffect(id: "tab", in: tabSelection)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.04), in: Capsule())
    }
}

/// Placeholder content for tabs that land in later phases.
struct EmptyStateView: View {
    let coordinator: AppCoordinator
    let expression: NovaExpression
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 18) {
            NovaCharacterView(art: .body, expression: expression, cursor: coordinator.cursor, anchor: coordinator.novaAnchor)
                .frame(height: 110)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .premiumCard(glow: Theme.violet, glowCenter: .leading)
    }
}

/// The 5-hour usage window of your busiest agent, once you've set a limit.
private struct UsageRing: View {
    let coordinator: AppCoordinator

    var body: some View {
        let busiest = coordinator.usage.summaries.compactMap { source, s in s.blockFraction.map { (source, $0, s) } }
            .max { $0.1 < $1.1 }
        if let (source, fraction, summary) = busiest {
            let color = fraction >= 0.95 ? Theme.error : fraction >= 0.8 ? Theme.warning : Theme.success
            Button { coordinator.openSettings(.usage) } label: {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 2.5)
                    Circle().trim(from: 0, to: min(fraction, 1)).stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(min(Int(fraction * 100), 99))").font(.system(size: 7.5, weight: .bold)).monospacedDigit().foregroundStyle(color)
                }
                .frame(width: 20, height: 20)
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("\(UsageService.name(source)): \(Int(fraction * 100))% of your 5-hour window" + (summary.blockEnd.map { ", resets \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
            .accessibilityLabel("Usage \(Int(fraction * 100)) percent")
        }
    }
}

