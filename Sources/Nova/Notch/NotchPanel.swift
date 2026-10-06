import AppKit
import SwiftUI

/// Borderless, transparent, always-on-top panel that sits over the notch.
/// It never activates the app; it only becomes key while a full panel is
/// open so it can receive Esc.
final class NotchPanel: NSPanel {
    var allowsKey = false

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
        setAccessibilityLabel("Nova")
        setAccessibilityRole(.popover)
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that accepts the first click, so buttons work without the
/// panel first having to become key.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
