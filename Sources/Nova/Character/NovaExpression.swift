import Foundation

/// Nova's moods. They're shown through the eyes (shape + glow), never
/// through big body movement.
enum NovaExpression: String, CaseIterable, Sendable {
    case idle, happy, thinking, coding, typing, listening, surprised, warning, error
    case sleepy, sleeping, excited, confused, annoyed, success, loading, dizzy, notification

    /// What VoiceOver says about Nova's mood.
    var spokenDescription: String {
        switch self {
        case .idle: "relaxed"
        case .coding, .typing: "working"
        case .sleeping, .sleepy: "resting"
        case .warning: "needs your attention"
        case .error, .dizzy: "reporting a problem"
        case .notification: "has an update"
        default: rawValue
        }
    }
}
