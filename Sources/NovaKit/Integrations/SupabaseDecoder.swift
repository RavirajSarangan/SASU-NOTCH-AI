import Foundation

public enum SupabaseDecoder {
    public struct Project: Sendable, Equatable, Identifiable {
        public var id: String { ref }
        public var ref: String
        public var name: String
        public var region: String
        public var status: String

        public init(ref: String, name: String, region: String, status: String) {
            self.ref = ref
            self.name = name
            self.region = region
            self.status = status
        }
    }

    public struct ServiceStatus: Sendable, Equatable {
        public var name: String
        public var healthy: Bool
        public var status: String

        public init(name: String, healthy: Bool, status: String) {
            self.name = name
            self.healthy = healthy
            self.status = status
        }
    }

    public static func projects(_ data: Data) throws -> [Project] {
        try JSON.array(data).map {
            Project(ref: ($0["ref"] ?? $0["id"]) as? String ?? "", name: $0["name"] as? String ?? "Project",
                    region: $0["region"] as? String ?? "", status: $0["status"] as? String ?? "")
        }
    }

    public static func health(_ data: Data) throws -> [ServiceStatus] {
        try JSON.array(data).map {
            ServiceStatus(name: $0["name"] as? String ?? "", healthy: $0["healthy"] as? Bool ?? false, status: $0["status"] as? String ?? "")
        }
    }

    static func label(_ service: String) -> String {
        switch service {
        case "db": "Database"
        case "auth": "Auth"
        case "storage": "Storage"
        case "rest": "API"
        case "realtime": "Realtime"
        default: service.capitalized
        }
    }

    public static func snapshot(project: Project, services: [ServiceStatus]) -> ServiceSnapshot {
        let unhealthy = services.filter { !$0.healthy }
        let paused = project.status.uppercased().contains("PAUSE") || project.status.uppercased().contains("INACTIVE")
        return ServiceSnapshot(
            kind: .supabase,
            headline: paused ? "Paused" : (unhealthy.isEmpty ? "Healthy" : "\(unhealthy.count) issue\(unhealthy.count == 1 ? "" : "s")"),
            detail: unhealthy.isEmpty ? project.name : unhealthy.map { label($0.name) }.joined(separator: ", "),
            health: paused ? .attention : (unhealthy.isEmpty ? .healthy : .failing),
            sections: [.init(title: project.name, items: services.map {
                ServiceItem(id: $0.name, title: label($0.name), subtitle: $0.status.replacingOccurrences(of: "_", with: " ").lowercased(),
                            health: $0.healthy ? .healthy : .failing)
            })],
            webURL: "https://supabase.com/dashboard/project/\(project.ref)"
        )
    }
}
