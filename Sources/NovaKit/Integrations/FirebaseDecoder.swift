import Foundation

public enum FirebaseDecoder {
    public struct Project: Sendable, Equatable, Identifiable {
        public var id: String { projectId }
        public var projectId: String
        public var displayName: String

        public init(projectId: String, displayName: String) {
            self.projectId = projectId
            self.displayName = displayName
        }
    }

    public static func projects(_ data: Data) throws -> [Project] {
        (try JSON.object(data)["results"] as? [[String: Any]] ?? []).map {
            let id = $0["projectId"] as? String ?? ""
            return Project(projectId: id, displayName: $0["displayName"] as? String ?? id)
        }
    }

    /// Cloud Functions v2 `functions.list` → (name, state).
    public static func functions(_ data: Data) throws -> [(name: String, state: String)] {
        (try JSON.object(data)["functions"] as? [[String: Any]] ?? []).map {
            ((($0["name"] as? String) ?? "").components(separatedBy: "/").last ?? "", $0["state"] as? String ?? "UNKNOWN")
        }
    }

    /// Firestore `databases.list` → database ids.
    public static func databases(_ data: Data) throws -> [String] {
        (try JSON.object(data)["databases"] as? [[String: Any]] ?? []).compactMap {
            ($0["name"] as? String)?.components(separatedBy: "/").last
        }
    }

    /// Hosting `sites` → site ids.
    public static func sites(_ data: Data) throws -> [String] {
        (try JSON.object(data)["sites"] as? [[String: Any]] ?? []).compactMap {
            ($0["name"] as? String)?.components(separatedBy: "/").last
        }
    }

    /// Hosting `releases?pageSize=1` → (release time, version status).
    public static func latestRelease(_ data: Data) throws -> (date: Date?, status: String)? {
        guard let release = (try JSON.object(data)["releases"] as? [[String: Any]])?.first else { return nil }
        let status = (release["version"] as? [String: Any])?["status"] as? String ?? "UNKNOWN"
        return (JSON.date(release["releaseTime"]), status)
    }

    public static func snapshot(project: Project, databases: [String], functions: [(name: String, state: String)],
                                hosting: [(site: String, date: Date?, status: String)]) -> ServiceSnapshot {
        let brokenFunctions = functions.filter { $0.state != "ACTIVE" && $0.state != "DEPLOYING" }
        var items: [ServiceItem] = []
        items.append(ServiceItem(id: "firestore", title: "Firestore",
                                 subtitle: databases.isEmpty ? "not enabled" : "\(databases.count) database\(databases.count == 1 ? "" : "s")",
                                 health: databases.isEmpty ? .unknown : .healthy))
        items.append(ServiceItem(id: "functions", title: "Functions",
                                 subtitle: functions.isEmpty ? "none" : (brokenFunctions.isEmpty ? "\(functions.count) active" : "\(brokenFunctions.count) failing"),
                                 health: functions.isEmpty ? .unknown : (brokenFunctions.isEmpty ? .healthy : .failing)))
        for site in hosting {
            items.append(ServiceItem(id: "hosting-\(site.site)", title: "Hosting · \(site.site)", subtitle: site.status.lowercased(),
                                     health: site.status == "FINALIZED" ? .healthy : .attention,
                                     url: "https://\(site.site).web.app", date: site.date))
        }
        let health = items.map(\.health).max() ?? .unknown
        return ServiceSnapshot(
            kind: .firebase,
            headline: health == .failing ? "Needs attention" : "Healthy",
            detail: project.displayName,
            health: health == .unknown ? .healthy : health,
            sections: [.init(title: project.displayName, items: items),
                       .init(title: "Functions", items: functions.map {
                           ServiceItem(id: $0.name, title: $0.name, subtitle: $0.state.lowercased(),
                                       health: $0.state == "ACTIVE" ? .healthy : .failing)
                       })].filter { !$0.items.isEmpty },
            webURL: "https://console.firebase.google.com/project/\(project.projectId)/overview"
        )
    }
}
