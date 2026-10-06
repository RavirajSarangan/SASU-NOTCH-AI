import AppKit
import SwiftUI

/// Regular window for Settings (text entry is more comfortable than in the notch).
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(coordinator: AppCoordinator, section: SettingsSection = .ai) {
        coordinator.settingsSection = section
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(coordinator: coordinator))
            let window = NSWindow(contentViewController: host)
            window.title = "Nova Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.setContentSize(NSSize(width: 720, height: 520))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
