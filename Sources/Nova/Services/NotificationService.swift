import AppKit
import Foundation
import NovaKit
import UserNotifications

/// macOS notifications (Notification Center). Permission requests carry
/// Allow Once / Deny actions; clicking any notification opens the notch.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let permissionCategory = "nova.permission"
    /// High-risk requests: Deny only. Allowing needs the two-step in the notch.
    static let highRiskPermissionCategory = "nova.permission.highRisk"
    static let allowAction = "nova.allowOnce"
    static let denyAction = "nova.deny"

    /// (requestId, allow?) when the user answers from a notification.
    var onPermissionAction: ((String, Bool) -> Void)?
    /// Called when a notification is clicked (with its kind).
    var onOpen: ((NovaNotificationKind?) -> Void)?

    private(set) var authorized = false

    /// UNUserNotificationCenter needs a real app bundle (not `swift run`).
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil || Bundle.main.bundleURL.pathExtension != "app" ? nil : .current()
    }

    func start() {
        guard let center else { return }
        center.delegate = self
        let allow = UNNotificationAction(identifier: Self.allowAction, title: "Allow Once", options: [])
        let deny = UNNotificationAction(identifier: Self.denyAction, title: "Deny", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.permissionCategory, actions: [deny, allow], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.highRiskPermissionCategory, actions: [deny], intentIdentifiers: []),
        ])
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        guard let center else { return }
        let settings = await center.notificationSettings()
        authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        guard let center else { return false }
        authorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        return authorized
    }

    func post(_ kind: NovaNotificationKind, title: String, body: String, id: String = UUID().uuidString,
              requestId: String? = nil, highRisk: Bool = false) {
        guard let center, authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = kind.isUrgent ? .default : nil
        content.threadIdentifier = kind.rawValue
        var info: [String: String] = ["kind": kind.rawValue]
        if let requestId {
            content.categoryIdentifier = highRisk ? Self.highRiskPermissionCategory : Self.permissionCategory
            info["requestId"] = requestId
        }
        content.userInfo = info
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func remove(id: String) {
        center?.removeDeliveredNotifications(withIdentifiers: [id])
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let kind = (info["kind"] as? String).flatMap(NovaNotificationKind.init(rawValue:))
        let requestId = info["requestId"] as? String
        let action = response.actionIdentifier
        await MainActor.run {
            if let requestId, action == Self.allowAction || action == Self.denyAction {
                onPermissionAction?(requestId, action == Self.allowAction)
            } else {
                onOpen?(kind)
            }
        }
    }
}
