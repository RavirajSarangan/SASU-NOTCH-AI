import Foundation

/// When the daily morning greeting/brief runs, including catch-up after the
/// Mac wakes from sleep (only until the cutoff hour, so nobody gets a
/// "good morning" at 3 pm).
public struct MorningSchedule: Sendable, Equatable, Codable {
    public var hour: Int
    public var minute: Int
    public var cutoffHour: Int

    public init(hour: Int = 7, minute: Int = 30, cutoffHour: Int = 11) {
        self.hour = hour
        self.minute = minute
        self.cutoffHour = cutoffHour
    }

    public func fireDate(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// The next scheduled time strictly after `date`.
    public func nextFire(after date: Date, calendar: Calendar = .current) -> Date {
        let today = fireDate(on: date, calendar: calendar)
        if today > date { return today }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return fireDate(on: tomorrow, calendar: calendar)
    }

    /// Whether to run now: it's past today's time, before the cutoff, and
    /// hasn't already run today.
    public func isDue(now: Date, lastRunDay: String?, calendar: Calendar = .current) -> Bool {
        guard lastRunDay != Self.dayKey(now, calendar: calendar) else { return false }
        guard now >= fireDate(on: now, calendar: calendar) else { return false }
        let cutoff = calendar.date(bySettingHour: cutoffHour, minute: 0, second: 0, of: now) ?? now
        return now < cutoff
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Keeps daily greetings from repeating.
public enum GreetingDeduper {
    public static func normalized(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// True when `candidate` is the same as, or nearly the same as, any recent greeting.
    public static func isTooSimilar(_ candidate: String, to recent: [String], threshold: Double = 0.75) -> Bool {
        let a = Set(normalized(candidate))
        guard !a.isEmpty else { return true }
        return recent.contains { previous in
            let b = Set(normalized(previous))
            guard !b.isEmpty else { return false }
            let jaccard = Double(a.intersection(b).count) / Double(a.union(b).count)
            return jaccard >= threshold
        }
    }
}
