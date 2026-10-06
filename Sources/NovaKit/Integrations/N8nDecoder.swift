import Foundation

public enum N8nDecoder {
    public struct Workflow: Sendable, Equatable {
        public var id: String
        public var name: String
        public var active: Bool
        public init(id: String, name: String, active: Bool) { self.id = id; self.name = name; self.active = active }
    }
    public struct Execution: Sendable, Equatable {
        public var id: String
        public var workflowId: String
        public var status: String   // success, error, running, waiting, canceled, crashed
        public var startedAt: Date?

        public init(id: String, workflowId: String, status: String, startedAt: Date?) {
            self.id = id
            self.workflowId = workflowId
            self.status = status
            self.startedAt = startedAt
        }

        public var health: ServiceHealth {
            switch status {
            case "success": .healthy
            case "error", "crashed": .failing
            case "running", "waiting", "new": .attention
            default: .unknown
            }
        }
    }

    public static func workflows(_ data: Data) throws -> [Workflow] {
        (try JSON.object(data)["data"] as? [[String: Any]] ?? []).map {
            Workflow(id: "\($0["id"] ?? "")", name: $0["name"] as? String ?? "Workflow", active: $0["active"] as? Bool ?? false)
        }
    }

    public static func executions(_ data: Data) throws -> [Execution] {
        (try JSON.object(data)["data"] as? [[String: Any]] ?? []).map { e in
            let status = e["status"] as? String ?? ((e["finished"] as? Bool ?? false) ? "success" : "error")
            return Execution(id: "\(e["id"] ?? "")", workflowId: "\(e["workflowId"] ?? "")", status: status,
                             startedAt: JSON.date(e["startedAt"]))
        }
    }

    /// Share of finished executions that succeeded (nil if none finished).
    public static func successRate(_ executions: [Execution]) -> Double? {
        let finished = executions.filter { ["success", "error", "crashed"].contains($0.status) }
        guard !finished.isEmpty else { return nil }
        return Double(finished.filter { $0.status == "success" }.count) / Double(finished.count)
    }

    public static func snapshot(workflows: [Workflow], executions: [Execution], baseURL: String) -> ServiceSnapshot {
        let active = workflows.filter(\.active)
        let failed = executions.filter { $0.health == .failing }
        let names = Dictionary(workflows.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let rate = successRate(executions)
        let recentFailure = failed.contains { ($0.startedAt ?? .distantPast) > Date().addingTimeInterval(-86_400) }
        return ServiceSnapshot(
            kind: .n8n,
            headline: "\(active.count) active",
            detail: [rate.map { "\(Int(($0 * 100).rounded()))% success" }, failed.isEmpty ? nil : "\(failed.count) failed"]
                .compactMap { $0 }.joined(separator: " · "),
            health: recentFailure ? .failing : (failed.isEmpty ? .healthy : .attention),
            sections: [
                .init(title: "Failed executions", items: failed.prefix(8).map {
                    ServiceItem(id: $0.id, title: names[$0.workflowId] ?? "Workflow \($0.workflowId)", subtitle: $0.status,
                                health: .failing, url: "\(baseURL)/workflow/\($0.workflowId)/executions/\($0.id)", date: $0.startedAt)
                }),
                .init(title: "Active workflows", items: active.prefix(12).map {
                    ServiceItem(id: $0.id, title: $0.name, subtitle: "active", health: .healthy, url: "\(baseURL)/workflow/\($0.id)")
                }),
            ].filter { !$0.items.isEmpty },
            webURL: baseURL
        )
    }
}
