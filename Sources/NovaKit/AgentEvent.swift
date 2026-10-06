import Foundation

/// Wire format for messages sent to Nova's local socket: one JSON object per
/// line. Example:
///
///     {"agent":"claude","sessionId":"abc123","event":"tool_start","tool":"bash","description":"Running npm test"}
public struct AgentEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case sessionStart = "session_start"
        case prompt
        case toolStart = "tool_start"
        case toolEnd = "tool_end"
        case toolFailed = "tool_failed"
        case permissionRequest = "permission_request"
        case notification
        case stop
        case sessionEnd = "session_end"
        case error
        case unknown

        /// Unrecognised event names decode to `.unknown` instead of failing.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    public var agent: AgentKind
    public var sessionId: String
    public var event: Kind
    public var tool: String?
    public var description: String?
    public var command: String?
    public var workingDirectory: String?
    public var filePath: String?
    public var message: String?
    public var requestId: String?
    /// Where the agent runs (see AgentSession.host).
    public var host: String?
    /// The app the agent runs in (bundle path, e.g. /Applications/iTerm.app)
    /// and its pid, so Nova can bring the right window forward.
    public var terminalApp: String?
    public var terminalPid: Int32?
    /// Questions the agent wants answered (AskUserQuestion).
    public var questions: [AgentQuestion]?
    /// What an Edit/Write would change (masked, capped).
    public var edit: EditPreview?

    public init(agent: AgentKind, sessionId: String, event: Kind, tool: String? = nil, description: String? = nil,
                command: String? = nil, workingDirectory: String? = nil, filePath: String? = nil,
                message: String? = nil, requestId: String? = nil, host: String? = nil) {
        self.host = host
        self.agent = agent
        self.sessionId = sessionId
        self.event = event
        self.tool = tool
        self.description = description
        self.command = command
        self.workingDirectory = workingDirectory
        self.filePath = filePath
        self.message = message
        self.requestId = requestId
    }
}

/// Nova's answer to a `permission_request`, written back on the same socket.
public struct PermissionReply: Codable, Sendable, Equatable {
    public enum Decision: String, Codable, Sendable {
        case allow, deny
        /// Defer to the agent's own prompt (timeout, Nova hidden, etc.).
        case ask
    }

    public var requestId: String
    public var decision: Decision
    public var reason: String?
    /// For questions: question → chosen labels. Sent with `.allow`.
    public var answers: [String: [String]]?

    public init(requestId: String, decision: Decision, reason: String? = nil, answers: [String: [String]]? = nil) {
        self.requestId = requestId
        self.decision = decision
        self.reason = reason
        self.answers = answers
    }
}

public enum AgentEventDecoder {
    public static let maxMessageSize = 64 * 1024

    public enum DecodeError: Error, Equatable {
        case tooLarge
        case invalid
    }

    public static func decode(_ data: Data) throws -> AgentEvent {
        guard data.count <= maxMessageSize else { throw DecodeError.tooLarge }
        do {
            return try JSONDecoder().decode(AgentEvent.self, from: data)
        } catch {
            throw DecodeError.invalid
        }
    }

    public static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }
}

/// Where Nova listens. Override with NOVA_SOCKET for testing.
public enum NovaPaths {
    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Nova", isDirectory: true)
    }

    public static var socketPath: String {
        if let override = ProcessInfo.processInfo.environment["NOVA_SOCKET"], !override.isEmpty { return override }
        return supportDirectory.appendingPathComponent("nova.sock").path
    }
}
