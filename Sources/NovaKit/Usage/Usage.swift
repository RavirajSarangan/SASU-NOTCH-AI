import Foundation

// Usage and limits, from the agents' own local logs. Only numbers,
// timestamps and project folder names are extracted from each line;
// prompts and replies are never kept.

public enum UsageSource: String, Sendable, CaseIterable { case claude, codex }

public struct UsageEntry: Sendable, Equatable {
    public var date: Date
    public var input: Int
    public var output: Int
    public var cacheWrite: Int
    public var cacheRead: Int
    public var project: String
    public var source: UsageSource

    public init(date: Date, input: Int, output: Int, cacheWrite: Int = 0, cacheRead: Int = 0, project: String, source: UsageSource) {
        self.date = date; self.input = input; self.output = output
        self.cacheWrite = cacheWrite; self.cacheRead = cacheRead; self.project = project; self.source = source
    }

    /// All tokens processed (what plan limits are measured against, approximately).
    public var tokens: Int { input + output + cacheWrite + cacheRead }
}

public enum UsageLineParser {
    /// A Claude Code log line (`~/.claude/projects/*/*.jsonl`). Returns the
    /// message id (for de-duplication: the same reply is logged several times).
    public static func claude(_ line: String) -> (id: String?, entry: UsageEntry)? {
        guard let usage = line.range(of: "\"usage\":{") else { return nil }
        let window = line[usage.upperBound...].prefix(600)
        guard let date = timestamp(in: line),
              let input = number("\"input_tokens\":", in: window),
              let output = number("\"output_tokens\":", in: window) else { return nil }
        let entry = UsageEntry(date: date, input: input, output: output,
                               cacheWrite: number("\"cache_creation_input_tokens\":", in: window) ?? 0,
                               cacheRead: number("\"cache_read_input_tokens\":", in: window) ?? 0,
                               project: project(in: line), source: .claude)
        return (string(after: "\"id\":\"msg_", in: line).map { "msg_" + $0 }, entry)
    }

    /// A Codex log line (`~/.codex/sessions/**/rollout-*.jsonl`) with a `token_count` event.
    public static func codex(_ line: String, project: String = "Codex") -> UsageEntry? {
        guard line.contains("\"token_count\""), let usage = line.range(of: "\"last_token_usage\":{") else { return nil }
        let window = line[usage.upperBound...].prefix(400)
        guard let date = timestamp(in: line),
              let input = number("\"input_tokens\":", in: window),
              let output = number("\"output_tokens\":", in: window) else { return nil }
        let cached = number("\"cached_input_tokens\":", in: window) ?? 0
        return UsageEntry(date: date, input: max(input - cached, 0), output: output,
                          cacheWrite: number("\"cache_write_input_tokens\":", in: window) ?? 0,
                          cacheRead: cached, project: project, source: .codex)
    }

    static func number(_ key: String, in text: Substring) -> Int? {
        guard let r = text.range(of: key) else { return nil }
        let digits = text[r.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    static func string(after key: String, in text: String) -> String? {
        guard let r = text.range(of: key) else { return nil }
        let value = text[r.upperBound...].prefix { $0 != "\"" }
        return value.isEmpty ? nil : String(value)
    }

    static func timestamp(in line: String) -> Date? {
        guard let value = string(after: "\"timestamp\":\"", in: line) else { return nil }
        return iso.date(from: value) ?? isoPlain.date(from: value)
    }

    /// The last folder of the working directory, e.g. "portfolio".
    static func project(in line: String) -> String {
        guard let cwd = string(after: "\"cwd\":\"", in: line) else { return "Other" }
        return cwd.split(separator: "/").last.map(String.init) ?? "Other"
    }

    nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) static let isoPlain = ISO8601DateFormatter()
}

/// What the meter shows for one tool.
public struct UsageSummary: Sendable, Equatable {
    /// The current 5-hour window (Claude Code's limit window), if one is active.
    public var blockStart: Date?
    public var blockEnd: Date?
    public var blockTokens = 0
    public var todayTokens = 0
    public var weekTokens = 0
    /// Tokens per hour over the last hour of the window.
    public var burnPerHour = 0
    /// When the window limit would be reached at this pace (nil = not before it resets).
    public var limitReachedAt: Date?
    /// 0…1 of the limit you set, if any.
    public var blockFraction: Double?
    public var weekFraction: Double?
    /// Biggest window so far in the data (a good starting limit).
    public var largestBlock = 0
    /// Last 7 days, oldest first.
    public var byDay: [Int] = []
    /// Projects in the last 7 days, biggest first.
    public var byProject: [ProjectUsage] = []

    public struct ProjectUsage: Sendable, Equatable {
        public var name: String
        public var tokens: Int
    }

    public init() {}
}

public enum UsageMath {
    public static let blockLength: TimeInterval = 5 * 3600

    /// Builds the summary. Windows start at the hour of the first message
    /// after the previous window ended and last five hours, like Claude Code.
    public static func summary(_ entries: [UsageEntry], now: Date, blockLimit: Int? = nil, weekLimit: Int? = nil,
                               calendar: Calendar = .current) -> UsageSummary {
        var s = UsageSummary()
        let sorted = entries.sorted { $0.date < $1.date }
        var blockStart: Date?
        var blockTokens = 0
        for e in sorted where e.date <= now {
            if let start = blockStart, e.date < start.addingTimeInterval(blockLength) {
                blockTokens += e.tokens
            } else {
                s.largestBlock = max(s.largestBlock, blockTokens)
                blockStart = calendar.dateInterval(of: .hour, for: e.date)?.start ?? e.date
                blockTokens = e.tokens
            }
        }
        s.largestBlock = max(s.largestBlock, blockTokens)
        if let start = blockStart, now < start.addingTimeInterval(blockLength) {
            s.blockStart = start
            s.blockEnd = start.addingTimeInterval(blockLength)
            s.blockTokens = blockTokens
            let since = max(start, now.addingTimeInterval(-3600))
            let recent = sorted.filter { $0.date >= since && $0.date <= now }.reduce(0) { $0 + $1.tokens }
            let hours = max(now.timeIntervalSince(since) / 3600, 1.0 / 12)
            s.burnPerHour = Int(Double(recent) / hours)
            if let limit = blockLimit, limit > 0 {
                s.blockFraction = Double(blockTokens) / Double(limit)
                if blockTokens >= limit {
                    s.limitReachedAt = now
                } else if s.burnPerHour > 0 {
                    let at = now.addingTimeInterval(Double(limit - blockTokens) / Double(s.burnPerHour) * 3600)
                    s.limitReachedAt = at < start.addingTimeInterval(blockLength) ? at : nil
                }
            }
        }

        let dayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
        let week = sorted.filter { $0.date >= weekStart && $0.date <= now }
        s.weekTokens = week.reduce(0) { $0 + $1.tokens }
        s.todayTokens = week.filter { $0.date >= dayStart }.reduce(0) { $0 + $1.tokens }
        if let limit = weekLimit, limit > 0 { s.weekFraction = Double(s.weekTokens) / Double(limit) }
        s.byDay = (0..<7).map { offset in
            let start = calendar.date(byAdding: .day, value: offset - 6, to: dayStart) ?? dayStart
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return week.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.tokens }
        }
        var projects: [String: Int] = [:]
        for e in week { projects[e.project, default: 0] += e.tokens }
        s.byProject = projects.map { .init(name: $0.key, tokens: $0.value) }.sorted { $0.tokens > $1.tokens }
        return s
    }

    /// Which alert (if any) to raise for a window fraction: 0.8 or 0.95.
    public static func alertLevel(for fraction: Double?) -> Double? {
        guard let fraction else { return nil }
        if fraction >= 0.95 { return 0.95 }
        if fraction >= 0.8 { return 0.8 }
        return nil
    }

    /// "1.2M", "48k", "900".
    public static func short(_ tokens: Int) -> String {
        switch tokens {
        case 1_000_000...: String(format: "%.1fM", Double(tokens) / 1_000_000)
        case 10_000...: "\(tokens / 1000)k"
        case 1000...: String(format: "%.1fk", Double(tokens) / 1000)
        default: "\(tokens)"
        }
    }
}

/// Reads the agents' logs incrementally: each file is read from where the
/// last scan stopped, only complete lines, only files changed recently.
/// Keeps numbers only (see `UsageLineParser`). Not thread-safe: use from one
/// queue at a time.
public final class UsageScanner: @unchecked Sendable {
    public let claudeRoot: URL
    public let codexRoot: URL
    public var keepDays: Double = 8

    private var offsets: [String: UInt64] = [:]
    private var seenIds: Set<String> = []
    public private(set) var entries: [UsageEntry] = []

    public init(claudeRoot: URL, codexRoot: URL) {
        self.claudeRoot = claudeRoot
        self.codexRoot = codexRoot
    }

    public static var standard: UsageScanner {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return UsageScanner(claudeRoot: home.appendingPathComponent(".claude/projects"), codexRoot: home.appendingPathComponent(".codex/sessions"))
    }

    /// Reads what's new. Returns true when anything changed.
    @discardableResult
    public func scan(now: Date = Date()) -> Bool {
        let cutoff = now.addingTimeInterval(-keepDays * 86_400)
        var changed = false
        for (url, source) in files(changedAfter: cutoff) {
            changed = read(url, source: source) || changed
        }
        let before = entries.count
        entries.removeAll { $0.date < cutoff }
        return changed || entries.count != before
    }

    public func entries(for source: UsageSource) -> [UsageEntry] { entries.filter { $0.source == source } }

    private func files(changedAfter cutoff: Date) -> [(URL, UsageSource)] {
        var found: [(URL, UsageSource)] = []
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        func recent(_ url: URL) -> Bool {
            let values = try? url.resourceValues(forKeys: Set(keys))
            return values?.isRegularFile == true && (values?.contentModificationDate ?? .distantPast) >= cutoff
        }
        // Claude Code: projects/<project>/<session>.jsonl
        for project in (try? fm.contentsOfDirectory(at: claudeRoot, includingPropertiesForKeys: nil)) ?? [] {
            for file in (try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: keys)) ?? []
            where file.pathExtension == "jsonl" && recent(file) {
                found.append((file, .claude))
            }
        }
        // Codex: sessions/YYYY/MM/DD/rollout-*.jsonl
        if let walker = fm.enumerator(at: codexRoot, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            for case let file as URL in walker where file.pathExtension == "jsonl" && file.lastPathComponent.hasPrefix("rollout-") && recent(file) {
                found.append((file, .codex))
            }
        }
        return found
    }

    private static let chunk = 4 << 20
    private static let claudeMarker = Array(#""output_tokens""#.utf8)
    private static let codexMarker = Array(#""token_count""#.utf8)

    /// Reads new complete lines in 4 MB chunks. Lines without a usage marker
    /// are skipped as bytes, without being decoded.
    private func read(_ url: URL, source: UsageSource) -> Bool {
        let path = url.path
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        var offset = offsets[path] ?? 0
        if size < offset { offset = 0 }   // the file was replaced
        guard size > offset else { return false }
        try? handle.seek(toOffset: offset)
        let marker = source == .claude ? Self.claudeMarker : Self.codexMarker
        var added = false
        var carry = Data()
        while offset + UInt64(carry.count) < size {
            guard let data = try? handle.read(upToCount: Self.chunk), !data.isEmpty else { break }
            var buffer = carry
            buffer.append(data)
            let (lines, consumed) = Self.matchingLines(in: buffer, marker: marker)
            carry = consumed < buffer.count ? Data(buffer[(buffer.startIndex + consumed)...]) : Data()
            offset += UInt64(consumed)
            for text in lines { added = ingest(text, source: source) || added }
        }
        // Only complete lines count; a half-written last line is read next time.
        offsets[path] = offset
        return added
    }

    /// Complete lines containing `marker`, found with memchr/memmem (logs are
    /// hundreds of MB; most lines are prompts and replies we skip). Also
    /// returns how many bytes of complete lines were consumed.
    static func matchingLines(in buffer: Data, marker: [UInt8]) -> (lines: [String], consumed: Int) {
        buffer.withUnsafeBytes { raw -> ([String], Int) in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return ([], 0) }
            let count = raw.count
            var lines: [String] = []
            var start = 0
            while start < count, let newline = memchr(base + start, 0x0A, count - start) {
                let end = UnsafeRawPointer(newline).assumingMemoryBound(to: UInt8.self) - base
                let length = end - start
                if length > 0, memmem(base + start, length, marker, marker.count) != nil {
                    lines.append(String(decoding: UnsafeBufferPointer(start: base + start, count: length), as: UTF8.self))
                }
                start = end + 1
            }
            return (lines, start)
        }
    }

    private func ingest(_ text: String, source: UsageSource) -> Bool {
        switch source {
        case .claude:
            guard let (id, entry) = UsageLineParser.claude(text) else { return false }
            if let id {
                guard !seenIds.contains(id) else { return false }
                seenIds.insert(id)
            }
            entries.append(entry)
        case .codex:
            guard let entry = UsageLineParser.codex(text) else { return false }
            entries.append(entry)
        }
        return true
    }
}
