import AVFoundation
import Foundation

/// One synthesized note. Frequencies glide linearly from `freq` to `endFreq`.
struct Tone: Sendable {
    var freq: Double
    var endFreq: Double?
    var duration: Double
    var gap: Double = 0.02
    /// Vibrato rate in Hz (0 = none).
    var wobble: Double = 0
    /// Adds a short bell-like shimmer on top (success, sparkle).
    var sparkle = false
}

/// How Nova sounds. All packs are synthesized at runtime (no audio assets).
enum SoundPack: String, CaseIterable, Identifiable, Sendable {
    /// Warm chimes with a soft room reverb (default).
    case soft
    /// Retro 8-bit square waves.
    case playful
    /// One quiet tick per cue.
    case minimal

    var id: String { rawValue }
    var label: String {
        switch self {
        case .soft: "Soft"
        case .playful: "Playful (8-bit)"
        case .minimal: "Minimal"
        }
    }
}

/// Notes of C major pentatonic, so every cue belongs to one family.
enum Note {
    static let A4 = 440.0, C5 = 523.25, D5 = 587.33, E5 = 659.25, G5 = 783.99, A5 = 880.0
    static let C6 = 1046.5, D6 = 1174.66, E6 = 1318.51, G6 = 1567.98, A6 = 1760.0, C7 = 2093.0
}

/// Nova's sound palette: one cue per emotion plus event cues.
enum SoundCue: String, CaseIterable, Sendable {
    case open, close
    case happy, surprised, sleepy, yawn, thinking, ticks, typing, listening
    case warning, error, excited, confused, annoyed, success, loading, dizzy, notification
    // Events (distinct from moods).
    case permission, taskDone, security, sent

    var tones: [Tone] {
        typealias N = Note
        return switch self {
        case .open: [Tone(freq: N.G5, duration: 0.06, gap: 0.0), Tone(freq: N.C6, duration: 0.1)]
        case .close: [Tone(freq: N.C6, duration: 0.06, gap: 0.0), Tone(freq: N.G5, duration: 0.1)]
        case .happy: [Tone(freq: N.E5, duration: 0.07), Tone(freq: N.G5, duration: 0.07), Tone(freq: N.C6, duration: 0.14)]
        case .surprised: [Tone(freq: N.G5, endFreq: N.E6, duration: 0.14)]
        case .sleepy: [Tone(freq: N.E5, endFreq: N.C5, duration: 0.24, gap: 0.05), Tone(freq: N.C5, endFreq: N.A4, duration: 0.28)]
        case .yawn: [Tone(freq: N.G5, endFreq: N.C5, duration: 0.5, wobble: 3)]
        case .thinking: [Tone(freq: N.D5, duration: 0.06, gap: 0.05), Tone(freq: N.E5, duration: 0.06, gap: 0.05), Tone(freq: N.D5, duration: 0.08)]
        case .ticks: [Tone(freq: N.E6, duration: 0.025, gap: 0.04), Tone(freq: N.G6, duration: 0.03)]
        case .typing: [Tone(freq: N.G6, duration: 0.018, gap: 0.045), Tone(freq: N.E6, duration: 0.018, gap: 0.045), Tone(freq: N.G6, duration: 0.02)]
        case .listening: [Tone(freq: N.C6, endFreq: N.E6, duration: 0.09)]
        case .warning: [Tone(freq: N.A5, duration: 0.11, gap: 0.07), Tone(freq: N.A5, duration: 0.13)]
        case .error: [Tone(freq: N.E5, endFreq: N.C5, duration: 0.18, gap: 0.03), Tone(freq: N.A4, duration: 0.18)]
        case .excited: [Tone(freq: N.C6, duration: 0.05, gap: 0.01), Tone(freq: N.E6, duration: 0.05, gap: 0.01),
                        Tone(freq: N.G6, duration: 0.05, gap: 0.01), Tone(freq: N.C7, duration: 0.12, sparkle: true)]
        case .confused: [Tone(freq: N.D5, endFreq: N.E5, duration: 0.1, gap: 0.04), Tone(freq: N.E5, endFreq: N.A5, duration: 0.15)]
        case .annoyed: [Tone(freq: N.C5, endFreq: N.A4, duration: 0.24, wobble: 12)]
        case .success: [Tone(freq: N.C6, duration: 0.07), Tone(freq: N.E6, duration: 0.07), Tone(freq: N.G6, duration: 0.2, sparkle: true)]
        case .loading: [Tone(freq: N.C5, endFreq: N.G5, duration: 0.13)]
        case .dizzy: [Tone(freq: N.A5, endFreq: N.E5, duration: 0.11, gap: 0.01, wobble: 9), Tone(freq: N.G5, endFreq: N.D5, duration: 0.11, gap: 0.01, wobble: 9),
                      Tone(freq: N.E5, endFreq: N.C5, duration: 0.16, wobble: 9)]
        case .notification: [Tone(freq: N.E6, duration: 0.07, gap: 0.05), Tone(freq: N.G6, duration: 0.13)]
        case .permission: [Tone(freq: N.A5, duration: 0.07, gap: 0.04), Tone(freq: N.D6, duration: 0.07, gap: 0.04), Tone(freq: N.A5, duration: 0.1)]
        case .taskDone: [Tone(freq: N.G5, duration: 0.06, gap: 0.01), Tone(freq: N.C6, duration: 0.06, gap: 0.01),
                         Tone(freq: N.E6, duration: 0.06, gap: 0.01), Tone(freq: N.G6, duration: 0.22, sparkle: true)]
        case .security: [Tone(freq: N.D6, duration: 0.12, gap: 0.02), Tone(freq: N.A5, duration: 0.12, gap: 0.06),
                         Tone(freq: N.D6, duration: 0.12, gap: 0.02), Tone(freq: N.A5, duration: 0.14)]
        case .sent: [Tone(freq: N.C6, endFreq: N.G6, duration: 0.11)]
        }
    }

    /// Interface and event cues follow "Open & close sounds"; the rest are moods.
    var isInterface: Bool { self == .open || self == .close }
}

extension NovaExpression {
    /// The chirp Nova makes on entering this expression. Idle is silent.
    var soundCue: SoundCue? {
        switch self {
        case .idle: nil
        case .happy: .happy
        case .thinking: .thinking
        case .coding: .ticks
        case .typing: .typing
        case .listening: .listening
        case .surprised: .surprised
        case .warning: .warning
        case .error: .error
        case .sleepy: .sleepy
        case .sleeping: .yawn
        case .excited: .excited
        case .confused: .confused
        case .annoyed: .annoyed
        case .success: .success
        case .loading: .loading
        case .dizzy: .dizzy
        case .notification: .notification
        }
    }
}

@Observable
@MainActor
final class SoundService {
    private static let mutedKey = "soundsMuted"
    nonisolated private static let sampleRate = 44_100.0
    private static let minimumSpacing: TimeInterval = 0.25

    var isMuted: Bool = UserDefaults.standard.bool(forKey: SoundService.mutedKey) {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: Self.mutedKey)
            if isMuted { audio.stop() }
        }
    }

    /// 0…1, applied to every cue.
    var volume: Double = UserDefaults.standard.object(forKey: "soundVolume") as? Double ?? 0.8 {
        didSet {
            UserDefaults.standard.set(volume, forKey: "soundVolume")
            audio.setVolume(Float(volume))
        }
    }

    /// Open/close whooshes when the panel expands and collapses.
    var interfaceSounds: Bool = UserDefaults.standard.object(forKey: "interfaceSounds") as? Bool ?? true {
        didSet { UserDefaults.standard.set(interfaceSounds, forKey: "interfaceSounds") }
    }

    var pack: SoundPack = SoundPack(rawValue: UserDefaults.standard.string(forKey: "soundPack") ?? "") ?? .soft {
        didSet {
            UserDefaults.standard.set(pack.rawValue, forKey: "soundPack")
            buffers.removeAll()
            audio.setReverb(pack == .soft ? 12 : 0)
        }
    }

    /// Nova's emotion chirps.
    var reactionSounds: Bool = UserDefaults.standard.object(forKey: "reactionSounds") as? Bool ?? true {
        didSet { UserDefaults.standard.set(reactionSounds, forKey: "reactionSounds") }
    }

    /// Owns the AVAudioEngine on its own queue: CoreAudio must never run on
    /// the main thread (it can take over the main run loop on macOS 26).
    @ObservationIgnored private lazy var audio = SoundEngine(reverb: pack == .soft ? 12 : 0)
    @ObservationIgnored private let format = AVAudioFormat(standardFormatWithSampleRate: SoundService.sampleRate, channels: 2)   // stereo: the reverb unit rejects mono
    @ObservationIgnored private var buffers: [SoundCue: AVAudioPCMBuffer] = [:]
    @ObservationIgnored private var lastPlayed: [SoundCue: Date] = [:]
    @ObservationIgnored private var lastAny = Date.distantPast

    /// Plays a cue. `cooldown` suppresses repeats of the same cue (e.g. the
    /// hover chirp) within that window.
    func play(_ cue: SoundCue, cooldown: TimeInterval = 0) {
        guard !isMuted else { return }
        if cue.isInterface { guard interfaceSounds else { return } } else if !reactionSounds { return }
        let now = Date()
        guard now.timeIntervalSince(lastAny) >= Self.minimumSpacing else { return }
        if cooldown > 0, let last = lastPlayed[cue], now.timeIntervalSince(last) < cooldown { return }
        guard let buffer = buffer(for: cue) else { return }
        lastAny = now
        lastPlayed[cue] = now
        audio.play(SoundBuffer(buffer: buffer), volume: Float(volume))
    }

    /// Plays every cue once, in order (Settings → Advanced, --sound-test).
    func playAll(printing: Bool = false) async {
        for cue in SoundCue.allCases {
            if printing { print("▶︎ \(cue.rawValue)") }
            lastAny = .distantPast
            lastPlayed[cue] = nil
            let wasMuted = isMuted
            isMuted = false
            let interface = interfaceSounds, reactions = reactionSounds
            interfaceSounds = true
            reactionSounds = true
            play(cue)
            interfaceSounds = interface
            reactionSounds = reactions
            isMuted = wasMuted
            let length = Self.duration(of: cue, pack: pack)
            try? await Task.sleep(for: .seconds(length + 0.45))
        }
    }

    private func buffer(for cue: SoundCue) -> AVAudioPCMBuffer? {
        if let cached = buffers[cue] { return cached }
        guard let format else { return nil }
        let samples = Self.synthesize(cue.tones, pack: pack)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for c in 0..<Int(format.channelCount) {
            for (i, sample) in samples.enumerated() { channels[c][i] = sample }
        }
        buffers[cue] = buffer
        return buffer
    }

    nonisolated static func duration(of cue: SoundCue, pack: SoundPack) -> Double {
        Double(synthesize(cue.tones, pack: pack).count) / sampleRate
    }

    /// Renders tones for a pack. Every note has a click-free envelope
    /// (short attack, gentle decay, faded tail), and output is normalized so
    /// no cue clips.
    nonisolated static func synthesize(_ tones: [Tone], pack: SoundPack = .soft, amplitude: Float = 0.18) -> [Float] {
        let notes = pack == .minimal ? Array(tones.prefix(1)).map { Tone(freq: $0.freq, duration: min($0.duration, 0.05), gap: 0.02) } : tones
        var out: [Float] = []
        for tone in notes {
            let count = Int(tone.duration * sampleRate)
            var phase = 0.0
            for i in 0..<count {
                let t = Double(i) / sampleRate
                let progress = Double(i) / Double(max(count - 1, 1))
                var freq = tone.freq + ((tone.endFreq ?? tone.freq) - tone.freq) * progress
                if tone.wobble > 0 { freq *= 1 + 0.035 * sin(2 * .pi * tone.wobble * t) }
                phase += 2 * .pi * freq / sampleRate

                let wave: Double
                switch pack {
                case .soft:
                    // Warm additive chime + optional bell shimmer (inharmonic partial).
                    var w = sin(phase) + 0.3 * sin(2 * phase) + 0.1 * sin(3 * phase)
                    if tone.sparkle { w += 0.25 * sin(2.76 * phase) * exp(-12 * t) }
                    wave = w / 1.4
                case .playful:
                    // Band-limited square (odd harmonics), the classic 8-bit tone.
                    var w = 0.0
                    for k in stride(from: 1, through: 9, by: 2) { w += sin(Double(k) * phase) / Double(k) }
                    wave = w * 0.75
                case .minimal:
                    wave = sin(phase) * 0.6
                }

                let attack = min(t / 0.007, 1)
                let decay = pack == .playful ? (progress < 0.85 ? 1 : 1 - (progress - 0.85) / 0.15) : exp(-3.2 * progress)
                let tail = min(Double(count - 1 - i) / (0.006 * sampleRate), 1)   // fade the last 6 ms
                out.append(Float(wave * attack * decay * tail) * amplitude)
            }
            out.append(contentsOf: repeatElement(0, count: Int(tone.gap * sampleRate)))
        }
        // Normalize so the loudest peak sits at `amplitude` (no clipping, even levels).
        if let peak = out.map(abs).max(), peak > amplitude { out = out.map { $0 * amplitude / peak } }
        return out
    }
}

/// An immutable rendered cue, handed to the audio queue.
struct SoundBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

/// AVAudioEngine wrapper that does all CoreAudio work on one serial queue.
final class SoundEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "nova.sound", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let reverb = AVAudioUnitReverb()
    private var configured = false
    private var reverbMix: Float

    init(reverb mix: Float) { reverbMix = mix }

    func play(_ sound: SoundBuffer, volume: Float) {
        queue.async { [self] in
            guard start(format: sound.buffer.format) else { return }
            player.stop()
            player.volume = volume
            player.scheduleBuffer(sound.buffer, at: nil, options: .interrupts)
            player.play()
            scheduleIdleStop(after: Double(sound.buffer.frameLength) / sound.buffer.format.sampleRate + 2)
        }
    }

    /// A running engine renders (and resamples) silence in real time, which
    /// costs CPU all day; stop it shortly after the last sound.
    private var idleStop: DispatchWorkItem?

    private func scheduleIdleStop(after seconds: Double) {
        idleStop?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.engine.isRunning else { return }
            self.player.stop()
            self.engine.stop()
        }
        idleStop = work
        queue.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func stop() { queue.async { [self] in player.stop() } }
    func setVolume(_ v: Float) { queue.async { [self] in player.volume = v } }
    func setReverb(_ mix: Float) { queue.async { [self] in reverbMix = mix; reverb.wetDryMix = mix } }

    private func start(format: AVAudioFormat) -> Bool {
        if !configured {
            engine.attach(player)
            engine.attach(reverb)
            reverb.loadFactoryPreset(.smallRoom)
            reverb.wetDryMix = reverbMix
            engine.connect(player, to: reverb, format: format)
            engine.connect(reverb, to: engine.mainMixerNode, format: format)
            configured = true
        }
        if !engine.isRunning {
            do { try engine.start() } catch { return false }
        }
        return true
    }
}
