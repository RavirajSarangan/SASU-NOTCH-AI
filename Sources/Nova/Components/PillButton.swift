import SwiftUI

/// Capsule button used for actions inside the notch.
struct PillButton: View {
    enum Style { case primary, secondary, quiet }

    let title: String
    var systemImage: String?
    var hint: String?
    var style: Style = .secondary
    var tint: Color = Theme.cyan
    var action: () -> Void

    @ViewState private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 11, weight: .bold)) }
                Text(title).font(.system(size: 12, weight: .semibold))
                if let hint { Text(hint).font(.system(size: 10, weight: .medium)).opacity(0.6) }
            }
            .foregroundStyle(style == .primary ? Color.black : (style == .quiet ? Theme.textSecondary : Theme.textPrimary))
            .padding(.horizontal, 14)
            .frame(maxWidth: style == .quiet ? nil : .infinity)
            .frame(height: 30)
            .background {
                switch style {
                case .primary:
                    Capsule().fill(LinearGradient(colors: [tint, tint.opacity(0.75)], startPoint: .leading, endPoint: .trailing))
                        .brightness(hovering ? 0.06 : 0)
                case .secondary:
                    Capsule().fill(Color.white.opacity(hovering ? 0.12 : 0.07))
                case .quiet:
                    Capsule().fill(Color.white.opacity(hovering ? 0.08 : 0))
                }
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(style == .secondary ? 0.08 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovering = $0 }
    }
}
