import Foundation

public enum VercelDecoder {
    public struct Deployment: Sendable, Equatable {
        public var id: String
        public var project: String
        public var state: String      // READY, ERROR, BUILDING, QUEUED, INITIALIZING, CANCELED
        public var target: String?    // production / preview
        public var url: String?
        public var created: Date?

        public init(id: String, project: String, state: String, target: String?, url: String?, created: Date?) {
            self.id = id
            self.project = project
            self.state = state
            self.target = target
            self.url = url
            self.created = created
        }

        public var health: ServiceHealth {
            switch state {
            case "READY": .healthy
            case "ERROR": .failing
            case "CANCELED": .unknown
            default: .attention
            }
        }

        public var stateLabel: String {
            switch state {
            case "READY": "Ready"
            case "ERROR": "Failed"
            case "CANCELED": "Canceled"
            case "BUILDING", "INITIALIZING", "QUEUED": "Building"
            default: state.capitalized
            }
        }
    }

    public static func deployments(_ data: Data) throws -> [Deployment] {
        (try JSON.object(data)["deployments"] as? [[String: Any]] ?? []).map { d in
            Deployment(id: d["uid"] as? String ?? UUID().uuidString, project: d["name"] as? String ?? "project",
                       state: (d["state"] ?? d["readyState"]) as? String ?? "",
                       target: d["target"] as? String, url: (d["url"] as? String).map { "https://\($0)" },
                       created: JSON.date(d["created"] ?? d["createdAt"]))
        }
    }

    public static func snapshot(_ deployments: [Deployment], now: Date = Date()) -> ServiceSnapshot {
        guard let latest = deployments.max(by: { ($0.created ?? .distantPast) < ($1.created ?? .distantPast) }) else {
            return ServiceSnapshot(kind: .vercel, headline: "No deployments", detail: "", health: .unknown, webURL: "https://vercel.com/dashboard")
        }
        // Latest deployment per project decides that project's health.
        var perProject: [String: Deployment] = [:]
        for d in deployments where (perProject[d.project]?.created ?? .distantPast) < (d.created ?? .distantPast) {
            perProject[d.project] = d
        }
        let health = perProject.values.map(\.health).max() ?? .unknown
        let age = latest.created.map { RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: now) } ?? ""
        return ServiceSnapshot(
            kind: .vercel,
            headline: latest.stateLabel,
            detail: "\(latest.project)\(latest.target == "production" ? " · prod" : "") · \(age)",
            health: health,
            sections: [.init(title: "Recent deployments", items: deployments.prefix(10).map {
                ServiceItem(id: $0.id, title: $0.project, subtitle: "\($0.stateLabel) · \($0.target ?? "preview")",
                            health: $0.health, url: $0.url, date: $0.created)
            })],
            webURL: "https://vercel.com/dashboard"
        )
    }
}
