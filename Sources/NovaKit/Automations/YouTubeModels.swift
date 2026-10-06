import Foundation

public struct YouTubeChannel: Sendable, Equatable {
    public var id: String
    public var title: String
    public var subscribers: Int
    public var views: Int
    public var videos: Int

    public init(id: String, title: String, subscribers: Int, views: Int, videos: Int) {
        self.id = id
        self.title = title
        self.subscribers = subscribers
        self.views = views
        self.videos = videos
    }
}

/// A YouTube Analytics `reports.query` result.
public struct AnalyticsReport: Sendable, Equatable {
    public enum Value: Sendable, Equatable {
        case number(Double)
        case text(String)

        public var number: Double { if case .number(let n) = self { n } else { Double(text) ?? 0 } }
        public var text: String {
            switch self {
            case .text(let t): t
            case .number(let n): n.rounded() == n ? String(Int(n)) : String(n)
            }
        }
    }

    public var columns: [String]
    public var rows: [[Value]]

    public func index(of column: String) -> Int? { columns.firstIndex(of: column) }

    public func total(_ column: String) -> Double {
        guard let i = index(of: column) else { return 0 }
        return rows.reduce(0) { $0 + ($1.indices.contains(i) ? $1[i].number : 0) }
    }

    public func series(_ column: String) -> [Double] {
        guard let i = index(of: column) else { return [] }
        return rows.map { $0.indices.contains(i) ? $0[i].number : 0 }
    }
}

public enum YouTubeDecoder {
    public static func channel(from data: Data) throws -> YouTubeChannel? {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = (object["items"] as? [[String: Any]])?.first else { return nil }
        let stats = item["statistics"] as? [String: Any] ?? [:]
        func int(_ key: String) -> Int { Int(stats[key] as? String ?? "") ?? (stats[key] as? Int ?? 0) }
        return YouTubeChannel(id: item["id"] as? String ?? "",
                              title: (item["snippet"] as? [String: Any])?["title"] as? String ?? "",
                              subscribers: int("subscriberCount"), views: int("viewCount"), videos: int("videoCount"))
    }

    public static func report(from data: Data) throws -> AnalyticsReport {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let columns = (object["columnHeaders"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let rows = (object["rows"] as? [[Any]] ?? []).map { row in
            row.map { value -> AnalyticsReport.Value in
                if let n = value as? NSNumber { return .number(n.doubleValue) }
                return .text("\(value)")
            }
        }
        return AnalyticsReport(columns: columns, rows: rows)
    }

    /// `videos.list` → [videoId: title]
    public static func titles(from data: Data) throws -> [String: String] {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var result: [String: String] = [:]
        for item in object["items"] as? [[String: Any]] ?? [] {
            if let id = item["id"] as? String, let title = (item["snippet"] as? [String: Any])?["title"] as? String {
                result[id] = title
            }
        }
        return result
    }
}
