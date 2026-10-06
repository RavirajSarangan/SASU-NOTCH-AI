import AppKit
import AudioToolbox
import CoreAudio
import NovaKit
import os
import QuartzCore

/// Lets Nova 2 dance on the real beat of Spotify or Apple Music.
///
/// While music plays and "Dance to music" is on, it taps only those apps'
/// audio with a Core Audio process tap (macOS asks for permission once) and
/// runs `BeatTracker` on it. Audio is analysed in memory, a few numbers at a
/// time, and is never stored or sent. Without permission it falls back to a
/// steady groove so Nova still dances.
@MainActor
@Observable
final class MusicTapService {
    /// Turned on by the "Dance to music" setting.
    var enabled = false { didSet { update() } }
    /// Spotify's play state, fed by `SpotifyService`.
    var spotifyPlaying = false { didSet { update() } }
    private(set) var appleMusicPlaying = false
    /// True while listening to real audio (vs. the steady fallback groove).
    private(set) var listening = false
    private(set) var lastError: String?

    var isPlaying: Bool { spotifyPlaying || appleMusicPlaying }

    @ObservationIgnored private var tap: ProcessTap?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private let startedAt = CACurrentMediaTime()

    static let fallbackBPM = 110.0

    func start() {
        observer = DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] note in
            let playing = (note.userInfo?["Player State"] as? String) == "Playing"
            Task { @MainActor in
                self?.appleMusicPlaying = playing
                self?.update()
            }
        }
    }

    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        if let t = tap { HardwareRunLoops.queue.async { t.stop() } }
        tap = nil
        listening = false
    }

    /// A dance party with no music: Nova grooves to a built-in beat until then.
    var partyUntil: Date?

    /// The current beat for Nova 2, or nil when Nova shouldn't dance.
    func sample() -> RigMusic? {
        if let partyUntil, partyUntil > Date() {
            let t = CACurrentMediaTime() - startedAt
            return RigMusic(beat: t * 118 / 60, energy: 0.25)
        }
        guard enabled, isPlaying else { return nil }
        if let tap, let music = tap.sample() { return music }
        let t = CACurrentMediaTime() - startedAt
        return RigMusic(beat: t * Self.fallbackBPM / 60, energy: 0.15)
    }

    @ObservationIgnored private var starting = false

    /// Starts or stops the tap. CoreAudio work runs on `HardwareRunLoops.queue`,
    /// never on the main thread.
    private func update() {
        let want = enabled && isPlaying
        if want, tap == nil, !starting {
            starting = true
            let bundles = (spotifyPlaying ? ["com.spotify.client"] : []) + (appleMusicPlaying ? ["com.apple.Music"] : [])
            HardwareRunLoops.queue.async {
                let result: Result<ProcessTap, Error> = Result {
                    let t = try ProcessTap(bundlePrefixes: bundles)
                    try t.start()
                    return t
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.starting = false
                    switch result {
                    case .success(let t):
                        guard self.enabled && self.isPlaying else { HardwareRunLoops.queue.async { t.stop() }; return }
                        self.tap = t
                        self.listening = true
                        self.lastError = nil
                    case .failure(let error):
                        self.lastError = error.localizedDescription
                        self.listening = false
                    }
                }
            }
        } else if !want, let t = tap {
            tap = nil
            listening = false
            HardwareRunLoops.queue.async { t.stop() }
        }
    }
}

/// A Core Audio process tap on the music apps, feeding a beat tracker on
/// the audio thread. Thread-safe: the tracker lives behind a lock.
final class ProcessTap: @unchecked Sendable {
    enum TapError: LocalizedError {
        case noProcess, coreAudio(String, OSStatus)
        var errorDescription: String? {
            switch self {
            case .noProcess: "The music app isn't playing through Core Audio yet."
            case let .coreAudio(step, status): "Couldn't listen to the music (\(step): \(status))."
            }
        }
    }

    private struct Analysis {
        var tracker = BeatTracker()
        var trackerTime = 0.0
        var hostTime = 0.0
        var energy = 0.0
    }

    private let state = OSAllocatedUnfairLock(initialState: Analysis())
    private let queue = DispatchQueue(label: "nova.music-tap", qos: .userInitiated)
    private let processes: [AudioObjectID]
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var sampleRate = 48_000.0

    // Audio-thread analysis state (only touched on `queue`).
    private var lowState = 0.0
    private var hopLow = 0.0, hopAll = 0.0, hopCount = 0
    private var samplesSeen = 0.0

    init(bundlePrefixes: [String]) throws {
        processes = Self.processObjects(matching: bundlePrefixes)
        guard !processes.isEmpty else { throw TapError.noProcess }
    }

    deinit { stop() }

    func start() throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw TapError.coreAudio("tap", status) }

        let outputUID = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Nova beat listener",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { stop(); throw TapError.coreAudio("device", status) }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr, format.mSampleRate > 0 {
            sampleRate = format.mSampleRate
        }

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.analyse(input)
        }
        guard status == noErr else { stop(); throw TapError.coreAudio("listener", status) }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { stop(); throw TapError.coreAudio("start", status) }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    /// The beat now, or nil while no beat has been found (silence, or no permission).
    func sample() -> RigMusic? {
        state.withLock { s in
            let drop = s.tracker.takeDrop()
            guard s.tracker.tracked else { return nil }
            let now = s.trackerTime + (CACurrentMediaTime() - s.hostTime)
            return RigMusic(beat: s.tracker.beat(at: now), energy: s.energy, drop: drop)
        }
    }

    /// Bass level and loudness every ~10 ms, into the tracker.
    private func analyse(_ list: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let first = buffers.first, let data = first.mData else { return }
        let channels = max(Int(first.mNumberChannels), 1)
        let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channels)
        let samples = data.assumingMemoryBound(to: Float.self)
        let alpha = 1 - exp(-2 * Double.pi * 150 / sampleRate)       // one-pole low-pass at ~150 Hz
        let hop = Int(sampleRate / 100)
        for i in 0..<frames {
            var mono = 0.0
            for c in 0..<channels { mono += Double(samples[i * channels + c]) }
            mono /= Double(channels)
            lowState += alpha * (mono - lowState)
            hopLow += lowState * lowState
            hopAll += mono * mono
            hopCount += 1
            if hopCount >= hop {
                let low = (hopLow / Double(hopCount)).squareRoot() * 1000
                let rms = (hopAll / Double(hopCount)).squareRoot()
                samplesSeen += Double(hopCount)
                let t = samplesSeen / sampleRate, host = CACurrentMediaTime()
                state.withLock { s in
                    s.tracker.push(time: t, low: low, rms: rms)
                    s.energy += (rms - s.energy) * 0.1
                    s.trackerTime = t
                    s.hostTime = host
                }
                hopLow = 0; hopAll = 0; hopCount = 0
            }
        }
    }

    // MARK: Core Audio lookups

    private static func processObjects(matching prefixes: [String]) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { id in
            var a = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var bundle: Unmanaged<CFString>?
            var s = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &a, 0, nil, &s, &bundle) == noErr, let value = bundle?.takeRetainedValue() as String? else { return false }
            return prefixes.contains { value.hasPrefix($0) }
        }
    }

    private static func defaultOutputUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr else { throw TapError.coreAudio("output", status) }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid)
        guard status == noErr, let value = uid?.takeRetainedValue() as String? else { throw TapError.coreAudio("output", status) }
        return value
    }
}
