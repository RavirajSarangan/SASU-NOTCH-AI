import AppKit
import NovaKit
import SwiftUI

/// Detail panel for one connected service.
struct IntegrationDetailView: View {
    let coordinator: AppCoordinator
    let kind: IntegrationKind

    var body: some View {
        let manager = coordinator.integrations
        let snapshot = manager.snapshots[kind]
        let g = coordinator.state.geometry
        let wing = NotchLayout.wingWidth(for: coordinator.state.size, geometry: g)

        VStack(spacing: 8) {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    IconButton(systemName: "chevron.left", label: "Back") { coordinator.backToHome() }
                    LogoTile(mark: kind.brand, size: 20)
                    Text(kind.displayName).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                }
                .frame(width: g.hasNotch ? wing - 14 : nil, alignment: .leading)
                Spacer(minLength: g.hasNotch ? g.notchWidth : 0)
                HStack(spacing: 6) {
                    if manager.refreshing.contains(kind) { Spinner(size: 11) }
                    IconButton(systemName: "arrow.clockwise", label: "Refresh") { Task { await manager.refresh(kind) } }
                    if let web = snapshot?.webURL, let url = URL(string: web) {
                        IconButton(systemName: "arrow.up.right.square", label: "Open in browser") { NSWorkspace.shared.open(url) }
                    }
                }
            }
            .frame(height: g.notchHeight)

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    StatusDot(color: snapshot?.health.color ?? Theme.textSecondary, live: snapshot?.health == .failing, size: 8)
                    Text(snapshot?.headline ?? "Loading…")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(manager.errors[kind] ?? snapshot?.detail ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(manager.errors[kind] == nil ? Theme.textSecondary : Theme.warning)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(width: 190)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .premiumCard(glow: kind.brand.tint)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(snapshot?.sections ?? []) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.title.uppercased())
                                    .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                                    .foregroundStyle(Theme.textSecondary)
                                ForEach(section.items) { item in ItemRow(item: item) }
                            }
                        }
                        if snapshot?.sections.isEmpty ?? true {
                            Text("Nothing to show yet.").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(12)
                }
                .scrollIndicators(.never)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .premiumCard(glow: Theme.blue, glowCenter: .topTrailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }
}

private struct ItemRow: View {
    let item: ServiceItem

    @ViewState private var hovering = false

    var body: some View {
        Button {
            if let link = item.url, let url = URL(string: link) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(item.health.color).frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(item.subtitle).font(.system(size: 10)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let date = item.date {
                    Text(date, format: .relative(presentation: .named))
                        .font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                }
                if item.url != nil {
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textSecondary)
                        .opacity(hovering ? 1 : 0)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
