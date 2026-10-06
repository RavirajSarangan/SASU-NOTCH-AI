import AppKit
import ApplicationServices
import NovaKit

/// The Mac actions voice can take. Accessibility calls run on their own queue
/// with a short timeout, so a frozen app can't freeze Nova. Nothing here ever
/// touches Nova's own windows, password prompts or System Settings.
enum MacActions {
    private static let queue = DispatchQueue(label: "nova.mac-actions", qos: .userInitiated)

    // MARK: Apps

    /// Installed app names (without ".app"), for "Hey Safari" and app lookups.
    static func installedApps() -> [String] {
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        var names = Set<String>()
        for folder in folders {
            for item in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] where item.hasSuffix(".app") {
                names.insert(String(item.dropLast(4)))
            }
        }
        return names.sorted()
    }

    static func runningApp(named name: String) -> NSRunningApplication? {
        let wanted = name.lowercased().replacingOccurrences(of: " ", with: "")
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        func key(_ app: NSRunningApplication) -> String { (app.localizedName ?? "").lowercased().replacingOccurrences(of: " ", with: "") }
        return apps.first { key($0) == wanted } ?? apps.first { key($0).hasPrefix(wanted) }
    }

    /// Asks the app to quit, like ⌘Q: apps with unsaved work ask you first.
    static func quit(_ name: String) async -> String {
        guard !VoiceSafety.unquittable.contains(name.lowercased()) else { return "I'll leave \(name) running." }
        guard let app = runningApp(named: name) else { return "\(name.capitalized) isn't open." }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return "I'll stay right here." }
        app.terminate()
        // An app that is still starting up ignores the first request.
        try? await Task.sleep(for: .seconds(1))
        if !app.isTerminated { app.terminate() }
        return "Closing \(app.localizedName ?? name)."
    }

    // MARK: Web

    static let knownSites = [
        "youtube": "youtube.com", "github": "github.com", "gmail": "mail.google.com", "google": "google.com",
        "chatgpt": "chatgpt.com", "claude": "claude.ai", "instagram": "instagram.com", "facebook": "facebook.com",
        "twitter": "x.com", "x": "x.com", "linkedin": "linkedin.com", "netflix": "netflix.com", "whatsapp": "web.whatsapp.com",
        "google maps": "maps.google.com", "maps": "maps.google.com", "vercel": "vercel.com", "supabase": "supabase.com",
    ]

    static func openWebsite(_ site: String) -> String {
        let host = knownSites[site.lowercased()] ?? site.lowercased()
        guard let url = URL(string: host.hasPrefix("http") ? host : "https://" + host), url.host != nil else { return "That doesn't look like a website." }
        NSWorkspace.shared.open(url)
        return "Opening \(host)."
    }

    static func search(_ query: String, on engine: VoiceIntent.SearchEngine) -> String {
        var parts = URLComponents(string: engine == .youtube ? "https://www.youtube.com/results" : "https://www.google.com/search")!
        parts.queryItems = [URLQueryItem(name: engine == .youtube ? "search_query" : "q", value: query)]
        guard let url = parts.url else { return "I couldn't search for that." }
        NSWorkspace.shared.open(url)
        return engine == .youtube ? "Here's YouTube for \(query)." : "Searching for \(query)."
    }

    static func spotifySearch(_ query: String) -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        guard let url = URL(string: "spotify:search:" + encoded) else { return "I couldn't search Spotify." }
        NSWorkspace.shared.open(url)
        return "Here's \(query) in Spotify. Pick one to play."
    }

    // MARK: Files

    /// Spotlight search in your home folder (not Library or hidden folders),
    /// newest first, at most 5.
    static func findFiles(_ query: FileQuery) async -> [URL] {
        let spotlight = query.spotlight
        guard !spotlight.isEmpty else { return [] }
        let home = NSHomeDirectory()
        let output = await CommandRunner.run("/usr/bin/mdfind", ["-onlyin", home, spotlight], timeout: 8)
        let paths = output.split(separator: "\n").map(String.init).filter { FileQuery.isUserFile($0, home: home) }.prefix(200)
        let dated: [(URL, Date)] = paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]), values.isDirectory != true else { return nil }
            return (url, values.contentModificationDate ?? .distantPast)
        }
        return dated.sorted { $0.1 > $1.1 }.prefix(5).map(\.0)
    }

    // MARK: Keyboard

    static let browsers: Set<String> = ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox",
                                        "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi"]

    /// Sends a browser shortcut to the front browser (or the last one you used).
    static func browser(_ command: VoiceIntent.BrowserCommand) async -> String {
        guard AXIsProcessTrusted() else { return needsAccessibility }
        var front = NSWorkspace.shared.frontmostApplication
        if !browsers.contains(front?.bundleIdentifier ?? "") {
            guard let browser = NSWorkspace.shared.runningApplications.first(where: { browsers.contains($0.bundleIdentifier ?? "") }) else {
                return "No browser is open."
            }
            browser.activate()
            try? await Task.sleep(for: .milliseconds(350))
            front = browser
        }
        let (key, flags): (CGKeyCode, CGEventFlags) = switch command {
        case .newTab: (17, .maskCommand)
        case .closeTab: (13, .maskCommand)
        case .back: (33, .maskCommand)
        case .forward: (30, .maskCommand)
        case .reload: (15, .maskCommand)
        case .nextTab: (30, [.maskCommand, .maskShift])
        case .previousTab: (33, [.maskCommand, .maskShift])
        }
        press(key, flags: flags)
        let name = front?.localizedName ?? "the browser"
        return switch command {
        case .newTab: "New tab in \(name)."
        case .closeTab: "Closed the tab."
        case .back: "Back."
        case .forward: "Forward."
        case .reload: "Reloading."
        case .nextTab: "Next tab."
        case .previousTab: "Previous tab."
        }
    }

    /// Types into the focused field of the front app. Refuses password fields,
    /// blocked apps and Nova itself, and never presses Return.
    static func type(_ text: String) async -> String {
        guard AXIsProcessTrusted() else { return needsAccessibility }
        guard let app = NSWorkspace.shared.frontmostApplication else { return "There's nothing to type into." }
        if let refusal = refusal(for: app) { return refusal }
        let pid = app.processIdentifier
        let secure = await onQueue { () -> Bool? in
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 1)
            guard let focused: AXUIElement = attribute(element, kAXFocusedUIElementAttribute) else { return nil }
            let role: String? = attribute(focused, kAXRoleAttribute)
            let subrole: String? = attribute(focused, kAXSubroleAttribute)
            return role == "AXSecureTextField" || subrole == "AXSecureTextField"
        }
        switch secure {
        case nil: return "Click into a text field first, then ask me again."
        case true?: return "That's a password field. I never type into those."
        case false?: break
        }
        // Unicode text in small chunks (CGEvent caps each event's string length).
        let source = CGEventSource(stateID: .hidSystemState)
        let utf16 = Array(text.utf16)
        for start in stride(from: 0, to: utf16.count, by: 16) {
            var chunk = Array(utf16[start..<min(start + 16, utf16.count)])
            for keyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else { continue }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                event.postToPid(pid)
            }
            try? await Task.sleep(for: .milliseconds(12))
        }
        return "Typed it."
    }

    static func lockScreen() {
        press(12, flags: [.maskCommand, .maskControl])   // ⌃⌘Q
    }

    private static func press(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Buttons

    /// A button found by name. `element` is only used on the actions queue.
    struct Button: @unchecked Sendable {
        let element: AXUIElement
        let title: String
        let appName: String
        var risky: Bool { VoiceSafety.isRisky(button: title) }
    }

    enum FindResult: Sendable {
        case found(Button)
        case several([String])
        case none(String)
    }

    /// Looks for a button, link, menu item or checkbox with this name in the
    /// front window of the front app.
    static func findButton(_ label: String) async -> FindResult {
        guard AXIsProcessTrusted() else { return .none(needsAccessibility) }
        guard let app = NSWorkspace.shared.frontmostApplication else { return .none("No app is in front.") }
        if let refusal = refusal(for: app) { return .none(refusal) }
        let pid = app.processIdentifier
        let appName = app.localizedName ?? "this app"
        let wanted = normalize(label)
        return await onQueue {
            let root = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(root, 1)
            let window: AXUIElement? = attribute(root, kAXFocusedWindowAttribute)
            var queue: [AXUIElement] = [window ?? root]
            var exact: [(AXUIElement, String)] = []
            var partial: [(AXUIElement, String)] = []
            var visited = 0
            let roles: Set<String> = ["AXButton", "AXLink", "AXMenuItem", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXTab"]
            while !queue.isEmpty, visited < 4000 {
                let element = queue.removeFirst()
                visited += 1
                let role: String? = attribute(element, kAXRoleAttribute)
                if let role, roles.contains(role) {
                    let names = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { (key: String) -> String? in
                        let value: String? = attribute(element, key)
                        return value?.isEmpty == false ? value : nil
                    }
                    if let name = names.first(where: { normalize($0) == wanted }) {
                        exact.append((element, name))
                    } else if let name = names.first(where: { normalize($0).contains(wanted) }) {
                        partial.append((element, name))
                    }
                }
                if let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) { queue += children }
            }
            let matches = exact.isEmpty ? partial : exact
            let distinct = Array(Set(matches.map(\.1)))
            if matches.count == 1 || distinct.count == 1, let first = matches.first {
                return .found(Button(element: first.0, title: first.1, appName: appName))
            }
            if matches.count > 1 { return .several(distinct.sorted().prefix(4).map { $0 }) }
            return .none("I couldn't find “\(label)” in \(appName).")
        }
    }

    static func press(_ button: Button) async -> Bool {
        await onQueue { AXUIElementPerformAction(button.element, kAXPressAction as CFString) == .success }
    }

    // MARK: Helpers

    static let needsAccessibility = "I need Accessibility access for that. Turn on Nova in System Settings → Privacy & Security → Accessibility."

    private static func refusal(for app: NSRunningApplication) -> String? {
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return "Click a different app first, then ask me again." }
        if VoiceSafety.blockedBundleIDs.contains(app.bundleIdentifier ?? "") {
            return "For your safety I don't click or type in \(app.localizedName ?? "that app")."
        }
        return nil
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func attribute<T>(_ element: AXUIElement, _ key: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func onQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}
