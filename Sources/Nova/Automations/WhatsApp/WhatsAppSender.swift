import AppKit
import ApplicationServices
import Foundation
import NovaKit

/// Sends a WhatsApp message through the installed WhatsApp app: open the chat
/// with the text pre-filled (whatsapp:// URL), then press Return.
/// Pressing Return needs Accessibility permission. In test mode the message
/// is filled in but never sent.
@MainActor
enum WhatsAppSender {
    static let bundleID = "net.whatsapp.WhatsApp"

    enum SendError: LocalizedError {
        case notInstalled, needsAccessibility, didNotOpen, didNotFill, lostFocus

        var errorDescription: String? {
            switch self {
            case .notInstalled: "WhatsApp for Mac isn't installed."
            case .needsAccessibility: "Allow Nova in System Settings → Privacy & Security → Accessibility so it can press Send."
            case .didNotOpen: "WhatsApp didn't open the chat in time."
            case .didNotFill: "WhatsApp didn't show the message in the chat box, so Nova didn't press Send."
            case .lostFocus: "Another app came to the front, so Nova didn't press Send."
            }
        }
    }

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        // Value of kAXTrustedCheckOptionPrompt (the global isn't concurrency-safe in Swift 6).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Returns true if Return was pressed (false in test mode).
    ///
    /// Return is only pressed when WhatsApp is frontmost and, if its chat box
    /// can be read, only once the box holds exactly this message.
    static func send(_ text: String, toPhone phone: String, testMode: Bool) async throws -> Bool {
        guard isInstalled else { throw SendError.notInstalled }
        guard testMode || hasAccessibility else { throw SendError.needsAccessibility }

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        guard let url = URL(string: "whatsapp://send?phone=\(phone)&text=\(encoded)") else { throw SendError.didNotOpen }

        let previous = NSWorkspace.shared.frontmostApplication
        NSWorkspace.shared.open(url)

        // Wait for WhatsApp to come forward.
        var app: NSRunningApplication?
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(150))
            if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == bundleID {
                app = front
                break
            }
        }
        guard let app else { throw SendError.didNotOpen }
        defer {
            if let previous, previous.bundleIdentifier != bundleID, previous.bundleIdentifier != Bundle.main.bundleIdentifier {
                previous.activate()
            }
        }

        try await waitUntilFilled(text, pid: app.processIdentifier, needed: !testMode)
        if testMode { return false }

        try pressSend(pid: app.processIdentifier)
        try await Task.sleep(for: .milliseconds(600))
        return true
    }

    /// Presses Send again, but only if the chat box provably still holds this
    /// message (so a message is never sent twice). Returns true if pressed.
    static func resendIfStillFilled(_ text: String) async -> Bool {
        guard hasAccessibility,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return false }
        app.activate()
        try? await Task.sleep(for: .milliseconds(500))
        guard let box = composeText(pid: app.processIdentifier), matches(box, text) else { return false }
        do { try pressSend(pid: app.processIdentifier) } catch { return false }
        try? await Task.sleep(for: .milliseconds(600))
        return true
    }

    /// Waits for the chat to load with the text in the box. If the box can be
    /// read and never shows the text, throws instead of sending. If it can't
    /// be read (no Accessibility, or WhatsApp doesn't expose it), falls back
    /// to a generous fixed delay; the send is confirmed later from WhatsApp's
    /// database either way.
    private static func waitUntilFilled(_ text: String, pid: pid_t, needed: Bool) async throws {
        try await Task.sleep(for: .milliseconds(700))
        guard hasAccessibility else {
            try await Task.sleep(for: .milliseconds(1800))
            return
        }
        var sawReadableBox = false
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if let box = composeText(pid: pid) {
                sawReadableBox = true
                if matches(box, text) { return }
            }
            try await Task.sleep(for: .milliseconds(300))
        }
        if sawReadableBox && needed { throw SendError.didNotFill }
    }

    private static func pressSend(pid: pid_t) throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw SendError.lostFocus }
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
        down?.postToPid(pid)
        up?.postToPid(pid)
    }

    /// The text of WhatsApp's focused text field, via Accessibility.
    static func composeText(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func matches(_ box: String, _ text: String) -> Bool {
        ComposeMatch.matches(box: box, text: text)
    }
}
