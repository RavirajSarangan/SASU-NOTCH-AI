import AppKit
import SwiftUI

/// Owns the notch panel: positioning on the right screen, click-through
/// management and focus.
@MainActor
final class NotchWindowController {
    let panel: NotchPanel
    private(set) var geometry: NotchGeometry = .fallback

    init<Content: View>(rootView: Content) {
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: NotchLayout.canvasSize))
        let host = NotchHostingView(rootView: rootView)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: NotchLayout.canvasSize)
        panel.contentView = host
        reposition()
    }

    /// Which screen to use; set by the coordinator from preferences.
    var screenChoice: ScreenChoice = .automatic

    /// Re-measure the notch and pin the panel to the top-center of the screen.
    func reposition() {
        guard let screen = NotchLayout.preferredScreen(screenChoice) else { return }
        geometry = NotchLayout.geometry(for: screen)
        let size = NotchLayout.canvasSize
        let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Screen-space rect of the visible shape for a given shape size.
    func visibleRect(for size: CGSize) -> CGRect {
        let frame = panel.frame
        return CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Only intercept the mouse while it is over the visible shape, so the
    /// transparent rest of the panel never blocks the menu bar or apps.
    func setInteractive(_ interactive: Bool) {
        if panel.ignoresMouseEvents == interactive {
            panel.ignoresMouseEvents = !interactive
        }
    }

    func setKeyable(_ keyable: Bool) {
        panel.allowsKey = keyable
        if keyable {
            panel.makeKey()
        } else if panel.isKeyWindow {
            panel.resignKey()
        }
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
}
