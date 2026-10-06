import SwiftUI

/// Design tokens for Nova. Every color in the UI should come from here.
enum Theme {
    // Surfaces
    static let background = Color(hex: 0x0A0B10)
    static let panel = Color(hex: 0x11131A)
    static let panelSecondary = Color(hex: 0x171A23)
    static let hairline = Color.white.opacity(0.06)

    // Text
    static let textPrimary = Color(hex: 0xF5F7FF)
    static let textSecondary = Color(hex: 0x9DA4B4)

    // Accents
    static let cyan = Color(hex: 0x53E7FF)
    static let blue = Color(hex: 0x5A7CFF)
    static let violet = Color(hex: 0xA36CFF)
    /// One color per concurrent session (see AgentSession.tag).
    static let sessionColors: [Color] = [Color(hex: 0x53E7FF), Color(hex: 0xA36CFF), Color(hex: 0xFFB454),
                                         Color(hex: 0x5BE49B), Color(hex: 0xFF6FB5), Color(hex: 0x7FA8FF)]

    // Semantic
    static let success = Color(hex: 0x5BD69A)
    static let warning = Color(hex: 0xF5C26B)
    static let error = Color(hex: 0xFF7A7A)

    /// Type scale. Prefer these over ad-hoc sizes.
    enum Typography {
        static let micro = Font.system(size: 9, weight: .medium)
        static let caption = Font.system(size: 10)
        static let footnote = Font.system(size: 11)
        static let body = Font.system(size: 12)
        static let headline = Font.system(size: 13, weight: .semibold)
        static let title = Font.system(size: 15, weight: .semibold)
        static let display = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let mono = Font.system(size: 11, design: .monospaced)
    }

    enum Radius {
        static let card: CGFloat = 20
        static let control: CGFloat = 9
    }

    enum Motion {
        static let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)
        static let reduced = Animation.easeInOut(duration: 0.18)

        @MainActor static var current: Animation {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? reduced : spring
        }
    }
}
