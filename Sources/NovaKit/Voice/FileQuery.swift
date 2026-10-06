import Foundation

/// "Open the invoice PDF from last week" → a Spotlight query.
public struct FileQuery: Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case pdf, image, document, spreadsheet, presentation, video, code, screenshot
    }
    public enum Since: String, Sendable { case today, yesterday, week, month }

    /// Name words to look for ("invoice", "resume").
    public var words: [String]
    public var kind: Kind?
    public var since: Since?

    public init(words: [String], kind: Kind? = nil, since: Since? = nil) {
        self.words = words; self.kind = kind; self.since = since
    }

    static let kindWords: [(String, Kind)] = [
        ("pdfs", .pdf), ("pdf", .pdf), ("screenshots", .screenshot), ("screenshot", .screenshot),
        ("images", .image), ("image", .image), ("photos", .image), ("photo", .image), ("pictures", .image), ("picture", .image),
        ("documents", .document), ("document", .document), ("docs", .document), ("doc", .document), ("word", .document),
        ("spreadsheets", .spreadsheet), ("spreadsheet", .spreadsheet), ("sheet", .spreadsheet), ("excel", .spreadsheet),
        ("slides", .presentation), ("presentation", .presentation), ("keynote", .presentation), ("powerpoint", .presentation),
        ("videos", .video), ("video", .video), ("recording", .video), ("code", .code),
    ]
    static let filler: Set = ["open", "find", "show", "me", "my", "the", "a", "an", "where", "is", "are", "file", "files", "from",
                              "last", "this", "of", "for", "that", "called", "named", "search", "in", "on", "mac", "please",
                              "today", "yesterday", "week", "month", "todays", "yesterdays", "s", "i", "saved", "downloaded"]

    /// Reads a request. Nil when it isn't about files.
    public static func parse(_ text: String) -> FileQuery? {
        let t = text.lowercased().replacingOccurrences(of: "'", with: " ").replacingOccurrences(of: "’", with: " ")
        let words = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard let verb = words.first, ["find", "open", "show", "where", "search", "locate"].contains(verb) else { return nil }
        let kind = kindWords.first { words.contains($0.0) }?.1
        var since: Since?
        if t.contains("yesterday") { since = .yesterday }
        else if t.contains("today") || t.contains("this morning") { since = .today }
        else if t.contains("last week") || t.contains("this week") { since = .week }
        else if t.contains("last month") || t.contains("this month") { since = .month }
        let mentionsFile = words.contains("file") || words.contains("files") || t.contains("search my files")
        // "open Safari" is an app: only "find …"/"where is …", or a file word, means files.
        let fileVerb = verb == "find" || verb == "where" || verb == "locate" || (verb == "search" && mentionsFile)
        guard fileVerb || kind != nil || mentionsFile || (since != nil && verb != "search") else { return nil }
        let kindSet = Set(kindWords.map(\.0))
        let name = words.dropFirst().filter { !filler.contains($0) && !kindSet.contains($0) }
        guard !name.isEmpty || kind != nil else { return nil }
        return FileQuery(words: Array(name.prefix(4)), kind: kind, since: since)
    }

    /// The `mdfind` query.
    public var spotlight: String {
        var parts = words.map { #"kMDItemFSName == "*\#($0)*"cd"# }
        if let kind {
            let clause: String = switch kind {
            case .pdf: #"kMDItemContentTypeTree == "com.adobe.pdf""#
            case .image: #"kMDItemContentTypeTree == "public.image""#
            case .screenshot: "kMDItemIsScreenCapture == 1"
            case .document: #"(kMDItemContentTypeTree == "public.text" || kMDItemContentTypeTree == "org.openxmlformats.wordprocessingml.document" || kMDItemContentTypeTree == "com.apple.iwork.pages.sffpages" || kMDItemContentTypeTree == "com.microsoft.word.doc")"#
            case .spreadsheet: #"(kMDItemContentTypeTree == "public.spreadsheet" || kMDItemContentTypeTree == "org.openxmlformats.spreadsheetml.sheet")"#
            case .presentation: #"(kMDItemContentTypeTree == "public.presentation" || kMDItemContentTypeTree == "org.openxmlformats.presentationml.presentation")"#
            case .video: #"kMDItemContentTypeTree == "public.movie""#
            case .code: #"kMDItemContentTypeTree == "public.source-code""#
            }
            parts.append(clause)
        }
        if let since {
            let clause: String = switch since {
            case .today: "kMDItemFSContentChangeDate >= $time.today"
            case .yesterday: "kMDItemFSContentChangeDate >= $time.today(-1) && kMDItemFSContentChangeDate < $time.today"
            case .week: "kMDItemFSContentChangeDate >= $time.today(-7)"
            case .month: "kMDItemFSContentChangeDate >= $time.today(-31)"
            }
            parts.append(clause)
        }
        return parts.joined(separator: " && ")
    }

    /// Paths Nova never offers (system and app data, hidden folders).
    public static func isUserFile(_ path: String, home: String) -> Bool {
        guard path.hasPrefix(home + "/") else { return false }
        let rest = path.dropFirst(home.count + 1)
        if rest.hasPrefix("Library/") { return false }
        return !rest.split(separator: "/").contains { $0.hasPrefix(".") || $0.hasSuffix(".app") }
    }
}

/// What to do with the text on the clipboard.
public enum ClipboardTask: Equatable, Sendable {
    case summarize, explain, fix, shorten
    case translate(to: String)

    /// Tasks whose result replaces the clipboard (you'll paste it).
    public var replacesClipboard: Bool {
        switch self {
        case .fix, .shorten, .translate: true
        case .summarize, .explain: false
        }
    }

    public var instruction: String {
        switch self {
        case .summarize: "Summarise this in 2-3 short spoken sentences."
        case .explain: "Explain this simply in 2-3 short spoken sentences."
        case .fix: "Fix the spelling and grammar. Reply with only the corrected text, same language and tone."
        case .shorten: "Make this shorter and clearer. Reply with only the new text."
        case .translate(let language): "Translate this to \(language). Reply with only the translation."
        }
    }

    static func parse(_ text: String) -> ClipboardTask? {
        let t = text.lowercased()
        let aboutClipboard = ["clipboard", "what i copied", "i just copied", "copied text", "the text i copied"].contains(where: t.contains)
            || ["this", "that", "it"].contains(where: { t.hasSuffix(" " + $0) || t.contains(" " + $0 + " to ") || t.contains(" " + $0 + " in ") })
        guard aboutClipboard else { return nil }
        if t.contains("translate") || t.contains("in tamil") || t.contains("to tamil") || t.contains("tamil la") {
            return .translate(to: t.contains("english") ? "English" : "Tamil")
        }
        if t.contains("summar") || t.contains("tl;dr") || t.contains("tldr") { return .summarize }
        if t.contains("explain") || t.contains("what does") || t.contains("meaning") { return .explain }
        if t.contains("fix") || t.contains("grammar") || t.contains("spelling") || t.contains("correct") { return .fix }
        if t.contains("shorten") || t.contains("shorter") || t.contains("make it short") { return .shorten }
        return nil
    }
}
