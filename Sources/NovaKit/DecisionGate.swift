import Foundation

/// Protects permission decisions from accidental clicks: a request can only
/// be answered once it has been on screen for `armDelay`, and only by a
/// click whose mouse-down happened *after* it appeared (so a click that was
/// already in progress when the panel popped up under the cursor is ignored).
public struct DecisionGate: Sendable, Equatable {
    public static let armDelay: TimeInterval = 0.8

    public var requestId: String
    /// System uptime when the request was first shown.
    public var presentedAt: TimeInterval

    public init(requestId: String, presentedAt: TimeInterval) {
        self.requestId = requestId
        self.presentedAt = presentedAt
    }

    public func isArmed(now: TimeInterval) -> Bool {
        now - presentedAt >= Self.armDelay
    }

    /// - Parameters:
    ///   - now: current system uptime.
    ///   - mouseDownAt: uptime of the click's mouse-down (nil for keyboard).
    public func accepts(requestId: String, now: TimeInterval, mouseDownAt: TimeInterval?) -> Bool {
        guard requestId == self.requestId, isArmed(now: now) else { return false }
        if let mouseDownAt, mouseDownAt < presentedAt + 0.05 { return false }
        return true
    }
}

/// Counts quick taps on Nova: a single poke, or "dizzy" after `threshold`
/// taps within `window` seconds.
public struct RapidTapCounter: Sendable {
    public enum Reaction: Equatable, Sendable { case poke, dizzy }

    public var window: TimeInterval
    public var threshold: Int
    private var taps: [TimeInterval] = []

    public init(window: TimeInterval = 1.2, threshold: Int = 3) {
        self.window = window
        self.threshold = threshold
    }

    public mutating func tap(at time: TimeInterval) -> Reaction {
        taps = taps.filter { time - $0 <= window } + [time]
        guard taps.count >= threshold else { return .poke }
        taps.removeAll()
        return .dizzy
    }
}
