import SwiftUI

/// Wide alert card shown in the `.notification` state.
struct NotificationBannerView: View {
    let coordinator: AppCoordinator
    let banner: NotchBanner

    @ViewState private var fire = 0
    @Environment(\.novaStyle) private var style

    private var tint: Color {
        switch banner.expression {
        case .error, .dizzy: Theme.violet
        case .warning: Theme.warning
        case .success: Theme.success
        default: Theme.cyan
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: coordinator.state.geometry.notchHeight)
            HStack(spacing: 14) {
                NovaCharacterView(art: .head, expression: banner.expression,
                                  cursor: coordinator.cursor, anchor: coordinator.novaAnchor)
                    .frame(width: 54, height: 50)
                VStack(alignment: .leading, spacing: 3) {
                    Text(banner.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(banner.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(colors: [tint.opacity(0.12), .clear], startPoint: .leading, endPoint: .trailing)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            )
            .overlay(alignment: .leading) {
                Capsule().fill(tint).frame(width: 3).padding(.vertical, 16).padding(.leading, 1)
            }
            .premiumCard()
            .modifier(BannerEffect(expression: banner.expression, fire: fire))
            .overlay(alignment: .leading) {
                if banner.expression == .success {
                    ParticleBurst(trigger: fire, style: .confetti).frame(width: 140, height: 120).offset(x: -10)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .onAppear { if style.animations { fire += 1 } }
        .onChange(of: banner.title) { if style.animations { fire += 1 } }
    }
}

/// Error → shake; warnings and news → a light sweep; success uses confetti.
private struct BannerEffect: ViewModifier {
    let expression: NovaExpression
    let fire: Int

    func body(content: Content) -> some View {
        switch expression {
        case .error, .dizzy, .annoyed: content.shake(fire)
        case .success: content
        default: content.shine(fire)
        }
    }
}
