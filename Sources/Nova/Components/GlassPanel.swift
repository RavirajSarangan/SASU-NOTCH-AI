import SwiftUI

/// Subtle raised surface for small elements (chips, tiles).
struct GlassPanel: ViewModifier {
    var radius: CGFloat = Theme.Radius.control
    var fill: Color = Theme.panelSecondary

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline))
    }
}

/// Main card surface: gradient hairline border, a faint top highlight and an
/// optional accent glow bleeding in from one corner.
struct PremiumCard: ViewModifier {
    var radius: CGFloat = Theme.Radius.card
    var glow: Color?
    var glowCenter: UnitPoint = .topLeading

    @Environment(\.novaStyle) private var style

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(Theme.panel)
                    if let glow {
                        RadialGradient(colors: [glow.opacity(0.10 * style.glow), .clear], center: glowCenter, startRadius: 0, endRadius: 240)
                    }
                    LinearGradient(colors: [Color.white.opacity(0.035), .clear], startPoint: .top, endPoint: .center)
                }
                .clipShape(shape)
            }
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            )
            // Inner top highlight for depth.
            .overlay(
                shape.inset(by: 1.5).strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.07), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25)),
                    lineWidth: 1
                )
            )
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}

extension View {
    func glassPanel(radius: CGFloat = Theme.Radius.control, fill: Color = Theme.panelSecondary) -> some View {
        modifier(GlassPanel(radius: radius, fill: fill))
    }

    func premiumCard(radius: CGFloat = Theme.Radius.card, glow: Color? = nil, glowCenter: UnitPoint = .topLeading) -> some View {
        modifier(PremiumCard(radius: radius, glow: glow, glowCenter: glowCenter))
    }
}
