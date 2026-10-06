import Foundation

/// One question an agent asks the user (Claude Code's AskUserQuestion),
/// answered in the notch instead of the terminal.
public struct AgentQuestion: Codable, Sendable, Equatable, Identifiable {
    public struct Option: Codable, Sendable, Equatable, Hashable {
        public var label: String
        public var description: String

        public init(label: String, description: String = "") {
            self.label = label
            self.description = description
        }
    }

    public var question: String
    /// A short chip label (Claude sends up to ~12 characters).
    public var header: String
    public var multiSelect: Bool
    public var options: [Option]

    public var id: String { question }

    public init(question: String, header: String = "", multiSelect: Bool = false, options: [Option]) {
        self.question = question
        self.header = header
        self.multiSelect = multiSelect
        self.options = options
    }

    /// The most questions shown at once.
    public static let maxQuestions = 4

    /// Parses AskUserQuestion's `tool_input`. Returns nil if it isn't usable,
    /// so the agent falls back to asking in the terminal.
    public static func parse(toolInput: [String: Any]) -> [AgentQuestion]? {
        guard let raw = toolInput["questions"] as? [[String: Any]], !raw.isEmpty, raw.count <= maxQuestions else { return nil }
        var result: [AgentQuestion] = []
        for item in raw {
            guard let text = item["question"] as? String, !text.isEmpty,
                  let rawOptions = item["options"] as? [[String: Any]], !rawOptions.isEmpty else { return nil }
            let options = rawOptions.compactMap { option -> Option? in
                guard let label = option["label"] as? String, !label.isEmpty else { return nil }
                return Option(label: label, description: option["description"] as? String ?? "")
            }
            guard options.count == rawOptions.count else { return nil }
            result.append(AgentQuestion(question: text, header: item["header"] as? String ?? "",
                                        multiSelect: item["multiSelect"] as? Bool ?? false, options: options))
        }
        guard Set(result.map(\.question)).count == result.count else { return nil }   // answers are keyed by question
        return result
    }

    /// The `answers` object for the tool: question → label (single choice)
    /// or [labels] (multi-select). Answers to unknown questions or with
    /// unknown labels are dropped.
    public static func answersJSON(_ answers: [String: [String]], for questions: [AgentQuestion]) -> [String: Any] {
        var out: [String: Any] = [:]
        for q in questions {
            let valid = (answers[q.question] ?? []).filter { label in q.options.contains { $0.label == label } }
            guard !valid.isEmpty else { continue }
            out[q.question] = q.multiSelect ? valid : valid[0]
        }
        return out
    }

    /// True when every question has at least one valid choice.
    public static func isComplete(_ answers: [String: [String]], for questions: [AgentQuestion]) -> Bool {
        answersJSON(answers, for: questions).count == questions.count
    }
}
