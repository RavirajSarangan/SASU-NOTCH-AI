import Foundation
import CoreGraphics
import NovaKit
import Observation

enum NovaTab: String, CaseIterable, Sendable {
    case home, chat, brief, add

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .chat: "bubble.left.fill"
        case .brief: "sun.max.fill"
        case .add: "plus"
        }
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .chat: "Chat"
        case .brief: "Brief"
        case .add: "Add"
        }
    }
}

enum IntegrationFocus: Equatable, Sendable {
    case automationReview
    case service(IntegrationKind)
    case security
}

/// Transient message shown in the `.notification` state.
struct NotchBanner: Equatable, Sendable {
    enum Action: Sendable, Equatable { case reviewAutomations, openBrief, openSecurity, enableWakeWord, openVoiceSettings, openURL(URL) }

    var title: String
    var subtitle: String
    var expression: NovaExpression
    /// What tapping the banner opens.
    var action: Action? = nil
}

/// Observable UI state shared by every notch view.
@Observable
@MainActor
final class AppState {
    var notchState: NotchState = .hidden
    var geometry: NotchGeometry = .fallback
    var isVisible = true
    /// False while the display sleeps or the screen is locked.
    var isOnScreen = true
    var selectedTab: NovaTab = .home
    var focusedAgentID: String = AgentKind.claude.rawValue
    /// One entry per agent, refreshed from AgentSessionManager.
    var agents: [AgentSummary] = AgentKind.allCases.map { AgentSummary.live($0, session: nil) }
    var banner: NotchBanner?
    /// What `.integrationView` shows.
    var integrationFocus: IntegrationFocus = .automationReview

    /// Short-lived expression (e.g. surprised on click) layered over the
    /// state's default expression.
    var expressionOverride: NovaExpression?
    /// Nova's face while you talk to it (listening, thinking, replying).
    var voiceExpression: NovaExpression?

    var expression: NovaExpression {
        if let expressionOverride { return expressionOverride }
        if notchState == .voice, let voiceExpression { return voiceExpression }
        if notchState == .notification, let banner { return banner.expression }
        // While an agent is live, Nova mirrors what it's doing (thinking,
        // coding, needs approval…), not just the notch state.
        if [.idle, .compact, .agentSession].contains(notchState), let urgent = mostUrgentAgent {
            return urgent.status.expression
        }
        return notchState.defaultExpression
    }

    /// Layout size of the current state (content is laid out at this size).
    var size: CGSize {
        var size = NotchLayout.size(for: notchState, geometry: geometry)
        if notchState == .permissionRequest { size.height += permissionExtraHeight }
        return size
    }

    /// Extra room for the current request's content (a diff, many options).
    var permissionExtraHeight: CGFloat = 0

    /// "Large" panel size scales full panels (never the slim notch states).
    var panelScale: CGFloat = 1

    var contentScale: CGFloat { notchState.isExpanded ? panelScale : 1 }

    /// On-screen size of the shape (used for drawing and hit-testing).
    var displaySize: CGSize {
        CGSize(width: size.width * contentScale, height: size.height * contentScale)
    }

    /// The live session that most needs the user (approval > error > working…).
    var mostUrgentAgent: AgentSummary? {
        agents.filter { $0.isConnected && $0.status.isLive }
            .max { AgentSessionState.priority($0.status) < AgentSessionState.priority($1.status) }
    }

    /// Live sessions right now (for the "2 active" pill).
    var liveSessionCount: Int { agents.filter { $0.isConnected && $0.status.isLive }.count }

    var focusedAgent: AgentSummary {
        if let match = agents.first(where: { $0.id == focusedAgentID }) { return match }
        // The focused session ended: stay on the same agent if it has another.
        let kind = AgentKind(rawValue: focusedAgentID) ?? agents.first { $0.sessionId == focusedAgentID }?.kind
        return mostUrgentAgent ?? agents.first { $0.kind == kind } ?? agents.first
            ?? AgentSummary(kind: .claude, status: .idle, detail: "Not connected", preview: .idle)
    }
}
