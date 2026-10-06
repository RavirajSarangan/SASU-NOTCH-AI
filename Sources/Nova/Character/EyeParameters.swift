import CoreGraphics
import SwiftUI

/// A glow color as plain components so it can be interpolated.
struct EyeTint: Equatable, Sendable {
    var r: Double, g: Double, b: Double

    static let cyan = EyeTint(r: 0.45, g: 0.86, b: 1.0)
    static let mint = EyeTint(r: 0.45, g: 0.95, b: 0.78)
    static let amber = EyeTint(r: 1.0, g: 0.78, b: 0.42)
    static let coral = EyeTint(r: 1.0, g: 0.50, b: 0.50)

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

    func mixed(to other: EyeTint, _ t: Double) -> EyeTint {
        EyeTint(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }
}

/// Everything that defines how Nova's eyes look at a moment. Moods map to a
/// target, and the animation controller eases the current value toward it,
/// so expressions morph instead of popping.
struct EyeParameters: Equatable, Sendable {
    /// Height factor of the eye (1 = default pill, ~0.06 = closed line).
    var openness: Double = 1
    /// Flat cut from the top (0 = none … 0.6 = strong squint).
    var topLid: Double = 0
    /// Lower arc cut that turns the pill into a soft smile (0 … 1).
    var smile: Double = 0
    /// Overall eye size.
    var scale: Double = 1
    /// Right eye openness relative to the left (for "confused").
    var rightEyeFactor: Double = 1
    var tint: EyeTint = .cyan
    /// Glow intensity (0 … 1).
    var glow: Double = 0.7
    /// Fixed look direction (unit disk, +y down); nil = follow the cursor.
    var gaze: CGPoint?
    /// Gentle side-to-side look (loading).
    var sweep = false

    static func target(for expression: NovaExpression) -> EyeParameters {
        var p = EyeParameters()
        switch expression {
        case .idle:
            break
        case .listening:
            p.openness = 1.05
            p.glow = 0.9
        case .thinking:
            p.openness = 0.9
            p.gaze = CGPoint(x: 0.6, y: -0.7)
        case .coding, .typing:
            p.openness = 0.78
            p.topLid = 0.22
            p.gaze = CGPoint(x: 0.1, y: 0.75)
        case .happy, .excited:
            p.smile = 0.8
            p.scale = 1.08
            p.openness = 0.72
            p.glow = 0.85
        case .success:
            p.smile = 0.8
            p.scale = 1.08
            p.openness = 0.72
            p.tint = .mint
            p.glow = 0.9
        case .sleepy:
            p.openness = 0.35
            p.glow = 0.4
            p.gaze = CGPoint(x: 0, y: 0.4)
        case .sleeping:
            p.openness = 0.06
            p.glow = 0.3
            p.gaze = .zero
        case .warning:
            p.openness = 1.08
            p.tint = .amber
            p.glow = 0.9
        case .notification, .surprised:
            p.openness = 1.08
            p.scale = 1.04
            p.glow = 0.9
        case .error, .dizzy:
            p.openness = 0.7
            p.topLid = 0.15
            p.tint = .coral
            p.glow = 0.85
        case .annoyed:
            p.topLid = 0.45
        case .confused:
            p.openness = 0.95
            p.rightEyeFactor = 0.8
            p.gaze = CGPoint(x: -0.3, y: -0.4)
        case .loading:
            p.sweep = true
        }
        return p
    }

    /// Eases every numeric field toward `target` by `t` (0 … 1).
    func approaching(_ target: EyeParameters, _ t: Double) -> EyeParameters {
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        var p = self
        p.openness = lerp(openness, target.openness)
        p.topLid = lerp(topLid, target.topLid)
        p.smile = lerp(smile, target.smile)
        p.scale = lerp(scale, target.scale)
        p.rightEyeFactor = lerp(rightEyeFactor, target.rightEyeFactor)
        p.tint = tint.mixed(to: target.tint, t)
        p.glow = lerp(glow, target.glow)
        p.gaze = target.gaze
        p.sweep = target.sweep
        return p
    }

    /// Blinks only make sense for open, non-smiling eyes.
    var canBlink: Bool { openness > 0.3 && smile < 0.4 }
}

/// Natural blink timing: cosine-eased close and open, 3.5–7 s apart,
/// with an occasional double blink.
struct BlinkSchedule: Sendable {
    static let closeDuration = 0.11
    static let openDuration = 0.16

    private(set) var nextBlink: TimeInterval = 0
    private(set) var blinkStart: TimeInterval = -10

    /// 1 = open, 0 = closed.
    mutating func openness(at time: TimeInterval, random: () -> Double = { Double.random(in: 0...1) }) -> Double {
        if nextBlink == 0 { nextBlink = time + 1.5 + random() * 2 }
        if time >= nextBlink {
            blinkStart = time
            let isDouble = random() < 0.08
            nextBlink = time + (isDouble ? 0.38 : 3.5 + random() * 3.5)
        }
        let elapsed = time - blinkStart
        if elapsed < 0 || elapsed > Self.closeDuration + Self.openDuration { return 1 }
        if elapsed < Self.closeDuration {
            return 0.5 + 0.5 * cos(.pi * elapsed / Self.closeDuration)
        }
        return 0.5 - 0.5 * cos(.pi * (elapsed - Self.closeDuration) / Self.openDuration)
    }
}
