import Foundation

public struct LinkedInDigest: Sendable, Equatable {
    public struct Message: Sendable, Equatable {
        public var sender: String
        public var preview: String

        public init(sender: String, preview: String) {
            self.sender = sender
            self.preview = preview
        }
    }

    public var messages: [Message] = []
    public var profileViews: Int?
    public var viewers: [String] = []
    public var searchAppearances: Int?
    public var postActivity: [String] = []
    public var invitations: [String] = []

    public init() {}

    public var isEmpty: Bool {
        messages.isEmpty && profileViews == nil && viewers.isEmpty && postActivity.isEmpty && invitations.isEmpty && searchAppearances == nil
    }
}

/// Builds a LinkedIn summary from LinkedIn's notification emails. LinkedIn has
/// no personal API for messages or profile views; the emails are the safe,
/// allowed source.
public enum LinkedInDigestParser {
    public static func isLinkedIn(_ item: MailItem) -> Bool {
        item.senderAddress.hasSuffix("linkedin.com")
    }

    public static func parse(_ items: [MailItem]) -> LinkedInDigest {
        var digest = LinkedInDigest()
        for item in items.filter(isLinkedIn).sorted(by: { $0.date > $1.date }) {
            let subject = item.subject.trimmingCharacters(in: .whitespaces)
            let lower = subject.lowercased()

            if let name = capture(subject, #"^(.+?) (?:sent you a (?:new )?message|just messaged you|messaged you)"#)
                ?? capture(subject, #"^New message from (.+)$"#)
                ?? (item.senderAddress.hasPrefix("messages-noreply") ? item.senderName.replacingOccurrences(of: " via LinkedIn", with: "") : nil) {
                digest.messages.append(.init(sender: name, preview: item.snippet))
            } else if let count = number(lower, #"(\d[\d,]*) (?:people|person|others?) viewed your profile"#)
                        ?? number(lower, #"your profile was viewed by (\d[\d,]*)"#) {
                digest.profileViews = max(digest.profileViews ?? 0, count)
            } else if let name = capture(subject, #"^(.+?) viewed your profile"#) {
                digest.viewers.append(name)
                digest.profileViews = max(digest.profileViews ?? 0, 1)
            } else if let count = number(lower, #"you appeared in (\d[\d,]*) searches?"#) {
                digest.searchAppearances = max(digest.searchAppearances ?? 0, count)
            } else if lower.contains("wants to connect") || lower.contains("invited you to connect") || lower.contains("invitation") {
                digest.invitations.append(capture(subject, #"^(.+?) (?:wants to connect|has invited you|invited you)"#) ?? subject)
            } else if lower.contains("your post") || lower.contains("reacted to") || lower.contains("commented on")
                        || lower.contains("reposted") || lower.contains("mentioned you") || lower.contains("impressions") {
                digest.postActivity.append(subject)
            }
        }
        digest.viewers = Array(NSOrderedSet(array: digest.viewers)) as? [String] ?? digest.viewers
        return digest
    }

    private static func capture(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        let value = text[range].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func number(_ text: String, _ pattern: String) -> Int? {
        capture(text, pattern).flatMap { Int($0.replacingOccurrences(of: ",", with: "")) }
    }
}
