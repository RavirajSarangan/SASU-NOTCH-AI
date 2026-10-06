import OSLog

/// Structured logs, visible in Console.app (subsystem "app.nova.companion").
/// Never log secrets or message contents.
enum Log {
    private static let subsystem = "app.nova.companion"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let socket = Logger(subsystem: subsystem, category: "socket")
    static let agents = Logger(subsystem: subsystem, category: "agents")
    static let ai = Logger(subsystem: subsystem, category: "ai")
    static let integrations = Logger(subsystem: subsystem, category: "integrations")
    static let automations = Logger(subsystem: subsystem, category: "automations")
}
