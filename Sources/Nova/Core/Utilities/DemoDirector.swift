#if DEBUG
import AVFoundation
import NovaKit
import ScreenCaptureKit
import SwiftUI

/// Records the landing-page videos from the real app: the real notch window,
/// real SwiftUI springs and the live Nova 2 renderer, driven by a script and
/// filled with demo data. Debug builds only.
///
/// Safety: demo mode starts only the window. No agent socket, automations
/// (WhatsApp is never touched), security monitor, notifications, Spotify,
/// music tap or microphone. Only Nova's own window is recorded, over a drawn
/// wallpaper, so nothing from your screen appears.
@MainActor
enum DemoDirector {
    static var active = false

    static let clips = ["hero", "approval", "voice", "dance", "guard"]

    static func runIfRequested(_ coordinator: AppCoordinator) -> Bool {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--record-demo"), args.indices.contains(flag + 1) else { return false }
        let out = URL(fileURLWithPath: args[flag + 1])
        let wanted = Array(args[(flag + 2)...]).filter { clips.contains($0) }
        active = true
        logURL = out.appendingPathComponent("record.log")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? "demo started\n".write(to: logURL!, atomically: true, encoding: .utf8)
        coordinator.startDemo()
        Task {
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            for clip in wanted.isEmpty ? clips : wanted {
                do {
                    try await record(clip, coordinator: coordinator, to: out.appendingPathComponent("\(clip).mov"))
                    log("recorded \(clip)")
                } catch {
                    log("Couldn't record \(clip): \(error)")
                    if "\(error)".localizedCaseInsensitiveContains("declined") || "\(error)".contains("-3801") {
                        log("Allow Screen Recording for Nova in System Settings → Privacy & Security, then run again.")
                        exit(2)
                    }
                }
            }
            exit(0)
        }
        return true
    }

    private static var logURL: URL?

    private static func log(_ line: String) {
        guard let logURL, let handle = try? FileHandle(forWritingTo: logURL) else { return }
        handle.seekToEndOfFile()
        handle.write((line + "\n").data(using: .utf8)!)
        try? handle.close()
    }

    // MARK: Clips

    private static func record(_ clip: String, coordinator c: AppCoordinator, to url: URL) async throws {
        reset(c)
        try await Task.sleep(for: .seconds(0.8))
        guard let window = c.window?.panel else { return }
        let recorder = try await DemoRecorder.start(window: window, crop: crop(for: clip, c), to: url)
        try await Task.sleep(for: .seconds(0.6))
        switch clip {
        case "hero": await hero(c)
        case "approval": await approval(c)
        case "voice": await voice(c)
        case "dance": await dance(c)
        case "guard": await guardClip(c)
        default: break
        }
        try await recorder.stop()
    }

    /// The part of the canvas a clip needs: the notch plus the tallest panel it opens.
    private static func crop(for clip: String, _ c: AppCoordinator) -> CGRect {
        let width = NotchLayout.canvasSize.width
        let height: CGFloat = switch clip {
        case "voice": 150
        case "approval": 420
        default: 372
        }
        return CGRect(x: 0, y: 0, width: width, height: height)
    }

    private static func reset(_ c: AppCoordinator) {
        c.pendingVoiceAction = nil
        c.music.partyUntil = nil
        c.voice.loadPreview(.idle, transcript: "", reply: "", level: 0)
        c.state.selectedTab = .home
        c.transition(to: .idle, animated: false)
    }

    private static func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    private static func hero(_ c: AppCoordinator) async {
        startWorking(c)
        await wait(1.2)
        c.transition(to: .hover)
        await wait(0.9)
        c.transition(to: .compact)
        await wait(2.2)
        c.transition(to: .expandedHome)
        await wait(4.5)
        c.transition(to: .compact)
        await wait(1.6)
        c.transition(to: .idle)
        await wait(1.2)
    }

    private static func approval(_ c: AppCoordinator) async {
        startWorking(c)
        c.transition(to: .compact)
        await wait(1.8)
        var event = AgentEvent(agent: .claude, sessionId: "demo", event: .permissionRequest, tool: "Edit",
                               workingDirectory: "/Users/me/portfolio", filePath: "/Users/me/portfolio/Sources/APIClient.swift", requestId: "demo-edit")
        event.edit = EditPreview.diff(old: "func load() async throws -> [Item] {\n    let data = try await api.get(\"/items\")\n    return try decode(data)\n}",
                                      new: "func load() async throws -> [Item] {\n    let data = try await api.get(\"/items\", timeout: 10)\n    guard !data.isEmpty else { return [] }\n    return try decode(data)\n}",
                                      file: "/Users/me/portfolio/Sources/APIClient.swift")
        if let request = AgentPermissionRequest(event: event, now: Date()) { c.permissions.enqueue(request) }
        c.updatePermissionLayout()
        c.transition(to: .permissionRequest)
        await wait(3.6)
        c.permissions.decide(.allowOnce, for: "demo-edit")
        c.flash(.success, for: .milliseconds(900))
        c.transition(to: .compact)
        await wait(2.0)
        c.showBanner(NotchBanner(title: "Claude Code finished", subtitle: "Added a timeout and an empty check to the API client.", expression: .success),
                     for: .seconds(3))
        await wait(3.2)
    }

    private static func voice(_ c: AppCoordinator) async {
        c.showVoicePanel()
        let words = ["Hey", "Nova,", "google", "swift", "concurrency"]
        for i in 1...words.count {
            c.voice.loadPreview(.listening, transcript: i <= 2 ? "" : words[2..<i].joined(separator: " "), level: Double.random(in: 0.35...0.9))
            await wait(0.45)
        }
        for _ in 0..<4 {
            c.voice.loadPreview(.listening, transcript: "google swift concurrency", level: Double.random(in: 0.1...0.4))
            await wait(0.25)
        }
        c.voice.loadPreview(.thinking, transcript: "google swift concurrency", level: 0)
        await wait(1.1)
        for _ in 0..<10 {
            c.voice.loadPreview(.speaking, transcript: "", reply: "Searching for swift concurrency.", level: Double.random(in: 0.4...1))
            await wait(0.2)
        }
        c.voice.loadPreview(.speaking, transcript: "", reply: "Searching for swift concurrency.", level: 0)
        await wait(0.8)
        c.voice.loadPreview(.idle, transcript: "", reply: "", level: 0)
        c.closeVoice()
        await wait(1.0)
    }

    private static func dance(_ c: AppCoordinator) async {
        startWorking(c)
        c.music.partyUntil = Date().addingTimeInterval(30)
        c.transition(to: .expandedHome)
        await wait(7.5)
        c.music.partyUntil = nil
    }

    private static func guardClip(_ c: AppCoordinator) async {
        startWorking(c)
        c.security.loadPreview()
        c.transition(to: .expandedHome)
        await wait(1.2)
        c.openSecurity()
        await wait(5.5)
        c.backToHome()
        await wait(1.2)
    }

    /// A live Claude Code session plus the mock agents, as on a busy day.
    private static var working = false

    private static func startWorking(_ c: AppCoordinator) {
        // One session for every clip (adding it again would repeat its steps).
        guard !working else { return }
        working = true
        c.sessions.start()
        let cwd = "/Users/me/portfolio"
        let steps: [(AgentEvent.Kind, String?, String?)] = [
            (.sessionStart, nil, nil), (.prompt, nil, "Add retry with backoff to the API client"),
            (.toolStart, "Read", "Reading Models.swift"), (.toolEnd, "Read", nil),
            (.toolStart, "Edit", "Editing APIClient.swift"),
        ]
        for (kind, tool, text) in steps {
            c.sessions.ingest(AgentEvent(agent: .claude, sessionId: "demo", event: kind, tool: tool, description: text,
                                         workingDirectory: cwd, filePath: tool == "Edit" ? cwd + "/Sources/APIClient.swift" : nil))
        }
        c.state.agents = c.sessions.summaries() + AgentSummary.mocks.filter { $0.id != "claude" }
        if let first = c.state.agents.first?.id { c.state.focusedAgentID = first }
        c.integrations.loadPreview()
        c.spotify.loadPreview()
        c.launcher.loadDemo()
    }
}

/// Nova's demo wallpaper and a generic menu bar (nothing from your Mac).
struct DemoBackdrop: View {
    let notchHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x1B2350), Color(hex: 0x3A2A6B), Color(hex: 0x0E3B4F)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(hex: 0x6F7CFF).opacity(0.35), .clear], center: .init(x: 0.25, y: 0.9), startRadius: 10, endRadius: 420)
            HStack(spacing: 16) {
                Text("Window").fontWeight(.regular)
                Text("Help")
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Image(systemName: "magnifyingglass")
                Text("Mon 9:41")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 18)
            .frame(height: notchHeight)
            .background(Color.black.opacity(0.18))
        }
    }
}

/// Records one window with ScreenCaptureKit into a QuickTime movie.
final class DemoRecorder: NSObject, SCStreamOutput, @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var stream: SCStream?
    private var started = false
    private let queue = DispatchQueue(label: "nova.demo-recorder")

    private init(url: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 24_000_000],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
    }

    @MainActor
    static func start(window: NSWindow, crop: CGRect, to url: URL) async throws -> DemoRecorder {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw NSError(domain: "Nova", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nova's window isn't visible to ScreenCaptureKit."])
        }
        let scale = window.backingScaleFactor
        let width = Int(crop.width * scale) / 2 * 2, height = Int(crop.height * scale) / 2 * 2
        let recorder = try DemoRecorder(url: url, width: width, height: height)
        let config = SCStreamConfiguration()
        config.sourceRect = crop
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = false
        config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.ignoreShadowsSingleWindow = true
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: target), configuration: config, delegate: nil)
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: recorder.queue)
        recorder.writer.startWriting()
        try await stream.startCapture()
        recorder.stream = stream
        return recorder
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        if !started {
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            started = true
        }
        if input.isReadyForMoreMediaData { input.append(sampleBuffer) }
    }

    func stop() async throws {
        try await stream?.stopCapture()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.input.markAsFinished()
                self.writer.finishWriting { continuation.resume() }
            }
        }
    }
}
#endif
