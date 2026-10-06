import Foundation
import NovaKit
import Observation

/// Token usage of Claude Code and Codex from their own logs on this Mac
/// (numbers only), scanned every minute off the main thread.
@Observable
@MainActor
final class UsageService {
    private(set) var summaries: [UsageSource: UsageSummary] = [:]
    private(set) var lastScan: Date?

    /// Called at 80% and 95% of a 5-hour window (once per window and level).
    @ObservationIgnored var onAlert: ((UsageSource, Double, UsageSummary) -> Void)?

    @ObservationIgnored private let scanner = UsageScanner.standard
    @ObservationIgnored private let queue = DispatchQueue(label: "nova.usage", qos: .utility)
    @ObservationIgnored private var alerted: Set<String> = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard

    // MARK: Limits (tokens; 0 = not set)

    func blockLimit(_ source: UsageSource) -> Int { defaults.integer(forKey: "usage.blockLimit.\(source.rawValue)") }
    func weekLimit(_ source: UsageSource) -> Int { defaults.integer(forKey: "usage.weekLimit.\(source.rawValue)") }

    func setBlockLimit(_ value: Int, for source: UsageSource) {
        defaults.set(max(0, value), forKey: "usage.blockLimit.\(source.rawValue)")
        recompute()
    }

    func setWeekLimit(_ value: Int, for source: UsageSource) {
        defaults.set(max(0, value), forKey: "usage.weekLimit.\(source.rawValue)")
        recompute()
    }

    // MARK: Scanning

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scan()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func scan() async {
        let scanner = scanner
        let entries: [UsageEntry]? = await withCheckedContinuation { continuation in
            queue.async {
                let changed = scanner.scan()
                continuation.resume(returning: changed ? scanner.entries : nil)
            }
        }
        lastScan = Date()
        if let entries { latest = entries }
        recompute()
    }

    @ObservationIgnored private var latest: [UsageEntry] = []

    private func recompute() {
        var next: [UsageSource: UsageSummary] = [:]
        for source in UsageSource.allCases {
            let mine = latest.filter { $0.source == source }
            guard !mine.isEmpty else { continue }
            let block = blockLimit(source), week = weekLimit(source)
            next[source] = UsageMath.summary(mine, now: Date(), blockLimit: block > 0 ? block : nil, weekLimit: week > 0 ? week : nil)
        }
        if next != summaries { summaries = next }
        for (source, summary) in next {
            guard let level = UsageMath.alertLevel(for: summary.blockFraction), let start = summary.blockStart else { continue }
            let key = "\(source.rawValue)|\(start.timeIntervalSince1970)|\(level)"
            guard !alerted.contains(key) else { continue }
            alerted.insert(key)
            onAlert?(source, level, summary)
        }
    }

    // MARK: Words

    static func name(_ source: UsageSource) -> String { source == .claude ? "Claude Code" : "Codex" }

    /// "Claude Code: 62% of your 5-hour window, resets at 3:00 PM. At this pace you'd hit it around 2:40 PM."
    func spokenSummary() -> String {
        guard !summaries.isEmpty else { return "I don't see any Claude Code or Codex usage in the last week." }
        return summaries.sorted { $0.key.rawValue < $1.key.rawValue }.map { source, s in
            let name = Self.name(source)
            guard let end = s.blockEnd else { return "\(name): no active window. \(UsageMath.short(s.todayTokens)) tokens today." }
            let reset = end.formatted(date: .omitted, time: .shortened)
            guard let fraction = s.blockFraction else {
                return "\(name): \(UsageMath.short(s.blockTokens)) tokens in this window, resets at \(reset). Set a limit in Settings to see a percentage."
            }
            var line = "\(name): \(Int(fraction * 100))% of your 5-hour window, resets at \(reset)."
            if let hit = s.limitReachedAt, fraction < 1 { line += " At this pace you'd reach it around \(hit.formatted(date: .omitted, time: .shortened))." }
            return line
        }.joined(separator: " ")
    }
}
