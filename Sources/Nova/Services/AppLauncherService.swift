import AppKit
import NovaKit
import Observation

struct LauncherApp: Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let url: URL
    let icon: NSImage
}

/// Pinned apps for the notch dock: real icons, running state, launch/activate.
@Observable
@MainActor
final class AppLauncherService {
    private(set) var apps: [LauncherApp] = []
    private(set) var running: Set<String> = []

    private static let pinsKey = "launcher.pins"
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    var pinnedIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.pinsKey) ?? AppPins.defaults(isInstalled: Self.isInstalled) }
        set { UserDefaults.standard.set(newValue, forKey: Self.pinsKey); reload() }
    }

    func start() {
        reload()
        refreshRunning()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshRunning() }
            })
        }
    }

    func reload() {
        apps = pinnedIDs.compactMap(Self.app(for:))
    }

    #if DEBUG
    /// Landing videos: Apple apps every Mac has, not your own pins.
    func loadDemo() {
        apps = ["com.apple.Safari", "com.apple.Terminal", "com.apple.Notes", "com.apple.Music", "com.apple.mail", "com.apple.iCal"]
            .compactMap(Self.app(for:))
    }
    #endif

    private func refreshRunning() {
        running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func open(_ app: LauncherApp) {
        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first {
            runningApp.activate()
        } else {
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func hide(_ app: LauncherApp) {
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).forEach { $0.hide() }
    }

    func quit(_ app: LauncherApp) {
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).forEach { $0.terminate() }
    }

    func pin(_ bundleID: String) {
        guard !pinnedIDs.contains(bundleID) else { return }
        pinnedIDs = pinnedIDs + [bundleID]
    }

    func unpin(_ bundleID: String) {
        pinnedIDs = pinnedIDs.filter { $0 != bundleID }
    }

    func move(_ bundleID: String, by offset: Int) {
        var ids = pinnedIDs
        guard let i = ids.firstIndex(of: bundleID) else { return }
        let j = min(max(i + offset, 0), ids.count - 1)
        ids.swapAt(i, j)
        pinnedIDs = ids
    }

    /// Every app in the standard folders, for the pin picker.
    func installedApps() -> [LauncherApp] {
        let fm = FileManager.default
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                       fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        var seen = Set<String>()
        var result: [LauncherApp] = []
        for folder in folders {
            for name in (try? fm.contentsOfDirectory(atPath: folder)) ?? [] where name.hasSuffix(".app") {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
                guard let id = Bundle(url: url)?.bundleIdentifier, !seen.contains(id) else { continue }
                seen.insert(id)
                result.append(LauncherApp(bundleID: id, name: (name as NSString).deletingPathExtension, url: url,
                                          icon: NSWorkspace.shared.icon(forFile: url.path)))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static func app(for bundleID: String) -> LauncherApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return LauncherApp(bundleID: bundleID, name: name, url: url, icon: NSWorkspace.shared.icon(forFile: url.path))
    }
}
