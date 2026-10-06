import Foundation

/// A Gmail message reduced to what the brief needs (metadata + snippet).
public struct MailItem: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var from: String
    public var subject: String
    public var snippet: String
    public var date: Date
    public var labels: [String]

    public init(id: String, from: String, subject: String, snippet: String, date: Date, labels: [String] = []) {
        self.id = id
        self.from = from
        self.subject = subject
        self.snippet = snippet
        self.date = date
        self.labels = labels
    }

    public var isUnread: Bool { labels.contains("UNREAD") }
    public var isPromotion: Bool { labels.contains("CATEGORY_PROMOTIONS") || labels.contains("CATEGORY_SOCIAL") }

    /// "Jane Doe <jane@x.com>" → "Jane Doe"
    public var senderName: String {
        if let lt = from.firstIndex(of: "<") {
            let name = from[..<lt].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            if !name.isEmpty { return name }
        }
        return from.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
    }

    public var senderAddress: String {
        if let lt = from.firstIndex(of: "<"), let gt = from.lastIndex(of: ">"), lt < gt {
            return String(from[from.index(after: lt)..<gt]).lowercased()
        }
        return from.lowercased()
    }
}

public enum GmailDecoder {
    /// `users.messages.list` → message ids.
    public static func messageIds(from data: Data) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object?["messages"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    }

    /// `users.messages.get?format=metadata` → MailItem.
    public static func mailItem(from data: Data) throws -> MailItem? {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String else { return nil }
        let headers = ((object["payload"] as? [String: Any])?["headers"] as? [[String: Any]]) ?? []
        func header(_ name: String) -> String {
            headers.first { ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }?["value"] as? String ?? ""
        }
        let millis = Double(object["internalDate"] as? String ?? "") ?? 0
        let snippet = (object["snippet"] as? String ?? "")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
        return MailItem(id: id, from: header("From"), subject: header("Subject"), snippet: snippet,
                        date: Date(timeIntervalSince1970: millis / 1000), labels: object["labelIds"] as? [String] ?? [])
    }
}
