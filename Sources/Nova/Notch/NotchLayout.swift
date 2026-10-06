import AppKit

/// Physical notch measurements for the screen Nova lives on.
struct NotchGeometry: Equatable, Sendable {
    var screenFrame: CGRect
    /// Width of the camera housing; 0 on Macs without a notch.
    var notchWidth: CGFloat
    /// Height of the top row (the notch, or a menu-bar-height row).
    var notchHeight: CGFloat
    var hasNotch: Bool

    static let fallback = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        notchWidth: 0, notchHeight: 32, hasNotch: false
    )
}

enum NotchLayout {
    /// Fixed panel size. The visible shape animates inside it, so the window
    /// itself never resizes mid-animation. Large enough for the chat state.
    static let canvasSize = CGSize(width: 760, height: 640)

    static var forceNoNotch: Bool {
        ProcessInfo.processInfo.environment["NOVA_FORCE_NO_NOTCH"] == "1"
    }

    /// The screen Nova lives on, per the user's choice.
    @MainActor
    static func preferredScreen(_ choice: ScreenChoice = .automatic) -> NSScreen? {
        switch choice {
        case .main:
            return NSScreen.screens.first ?? NSScreen.main
        case .builtIn:
            let builtIn = NSScreen.screens.first { screen in
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
                return CGDisplayIsBuiltin(id) != 0
            }
            if let builtIn { return builtIn }
            fallthrough
        case .automatic:
            if !forceNoNotch, let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
                return notched
            }
            return NSScreen.main ?? NSScreen.screens.first
        }
    }

    @MainActor
    static func geometry(for screen: NSScreen) -> NotchGeometry {
        let top = screen.safeAreaInsets.top
        if !forceNoNotch, top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return NotchGeometry(screenFrame: screen.frame, notchWidth: width, notchHeight: top, hasNotch: true)
        }
        return NotchGeometry(screenFrame: screen.frame, notchWidth: 0, notchHeight: 32, hasNotch: false)
    }

    /// Visible shape size for a state. Notched screens grow "wings" either
    /// side of the camera housing; other screens use a floating pill.
    static func size(for state: NotchState, geometry g: NotchGeometry) -> CGSize {
        let nw = g.notchWidth, nh = g.notchHeight
        switch state {
        case .hidden:
            return CGSize(width: max(nw, 1), height: g.hasNotch ? nh : 1)
        case .idle, .sleep:
            return g.hasNotch ? CGSize(width: nw + 2 * (nh + 4), height: nh) : CGSize(width: 140, height: 34)
        case .hover:
            return g.hasNotch ? CGSize(width: nw + 2 * (nh + 14), height: nh + 2) : CGSize(width: 160, height: 36)
        case .compact:
            return CGSize(width: max(460, nw + 2 * (nh + 100)), height: nh + 52)
        case .notification:
            return CGSize(width: max(420, nw + 200), height: nh + 98)
        case .voice:
            return CGSize(width: max(480, nw + 260), height: nh + 86)
        case .expandedHome, .agentSession, .integrationView, .settings:
            return CGSize(width: 640, height: nh + 318)
        case .permissionRequest:
            return CGSize(width: 640, height: nh + 182)   // + AppState.permissionExtraHeight
        case .aiChat:
            return CGSize(width: 640, height: nh + 440)
        }
    }

    static func cornerRadii(for state: NotchState) -> (top: CGFloat, bottom: CGFloat) {
        switch state {
        case .hidden, .idle, .sleep, .hover: (6, 12)
        case .compact, .notification, .voice: (8, 18)
        default: (10, 26)
        }
    }

    /// Width of each side wing next to the notch.
    static func wingWidth(for size: CGSize, geometry g: NotchGeometry) -> CGFloat {
        max((size.width - g.notchWidth) / 2, 0)
    }
}
