import NovaKit
import SwiftUI

/// Claude Code and Codex token use from their logs on this Mac, with the
/// limits you set (the real plan limits aren't published as token counts).
struct UsageSettings: View {
    let usage: UsageService

    var body: some View {
        SettingsHeader(title: "Usage & limits", subtitle: "Read from Claude Code and Codex logs on this Mac. Only numbers are read; prompts and code are never kept.")
        ForEach(UsageSource.allCases, id: \.self) { source in
            SourceCard(usage: usage, source: source)
        }
        Text("Plans don't publish their limits in tokens, so set yours from experience: when you next hit a limit, click “Use my largest window”. Nova then warns you at 80% and 95%.")
            .font(.caption).foregroundStyle(.secondary)
            .task { await usage.scan() }
    }
}

private struct SourceCard: View {
    let usage: UsageService
    let source: UsageSource
    @ViewState private var blockText = ""
    @ViewState private var weekText = ""

    var body: some View {
        let s = usage.summaries[source]
        SettingsCard(title: UsageService.name(source), symbol: source == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right") {
            if let s {
                HStack(spacing: 18) {
                    stat("This window", UsageMath.short(s.blockTokens), s.blockEnd.map { "resets \($0.formatted(date: .omitted, time: .shortened))" })
                    stat("Today", UsageMath.short(s.todayTokens), nil)
                    stat("7 days", UsageMath.short(s.weekTokens), nil)
                    stat("Burn rate", UsageMath.short(s.burnPerHour) + "/h", nil)
                }
                if let fraction = s.blockFraction {
                    ProgressView(value: min(fraction, 1)) {
                        Text("\(Int(fraction * 100))% of your 5-hour limit" + (s.limitReachedAt.map { " · at this pace, reached around \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
                            .font(.caption)
                    }
                    .tint(fraction >= 0.95 ? Theme.error : fraction >= 0.8 ? Theme.warning : Theme.success)
                }
                DayBars(values: s.byDay).frame(height: 44)
                if !s.byProject.isEmpty {
                    Text("Top projects: " + s.byProject.prefix(4).map { "\($0.name) \(UsageMath.short($0.tokens))" }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("No usage in the last 7 days.").font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text("5-hour limit").frame(width: 100, alignment: .leading)
                TextField("tokens, e.g. 2000000", text: $blockText).textFieldStyle(.roundedBorder).frame(maxWidth: 170)
                    .onSubmit { usage.setBlockLimit(Int(blockText.filter(\.isNumber)) ?? 0, for: source) }
                if let largest = s?.largestBlock, largest > 0 {
                    Button("Use my largest window (\(UsageMath.short(largest)))") {
                        usage.setBlockLimit(largest, for: source)
                        blockText = String(largest)
                    }
                }
            }
            HStack {
                Text("Weekly limit").frame(width: 100, alignment: .leading)
                TextField("tokens (optional)", text: $weekText).textFieldStyle(.roundedBorder).frame(maxWidth: 170)
                    .onSubmit { usage.setWeekLimit(Int(weekText.filter(\.isNumber)) ?? 0, for: source) }
            }
        }
        .onAppear {
            let b = usage.blockLimit(source), w = usage.weekLimit(source)
            blockText = b > 0 ? String(b) : ""
            weekText = w > 0 ? String(w) : ""
        }
    }

    private func stat(_ title: String, _ value: String, _ note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            if let note { Text(note).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

/// Last 7 days, oldest first.
private struct DayBars: View {
    let values: [Int]

    var body: some View {
        let top = max(values.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(index == values.count - 1 ? Theme.cyan : Theme.cyan.opacity(0.45))
                        .frame(height: max(2, 30 * CGFloat(value) / CGFloat(top)))
                    Text(Self.day(offset: values.count - 1 - index)).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    static func day(offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
        return offset == 0 ? "Today" : date.formatted(.dateTime.weekday(.abbreviated))
    }
}
