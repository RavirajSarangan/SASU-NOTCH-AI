import Foundation

public enum GitHubDecoder {
    public struct WorkflowRun: Sendable, Equatable {
        public var repo: String
        public var name: String
        public var status: String       // queued, in_progress, completed
        public var conclusion: String?  // success, failure, cancelled…
        public var url: String?
        public var updated: Date?

        public init(repo: String, name: String, status: String, conclusion: String?, url: String?, updated: Date?) {
            self.repo = repo
            self.name = name
            self.status = status
            self.conclusion = conclusion
            self.url = url
            self.updated = updated
        }

        public var health: ServiceHealth {
            if status != "completed" { return .attention }
            switch conclusion {
            case "success", "skipped", "neutral": return .healthy
            case "failure", "timed_out", "startup_failure": return .failing
            default: return .attention
            }
        }
    }

    /// `GET /notifications` → unread notification items.
    public static func notifications(_ data: Data) throws -> [ServiceItem] {
        try JSON.array(data).map { item in
            let subject = item["subject"] as? [String: Any] ?? [:]
            let repo = (item["repository"] as? [String: Any])?["full_name"] as? String ?? ""
            return ServiceItem(id: item["id"] as? String ?? UUID().uuidString, title: subject["title"] as? String ?? "Notification",
                               subtitle: "\(repo) · \((item["reason"] as? String ?? "").replacingOccurrences(of: "_", with: " "))",
                               health: .attention, url: "https://github.com/notifications", date: JSON.date(item["updated_at"]))
        }
    }

    /// `GET /search/issues` → (total, items).
    public static func search(_ data: Data) throws -> (total: Int, items: [ServiceItem]) {
        let object = try JSON.object(data)
        let items = (object["items"] as? [[String: Any]] ?? []).map { item in
            let repo = (item["repository_url"] as? String)?.components(separatedBy: "/repos/").last ?? ""
            return ServiceItem(id: "\(item["id"] ?? UUID().uuidString)", title: item["title"] as? String ?? "",
                               subtitle: "\(repo) #\(item["number"] ?? "")", health: .attention,
                               url: item["html_url"] as? String, date: JSON.date(item["updated_at"]))
        }
        return (object["total_count"] as? Int ?? items.count, items)
    }

    /// `GET /user/repos` → full names.
    public static func repoNames(_ data: Data) throws -> [String] {
        try JSON.array(data).compactMap { $0["full_name"] as? String }
    }

    /// `GET /repos/{o}/{r}/actions/runs?per_page=1` → latest run.
    public static func latestRun(_ data: Data, repo: String) throws -> WorkflowRun? {
        guard let run = (try JSON.object(data)["workflow_runs"] as? [[String: Any]])?.first else { return nil }
        return WorkflowRun(repo: repo, name: run["name"] as? String ?? "Workflow", status: run["status"] as? String ?? "",
                           conclusion: run["conclusion"] as? String, url: run["html_url"] as? String, updated: JSON.date(run["updated_at"]))
    }

    public static func snapshot(notifications: [ServiceItem], reviews: (total: Int, items: [ServiceItem]),
                                assigned: (total: Int, items: [ServiceItem]), runs: [WorkflowRun]) -> ServiceSnapshot {
        let failed = runs.filter { $0.health == .failing }
        var parts: [String] = []
        if reviews.total > 0 { parts.append("\(reviews.total) PR review\(reviews.total == 1 ? "" : "s")") }
        if !failed.isEmpty { parts.append("\(failed.count) failed workflow\(failed.count == 1 ? "" : "s")") }
        if parts.isEmpty { parts.append(assigned.total > 0 ? "\(assigned.total) assigned" : "All clear") }
        let health: ServiceHealth = !failed.isEmpty ? .failing : (reviews.total + notifications.count > 0 ? .attention : .healthy)
        let runItems = runs.map {
            ServiceItem(id: "\($0.repo)-run", title: "\($0.repo): \($0.name)", subtitle: $0.conclusion ?? $0.status.replacingOccurrences(of: "_", with: " "),
                        health: $0.health, url: $0.url, date: $0.updated)
        }
        return ServiceSnapshot(
            kind: .github,
            headline: notifications.isEmpty ? "No notifications" : "\(notifications.count) notification\(notifications.count == 1 ? "" : "s")",
            detail: parts.joined(separator: " · "),
            health: health,
            sections: [
                .init(title: "Review requests", items: reviews.items),
                .init(title: "Workflows", items: runItems),
                .init(title: "Assigned to you", items: assigned.items),
                .init(title: "Notifications", items: Array(notifications.prefix(10))),
            ].filter { !$0.items.isEmpty },
            webURL: "https://github.com/notifications"
        )
    }
}
