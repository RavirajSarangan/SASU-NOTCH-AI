import Foundation

public enum IntegrationKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case github, vercel, n8n, supabase, stripe, firebase

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .github: "GitHub"
        case .vercel: "Vercel"
        case .n8n: "n8n"
        case .supabase: "Supabase"
        case .stripe: "Stripe"
        case .firebase: "Firebase"
        }
    }
}

public enum ServiceHealth: String, Sendable, Equatable, Comparable {
    case healthy, attention, failing, unknown

    private var rank: Int {
        switch self {
        case .unknown: 0
        case .healthy: 1
        case .attention: 2
        case .failing: 3
        }
    }

    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

/// One row in a service's detail view (a PR, a deployment, an execution…).
public struct ServiceItem: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var health: ServiceHealth
    public var url: String?
    public var date: Date?

    public init(id: String, title: String, subtitle: String, health: ServiceHealth = .unknown, url: String? = nil, date: Date? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.health = health
        self.url = url
        self.date = date
    }
}

/// What a service shows on its chip and in its detail view.
public struct ServiceSnapshot: Sendable, Equatable {
    public struct Section: Sendable, Equatable, Identifiable {
        public var title: String
        public var items: [ServiceItem]
        public var id: String { title }

        public init(title: String, items: [ServiceItem]) {
            self.title = title
            self.items = items
        }
    }

    public var kind: IntegrationKind
    public var headline: String
    public var detail: String
    public var health: ServiceHealth
    public var sections: [Section]
    public var webURL: String?

    public init(kind: IntegrationKind, headline: String, detail: String, health: ServiceHealth,
                sections: [Section] = [], webURL: String? = nil) {
        self.kind = kind
        self.headline = headline
        self.detail = detail
        self.health = health
        self.sections = sections
        self.webURL = webURL
    }
}

enum JSON {
    static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "expected object")) }
        return object
    }

    static func array(_ data: Data) throws -> [[String: Any]] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "expected array")) }
        return array
    }

    static func date(_ value: Any?) -> Date? {
        if let ms = value as? Double { return Date(timeIntervalSince1970: ms > 1e11 ? ms / 1000 : ms) }
        if let ms = value as? Int { return Date(timeIntervalSince1970: Double(ms) > 1e11 ? Double(ms) / 1000 : Double(ms)) }
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
