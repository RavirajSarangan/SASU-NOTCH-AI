import NovaKit
import Foundation

/// What an agent is doing right now, as shown on the Home focus card.
/// Built from live `AgentSession`s (see AgentSummary.live); the static
/// examples below are used for snapshots and previews.
struct SessionPreview: Sendable {
    struct CodeLine: Sendable, Identifiable {
        enum Kind: Sendable { case context, removed, added }
        var number: Int
        var text: String
        var kind: Kind = .context
        var id: String { "\(number)-\(kind)" }
    }

    struct Step: Sendable, Identifiable {
        enum State: Sendable { case done, active, pending }
        var title: String
        var symbol: String
        var state: State
        var id = UUID()
    }

    /// One line of recent activity, e.g. "✓ Read Models.swift".
    struct Note: Sendable, Identifiable {
        enum State: Sendable { case done, running, failed }
        var text: String
        var state: State
        /// The edit's diff, for "+N −M" and tap-to-view.
        var edit: EditPreview? = nil
        var id = UUID()
    }

    var fileName: String
    var path: String
    var languageBadge: String
    var elapsed: String
    var steps: [Step]
    var lines: [CodeLine]
    var notes: [Note] = []
}

extension SessionPreview {
    static let swiftEdit = SessionPreview(
        fileName: "APIClient.swift",
        path: "Sources/Core/APIClient.swift",
        languageBadge: "SW",
        elapsed: "2m 14s",
        steps: [
            .init(title: "Read", symbol: "doc.text", state: .done),
            .init(title: "Edit", symbol: "pencil", state: .active),
            .init(title: "Test", symbol: "terminal", state: .pending),
            .init(title: "Done", symbol: "checkmark", state: .pending),
        ],
        lines: [
            .init(number: 18, text: "func fetch(_ path: String) async throws -> Data {"),
            .init(number: 19, text: "  let timeout = 30", kind: .removed),
            .init(number: 19, text: "  let timeout: TimeInterval = 15", kind: .added),
            .init(number: 20, text: "  let request = try makeRequest(path, timeout)"),
            .init(number: 21, text: "  return try await session.data(for: request).0"),
            .init(number: 22, text: "}"),
        ]
    )

    static let planning = SessionPreview(
        fileName: "PLAN.md",
        path: "docs/PLAN.md",
        languageBadge: "MD",
        elapsed: "48s",
        steps: [
            .init(title: "Read", symbol: "doc.text", state: .done),
            .init(title: "Think", symbol: "brain", state: .active),
            .init(title: "Edit", symbol: "pencil", state: .pending),
            .init(title: "Done", symbol: "checkmark", state: .pending),
        ],
        lines: [
            .init(number: 1, text: "# Refactor networking layer"),
            .init(number: 2, text: ""),
            .init(number: 3, text: "- Split APIClient into transport + decoding"),
            .init(number: 4, text: "- Add retry with backoff", kind: .added),
            .init(number: 5, text: "- Remove legacy completion handlers", kind: .added),
        ]
    )

    static let approval = SessionPreview(
        fileName: "package.json",
        path: "web/package.json",
        languageBadge: "JS",
        elapsed: "5m 02s",
        steps: [
            .init(title: "Read", symbol: "doc.text", state: .done),
            .init(title: "Edit", symbol: "pencil", state: .done),
            .init(title: "Bash", symbol: "terminal", state: .active),
            .init(title: "Done", symbol: "checkmark", state: .pending),
        ],
        lines: [
            .init(number: 6, text: "\"scripts\": {"),
            .init(number: 7, text: "  \"build\": \"next build\","),
            .init(number: 8, text: "  \"lint\": \"eslint .\"", kind: .removed),
            .init(number: 8, text: "  \"lint\": \"eslint . --max-warnings 0\"", kind: .added),
            .init(number: 9, text: "}"),
        ]
    )

    static let idle = SessionPreview(
        fileName: "No open file",
        path: "",
        languageBadge: "—",
        elapsed: "—",
        steps: [
            .init(title: "Read", symbol: "doc.text", state: .pending),
            .init(title: "Edit", symbol: "pencil", state: .pending),
            .init(title: "Bash", symbol: "terminal", state: .pending),
            .init(title: "Done", symbol: "checkmark", state: .pending),
        ],
        lines: []
    )

    static let finished = SessionPreview(
        fileName: "Onboarding.swift",
        path: "Features/Onboarding.swift",
        languageBadge: "SW",
        elapsed: "11m 40s",
        steps: [
            .init(title: "Read", symbol: "doc.text", state: .done),
            .init(title: "Edit", symbol: "pencil", state: .done),
            .init(title: "Test", symbol: "terminal", state: .done),
            .init(title: "Done", symbol: "checkmark", state: .done),
        ],
        lines: [
            .init(number: 40, text: "struct OnboardingView: View {"),
            .init(number: 41, text: "  @State private var page = 0", kind: .added),
            .init(number: 42, text: "  var body: some View { pager }"),
            .init(number: 43, text: "}"),
        ]
    )
}
