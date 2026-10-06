import AppKit
import Foundation
import Observation

/// Spotify now-playing. Track info comes from Spotify's own distributed
/// notification (no permission needed). Controls and artwork use AppleScript,
/// which macOS asks the user to allow once.
@Observable
@MainActor
final class SpotifyService {
    struct Track: Equatable {
        var id: String
        var name: String
        var artist: String
        var album: String
        var duration: TimeInterval
    }

    private(set) var track: Track?
    private(set) var isPlaying = false
    private(set) var isRunning = false
    private(set) var artwork: NSImage?
    private(set) var controlError: String?
    /// Playback position at `positionDate`, for a smooth progress bar.
    private(set) var position: TimeInterval = 0
    private(set) var positionDate = Date()

    static let bundleID = "com.spotify.client"
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Called on every playback update (Nova 2 dances while music plays).
    @ObservationIgnored var onPlayingChanged: ((Bool) -> Void)?
    @ObservationIgnored private var artworkTrackID: String?

    struct PlaybackInfo: Sendable {
        var id, name, artist, album, state: String
        var durationMs: Double
        var position: Double
    }

    func start() {
        refreshRunning()
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main
        ) { [weak self] note in
            let info = note.userInfo ?? [:]
            let playback = PlaybackInfo(id: info["Track ID"] as? String ?? "", name: info["Name"] as? String ?? "",
                                        artist: info["Artist"] as? String ?? "", album: info["Album"] as? String ?? "",
                                        state: info["Player State"] as? String ?? "",
                                        durationMs: (info["Duration"] as? NSNumber)?.doubleValue ?? 0,
                                        position: (info["Playback Position"] as? NSNumber)?.doubleValue ?? 0)
            Task { @MainActor in self?.apply(playback) }
        })
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshRunning() }
            })
        }
    }

    var progress: Double {
        guard let track, track.duration > 0 else { return 0 }
        let now = isPlaying ? position + Date().timeIntervalSince(positionDate) : position
        return min(max(now / track.duration, 0), 1)
    }

    private func refreshRunning() {
        isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
        if !isRunning {
            track = nil
            isPlaying = false
            artwork = nil
        }
    }

    func apply(_ info: PlaybackInfo) {
        isRunning = true
        isPlaying = info.state == "Playing"
        onPlayingChanged?(isPlaying)
        guard info.state != "Stopped", !info.name.isEmpty else {
            track = nil
            return
        }
        track = Track(id: info.id, name: info.name, artist: info.artist, album: info.album, duration: info.durationMs / 1000)
        position = info.position
        positionDate = Date()
        if info.id != artworkTrackID { Task { await loadArtwork(for: info.id) } }
    }

    #if DEBUG
    func loadPreview() {
        isRunning = true
        isPlaying = true
        track = Track(id: "preview", name: "Kaathalae Kaathalae", artist: "Govind Vasantha", album: "96", duration: 240)
        position = 96
        positionDate = Date()
    }
    #endif

    // MARK: - Controls (AppleScript)

    func playPause() { run("playpause") }
    func next() { run("next track") }
    func previous() { run("previous track") }

    func open() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Sends a command to Spotify. AppleScript waits for Spotify to answer
    /// (seconds, if it's launching), so it runs on its own queue, never the
    /// main thread.
    private func run(_ command: String) {
        let source = "tell application \"Spotify\" to \(command)"
        Self.scriptQueue.async { [weak self] in
            var error: NSDictionary?
            _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let code = error?[NSAppleScript.errorNumber] as? Int
            Task { @MainActor in
                self?.controlError = code == -1743 ? "Allow Nova to control Spotify in System Settings → Privacy & Security → Automation." : nil
            }
        }
    }

    private static let scriptQueue = DispatchQueue(label: "nova.spotify-script", qos: .userInitiated)

    /// Asks Spotify for a value, off the main thread.
    private func query(_ expression: String) async -> String? {
        let source = "tell application \"Spotify\" to \(expression)"
        return await withCheckedContinuation { continuation in
            Self.scriptQueue.async {
                var error: NSDictionary?
                let value = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
                continuation.resume(returning: error == nil ? value : nil)
            }
        }
    }

    private func loadArtwork(for trackID: String) async {
        artworkTrackID = trackID
        guard let urlString = await query("artwork url of current track"), let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else {
            artwork = nil
            return
        }
        if artworkTrackID == trackID { artwork = NSImage(data: data) }
    }
}
