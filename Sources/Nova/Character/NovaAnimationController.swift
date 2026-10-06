import SwiftUI

/// One frame of Nova's animation.
struct NovaFrame {
    var breath: CGFloat = 1          // vertical scale from breathing
    var eyes = EyeParameters()       // eased toward the current mood
    var blink: CGFloat = 1           // 1 open … 0 closed
    var gaze: CGPoint = .zero        // smoothed, unit disk, +y down
    var time: TimeInterval = 0
    /// Seconds since the current mood started (drives one-shot reactions/effects).
    var age: TimeInterval = 10
    var body = BodyMotion.rest
}

/// Nova's motion: slow breathing, eased mood changes, natural blinks, smooth
/// (critically damped) eye tracking, plus a short body reaction when the
/// mood changes (see `NovaMotion`).
@MainActor
final class NovaAnimationController {
    private var eyes: EyeParameters?
    private var gaze: CGPoint = .zero
    private var gazeVelocity: CGPoint = .zero
    private var lastTime: TimeInterval?
    private var blinks = BlinkSchedule()
    private var expression: NovaExpression?
    private var enteredAt: TimeInterval = -10

    /// Mood transitions settle in about 0.25 s.
    static let moodTimeConstant = 0.08
    /// Eye-tracking spring stiffness (critically damped).
    static let gazeStiffness: CGFloat = 60

    /// `motion` scales breathing (0 = still).
    func frame(at time: TimeInterval, gazeTarget: CGPoint, expression: NovaExpression,
               reduceMotion: Bool, motion: Double = 1, reactions: Bool = true) -> NovaFrame {
        let dt = min(max(time - (lastTime ?? time), 0), 0.1)
        lastTime = time
        if expression != self.expression {
            // On the first frame, treat the mood as settled so nothing fires at launch.
            enteredAt = self.expression == nil ? time - 10 : time
            self.expression = expression
        }
        let age = time - enteredAt

        let target = EyeParameters.target(for: expression)
        let current = eyes ?? target
        let t = reduceMotion ? 1 : 1 - exp(-dt / Self.moodTimeConstant)
        let next = current.approaching(target, t)
        eyes = next

        var f = NovaFrame(eyes: next, time: time, age: age)
        if reactions, !reduceMotion, motion > 0 {
            f.body = NovaMotion.motion(for: expression, age: age, time: time, intensity: motion)
        }
        f.blink = next.canBlink ? CGFloat(blinks.openness(at: time)) : 1

        var lookAt = next.gaze ?? gazeTarget
        if next.sweep { lookAt = CGPoint(x: sin(time * 1.4) * 0.8, y: 0) }
        if reduceMotion {
            gaze = lookAt
        } else {
            // Critically damped spring: smooth, no overshoot, no jitter.
            let k = Self.gazeStiffness, c = 2 * sqrt(k)
            let ax = k * (lookAt.x - gaze.x) - c * gazeVelocity.x
            let ay = k * (lookAt.y - gaze.y) - c * gazeVelocity.y
            gazeVelocity.x += ax * dt
            gazeVelocity.y += ay * dt
            gaze.x += gazeVelocity.x * dt
            gaze.y += gazeVelocity.y * dt
        }
        f.gaze = gaze

        if !reduceMotion, motion > 0 {
            let period: Double = expression == .sleeping || expression == .sleepy ? 8 : 5.5
            let depth: CGFloat = expression == .sleeping ? 0.014 : 0.006
            f.breath = 1 + depth * CGFloat(motion) * CGFloat(sin(time * 2 * .pi / period))
        }
        return f
    }
}
