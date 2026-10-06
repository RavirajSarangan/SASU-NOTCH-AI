import AppKit
import CoreGraphics
import Foundation
import Network
import Observation

/// Is the Mac online, awake and unlocked? Automations wait until it is.
@Observable
@MainActor
final class ConnectivityMonitor {
    private(set) var isOnline = true
    private(set) var isAwake = true
    private(set) var isScreenLocked = false

    /// Called whenever the Mac becomes ready (online + awake + unlocked).
    @ObservationIgnored var onReady: (() -> Void)?

    @ObservationIgnored private var path: NWPathMonitor?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    var isReady: Bool { isOnline && isAwake && !isScreenLocked }

    func start() {
        guard path == nil else { return }
        isScreenLocked = Self.screenIsLockedNow()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] update in
            let online = update.status == .satisfied
            Task { @MainActor in self?.set(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "app.nova.connectivity"))
        path = monitor

        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        func observe(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping @MainActor (ConnectivityMonitor) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in if let self { body(self) } }
            }
            observers.append((center, token))
        }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.update { $0.isAwake = false } }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.update { $0.isAwake = true } }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.update { $0.isScreenLocked = Self.screenIsLockedNow() } }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.update { $0.isScreenLocked = Self.screenIsLockedNow() } }
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.update { $0.isScreenLocked = true } }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.update { $0.isScreenLocked = false } }
    }

    func stop() {
        path?.cancel()
        path = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
    }

    private func set(online: Bool) {
        update { $0.isOnline = online }
    }

    private func update(_ change: (ConnectivityMonitor) -> Void) {
        let wasReady = isReady
        change(self)
        if isReady && !wasReady { onReady?() }
    }

    /// Reads the login session's lock flag.
    static func screenIsLockedNow() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Bool) == true
    }
}
