import SwiftUI

/// Full-body poses cut from the pose sheet by scripts/prepare_poses.py.
/// Aspect ratios and eye positions live in PoseGeometry.generated.swift.
enum NovaPose: String, CaseIterable, Sendable {
    case idle, happy, thinking, typing, sleep, alert, dizzy, success, listening, loading

    var resourceName: String { "pose_\(rawValue)" }
}

extension NovaExpression {
    var pose: NovaPose {
        switch self {
        case .idle: .idle
        case .happy, .excited: .happy
        case .thinking, .confused: .thinking
        case .coding, .typing: .typing
        case .sleeping, .sleepy: .sleep
        case .warning, .notification, .surprised: .alert
        case .dizzy, .error, .annoyed: .dizzy
        case .success: .success
        case .listening: .listening
        case .loading: .loading
        }
    }
}
