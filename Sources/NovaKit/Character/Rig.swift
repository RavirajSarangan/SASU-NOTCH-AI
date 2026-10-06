import Foundation

// Nova 2's rig: the joints, their limits and springs, and the pose each mood
// aims for. Pure maths, shared by the app renderer and the tests. Numbers
// match the approved web prototype (docs/character/index.html).

/// The 18 moods; raw values match the app's `NovaExpression`.
public enum RigMood: String, CaseIterable, Sendable {
    case idle, happy, thinking, coding, typing, listening, surprised, warning, error
    case sleepy, sleeping, excited, confused, annoyed, success, loading, dizzy, notification
}

public enum RigVariant: String, CaseIterable, Sendable { case pearl, peek, orbit }

public enum RigEyes: String, CaseIterable, Sendable {
    case pill, arc, closed, half, focus, tall, wide, lookup, x, flat, uneven, dots, spiral, hum
}

/// Optional colour override for eyes or chest light.
public enum RigTint: String, Sendable { case none, amber, coral, mint }

/// Small symbols drawn next to Nova for some moods.
public enum RigFX: String, Sendable { case dots, code, waves, bang, sweat, zzz, question, badge, stars }

public enum RigTailMode: Sendable { case normal, fast, still }

public enum RigPaws: String, Sendable {
    case rest, type, wave, up, chin, cover
    /// Arm angles in degrees (left, right); 0 hangs straight down.
    public var angles: (left: Double, right: Double) {
        switch self {
        case .rest: (12, -12)
        case .type: (-6, 6)
        case .wave: (12, -132)
        case .up: (128, -128)
        case .chin: (12, 132)
        case .cover: (-158, 158)
        }
    }
}

public enum RigJoint: String, CaseIterable, Sendable {
    case tilt, turn, hy, earL, earR, gx, gy, pawL, pawR, tail, sy, dy, bx, lean, chest

    /// Spring stiffness and damping ratio. Lower damping = more overshoot:
    /// ears and tail are loose so they follow through; the head is firm.
    public var spring: (stiffness: Double, damping: Double) {
        switch self {
        case .tilt: (140, 0.8)
        case .turn: (170, 0.9)
        case .hy: (260, 0.5)
        case .earL, .earR: (110, 0.3)
        case .gx, .gy: (700, 1)
        case .pawL, .pawR: (130, 0.5)
        case .tail: (45, 0.28)
        case .sy: (320, 0.32)
        case .dy: (240, 0.45)
        case .bx: (160, 0.6)
        case .lean: (90, 0.4)
        case .chest: (60, 1)
        }
    }

    /// Hard limits, so no input combination can tear the character apart.
    public var limits: ClosedRange<Double> {
        switch self {
        case .tilt: -24...24
        case .turn: -1.3...1.3
        case .hy: -12...12
        case .earL, .earR: -34...34
        case .gx, .gy: -1.3...1.3
        case .pawL, .pawR: -180...180
        case .tail: -70...70
        case .sy: 0.7...1.3
        case .dy: -40...16
        case .bx: -24...24
        case .lean: -30...30
        case .chest: 0...3.5
        }
    }
}

/// One value per joint. `sy` is vertical squash (1 = rest); everything else rests at 0.
public struct RigPose: Equatable, Sendable {
    public var tilt = 0.0, turn = 0.0, hy = 0.0, earL = 0.0, earR = 0.0, gx = 0.0, gy = 0.0
    public var pawL = 12.0, pawR = -12.0, tail = 0.0, sy = 1.0, dy = 0.0, bx = 0.0, lean = 0.0, chest = 1.0

    public init() {}

    public subscript(_ j: RigJoint) -> Double {
        get {
            switch j {
            case .tilt: tilt
            case .turn: turn
            case .hy: hy
            case .earL: earL
            case .earR: earR
            case .gx: gx
            case .gy: gy
            case .pawL: pawL
            case .pawR: pawR
            case .tail: tail
            case .sy: sy
            case .dy: dy
            case .bx: bx
            case .lean: lean
            case .chest: chest
            }
        }
        set {
            switch j {
            case .tilt: tilt = newValue
            case .turn: turn = newValue
            case .hy: hy = newValue
            case .earL: earL = newValue
            case .earR: earR = newValue
            case .gx: gx = newValue
            case .gy: gy = newValue
            case .pawL: pawL = newValue
            case .pawR: pawR = newValue
            case .tail: tail = newValue
            case .sy: sy = newValue
            case .dy: dy = newValue
            case .bx: bx = newValue
            case .lean: lean = newValue
            case .chest: chest = newValue
            }
        }
    }

    public func clamped() -> RigPose {
        var p = self
        for j in RigJoint.allCases { p[j] = min(max(p[j], j.limits.lowerBound), j.limits.upperBound) }
        return p
    }
}

/// What a mood looks like at rest.
public struct MoodTarget: Sendable {
    public var pose: RigPose
    public var eyes: RigEyes
    public var eyeTint: RigTint = .none
    public var chestTint: RigTint = .none
    public var paws: RigPaws
    public var tail: RigTailMode
    public var fx: RigFX?
    public var hop = false
}

public extension RigMood {
    var target: MoodTarget {
        // (eyes, tilt, turn, earL, earR, gaze, paws, tail)
        func t(_ eyes: RigEyes, _ tilt: Double, _ turn: Double, _ earL: Double, _ earR: Double, _ gaze: Double,
               _ paws: RigPaws, _ tail: RigTailMode, fx: RigFX? = nil, eye: RigTint = .none, chest: RigTint = .none,
               drop: Double = 0, hop: Bool = false) -> MoodTarget {
            var p = RigPose()
            p.tilt = tilt; p.turn = turn; p.earL = earL; p.earR = earR; p.gx = gaze; p.dy = drop
            (p.pawL, p.pawR) = paws.angles
            return MoodTarget(pose: p, eyes: eyes, eyeTint: eye, chestTint: chest, paws: paws, tail: tail, fx: fx, hop: hop)
        }
        switch self {
        case .idle: return t(.pill, 0, 0, 0, 0, 0, .rest, .normal)
        case .happy: return t(.arc, -5, 0, 8, 8, 0, .rest, .fast, chest: .mint)
        case .thinking: return t(.lookup, 9, 0.3, -2, 6, 0.5, .chin, .normal, fx: .dots)
        case .coding: return t(.focus, 0, 0, 4, 4, 0, .type, .still, fx: .code)
        case .typing: return t(.focus, 3, -0.2, 2, 2, -0.3, .type, .still)
        case .listening: return t(.tall, -9, -0.25, 14, 10, -0.4, .rest, .normal, fx: .waves)
        case .surprised: return t(.wide, 0, 0, 16, 16, 0, .cover, .still, fx: .bang)
        case .warning: return t(.pill, 4, 0, -6, -4, 0, .rest, .still, fx: .sweat, eye: .amber, chest: .amber)
        case .error: return t(.x, 6, 0, -16, -16, 0, .cover, .still, eye: .coral, chest: .coral)
        case .sleepy: return t(.half, 7, 0, -10, -8, 0, .rest, .normal)
        case .sleeping: return t(.closed, 11, 0, -18, -18, 0, .rest, .still, fx: .zzz, drop: 6)
        case .excited: return t(.arc, 0, 0, 15, 15, 0, .up, .fast, hop: true)
        case .confused: return t(.uneven, -12, 0.2, 10, -10, 0.2, .rest, .normal, fx: .question)
        case .annoyed: return t(.flat, 0, 0.35, -9, -9, 0.6, .rest, .fast)
        case .success: return t(.arc, -4, 0, 12, 12, 0, .wave, .fast, eye: .mint, chest: .mint, hop: true)
        case .loading: return t(.dots, 0, 0, 3, 3, 0, .rest, .normal)
        case .dizzy: return t(.spiral, 13, 0, 6, -12, 0, .rest, .still, fx: .stars)
        case .notification: return t(.pill, -4, 0, 12, 12, 0, .wave, .normal, fx: .badge)
        }
    }
}

/// Damped spring for one joint, integrated in small fixed steps so it stays
/// stable at any frame rate.
public struct SpringState: Sendable, Equatable {
    public var x: Double
    public var v: Double = 0
    public init(_ x: Double) { self.x = x }

    public mutating func step(toward target: Double, dt: Double, stiffness k: Double, damping z: Double) {
        let c = 2 * z * k.squareRoot()
        var remaining = dt
        while remaining > 1e-9 {
            let h = min(remaining, 1.0 / 240)
            v += (k * (target - x) - c * v) * h
            x += v * h
            remaining -= h
        }
    }
}

/// The animated background behind Nova for each situation.
public enum RigScene: String, CaseIterable, Sendable {
    case aurora, code, thinking, music, success, error, warning, guarding, night

    public static func scene(for mood: RigMood, dancing: Bool, guardAlert: Bool) -> RigScene {
        if guardAlert { return .guarding }
        if dancing { return .music }
        switch mood {
        case .coding, .typing: return .code
        case .thinking, .loading, .confused, .dizzy: return .thinking
        case .success, .excited: return .success
        case .error: return .error
        case .warning, .annoyed: return .warning
        case .sleeping, .sleepy: return .night
        case .idle, .happy, .listening, .surprised, .notification: return .aurora
        }
    }
}
