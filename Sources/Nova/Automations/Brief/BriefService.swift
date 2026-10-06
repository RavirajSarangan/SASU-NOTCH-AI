import Foundation
import NovaKit
import Observation

struct MailBrief: Equatable {
    struct Line: Equatable, Identifiable {
        var id = UUID()
        var sender: String
        var summary: String
    }

    var overview: String
    var needsReply: [Line]
    var important: [Line]
    var updates: [Line]
    var promotions: Int
    var total: Int
    var unread: Int
}

struct YouTubeSummary: Equatable {
    var channel: YouTubeChannel
    var views7d: Int
    var watchHours7d: Double
    var subscribersNet7d: Int
    var dailyViews: [Double]
    var topVideos: [(title: String, views: Int)]
    var insight: String?

    static func == (a: Self, b: Self) -> Bool {
        a.channel == b.channel && a.views7d == b.views7d && a.dailyViews == b.dailyViews && a.insight == b.insight
    }
}

/// Morning brief: Gmail summary, LinkedIn (from its emails) and YouTube.
@Observable
@MainActor
final class BriefService {
    private(set) var mail: MailBrief?
    private(set) var linkedIn: LinkedInDigest?
    private(set) var youtube: YouTubeSummary?
    private(set) var youtubeNote: String?
    private(set) var updatedAt: Date?
    private(set) var isRefreshing = false
    private(set) var error: String?

    @ObservationIgnored let google: GoogleAuth
    @ObservationIgnored private let ai: AIService

    init(google: GoogleAuth, ai: AIService) {
        self.google = google
        self.ai = ai
    }

    func refresh() async {
        guard google.isSignedIn, !isRefreshing else { return }
        isRefreshing = true
        error = nil
        defer { isRefreshing = false }

        async let mailItems = fetchMail(query: "newer_than:1d -in:chats", max: 40)
        async let linkedInItems = fetchMail(query: "from:linkedin.com newer_than:7d", max: 30)
        do {
            let items = try await mailItems
            linkedIn = LinkedInDigestParser.parse(try await linkedInItems)
            mail = await summarize(items.filter { !LinkedInDigestParser.isLinkedIn($0) })
        } catch {
            self.error = error.localizedDescription
        }
        await refreshYouTube()
        updatedAt = Date()
    }

    #if DEBUG
    func loadPreview() {
        mail = MailBrief(overview: "Two people need a reply, and your Vercel deploy failed overnight.",
                         needsReply: [.init(sender: "Dr. Patel", summary: "Can we move the viva to Thursday?"),
                                      .init(sender: "Sara (Esoft)", summary: "Final report draft comments")],
                         important: [.init(sender: "Vercel", summary: "Production deployment failed")],
                         updates: [.init(sender: "GitHub", summary: "2 PRs merged in nova")],
                         promotions: 9, total: 23, unread: 7)
        var digest = LinkedInDigest()
        digest.messages = [.init(sender: "Priya Raman", preview: "Hi! Are you open to a quick call?")]
        digest.profileViews = 12
        digest.invitations = ["Sara Lee"]
        linkedIn = digest
        youtube = YouTubeSummary(channel: YouTubeChannel(id: "UC", title: "Nova Dev", subscribers: 1520, views: 98_000, videos: 42),
                                 views7d: 4_812, watchHours7d: 212, subscribersNet7d: 37,
                                 dailyViews: [420, 510, 380, 900, 760, 1010, 832],
                                 topVideos: [(title: "SwiftUI notch app in 10 min", views: 2100)],
                                 insight: "Thursday's upload doubled views. Post your next video on Thursday too.")
        updatedAt = Date()
    }
    #endif

    // MARK: - Gmail

    private func fetchMail(query: String, max: Int) async throws -> [MailItem] {
        var list = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        list.queryItems = [.init(name: "q", value: query), .init(name: "maxResults", value: String(max))]
        let ids = try GmailDecoder.messageIds(from: try await google.get(list.url!))

        return try await withThrowingTaskGroup(of: MailItem?.self) { group in
            for id in ids {
                group.addTask { [google] in
                    var get = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)")!
                    get.queryItems = [.init(name: "format", value: "metadata"),
                                      .init(name: "metadataHeaders", value: "From"),
                                      .init(name: "metadataHeaders", value: "Subject")]
                    return try GmailDecoder.mailItem(from: try await google.get(get.url!))
                }
            }
            var items: [MailItem] = []
            for try await item in group { if let item { items.append(item) } }
            return items.sorted { $0.date > $1.date }
        }
    }

    private func summarize(_ items: [MailItem]) async -> MailBrief {
        let promotions = items.filter(\.isPromotion)
        let rest = items.filter { !$0.isPromotion }
        var brief = MailBrief(overview: "", needsReply: [], important: [], updates: [], promotions: promotions.count,
                              total: items.count, unread: items.filter(\.isUnread).count)
        guard !rest.isEmpty else {
            brief.overview = items.isEmpty ? "No new email in the last day." : "Only promotions and social updates today."
            return brief
        }

        let listing = rest.prefix(30).enumerated().map { i, m in
            "\(i + 1). From: \(m.senderName) | Subject: \(m.subject) | Snippet: \(m.snippet.prefix(200))"
        }.joined(separator: "\n")
        let system = """
        You triage a person's inbox. Reply with JSON only, no prose, matching:
        {"overview": string (2 sentences max), "needsReply": [{"sender": string, "summary": string}],
         "important": [{"sender": string, "summary": string}], "updates": [{"sender": string, "summary": string}]}
        Each summary is one short line. Put each email in at most one list; skip noise.
        """
        do {
            let raw = try await ai.complete(system: system, prompt: "Emails from the last 24 hours:\n\(listing)", effort: "low")
            if let parsed = Self.parseBrief(raw) {
                brief.overview = parsed.overview
                brief.needsReply = parsed.needsReply
                brief.important = parsed.important
                brief.updates = parsed.updates
                return brief
            }
            brief.overview = raw
        } catch {
            // No AI key: fall back to a plain list.
            brief.overview = "\(rest.count) emails · \(brief.unread) unread. Add an AI key for smart summaries."
            brief.updates = rest.prefix(6).map { .init(sender: $0.senderName, summary: $0.subject) }
        }
        return brief
    }

    nonisolated static func parseBrief(_ raw: String) -> (overview: String, needsReply: [MailBrief.Line], important: [MailBrief.Line], updates: [MailBrief.Line])? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"),
              let data = String(raw[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func lines(_ key: String) -> [MailBrief.Line] {
            (object[key] as? [[String: Any]] ?? []).compactMap { entry in
                guard let summary = entry["summary"] as? String else { return nil }
                return MailBrief.Line(sender: entry["sender"] as? String ?? "", summary: summary)
            }
        }
        return (object["overview"] as? String ?? "", lines("needsReply"), lines("important"), lines("updates"))
    }

    // MARK: - YouTube

    private func refreshYouTube() async {
        do {
            let channelURL = URL(string: "https://www.googleapis.com/youtube/v3/channels?part=snippet,statistics&mine=true")!
            guard let channel = try YouTubeDecoder.channel(from: try await google.get(channelURL)) else {
                youtube = nil
                youtubeNote = "No YouTube channel on this Google account."
                return
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let end = formatter.string(from: Date())
            let start = formatter.string(from: Date().addingTimeInterval(-7 * 86_400))

            var daily = URLComponents(string: "https://youtubeanalytics.googleapis.com/v2/reports")!
            daily.queryItems = [.init(name: "ids", value: "channel==MINE"), .init(name: "startDate", value: start),
                                .init(name: "endDate", value: end), .init(name: "dimensions", value: "day"),
                                .init(name: "metrics", value: "views,estimatedMinutesWatched,subscribersGained,subscribersLost")]
            let report = try YouTubeDecoder.report(from: try await google.get(daily.url!))

            var top = daily
            top.queryItems = [.init(name: "ids", value: "channel==MINE"), .init(name: "startDate", value: start),
                              .init(name: "endDate", value: end), .init(name: "dimensions", value: "video"),
                              .init(name: "metrics", value: "views"), .init(name: "sort", value: "-views"),
                              .init(name: "maxResults", value: "5")]
            let topReport = try YouTubeDecoder.report(from: try await google.get(top.url!))
            let ids = topReport.rows.compactMap { $0.first?.text }
            var titles: [String: String] = [:]
            if !ids.isEmpty {
                let videosURL = URL(string: "https://www.googleapis.com/youtube/v3/videos?part=snippet&id=\(ids.joined(separator: ","))")!
                titles = try YouTubeDecoder.titles(from: try await google.get(videosURL))
            }
            let topVideos = topReport.rows.map { row in
                (title: titles[row.first?.text ?? ""] ?? row.first?.text ?? "Video", views: Int(row.last?.number ?? 0))
            }

            var summary = YouTubeSummary(
                channel: channel,
                views7d: Int(report.total("views")),
                watchHours7d: report.total("estimatedMinutesWatched") / 60,
                subscribersNet7d: Int(report.total("subscribersGained") - report.total("subscribersLost")),
                dailyViews: report.series("views"),
                topVideos: topVideos
            )
            summary.insight = try? await ai.complete(
                system: "You are a YouTube growth analyst. Give ONE short, specific, encouraging insight (max 25 words) from these stats. No preamble.",
                prompt: "Channel: \(channel.title). Last 7 days: \(summary.views7d) views, \(String(format: "%.1f", summary.watchHours7d)) watch hours, net subscribers \(summary.subscribersNet7d). Daily views: \(summary.dailyViews.map { Int($0) }). Top videos: \(topVideos.map { "\($0.title) (\($0.views))" }.joined(separator: "; "))",
                effort: "low", maxTokens: 300)
            youtube = summary
            youtubeNote = nil
        } catch {
            youtube = nil
            youtubeNote = "YouTube: \(error.localizedDescription)"
        }
    }
}
