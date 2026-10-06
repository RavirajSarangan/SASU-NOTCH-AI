import SwiftUI

/// Body transform for one frame (offsets in fractions of the view size).
struct BodyMotion: Equatable {
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var tilt: Double = 0   // degrees

    static let rest = BodyMotion()
}

/// Lively but polished body language. Each mood gets a short one-shot
/// reaction when it starts (hop, shake, pop…) and, for a few moods, a very
/// small ongoing motion. Everything is a pure function of time and settles
/// back to rest, so nothing drifts or jitters.
enum NovaMotion {
    enum Reaction: Equatable {
        case hop, bigHop, shake, pop, nod, tiltHold, droop, none

        /// How long the one-shot part lasts.
        var duration: TimeInterval {
            switch self {
            case .hop: 0.5
            case .bigHop: 0.8
            case .shake: 0.45
            case .pop: 0.4
            case .nod: 0.55
            case .tiltHold, .droop: 0.6
            case .none: 0
            }
        }
    }

    static func reaction(for expression: NovaExpression) -> Reaction {
        switch expression {
        case .happy, .listening: .hop
        case .success, .excited: .bigHop
        case .error, .annoyed, .dizzy: .shake
        case .warning, .notification, .surprised: .pop
        case .typing, .coding: .nod
        case .thinking, .confused: .tiltHold
        case .sleepy, .sleeping: .droop
        case .idle, .loading: .none
        }
    }

    /// `age` = seconds since the mood started.
    static func motion(for expression: NovaExpression, age: TimeInterval, time: TimeInterval, intensity: Double = 1) -> BodyMotion {
        var m = BodyMotion()
        let k = CGFloat(intensity)
        let reaction = reaction(for: expression)
        let u = reaction.duration > 0 ? min(max(age / reaction.duration, 0), 1) : 1
        let fade = CGFloat(1 - u)

        switch reaction {
        case .hop, .bigHop:
            let height: CGFloat = reaction == .bigHop ? 0.09 : 0.05
            if u < 0.18 {                       // crouch
                let s = CGFloat(sin(u / 0.18 * .pi / 2))
                m.scaleY = 1 - 0.07 * s * k
                m.scaleX = 1 + 0.05 * s * k
            } else if u < 0.75 {                // airborne, stretched
                let v = (u - 0.18) / 0.57
                m.dy = -height * CGFloat(sin(v * .pi)) * k
                m.scaleY = 1 + 0.05 * CGFloat(sin(v * .pi)) * k
                m.scaleX = 1 - 0.03 * CGFloat(sin(v * .pi)) * k
            } else if u < 1 {                   // land and settle
                let v = (u - 0.75) / 0.25
                let squash = CGFloat(sin(v * .pi)) * 0.05 * k
                m.scaleY = 1 - squash
                m.scaleX = 1 + squash * 0.7
            }
            if reaction == .bigHop, u < 1 { m.tilt = 6 * sin(u * 2 * .pi) * Double(fade) * intensity }
        case .shake:
            if u < 1 { m.dx = 0.035 * k * CGFloat(sin(age * 2 * .pi * 9)) * fade }
        case .pop:
            if u < 1 {
                // Quick overshoot: 1 → 1.08 → 1.
                let s = CGFloat(sin(u * .pi)) * fade + CGFloat(sin(u * .pi)) * 0.2
                m.scaleX = 1 + 0.07 * s * k
                m.scaleY = 1 + 0.07 * s * k
                m.dy = -0.02 * s * k
            }
        case .nod:
            if u < 1 { m.dy = 0.018 * k * CGFloat(abs(sin(u * 2 * .pi))) * fade }
        case .tiltHold:
            // Ease into a curious head tilt and hold it, with a slow sway.
            let ease = 1 - pow(1 - u, 3)
            m.tilt = (-5 * ease + 1.2 * sin(time * 0.9)) * intensity
        case .droop:
            let ease = 1 - pow(1 - u, 2)
            m.dy = 0.02 * CGFloat(ease) * k
            m.tilt = 3 * ease * intensity
        case .none:
            break
        }

        // Small ongoing motion for "busy" moods.
        switch expression {
        case .typing, .coding:
            if u >= 1 { m.dy += 0.006 * k * CGFloat(abs(sin(time * 2 * .pi * 1.6))) }
        case .loading:
            m.tilt += 2.5 * sin(time * 2.2) * intensity
        case .excited where u >= 1:
            m.dy -= 0.012 * k * CGFloat(abs(sin(time * 2 * .pi * 1.2)))
        default:
            break
        }
        return m
    }
}
