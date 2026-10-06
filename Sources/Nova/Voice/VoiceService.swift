import AVFoundation
import NovaKit
@preconcurrency import Speech

/// "Hey Nova": push-to-talk and an optional wake word, on-device speech
/// recognition, and spoken replies.
///
/// Privacy: recognition is forced on-device (`requiresOnDeviceRecognition`);
/// if a language isn't available offline, Nova says so instead of sending
/// audio anywhere. Audio is never written to disk. The microphone runs only
/// while you hold the shortcut, or — if you turned the wake word on — while
/// the screen is unlocked and no other app is recording.
@MainActor
@Observable
final class VoiceService: NSObject {
    enum Phase: Equatable { case idle, listening, thinking, speaking }

    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    private(set) var reply = ""
    /// 0…1 microphone level while listening, or speech pulse while speaking.
    private(set) var level = 0.0
    private(set) var lastError: String?
    /// True while the wake-word listener is running (shown as a dot in the notch).
    private(set) var wakeListening = false

    var speakReplies = true
    var rate: Float = 0.5
    /// "auto", "en-US", "en-IN" or "ta-IN".
    var language = "auto"

    /// Delivers a finished request (wake word already removed by the router).
    @ObservationIgnored var onCommand: ((String) -> Void)?
    /// Called when the panel should close (reply finished).
    @ObservationIgnored var onFinished: (() -> Void)?

    @ObservationIgnored private let capture = SpeechCapture()
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var wakeEnabled = false
    @ObservationIgnored private var wakeAllowed = true
    @ObservationIgnored private var wakeHeardAt: Date?
    @ObservationIgnored private var lastPartialAt = Date()
    @ObservationIgnored private var wakeLoop: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    #if DEBUG
    func loadPreview(_ phase: Phase, transcript: String, reply: String = "", level: Double = 0.6) {
        self.phase = phase
        self.transcript = transcript
        self.reply = reply
        self.level = level
    }
    #endif

    // MARK: Push to talk

    /// Starts listening. `autoStop` (the mic button) finishes by itself after a
    /// pause; holding ⌥ Space finishes on release. Either way the microphone
    /// never stays on longer than `maxListen`.
    func startListening(autoStop: Bool = false, quietLimit: Double = 7) {
        starting = true
        releasedEarly = false
        listenID += 1
        let id = listenID
        Task {
            defer { if listenID == id { starting = false } }
            guard await ensurePermissions() else { return }
            guard listenID == id else { return }
            bargeIn = false
            stopSpeaking()
            stopWakeListener()
            transcript = ""
            reply = ""
            lastError = nil
            phase = .listening
            listenStarted = Date()
            lastPartialAt = Date()
            beginCapture(continuous: false)
            starting = false
            // The shortcut was released before the mic was ready (a quick tap):
            // listen briefly, then finish, instead of listening forever.
            let quickTap = releasedEarly
            while phase == .listening, listenID == id {
                try? await Task.sleep(for: .milliseconds(250))
                guard phase == .listening, listenID == id else { return }
                let listened = Date().timeIntervalSince(listenStarted)
                let quiet = Date().timeIntervalSince(lastPartialAt)
                let pausedAfterSpeech = !transcript.isEmpty && quiet > 1.8
                let nothingSaid = transcript.isEmpty && listened > quietLimit
                if listened > Self.maxListen
                    || (quickTap && listened > 2.5 && (transcript.isEmpty || quiet > 1.2))
                    || ((autoStop || quickTap) && (pausedAfterSpeech || nothingSaid)) {
                    finishListening()
                }
            }
        }
    }

    static let maxListen: TimeInterval = 30

    @ObservationIgnored private var starting = false
    @ObservationIgnored private var releasedEarly = false
    @ObservationIgnored private var listenID = 0
    @ObservationIgnored private var listenStarted = Date()

    /// Ends push-to-talk and handles what was said.
    func finishListening() {
        if starting { releasedEarly = true; return }
        guard phase == .listening else { return }
        phase = .thinking
        level = 0
        capture.finish { [weak self] final in
            Task { @MainActor in self?.deliver(final) }
        }
    }

    func cancel() {
        bargeIn = false
        listenID += 1
        starting = false
        capture.cancel()
        stopSpeaking()
        phase = .idle
        level = 0
        resumeWakeListener()
    }

    // MARK: Wake word

    func setWakeWord(enabled: Bool) {
        wakeEnabled = enabled
        wakeFailures = 0
        enabled ? resumeWakeListener() : stopWakeListener()
    }

    /// Pauses the wake word (screen locked, another app recording). Called
    /// every few seconds, so it also restarts a listener that stopped.
    func setWakeAllowed(_ allowed: Bool) {
        if allowed != wakeAllowed {
            wakeAllowed = allowed
            if !allowed { stopWakeListener(); return }
        }
        if allowed, Date() >= wakeRetryAt { resumeWakeListener() }
    }

    private func resumeWakeListener() {
        guard wakeEnabled, wakeAllowed, phase == .idle, !wakeListening, !wakeStarting else { return }
        wakeStarting = true
        Task {
            defer { wakeStarting = false }
            guard await ensurePermissions(prompt: false) else { return }
            guard wakeEnabled, wakeAllowed, phase == .idle, !wakeListening else { return }
            wakeListening = true
            wakeHeardAt = nil
            transcript = ""
            heardApp = nil
            beginCapture(continuous: true)
            wakeLoop?.cancel()
            // The loop ends when the listener stops, so a strong capture is fine.
            wakeLoop = Task {
                // Speech tasks are limited to about a minute: restart quietly, and
                // finish a request 1.2 s after the speaker pauses.
                var started = Date()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard self.wakeListening else { return }
                    let now = Date()
                    if let heard = self.wakeHeardAt {
                        let command = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        let paused = now.timeIntervalSince(self.lastPartialAt) > 1.2 && now.timeIntervalSince(heard) > 0.6
                        if !command.isEmpty, paused {
                            self.endWake()
                            self.deliver(command)
                            return
                        }
                        // "Hello Nova" … (waiting for the request). Give up quietly
                        // after a while instead of closing the panel straight away.
                        if command.isEmpty, now.timeIntervalSince(self.lastPartialAt) > 6 || now.timeIntervalSince(heard) > 12 {
                            self.endWake()
                            self.deliver("")
                            return
                        }
                        if now.timeIntervalSince(heard) > Self.maxListen {
                            self.endWake()
                            self.deliver(command)
                            return
                        }
                    } else if now.timeIntervalSince(started) > 50 {
                        self.restartWakeCapture()
                        started = Date()
                    }
                }
            }
        }
    }

    private func endWake() {
        wakeListening = false
        phase = .thinking
        level = 0
        capture.cancel()
    }

    /// The recognizer ended by itself (a pause, its time limit, or an error):
    /// keep listening instead of going deaf until the next restart.
    private func wakeCaptureEnded() {
        guard wakeListening else { return }
        // Ending again right after a start means something is wrong: back off.
        if Date().timeIntervalSince(wakeCaptureStartedAt) < 2 {
            failed("The speech recognizer stopped.", continuous: true)
        } else {
            restartWakeCapture()
        }
    }

    /// Starts a fresh recognition task but keeps the microphone running, so the
    /// mic indicator doesn't flicker every time the recognizer resets.
    private func restartWakeCapture() {
        guard wakeListening else { return }
        beginCapture(continuous: true, reuseMicrophone: true)
    }

    @ObservationIgnored private var wakeCaptureStartedAt = Date.distantPast

    private func stopWakeListener() {
        wakeLoop?.cancel()
        wakeLoop = nil
        if wakeListening { capture.cancel() }
        wakeListening = false
    }

    @ObservationIgnored private var wakeStarting = false
    @ObservationIgnored private var wakeFailures = 0
    @ObservationIgnored private var wakeRetryAt = Date.distantPast

    // MARK: Capture

    private func beginCapture(continuous: Bool, reuseMicrophone: Bool = false) {
        if continuous { wakeCaptureStartedAt = Date() }
        let locale = Self.recognitionLocale(language)
        capture.start(locale: locale, reuseMicrophone: reuseMicrophone, onPartial: { [weak self] text in
            Task { @MainActor in self?.partial(text, continuous: continuous) }
        }, onLevel: { [weak self] value in
            Task { @MainActor in self?.level = value }
        }, onEnded: { [weak self] in
            Task { @MainActor in if continuous { self?.wakeCaptureEnded() } }
        }, onError: { [weak self] message in
            Task { @MainActor in self?.failed(message, continuous: continuous) }
        })
    }

    private func partial(_ text: String, continuous: Bool) {
        if bargeIn { heardWhileSpeaking(text); return }
        lastPartialAt = Date()
        if continuous {
            guard wakeListening else { return }
            wakeFailures = 0
            if wakeHeardAt == nil {
                if VoiceIntentRouter.containsWakeWord(text) {
                    heardApp = nil
                } else if let app = VoiceIntentRouter.heyApp(text, apps: appNames) {
                    // "Hey Safari": open that app.
                    heardApp = app
                } else {
                    return
                }
                wakeHeardAt = Date()
                phase = .listening
                onWake?()
            }
            if let app = heardApp {
                transcript = "open \(app)"
                return
            }
            // After a restart the new text no longer starts with the wake word.
            transcript = Self.afterWakeWord(text)
        } else {
            guard phase == .listening else { return }
            transcript = text
        }
    }

    /// Installed app names for "Hey <app>" (set by the coordinator).
    var appNames: [String] = []
    @ObservationIgnored private var heardApp: String?

    /// Opens the panel when the wake word is heard.
    @ObservationIgnored var onWake: (() -> Void)?

    private func failed(_ message: String, continuous: Bool) {
        lastError = message
        if continuous {
            // The wake word must not die on one hiccup (Bluetooth switching,
            // another app grabbing the mic): try again with a growing pause.
            guard wakeListening else { return }
            stopWakeListener()
            if phase == .listening || phase == .thinking { phase = .idle; onFinished?() }
            wakeFailures += 1
            let delay = [2.0, 5, 15, 30, 60][min(wakeFailures - 1, 4)]
            wakeRetryAt = Date().addingTimeInterval(delay)
            Task {
                try? await Task.sleep(for: .seconds(delay))
                resumeWakeListener()
            }
            return
        }
        if phase == .listening || phase == .thinking {
            listenID += 1
            phase = .speaking
            reply = message
            finishSoon()
        }
    }

    /// True when the last listen heard nothing (ends a follow-up).
    private(set) var lastDeliveredEmpty = false

    private func deliver(_ text: String) {
        level = 0
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lastDeliveredEmpty = trimmed.isEmpty
        guard !trimmed.isEmpty else {
            phase = .idle
            onFinished?()
            resumeWakeListener()
            return
        }
        transcript = trimmed
        onCommand?(trimmed)
    }

    // MARK: Speaking

    /// Shows and (if enabled) speaks a reply.
    func say(_ text: String) {
        // Cancelled, or a new request started while this one was thinking.
        guard phase == .thinking else { return }
        reply = text
        phase = .speaking
        guard speakReplies else { finishSoon(); return }
        let utterance = AVSpeechUtterance(string: Self.speakable(text))
        utterance.rate = rate
        utterance.voice = Self.voice(for: text, language: language)
        synthesizer.speak(utterance)
        startBargeIn()
    }

    // MARK: Interrupting Nova

    /// While Nova speaks (and only if "Hey Nova" is on, so the mic is already
    /// allowed to listen), "Hey Nova" or "stop" cuts the reply short.
    @ObservationIgnored private var bargeIn = false

    private func startBargeIn() {
        guard wakeEnabled, wakeAllowed, !bargeIn else { return }
        stopWakeListener()
        bargeIn = true
        beginCapture(continuous: true)
    }

    private func endBargeIn() {
        guard bargeIn else { return }
        bargeIn = false
        capture.cancel()
    }

    private func heardWhileSpeaking(_ text: String) {
        guard bargeIn, phase == .speaking else { return }
        switch VoiceIntentRouter.interruption(in: text, reply: reply) {
        case .wake?:
            endBargeIn()
            stopSpeaking()
            phase = .idle
            startListening(autoStop: true)
        case .stop?:
            endBargeIn()
            cancel()
            onFinished?()
        case nil:
            break
        }
    }

    /// Shows what Nova is doing during a multi-step plan.
    func showProgress(_ text: String) {
        stopWakeListener()
        transcript = text
        reply = ""
        phase = .thinking
    }

    /// Speaks a short notice (a timer) without opening the voice panel.
    func announce(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.voice = Self.voice(for: text, language: language)
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func finishSoon() {
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard phase == .speaking, !synthesizer.isSpeaking else { return }
            endBargeIn()
            phase = .idle
            level = 0
            onFinished?()
            resumeWakeListener()
        }
    }

    // MARK: Permissions

    private func ensurePermissions(prompt: Bool = true) async -> Bool {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        if speech == .authorized && mic == .authorized { return true }
        guard prompt else { return false }
        let speechOK = speech == .authorized ? true : await Self.requestSpeechAccess()
        let micOK = mic == .authorized ? true : await AVCaptureDevice.requestAccess(for: .audio)
        guard speechOK && micOK else {
            lastError = "Nova needs Microphone and Speech Recognition access. Turn them on in System Settings → Privacy & Security."
            phase = .speaking
            reply = lastError ?? ""
            finishSoon()
            return false
        }
        return true
    }

    /// macOS answers on a background queue. This must not be a main-actor
    /// closure, or the actor check traps and Nova crashes (seen on the first
    /// mic click, while the permission prompt was answered).
    nonisolated private static func requestSpeechAccess() async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in c.resume(returning: status == .authorized) }
        }
    }

    // MARK: Helpers

    static func recognitionLocale(_ setting: String) -> Locale {
        if setting != "auto" { return Locale(identifier: setting) }
        let preferred = Locale.preferredLanguages.first ?? "en-US"
        return Locale(identifier: preferred.hasPrefix("ta") ? "ta-IN" : preferred)
    }

    static func afterWakeWord(_ text: String) -> String {
        VoiceIntentRouter.textAfterWakeWord(text)
    }

    /// Tamil text gets a Tamil voice when one is installed.
    static func voice(for text: String, language: String) -> AVSpeechSynthesisVoice? {
        let tamil = text.unicodeScalars.contains { (0x0B80...0x0BFF).contains($0.value) }
        if tamil || language == "ta-IN", let v = AVSpeechSynthesisVoice(language: "ta-IN") { return v }
        if language.hasPrefix("en") { return AVSpeechSynthesisVoice(language: language) }
        return AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode()) ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Drops Markdown and code so the voice reads naturally; keeps it short.
    static func speakable(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: " (code shown on screen) ", options: .regularExpression)
        s = s.replacingOccurrences(of: "[*_`#>]", with: "", options: .regularExpression)
        let sentences = s.split(whereSeparator: { ".!?".contains($0) })
        return sentences.count > 4 ? sentences.prefix(4).joined(separator: ". ") + ". The rest is on screen." : s
    }

    /// Microphone and speech recognition are both allowed.
    static var permissionsGranted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var tamilVoiceInstalled: Bool { AVSpeechSynthesisVoice(language: "ta-IN") != nil }
    static var tamilRecognitionOnDevice: Bool { SFSpeechRecognizer(locale: Locale(identifier: "ta-IN"))?.supportsOnDeviceRecognition ?? false }
}

extension VoiceService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in self.level = Double.random(in: 0.5...1) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.level = 0
            self.finishSoon()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.level = 0 }
    }
}

/// Microphone + recognizer, all on one serial queue (CoreAudio must stay off
/// the main thread). Nothing is recorded to disk.
final class SpeechCapture: @unchecked Sendable {
    private let queue = DispatchQueue(label: "nova.voice", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastText = ""
    private var finalHandler: ((String) -> Void)?
    /// The request the microphone tap feeds (swapped without stopping the mic).
    private let feed = RequestFeed()
    /// Bumped on every start/cancel so late callbacks from an old
    /// recognition task can't leak into the new one.
    private var generation = 0

    func start(locale: Locale, reuseMicrophone: Bool = false, onPartial: @escaping @Sendable (String) -> Void,
               onLevel: @escaping @Sendable (Double) -> Void,
               onEnded: @escaping @Sendable () -> Void, onError: @escaping @Sendable (String) -> Void) {
        queue.async { [self] in
            let keepEngine = reuseMicrophone && engine?.isRunning == true
            if keepEngine {
                task?.cancel()
                task = nil
                request?.endAudio()
                request = nil
                feed.set(nil)
            } else {
                stopEngine()
            }
            generation += 1
            let current = generation
            lastText = ""
            finalHandler = nil
            guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
                onError("Speech recognition isn't available for \(locale.identifier) on this Mac.")
                return
            }
            guard recognizer.supportsOnDeviceRecognition else {
                onError("\(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier) can't be recognised offline on this Mac yet, so Nova won't listen in it. Pick English in Settings → Nova → Voice.")
                return
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            request.addsPunctuation = true
            if keepEngine {
                self.request = request
                feed.set(request)
                task = recognitionTask(recognizer, request, current, onPartial: onPartial, onEnded: onEnded)
                return
            }
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { onError("No microphone found."); return }
            let feed = self.feed
            feed.set(request)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                feed.current?.append(buffer)
                if let data = buffer.floatChannelData?[0] {
                    var sum: Float = 0
                    let n = Int(buffer.frameLength)
                    for i in stride(from: 0, to: n, by: 4) { sum += data[i] * data[i] }
                    onLevel(min(1, Double(sqrt(sum / Float(max(n / 4, 1)))) * 12))
                }
            }
            engine.prepare()
            do { try engine.start() } catch {
                input.removeTap(onBus: 0)
                onError("Couldn't start the microphone.")
                return
            }
            self.engine = engine
            self.request = request
            task = recognitionTask(recognizer, request, current, onPartial: onPartial, onEnded: onEnded)
        }
    }

    private func recognitionTask(_ recognizer: SFSpeechRecognizer, _ request: SFSpeechAudioBufferRecognitionRequest, _ current: Int,
                                 onPartial: @escaping @Sendable (String) -> Void, onEnded: @escaping @Sendable () -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            self.queue.async {
                guard self.generation == current else { return }
                if let result {
                    self.lastText = result.bestTranscription.formattedString
                    onPartial(self.lastText)
                }
                if result?.isFinal == true || (result == nil && error != nil) {
                    if self.finalHandler != nil {
                        self.complete()
                    } else {
                        // Ended on its own while nobody was waiting for it: the
                        // owner restarts recognition (the microphone keeps running).
                        self.generation += 1
                        self.task = nil
                        self.request = nil
                        self.feed.set(nil)
                        onEnded()
                    }
                }
            }
        }
    }

    /// Stops listening and returns the final transcript (or the latest partial after 1.5 s).
    func finish(_ handler: @escaping @Sendable (String) -> Void) {
        queue.async { [self] in
            guard engine != nil || task != nil else { handler(lastText); return }
            finalHandler = handler
            engine?.stop()
            engine?.inputNode.removeTap(onBus: 0)
            request?.endAudio()
            let current = generation
            queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.generation == current else { return }
                self.complete()
            }
        }
    }

    func cancel() {
        queue.async { [self] in
            generation += 1
            finalHandler = nil
            stopEngine()
        }
    }

    private func complete() {
        guard let handler = finalHandler else { return }
        finalHandler = nil
        generation += 1
        let text = lastText
        stopEngine()
        handler(text)
    }

    private func stopEngine() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        feed.set(nil)
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
    }
}

/// The current recognition request, read from the audio thread.
final class RequestFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    var current: SFSpeechAudioBufferRecognitionRequest? {
        lock.lock(); defer { lock.unlock() }
        return request
    }

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); self.request = request; lock.unlock()
    }
}
