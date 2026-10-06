import AppKit
import SwiftUI

@main
struct NovaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Nova", systemImage: "sparkles") {
            let coordinator = appDelegate.coordinator
            Button("Open Nova") { coordinator.open() }
            Button(coordinator.state.isVisible ? "Hide from Notch" : "Show in Notch") {
                coordinator.toggleVisibility()
            }
            Button("Settings…") { coordinator.openSettings(.general) }
                .keyboardShortcut(",")
            Button("Show Onboarding…") { coordinator.showOnboarding() }
            Button("Test Notification") { coordinator.showTestBanner() }
            Toggle("Mute Sounds", isOn: Binding(
                get: { coordinator.sound.isMuted },
                set: { coordinator.sound.isMuted = $0 }
            ))
            Divider()
            Button("Quit Nova") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if SnapshotExporter.runIfRequested() { exit(0) }
        if CommandLine.arguments.contains("--sound-test") {
            Task { await SoundTester.run(coordinator.sound); exit(0) }
            return
        }
        #endif
        // Menu bar utility: no Dock icon even when launched via `swift run`.
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if DemoDirector.runIfRequested(coordinator) { return }
        #endif
        coordinator.start()
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--ask-nova"), CommandLine.arguments.indices.contains(i + 1) {
            // Debug: route typed sentences through voice handling and print the replies (silent).
            let lines = Array(CommandLine.arguments[(i + 1)...])
            coordinator.voice.speakReplies = false
            Task { @MainActor [coordinator] in
                try? await Task.sleep(for: .seconds(2))
                for line in lines {
                    coordinator.voice.loadPreview(.thinking, transcript: line, level: 0)
                    await coordinator.handleVoice(line)
                    FileHandle.standardError.write("» \(line)\n  \(coordinator.voice.reply)\n".data(using: .utf8)!)
                }
                exit(0)
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--capture-home"), CommandLine.arguments.indices.contains(i + 1) {
            coordinator.debugCaptureHome(to: CommandLine.arguments[i + 1])
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.shutdown()
    }
}
