import Foundation

/// Events Nova can post as macOS notifications (spec §22).
public enum NovaNotificationKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case permissionRequest, agentCompleted, agentFailed, deploymentFailed, workflowFailed, integrationAlert, whatsappDraft, morningBrief
    case securityCritical, securityWarning, cameraMic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .permissionRequest: "Permission requests"
        case .agentCompleted: "Agent finished"
        case .agentFailed: "Agent failed"
        case .deploymentFailed: "Deployment failed"
        case .workflowFailed: "Workflow failed"
        case .integrationAlert: "Other service alerts"
        case .whatsappDraft: "WhatsApp reply drafts"
        case .morningBrief: "Morning brief ready"
        case .securityCritical: "Security: someone accessing this Mac"
        case .securityWarning: "Security: risks and suspicious changes"
        case .cameraMic: "Camera and microphone turning on"
        }
    }

    /// Notifications that matter even while you're looking at the notch.
    public var isUrgent: Bool { self == .permissionRequest || self == .securityCritical }
}

public enum NotificationPolicy {
    /// Whether to post a macOS notification for `kind`.
    /// - enabled: kinds the user turned on.
    /// - notchVisible: the notch already showed it on a screen the user can see.
    /// - onlyWhenAway: user prefers macOS notifications only when they're not looking at Nova.
    public static func shouldPost(_ kind: NovaNotificationKind, enabled: Set<NovaNotificationKind>,
                                  notchVisible: Bool, onlyWhenAway: Bool, userIdle: Bool) -> Bool {
        guard enabled.contains(kind) else { return false }
        if kind.isUrgent { return true }
        guard onlyWhenAway else { return true }
        return !notchVisible || userIdle
    }

    /// Integration alerts map to a more specific kind where possible.
    public static func kind(for integration: IntegrationKind) -> NovaNotificationKind {
        switch integration {
        case .vercel, .firebase: .deploymentFailed
        case .n8n: .workflowFailed
        default: .integrationAlert
        }
    }

    public static let defaults: Set<NovaNotificationKind> = [
        .permissionRequest, .agentCompleted, .agentFailed, .deploymentFailed, .workflowFailed, .integrationAlert, .whatsappDraft, .morningBrief,
        .securityCritical, .securityWarning, .cameraMic,
    ]
}
