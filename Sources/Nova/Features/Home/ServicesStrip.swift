import NovaKit
import SwiftUI

/// Live developer services. Tap one for details; unconnected ones open Settings.
struct ServicesStrip: View {
    let coordinator: AppCoordinator

    var body: some View {
        let manager = coordinator.integrations
        HStack(spacing: 6) {
            ForEach(IntegrationKind.allCases) { kind in
                ServiceChip(kind: kind, connected: manager.isConnected(kind), snapshot: manager.snapshots[kind],
                            error: manager.errors[kind], refreshing: manager.refreshing.contains(kind)) {
                    if manager.isConnected(kind) { coordinator.openIntegration(kind) } else { coordinator.openSettings(.integrations) }
                }
            }
        }
    }
}

private struct ServiceChip: View {
    let kind: IntegrationKind
    let connected: Bool
    let snapshot: ServiceSnapshot?
    let error: String?
    let refreshing: Bool
    var action: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                LogoTile(mark: kind.brand, size: 22)
                    .saturation(connected ? 1 : 0)
                    .opacity(connected ? 1 : 0.55)
                VStack(alignment: .leading, spacing: 0) {
                    Text(kind.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(Theme.textPrimary.opacity(connected ? 1 : 0.6))
                    Text(line)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(error != nil ? Theme.warning : Theme.textSecondary)
                        .lineLimit(1)
                }
                if refreshing {
                    Spinner(size: 8, lineWidth: 1.2)
                } else if let snapshot {
                    StatusDot(color: snapshot.health.color, live: snapshot.health == .failing, size: 5)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 36)
            .background(Theme.panel.opacity(hovering ? 1 : 0.85), in: Capsule())
            .overlay(Capsule().strokeBorder((snapshot?.health == .failing ? Theme.error : Color.white).opacity(hovering ? 0.18 : 0.08)))
            .shadow(color: kind.brand.tint.opacity(hovering ? 0.25 : 0), radius: 8)
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(error ?? snapshot?.detail ?? (connected ? "Loading…" : "Connect \(kind.displayName) in Settings"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.displayName)
        .accessibilityValue(connected ? [line, snapshot?.detail].compactMap { $0 }.joined(separator: ", ") : "not connected")
        .accessibilityHint(connected ? "Shows details" : "Opens Integrations settings")
        .accessibilityAddTraits(.isButton)
    }

    private var line: String {
        if !connected { return "Connect" }
        if error != nil { return "Error" }
        return snapshot?.headline ?? "Loading…"
    }
}
