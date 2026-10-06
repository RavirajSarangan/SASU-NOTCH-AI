import Foundation

/// On-device beat tracking. Feed it the low-band (bass) level and the RMS
/// loudness of each audio analysis frame; it estimates tempo by
/// autocorrelating onsets over the last 8 s, and beat phase with a comb
/// filter over the last 4 s. Nothing is stored beyond those 8 s of numbers.
public struct BeatTracker: Sendable {
    public private(set) var period = 60.0 / 110
    public private(set) var phase0 = 0.0
    public private(set) var tracked = false
    /// Set when the loudness jumps (a "drop"); read it with `takeDrop()`.
    public private(set) var dropPending = false

    private var onsets: [(Double, Double)] = []
    private var previousLow: Double?
    private var lastEstimate = 0.0
    private var shortEnergy = 0.0, longEnergy = 0.0
    private var lastDrop = -99.0

    static let window = 8.0
    static let rate = 100.0

    public init() {}

    public var bpm: Double { 60 / period }

    /// `low`: bass-band magnitude (any scale, consistent between frames). `rms`: 0…1 loudness.
    public mutating func push(time: Double, low: Double, rms: Double) {
        let flux = previousLow.map { max(0, low - $0) } ?? 0
        previousLow = low
        onsets.append((time, flux))
        while let first = onsets.first, time - first.0 > Self.window { onsets.removeFirst() }

        shortEnergy += (rms - shortEnergy) * 0.12
        longEnergy += (rms - longEnergy) * 0.006
        if shortEnergy > longEnergy * 1.45, shortEnergy > 0.06, time - lastDrop > 8, time > 3 {
            lastDrop = time
            dropPending = true
        }
        if time - lastEstimate > 1 {
            estimate(now: time)
            lastEstimate = time
        }
    }

    public mutating func takeDrop() -> Bool {
        defer { dropPending = false }
        return dropPending
    }

    /// Fractional beat count at `time` (integer = on the beat).
    public func beat(at time: Double) -> Double {
        tracked ? (time - phase0) / period : time / (60.0 / 110)
    }

    private mutating func estimate(now: Double) {
        let n = Int(Self.window * Self.rate), start = now - Self.window
        var grid = [Double](repeating: 0, count: n)
        for (t, f) in onsets {
            let i = Int((t - start) * Self.rate)
            if i >= 0 && i < n { grid[i] = max(grid[i], f) }
        }
        var env = [Double](repeating: 0, count: n)
        for i in 1..<(n - 1) { env[i] = grid[i - 1] * 0.5 + grid[i] + grid[i + 1] * 0.5 }
        let total = env.reduce(0) { $0 + $1 * $1 }
        guard total >= 1 else { tracked = false; return }

        // Tempo: autocorrelation over 70–180 BPM, gently preferring ~120.
        var best = 0.0, bestLag = 0
        for lag in 33...86 {
            var s = 0.0
            for i in lag..<n { s += env[i] * env[i - lag] }
            let bpm = 60 * Self.rate / Double(lag)
            s *= exp(-0.5 * pow(log2(bpm / 120) / 0.9, 2))
            if s > best { best = s; bestLag = lag }
        }
        guard bestLag > 0 else { return }
        // Refine the lag to sub-bin precision with a parabola through its neighbours.
        func score(_ lag: Int) -> Double {
            guard lag > 0, lag < n else { return 0 }
            var s = 0.0
            for i in lag..<n { s += env[i] * env[i - lag] }
            return s
        }
        let (a, b, c) = (score(bestLag - 1), score(bestLag), score(bestLag + 1))
        let denom = a - 2 * b + c
        let shift = denom < 0 ? max(-0.5, min(0.5, 0.5 * (a - c) / denom)) : 0
        let p = (Double(bestLag) + shift) / Self.rate
        period += (p - period) * (tracked ? 0.35 : 1)
        tracked = true

        // Phase: the comb offset that lands most onsets on beats.
        var bestScore = -1.0, bestPhi = 0.0
        for k in 0..<32 {
            let phi = Double(k) / 32 * period
            var s = 0.0, t = now - phi
            while t > now - 4 {
                let i = Int(((t - start) * Self.rate).rounded())
                for d in -2...2 where i + d >= 0 && i + d < n { s += env[i + d] }
                t -= period
            }
            if s > bestScore { bestScore = s; bestPhi = phi }
        }
        let target = now - bestPhi
        var diff = (target - phase0).truncatingRemainder(dividingBy: period)
        if diff < 0 { diff += period }
        if diff > period / 2 { diff -= period }
        phase0 += diff * (phase0 == 0 ? 1 : 0.5)
    }
}

/// Turns the beat into dance moves. Every 8 bars it switches to the next
/// combination; loudness sets how big the moves are.
public enum Choreographer {
    public enum Move: String, CaseIterable, Sendable { case bob, sway, earBop, pawPump, tailWag, sideStep }

    public static let combos: [[Move]] = [
        [.bob, .sway, .earBop],
        [.bob, .pawPump, .tailWag],
        [.sideStep, .earBop, .tailWag, .bob],
        [.bob, .sway, .pawPump, .earBop],
    ]

    public static func combo(forBeat beat: Double) -> [Move] {
        let bar = Int(floor(beat / 4))
        let i = ((bar / 8) % combos.count + combos.count) % combos.count
        return combos[i]
    }

    /// Applies the dance for this instant to `pose`. Deterministic in (beat, energy).
    public static func apply(beat: Double, energy: Double, reduceMotion: Bool, to pose: inout RigPose) {
        let bi = Int(floor(beat)), ph = beat - floor(beat)
        let hit = pow(1 - ph, 3)
        let odd = ((bi % 2) + 2) % 2 == 1
        if reduceMotion {
            if odd { pose.earL += 8 * hit } else { pose.earR += 8 * hit }
            return
        }
        let amp = min(max(0.35 + energy * 4, 0.35), 1)
        let sway = sin(.pi * (Double(odd ? 1 : 0) + ph))
        for move in combo(forBeat: beat) {
            switch move {
            case .bob:
                pose.hy += 4 * amp * hit
                pose.sy *= 1 - 0.045 * amp * pow(1 - ph, 4)
            case .sway:
                pose.lean += 6 * amp * sway
                pose.tilt += 4 * amp * sway
            case .earBop:
                if odd { pose.earL += 16 * amp * hit } else { pose.earR += 16 * amp * hit }
            case .pawPump:
                let w = amp * pow(1 - ph, 2)
                if odd { pose.pawL += (120 - pose.pawL) * w } else { pose.pawR += (-120 - pose.pawR) * w }
            case .tailWag:
                pose.tail += 22 * amp * sway
            case .sideStep:
                pose.bx += 9 * amp * sway
            }
        }
    }
}
