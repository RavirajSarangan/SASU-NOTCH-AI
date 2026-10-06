import Foundation

public struct RigPoint: Sendable, Equatable {
    public var x: Double, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// What's happening around Nova this frame.
public struct RigInputs: Sendable {
    public var mood: RigMood
    public var variant: RigVariant = .pearl
    /// Where to look, in unit offsets from the face (+y down); nil = nothing to look at.
    public var look: RigPoint?
    /// 0…1 from petting.
    public var pet = 0.0
    /// Horizontal drag speed (points/s) while Nova is being dragged; nil when not dragged.
    public var dragVelocity: Double?
    /// 0…1 agent activity while an agent is working.
    public var typingActivity: Double?
    /// Seconds an approval has been waiting.
    public var approvalAge: Double?
    public var guardAlert = false
    /// Right-paw angle to point at a session spark that needs you.
    public var pointAngle: Double?
    public var music: RigMusic?
    public var reduceMotion = false
    public var hour = 12
    public var idleSeconds = 0.0

    public init(mood: RigMood) { self.mood = mood }
}

public struct RigMusic: Sendable {
    public var beat: Double, energy: Double, drop: Bool
    public init(beat: Double, energy: Double, drop: Bool = false) { self.beat = beat; self.energy = energy; self.drop = drop }
}

/// Everything the renderer needs for one frame.
public struct RigFrame: Sendable {
    public var pose = RigPose()
    public var mood: RigMood = .idle
    public var eyes: RigEyes = .pill
    public var eyeTint: RigTint = .none
    public var chestTint: RigTint = .none
    public var blink = 1.0
    public var paws: RigPaws = .rest
    public var laptop = false
    public var headphones = false
    public var dancing = false
    /// 0…1 sweep position of the Guard shield glint; nil when not guarding.
    public var shield: Double?
    public var fx: RigFX?
    public var events: [RigEvent] = []
    /// The reaction or fidget playing now, for debugging and tests.
    public var motion: RigReaction?

    public init() {}
}

/// Nova 2's motion, in layers: mood pose → idle life → situations (agents,
/// approvals, Guard, sessions, music) → look and touch → fidgets and
/// reactions → follow-through → per-joint springs.
public struct RigEngine: Sendable {
    public private(set) var time = 0.0
    private var springs: [RigJoint: SpringState]
    private var random: RigRandom
    private var reaction: (RigReaction, Double, Set<Int>)?
    private var fidget: (RigReaction, Double)?
    private var nextFidget = 5.0
    private var fidgets = FidgetScheduler()
    private var lastMood: RigMood?
    private var weightShift = 0.0, nextWeightShift = 8.0
    private var saccade = RigPoint(x: 0, y: 0), nextSaccade = 1.0
    private var blinkStart = -9.0, nextBlink = 1.2
    private var typePhase = 0.0
    private var lastKnock = -99.0

    public init(seed: UInt64 = 1) {
        random = RigRandom(seed: seed)
        let rest = RigMood.idle.target.pose
        springs = Dictionary(uniqueKeysWithValues: RigJoint.allCases.map { ($0, SpringState(rest[$0])) })
    }

    public var currentPose: RigPose {
        var p = RigPose()
        for j in RigJoint.allCases { p[j] = springs[j]?.x ?? p[j] }
        return p
    }

    public mutating func play(_ r: RigReaction) { reaction = (r, time, []) }

    public mutating func step(dt rawDt: Double, _ input: RigInputs) -> RigFrame {
        let dt = min(max(rawDt, 0), 0.05)
        time += dt
        let t = time, calmMotion = !input.reduceMotion
        var frame = RigFrame()

        var mood = input.mood
        if input.guardAlert { mood = .warning } else if input.approvalAge != nil { mood = .notification }
        let interrupted = input.guardAlert || input.approvalAge != nil || input.pointAngle != nil || mood == .error || mood == .dizzy
        let dancing = input.music != nil && !interrupted
        if dancing && mood == .idle { mood = .happy }
        if mood != lastMood {
            if let last = lastMood, calmMotion, let b = RigBridge.reaction(from: last, to: mood) { play(b) }
            if lastMood != nil { blinkStart = t }
            lastMood = mood
        }

        let target = mood.target
        var p = target.pose
        var eyes: RigEyes? = nil
        var overrides: [RigJoint: Double] = [:]
        frame.mood = mood
        frame.eyeTint = target.eyeTint
        frame.chestTint = target.chestTint
        frame.paws = target.paws
        frame.laptop = target.paws == .type
        frame.fx = target.fx

        // Idle life.
        if calmMotion {
            let br = sin(t * 2 * .pi / 3.6)
            p.sy *= 1 + 0.012 * br
            p.chest += 0.25 * br
            if t > nextWeightShift {
                let options = [-1.6, 0, 1.6].filter { $0 != weightShift }
                weightShift = options[Int(random.next() * Double(options.count)) % options.count]
                nextWeightShift = t + 8 + random.next() * 4
            }
            p.lean += weightShift
            p.tilt += weightShift * 0.6
            let (amp, freq): (Double, Double) = switch target.tail {
            case .fast: (14, 1.1)
            case .still: (2, 0.35)
            case .normal: (8, 0.35)
            }
            p.tail += amp * sin(t * 2 * .pi * freq)
            if target.paws == .wave { p.pawR += 16 * sin(t * 2 * .pi * 1.6) }
            if input.variant == .orbit { p.dy += 3 * sin(t * 2) }
            if t > nextSaccade {
                saccade = RigPoint(x: (random.next() - 0.5) * 0.5, y: (random.next() - 0.5) * 0.3)
                nextSaccade = t + 1.2 + random.next() * 1.8
            }
            p.gx += saccade.x
            p.gy += saccade.y
        }

        // Agent working: paw speed follows activity; eyes on the laptop.
        if let activity = input.typingActivity, !dancing {
            typePhase += dt * 2 * .pi * (2 + 7 * min(max(activity, 0), 1))
            if calmMotion {
                p.pawL += 9 * sin(typePhase)
                p.pawR += 9 * sin(typePhase + .pi)
            }
            overrides[.gy] = 0.45
            overrides[.gx] = 0
        }

        // Approval waiting: look at you, then wave, then knock.
        if let age = input.approvalAge {
            overrides[.gx] = 0; overrides[.gy] = 0
            p.turn = 0; p.earL += 4; p.earR += 4
            if age < 4 || age >= 9 || !calmMotion { p.pawR = -12 } else { p.pawR = -132 + 16 * sin(t * 2 * .pi * 1.6) }
            if age >= 9, calmMotion, reaction == nil, t - lastKnock > 3.2 { play(.knock); lastKnock = t }
        }

        // Guard alert: ears back, focused amber eyes, coral chest, shield sweep.
        if input.guardAlert {
            p.earL = -14; p.earR = -14; p.sy *= 0.95; p.tilt = -2; p.turn = 0
            eyes = .focus
            frame.eyeTint = .amber
            frame.chestTint = .coral
            p.chest = 1 + 0.7 * sin(t * 2 * .pi * 2.2)
            frame.shield = (t.truncatingRemainder(dividingBy: 1.6)) / 1.6
            overrides[.gx] = 0; overrides[.gy] = 0
        }

        // A session needs you: point at its spark.
        if let angle = input.pointAngle {
            p.pawR = angle
            p.turn = 0.35
            overrides[.gx] = 0.8; overrides[.gy] = -0.6
        }

        // Music.
        if dancing, let music = input.music {
            Choreographer.apply(beat: music.beat, energy: music.energy, reduceMotion: input.reduceMotion, to: &p)
            eyes = .arc
            frame.headphones = true
            frame.fx = nil
            if music.drop, calmMotion { play(.spinHop) }
        }
        frame.dancing = dancing

        // Look at the cursor: eyes lead, the head follows a little.
        if let look = input.look, calmMotion, overrides[.gx] == nil {
            let gx = min(max(look.x, -1), 1), gy = min(max(look.y, -1), 1)
            overrides[.gx] = gx; overrides[.gy] = gy
            p.turn += gx * 0.4
            p.tilt -= gx * 2
        }

        // Petting: ears flatten happily, head leans in.
        if input.pet > 0.1 {
            p.earL -= 12 * input.pet; p.earR -= 12 * input.pet
            p.chest += input.pet * 0.6
            p.tilt += 5 * input.pet
            if input.pet > 0.35 { eyes = .arc }
            frame.fx = nil
        }

        // Dragged: dangle and swing against the motion.
        if let v = input.dragVelocity {
            p.pawL += (4 - p.pawL) * 0.8
            p.pawR += (-4 - p.pawR) * 0.8
            p.sy *= 1.05
            if eyes == nil { eyes = .tall }
            if calmMotion { p.lean += min(max(-v * 0.035, -25), 25) }
        }

        // Fidgets, only when nothing else is going on.
        let calmMoods: Set<RigMood> = [.idle, .happy, .listening, .sleepy]
        let calm = calmMotion && calmMoods.contains(mood) && !dancing && input.typingActivity == nil
            && input.pointAngle == nil && input.dragVelocity == nil && input.pet < 0.1
        if calm, reaction == nil, fidget == nil, t > nextFidget {
            fidget = (fidgets.pick(idleSeconds: input.idleSeconds, hour: input.hour, random: &random), t)
        }
        if let (f, start) = fidget {
            let u = min((t - start) / f.duration, 1)
            if calm { f.effect(at: u).apply(to: &p, overrides: &overrides, eyes: &eyes); frame.motion = f }
            if !calm || u >= 1 { fidget = nil; nextFidget = t + FidgetScheduler.gap(&random) }
        }
        if let (r, start, fired) = reaction {
            let u = min((t - start) / r.duration, 1)
            r.effect(at: u).apply(to: &p, overrides: &overrides, eyes: &eyes)
            var nowFired = fired
            for (i, ev) in r.events.enumerated() where u >= ev.0 && !fired.contains(i) {
                nowFired.insert(i)
                frame.events.append(ev.1)
            }
            frame.motion = r
            reaction = u >= 1 ? nil : (r, start, nowFired)
        }
        for (j, v) in overrides { p[j] = v }

        // Follow-through: ears and tail are pushed by the body's own motion.
        let dyV = springs[.dy]?.v ?? 0, hyV = springs[.hy]?.v ?? 0
        let leanV = springs[.lean]?.v ?? 0, bxV = springs[.bx]?.v ?? 0
        let ear = min(max(dyV * 0.3 + hyV * 0.4, -22), 22)
        p.earL += ear; p.earR += ear
        p.tail += min(max(leanV * 0.9 + bxV * 0.3 + dyV * 0.25, -35), 35)

        // Springs (Reduce Motion: snap straight to the target).
        p = p.clamped()
        for j in RigJoint.allCases {
            if input.reduceMotion {
                springs[j] = SpringState(p[j])
            } else {
                springs[j]?.step(toward: p[j], dt: dt, stiffness: j.spring.stiffness, damping: j.spring.damping)
            }
        }
        frame.pose = currentPose.clamped()

        // Blink.
        if calmMotion, t > nextBlink {
            blinkStart = t
            nextBlink = t + (random.next() < 0.15 ? 0.3 : 2.5 + random.next() * 3.5)
        }
        let bu = (t - blinkStart) / 0.16
        if bu >= 0 && bu < 1 { frame.blink = bu < 0.5 ? 1 - bu * 1.84 : 0.08 + (bu - 0.5) * 1.84 }

        frame.eyes = eyes ?? target.eyes
        return frame
    }
}
