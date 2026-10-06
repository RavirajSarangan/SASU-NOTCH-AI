import Foundation

/// A line diff of what an agent wants to change, small enough to send over
/// Nova's socket and show in the notch. Secrets are masked before it leaves
/// the hook.
public struct EditPreview: Codable, Sendable, Equatable {
    public struct Line: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable { case context, added, removed, gap }
        public var kind: Kind
        public var text: String

        public init(_ kind: Kind, _ text: String) {
            self.kind = kind
            self.text = text
        }
    }

    public var file: String?
    public var lines: [Line]
    public var added: Int
    public var removed: Int
    /// True when the diff was cut to `maxLines`.
    public var truncated: Bool
    /// New file (Write): everything is added.
    public var isNewContent: Bool

    public static let maxLines = 200
    public static let maxLineLength = 300
    static let context = 2

    public init(file: String?, lines: [Line], added: Int, removed: Int, truncated: Bool, isNewContent: Bool = false) {
        self.file = file
        self.lines = lines
        self.added = added
        self.removed = removed
        self.truncated = truncated
        self.isNewContent = isNewContent
    }

    /// Builds a preview from a tool's input: Edit (old_string/new_string),
    /// MultiEdit (edits[]), Write (content). Nil for other tools.
    public static func make(tool: String?, input: [String: Any]) -> EditPreview? {
        let file = (input["file_path"] ?? input["notebook_path"] ?? input["path"]) as? String
        switch tool {
        case "Edit", "replace", "edit":
            guard let old = (input["old_string"] ?? input["old_str"]) as? String,
                  let new = (input["new_string"] ?? input["new_str"]) as? String else { return nil }
            return diff(old: old, new: new, file: file)
        case "MultiEdit":
            guard let edits = input["edits"] as? [[String: Any]], !edits.isEmpty else { return nil }
            var parts: [EditPreview] = []
            for edit in edits {
                guard let old = edit["old_string"] as? String, let new = edit["new_string"] as? String else { continue }
                parts.append(diff(old: old, new: new, file: file))
            }
            guard !parts.isEmpty else { return nil }
            var lines: [Line] = []
            for (i, part) in parts.enumerated() {
                if i > 0 { lines.append(Line(.gap, "")) }
                lines += part.lines
            }
            return capped(file: file, lines: lines, added: parts.map(\.added).reduce(0, +),
                          removed: parts.map(\.removed).reduce(0, +))
        case "Write", "write_file":
            guard let content = (input["content"] ?? input["file_text"]) as? String else { return nil }
            let lines = split(content).map { Line(.added, $0) }
            var preview = capped(file: file, lines: lines, added: lines.count, removed: 0)
            preview.isNewContent = true
            return preview
        default:
            return nil
        }
    }

    /// Line diff (longest common subsequence) with a little context.
    public static func diff(old: String, new: String, file: String? = nil) -> EditPreview {
        let a = split(old), b = split(new)
        // LCS table; inputs are tool snippets, so this stays small. Very
        // large inputs fall back to "all removed, all added".
        guard a.count * b.count <= 400_000 else {
            let lines = a.map { Line(.removed, $0) } + b.map { Line(.added, $0) }
            return capped(file: file, lines: lines, added: b.count, removed: a.count)
        }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var full: [Line] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            // Removals before additions, as diffs usually read.
            if i < a.count, j < b.count, a[i] == b[j] { full.append(Line(.context, a[i])); i += 1; j += 1 }
            else if i < a.count, j == b.count || table[i + 1][j] >= table[i][j + 1] { full.append(Line(.removed, a[i])); i += 1 }
            else { full.append(Line(.added, b[j])); j += 1 }
        }
        let added = full.filter { $0.kind == .added }.count
        let removed = full.filter { $0.kind == .removed }.count
        return capped(file: file, lines: trimContext(full), added: added, removed: removed)
    }

    /// Keeps `context` unchanged lines around each change; collapses the rest.
    static func trimContext(_ lines: [Line]) -> [Line] {
        let changed = lines.indices.filter { lines[$0].kind != .context }
        guard !changed.isEmpty else { return Array(lines.prefix(context * 2)) }
        var keep = Set<Int>()
        for index in changed { for k in max(0, index - context)...min(lines.count - 1, index + context) { keep.insert(k) } }
        var out: [Line] = []
        var last = -1
        for index in keep.sorted() {
            if last >= 0, index > last + 1 { out.append(Line(.gap, "")) }
            out.append(lines[index])
            last = index
        }
        return out
    }

    static func capped(file: String?, lines: [Line], added: Int, removed: Int) -> EditPreview {
        let cut = lines.count > maxLines
        let kept = lines.prefix(maxLines).map { line in
            Line(line.kind, String(SecretMasker.mask(line.text).prefix(maxLineLength)))
        }
        return EditPreview(file: file, lines: Array(kept), added: added, removed: removed, truncated: cut)
    }

    static func split(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var parts = text.components(separatedBy: "\n")
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    /// "+12 −3"
    public var summary: String { "+\(added) −\(removed)" }
}

/// Hides secret values so diffs and commands never show them in the notch.
public enum SecretMasker {
    static let patterns: [String] = [
        // key = value / key: value for secret-looking names (keeps the name).
        #"(?i)((?:api[_-]?key|secret|token|passw(?:or)?d|private[_-]?key|access[_-]?key|client[_-]?secret|auth)[A-Za-z0-9_\-]*\s*[:=]\s*["']?)[^\s"']{4,}"#,
        #"sk-[A-Za-z0-9_\-]{12,}"#,                     // OpenAI / Anthropic style
        #"gh[pousr]_[A-Za-z0-9]{20,}"#, #"github_pat_[A-Za-z0-9_]{20,}"#,
        #"xox[abpr]-[A-Za-z0-9\-]{10,}"#,                // Slack
        #"AKIA[0-9A-Z]{16}"#,                            // AWS access key id
        #"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"#,   // JWT
        #"(?:sk|rk|pk)_(?:live|test)_[A-Za-z0-9]{10,}"#,  // Stripe
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
    ]

    public static func mask(_ text: String) -> String {
        var out = text
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(out.startIndex..., in: out)
            out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: index == 0 ? "$1••••••" : "••••••")
        }
        return out
    }
}
