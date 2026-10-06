import Foundation

/// Smoothstep-interpolated keyframes: `[(u, value)]` sorted by u in 0…1.
public enum Keyframes {
    public static func value(_ u: Double, _ points: [(Double, Double)]) -> Double {
        guard let first = points.first else { return 0 }
        if u <= first.0 { return first.1 }
        for i in 1..<points.count where u <= points[i].0 {
            let (u0, v0) = points[i - 1], (u1, v1) = points[i]
            let s = (u - u0) / max(u1 - u0, 1e-9), e = s * s * (3 - 2 * s)
            return v0 + (v1 - v0) * e
        }
        return points[points.count - 1].1
    }
}

/// What a reaction does to the target pose at one moment.
public struct RigEffect: Sendable {
    public var add: [RigJoint: Double] = [:]
    public var mul: [RigJoint: Double] = [:]
    /// Blend toward a value: (value, weight 0…1).
    public var to: [RigJoint: (Double, Double)] = [:]
    /// Override outright (gaze).
    public var set: [RigJoint: Double] = [:]
    public var eyes: RigEyes?

    public func apply(to p: inout RigPose, overrides: inout [RigJoint: Double], eyes e: inout RigEyes?) {
        for (j, v) in add { p[j] += v }
        for (j, v) in mul { p[j] *= v }
        for (j, (v, w)) in to { p[j] += (v - p[j]) * w }
        for (j, v) in set { overrides[j] = v }
        if let eyes { e = eyes }
    }
}

/// Moments inside a reaction that make a sound or particles.
public enum RigEvent: String, Sendable { case pop, chime, knock, boop, burst, drops, stamp }

/// One-shot gestures (wind-up → action → follow-through → settle) and idle fidgets.
public enum RigReaction: String, CaseIterable, Sendable {
    case hop, aha, startle, flinch, cheer, nod, headShake, knock, boop, stretch, yawn, shakeOff, stamp, spinHop
    case earFlick, tailCurl, lookAround, groom, peekEdge, hum

    public static let fidgets: [RigReaction] = [.earFlick, .tailCurl, .lookAround, .groom, .peekEdge, .hum, .stretch, .yawn]
    /// Fidgets that only happen after a couple of quiet minutes.
    public static let slowFidgets: Set<RigReaction> = [.stretch, .yawn]

    public var duration: Double {
        switch self {
        case .hop: 0.75
        case .aha, .shakeOff: 1.1
        case .startle, .nod, .headShake, .stamp: 0.9
        case .flinch, .tailCurl: 1.5
        case .cheer: 1.6
        case .knock: 1.3
        case .boop: 0.55
        case .stretch, .yawn: 2.2
        case .spinHop: 1.0
        case .earFlick: 0.6
        case .lookAround: 2.6
        case .groom: 2.0
        case .peekEdge: 1.8
        case .hum: 2.4
        }
    }

    public var events: [(Double, RigEvent)] {
        switch self {
        case .hop: [(0.12, .pop)]
        case .aha: [(0.2, .burst), (0.2, .chime)]
        case .startle: [(0.04, .pop)]
        case .flinch: [(0.06, .boop)]
        case .cheer: [(0.25, .burst), (0.25, .chime), (0.62, .burst)]
        case .knock: [(0.3, .knock), (0.5, .knock), (0.7, .knock)]
        case .boop: [(0, .boop)]
        case .shakeOff: [(0.1, .drops)]
        case .stamp: [(0.2, .stamp)]
        case .spinHop: [(0.12, .pop), (0.3, .burst)]
        default: []
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public func effect(at u: Double) -> RigEffect {
        let k = Keyframes.value
        var e = RigEffect()
        switch self {
        case .hop:
            e.mul[.sy] = k(u, [(0, 1), (0.15, 0.86), (0.3, 1.08), (0.62, 1.02), (0.72, 0.9), (0.86, 1.03), (1, 1)])
            e.add[.dy] = k(u, [(0, 0), (0.15, 3), (0.34, -22), (0.5, -24), (0.68, 0), (1, 0)])
        case .aha:
            let ear = k(u, [(0, 0), (0.1, -6), (0.25, 18), (1, 0)])
            e.add = [.earL: ear, .earR: ear, .chest: k(u, [(0, 0), (0.2, 1.6), (1, 0)])]
            e.mul[.sy] = k(u, [(0, 1), (0.12, 0.94), (0.28, 1.06), (1, 1)])
            e.eyes = u < 0.3 ? .wide : (u < 1 ? .arc : nil)
        case .startle:
            let w = k(u, [(0, 0), (0.1, 1), (0.55, 1), (1, 0)]), ear = k(u, [(0, 0), (0.08, 20), (1, 0)])
            e.add = [.dy: k(u, [(0, 0), (0.08, -14), (0.3, 0)]), .earL: ear, .earR: ear]
            e.to = [.pawL: (128, w), .pawR: (-128, w)]
            if u < 0.65 { e.eyes = .wide }
        case .flinch:
            let w = k(u, [(0, 0), (0.12, 1), (0.8, 1), (1, 0)])
            e.add = [.tilt: 9 * w, .earL: -18 * w, .earR: -18 * w]
            e.mul[.sy] = 1 - 0.07 * w
            e.to = [.pawL: (-158, w), .pawR: (158, w)]
            if u < 0.85 { e.eyes = .closed }
        case .cheer:
            let w = k(u, [(0, 0), (0.1, 1), (0.85, 1), (1, 0)])
            e.to = [.pawL: (128, w), .pawR: (-128, w)]
            e.add = [.dy: k(u, [(0, 0), (0.12, 2), (0.25, -18), (0.4, 0), (0.5, 2), (0.62, -18), (0.78, 0), (1, 0)]),
                     .earL: 10 * w, .earR: 10 * w]
            e.mul[.sy] = k(u, [(0, 1), (0.12, 0.9), (0.22, 1.06), (0.4, 0.92), (0.5, 0.9), (0.6, 1.06), (0.78, 0.92), (0.9, 1)])
            if u < 1 { e.eyes = .arc }
        case .nod:
            e.add[.hy] = k(u, [(0, 0), (0.15, 4), (0.3, -1), (0.45, 4), (0.6, -1), (0.75, 3), (1, 0)])
            e.set[.gy] = k(u, [(0, 0), (0.15, 0.5), (0.3, 0), (0.45, 0.5), (0.6, 0), (1, 0)])
        case .headShake:
            e.add[.turn] = k(u, [(0, 0), (0.15, -0.5), (0.35, 0.5), (0.55, -0.45), (0.75, 0.3), (1, 0)])
        case .knock:
            let w = k(u, [(0, 0), (0.15, 1), (0.85, 1), (1, 0)])
            e.to[.pawR] = (-112, w)
            e.add[.pawR] = k(u, [(0.2, 0), (0.27, -24), (0.3, 0), (0.47, -24), (0.5, 0), (0.67, -24), (0.7, 0), (1, 0)])
            e.set = [.gx: 0, .gy: 0]
        case .boop:
            let ear = k(u, [(0, 0), (0.1, -9), (1, 0)])
            e.mul[.sy] = k(u, [(0, 1), (0.12, 0.86), (0.4, 1.04), (1, 1)])
            e.add = [.earL: ear, .earR: ear]
            if u < 0.85 { e.eyes = .flat; e.set[.gx] = 0.6 }
        case .stretch:
            let w = k(u, [(0, 0), (0.25, 1), (0.7, 1), (1, 0)])
            e.to = [.pawL: (128, w), .pawR: (-128, w)]
            e.mul[.sy] = 1 + 0.08 * w
            e.add = [.dy: -4 * w, .earL: 10 * w, .earR: 10 * w, .tilt: -4 * w]
            if u > 0.2 && u < 0.8 { e.eyes = .closed }
        case .yawn:
            let w = k(u, [(0, 0), (0.3, 1), (0.7, 1), (1, 0)]), pw = k(u, [(0.3, 0), (0.45, 1), (0.7, 1), (0.85, 0)])
            e.add = [.tilt: -9 * w, .earL: -10 * w, .earR: -10 * w]
            e.mul[.sy] = 1 + 0.05 * w
            e.to[.pawR] = (150, pw)
            if u > 0.2 && u < 0.85 { e.eyes = .closed }
        case .shakeOff:
            let l = k(u, [(0, 0), (0.1, 8), (0.25, -8), (0.4, 7), (0.55, -6), (0.7, 4), (1, 0)])
            e.add = [.lean: l, .tilt: l * 0.8]
            e.eyes = u < 0.7 ? .closed : (u < 1 ? .arc : nil)
        case .stamp:
            e.add = [.chest: k(u, [(0, 0), (0.2, 2.2), (1, 0)]), .hy: k(u, [(0, 0), (0.2, 3), (0.45, 0)])]
        case .spinHop:
            e.add = [.dy: k(u, [(0, 0), (0.12, 3), (0.35, -26), (0.6, -20), (0.8, 0)]),
                     .turn: k(u, [(0, 0), (0.2, -1), (0.4, 1), (0.6, -1), (0.8, 0)])]
            e.mul[.sy] = k(u, [(0, 1), (0.12, 0.85), (0.3, 1.08), (0.8, 0.9), (1, 1)])
            if u < 1 { e.eyes = .arc }
        case .earFlick:
            e.add[.earR] = k(u, [(0, 0), (0.2, -16), (0.45, 10), (1, 0)])
        case .tailCurl:
            e.add[.tail] = k(u, [(0, 0), (0.35, 34), (0.7, 30), (1, 0)])
        case .lookAround:
            e.set[.gx] = k(u, [(0, 0), (0.15, -0.8), (0.45, -0.8), (0.6, 0.8), (0.85, 0.8), (1, 0)])
            e.add[.turn] = k(u, [(0, 0), (0.2, -0.45), (0.45, -0.45), (0.65, 0.45), (0.85, 0.45), (1, 0)])
        case .groom:
            let w = k(u, [(0, 0), (0.2, 1), (0.8, 1), (1, 0)])
            e.to[.pawR] = (132, w)
            e.add = [.pawR: 6 * sin(u * 40) * w, .tilt: 5 * w]
            if w > 0.5 { e.eyes = .closed }
        case .peekEdge:
            let w = k(u, [(0, 0), (0.25, 1), (0.75, 1), (1, 0)])
            e.set[.gy] = 0.9 * w
            e.add = [.hy: 3 * w, .tilt: 2 * w]
        case .hum:
            e.add[.tilt] = 3 * sin(u * .pi * 4)
            if u > 0.1 && u < 0.9 { e.eyes = .hum }
        }
        return e
    }
}

/// Gesture played on the way from one mood to another.
public enum RigBridge {
    public static func reaction(from a: RigMood, to b: RigMood) -> RigReaction? {
        let sleepy: Set<RigMood> = [.sleeping, .sleepy]
        if sleepy.contains(a) && !sleepy.contains(b) { return .startle }
        if a == .thinking && (b == .success || b == .happy) { return .aha }
        switch b {
        case .error: return .flinch
        case .success: return .cheer
        case .surprised: return .startle
        case .confused, .dizzy: return .headShake
        case .excited, .happy, .listening: return .hop
        default: return nil
        }
    }
}

/// Small deterministic random source (SplitMix64), so motion can be tested.
public struct RigRandom: Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

/// Picks idle fidgets: never one of the last two, slow ones only after two
/// quiet minutes, stretch favoured in the morning and yawns late at night.
public struct FidgetScheduler: Sendable {
    public private(set) var recent: [RigReaction] = []

    public init() {}

    public mutating func pick(idleSeconds: Double, hour: Int, random: inout RigRandom) -> RigReaction {
        let lastTwo = Set(recent.suffix(2))
        var pool = RigReaction.fidgets.filter {
            !lastTwo.contains($0) && (!RigReaction.slowFidgets.contains($0) || idleSeconds >= 120)
        }
        if pool.isEmpty { pool = [.earFlick] }
        let weights = pool.map { r -> Double in
            if r == .stretch && (5..<11).contains(hour) { return 3 }
            if r == .yawn && (hour >= 22 || hour < 4) { return 3 }
            return 1
        }
        var roll = random.next() * weights.reduce(0, +)
        var choice = pool[0]
        for (r, w) in zip(pool, weights) {
            roll -= w
            if roll <= 0 { choice = r; break }
        }
        recent.append(choice)
        if recent.count > 4 { recent.removeFirst() }
        return choice
    }

    /// Seconds until the next fidget: 6–14 s.
    public static func gap(_ random: inout RigRandom) -> Double { 6 + random.next() * 8 }
}
