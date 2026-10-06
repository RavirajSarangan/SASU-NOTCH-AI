/// Every visual state the notch can be in. Transitions are restricted by
/// `canTransition(to:)` so features can't push the UI into nonsense states.
enum NotchState: String, CaseIterable, Sendable {
    case hidden
    case idle
    case hover
    case compact
    case expandedHome
    case agentSession
    case permissionRequest
    case aiChat
    case integrationView
    case settings
    case notification
    case sleep
    /// Talking to Nova ("Hey Nova" / ⌥ Space).
    case voice

    /// States that show a full panel (and may take keyboard focus).
    var isExpanded: Bool {
        switch self {
        case .expandedHome, .agentSession, .permissionRequest, .aiChat, .integrationView, .settings: true
        default: false
        }
    }

    var defaultExpression: NovaExpression {
        switch self {
        case .hidden, .idle, .expandedHome, .settings, .integrationView: .idle
        case .hover: .happy
        case .compact: .listening
        case .agentSession: .coding
        case .permissionRequest: .warning
        case .aiChat: .listening
        case .notification: .notification
        case .sleep: .sleeping
        case .voice: .listening
        }
    }

    func canTransition(to next: NotchState) -> Bool {
        if next == self { return false }
        if next == .hidden { return true }
        // Permission requests must be able to interrupt anything visible.
        if next == .permissionRequest { return self != .hidden }
        return Self.allowed[self, default: []].contains(next)
    }

    private static let allowed: [NotchState: Set<NotchState>] = [
        .hidden: [.idle],
        .idle: [.hover, .compact, .expandedHome, .notification, .permissionRequest, .sleep, .integrationView, .voice],
        .hover: [.idle, .compact, .expandedHome, .notification, .permissionRequest, .integrationView],
        .compact: [.idle, .hover, .expandedHome, .agentSession, .notification, .permissionRequest, .integrationView],
        .expandedHome: [.idle, .compact, .agentSession, .permissionRequest, .aiChat, .integrationView, .settings],
        // (integrationView also shows service details opened from Home.)
        .agentSession: [.idle, .compact, .expandedHome, .permissionRequest],
        .permissionRequest: [.idle, .agentSession, .expandedHome, .compact],
        .aiChat: [.idle, .expandedHome, .integrationView],
        .integrationView: [.idle, .expandedHome, .compact, .aiChat],
        .settings: [.idle, .expandedHome],
        .notification: [.idle, .agentSession, .expandedHome, .compact, .permissionRequest, .integrationView],
        .sleep: [.idle, .hover, .notification, .permissionRequest, .integrationView],
        .voice: [.idle, .expandedHome, .compact, .aiChat, .notification, .permissionRequest],
    ]
}
