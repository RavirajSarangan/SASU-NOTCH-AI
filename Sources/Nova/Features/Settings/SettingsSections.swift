import AppKit
import NovaKit
import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
    let coordinator: AppCoordinator

    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @ViewState private var loginError: String?

    var body: some View {
        @Bindable var prefs = coordinator.prefs
        SettingsHeader(title: "General", subtitle: "")
        SettingsCard(title: "Startup", symbol: "power") {
            Toggle("Launch Nova at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch {
                        loginError = "Couldn't change the login item: \(error.localizedDescription). Move Nova.app to /Applications and try again."
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(Theme.warning) }
            Toggle("Start minimized (menu bar only, show the notch from the ✨ menu)", isOn: $prefs.startHidden)
        }
        SettingsCard(title: "Screen", symbol: "display") {
            Picker("Show Nova on", selection: $prefs.screen) {
                ForEach(ScreenChoice.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
        }
        NotchAppsSettings(launcher: coordinator.launcher)
    }
}

struct AppearanceSettings: View {
    @Bindable var prefs: NovaPreferences

    var body: some View {
        SettingsHeader(title: "Appearance", subtitle: "Nova is designed for dark mode, so the notch always blends with the camera housing.")
        SettingsCard(title: "Panel", symbol: "rectangle.topthird.inset.filled") {
            Picker("Panel size", selection: $prefs.panelSize) {
                ForEach(PanelSize.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            LabeledSlider(title: "Card glow", value: $prefs.glow, range: 0...1.5, format: { "\(Int($0 * 100))%" })
        }
        SettingsCard(title: "Motion", symbol: "wind") {
            Toggle("Animations", isOn: $prefs.animations)
            Toggle("Reduce motion", isOn: $prefs.reduceMotion)
            Text("Reduce motion is also on whenever it's enabled in System Settings → Accessibility → Display.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct NovaSettings: View {
    let coordinator: AppCoordinator

    private var voiceNote: String {
        var note = "Speech is recognised on your Mac only and never saved. Voice can deny an agent request but never approve one. "
        note += VoiceService.tamilRecognitionOnDevice ? "Tamil works offline on this Mac. " : "Tamil can't be recognised offline on this Mac yet, so Nova listens in English. "
        note += VoiceService.tamilVoiceInstalled ? "A Tamil voice is installed for replies." : "For Tamil replies, add a Tamil voice in System Settings → Accessibility → Spoken Content."
        return note
    }

    @ViewState private var previewExpression: NovaExpression = .happy

    var body: some View {
        @Bindable var prefs = coordinator.prefs
        @Bindable var sound = coordinator.sound
        SettingsHeader(title: "Nova", subtitle: "How your companion looks, moves and sounds.")
        HStack(alignment: .top, spacing: 18) {
            NovaCharacterView(art: .body, expression: previewExpression, cursor: coordinator.cursor, anchor: NSEvent.mouseLocation)
                .frame(width: 120 * prefs.characterScale, height: 110 * prefs.characterScale)
                .frame(width: 150, height: 140)
                .environment(\.novaStyle, prefs.style)
            SettingsCard(title: "Character", symbol: "face.smiling") {
                Picker("Style", selection: $prefs.characterStyle) {
                    Text("Classic").tag("classic")
                    Text("Nova 2 (new)").tag("nova2")
                }
                .pickerStyle(.segmented)
                .onChange(of: prefs.characterStyle) { coordinator.music.enabled = prefs.danceToMusic && prefs.characterStyle == "nova2" }
                if prefs.characterStyle == "nova2" {
                    Picker("Skin", selection: $prefs.characterSkin) {
                        ForEach(RigSkin.order, id: \.self) { id in Text(RigSkin.named(id).name).tag(id) }
                    }
                    Toggle("Animated backgrounds for each mood", isOn: $prefs.sceneBackgrounds)
                    Toggle("Dance to music (Spotify, Music)", isOn: $prefs.danceToMusic)
                        .onChange(of: prefs.danceToMusic) { coordinator.music.enabled = prefs.danceToMusic && prefs.characterStyle == "nova2" }
                    if prefs.danceToMusic {
                        Text(coordinator.music.listening
                             ? "Listening for the beat. Audio is analysed on your Mac and never saved or sent."
                             : "macOS asks once to let Nova hear Spotify or Music. Without it, Nova dances to a steady groove.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledSlider(title: "Size on Home", value: $prefs.characterScale, range: 0.8...1.25, format: { "\(Int($0 * 100))%" })
                LabeledSlider(title: "Animation intensity", value: $prefs.motionIntensity, range: 0...1.5, format: { $0 == 0 ? "Still" : "\(Int($0 * 100))%" })
                Toggle("Eyes follow the cursor", isOn: $prefs.eyeTracking)
                Toggle("Pose for each emotion", isOn: $prefs.characterPoses)
                Toggle("Reactions (hop, shake, pop when the mood changes)", isOn: $prefs.characterReactions)
                Toggle("Effects (hearts, Zs, sparkles, confetti)", isOn: $prefs.characterEffects)
            }
        }
        SettingsCard(title: "Voice", symbol: "mic.fill") {
            Toggle("Talk to Nova (hold ⌥ Space, or click the mic)", isOn: $prefs.voiceEnabled)
                .onChange(of: prefs.voiceEnabled) { coordinator.applyVoicePrefs() }
            Toggle("Listen for “Hey Nova”", isOn: $prefs.voiceWakeWord)
                .disabled(!prefs.voiceEnabled)
                .onChange(of: prefs.voiceWakeWord) { coordinator.applyVoicePrefs() }
            Picker("Language", selection: $prefs.voiceLanguage) {
                Text("Automatic").tag("auto")
                Text("English (US)").tag("en-US")
                Text("English (India)").tag("en-IN")
                Text("Tamil").tag("ta-IN")
            }
            .onChange(of: prefs.voiceLanguage) { coordinator.applyVoicePrefs() }
            Toggle("Follow-up questions (keep listening 6 s after a reply)", isOn: $prefs.voiceFollowUps)
                .disabled(!prefs.voiceEnabled)
            Toggle("Speak replies out loud", isOn: $prefs.voiceSpeakReplies)
                .onChange(of: prefs.voiceSpeakReplies) { coordinator.applyVoicePrefs() }
            LabeledSlider(title: "Speaking speed", value: $prefs.voiceRate, range: 0.35...0.6, format: { $0 < 0.45 ? "Slow" : $0 > 0.53 ? "Fast" : "Normal" })
                .onChange(of: prefs.voiceRate) { coordinator.applyVoicePrefs() }
            Text(voiceNote).font(.caption).foregroundStyle(.secondary)
        }
        RoutinesCard(coordinator: coordinator)
        SettingsCard(title: "Recent voice actions", symbol: "list.bullet.rectangle") {
            let entries = ActionLog.shared.entries.suffix(12).reversed()
            if entries.isEmpty {
                Text("Nothing yet. Everything you ask Nova to do is listed here, on this Mac only.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(entries)) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.date.formatted(date: .omitted, time: .shortened)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.request).font(.callout)
                        if !entry.result.isEmpty { Text(entry.result).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                }
            }
            Text("Voice never approves agent requests, runs shell commands, deletes files, changes settings or pays for anything. Sending a message waits for “send” or a click.")
                .font(.caption).foregroundStyle(.secondary)
        }
        SettingsCard(title: "Emotions", symbol: "theatermasks.fill") {
            Text("Click an emotion to see Nova's pose, reaction and sound.").font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(NovaExpression.allCases, id: \.self) { expression in
                    Button {
                        previewExpression = expression
                        if let cue = expression.soundCue { sound.play(cue) }
                    } label: {
                        Text(expression.rawValue.capitalized).font(.caption).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(previewExpression == expression ? Theme.cyan : nil)
                }
            }
        }
        SettingsCard(title: "Sounds", symbol: "speaker.wave.2") {
            Toggle("Sounds", isOn: Binding(get: { !sound.isMuted }, set: { sound.isMuted = !$0 }))
            Picker("Sound style", selection: $sound.pack) {
                ForEach(SoundPack.allCases) { pack in Text(pack.label).tag(pack) }
            }
            .pickerStyle(.segmented)
            .disabled(sound.isMuted)
            .onChange(of: sound.pack) { sound.play(.success) }
            LabeledSlider(title: "Volume", value: $sound.volume, range: 0...1, format: { "\(Int($0 * 100))%" })
                .disabled(sound.isMuted)
            Toggle("Open & close sounds", isOn: $sound.interfaceSounds).disabled(sound.isMuted)
            Toggle("Reaction sounds (each emotion has its own chirp)", isOn: $sound.reactionSounds).disabled(sound.isMuted)
            HStack {
                ForEach([SoundCue.taskDone, .permission, .security, .sent, .success, .error], id: \.self) { cue in
                    Button(cue.rawValue.capitalized) { sound.play(cue) }
                }
            }
            .controlSize(.small)
            .disabled(sound.isMuted)
        }
    }
}

struct NotificationSettings: View {
    @Bindable var prefs: NovaPreferences
    let service: NotificationService

    @ViewState private var authorized = false

    var body: some View {
        SettingsHeader(title: "Notifications", subtitle: "macOS notifications in addition to the notch. Permission requests include Allow Once and Deny buttons.")
        SettingsCard(title: "Permission", symbol: "bell") {
            if authorized {
                Label("Notifications are allowed", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
            } else {
                Text("Nova isn't allowed to post notifications yet.").font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Allow notifications") { Task { authorized = await service.requestAuthorization() } }
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                }
            }
            Toggle("Only when I'm away from the notch (urgent ones always notify)", isOn: $prefs.notifyOnlyWhenAway)
        }
        SettingsCard(title: "Notify me about", symbol: "list.bullet") {
            ForEach(NovaNotificationKind.allCases) { kind in
                Toggle(kind.title, isOn: Binding(get: { prefs.notifications.contains(kind) },
                                                 set: { on in if on { prefs.notifications.insert(kind) } else { prefs.notifications.remove(kind) } }))
            }
        }
        .task {
            await service.refreshAuthorization()
            authorized = service.authorized
        }
    }
}

struct PrivacySettings: View {
    let coordinator: AppCoordinator

    @ViewState private var confirmSecrets = false
    @ViewState private var confirmReset = false

    var body: some View {
        SettingsHeader(title: "Privacy", subtitle: "Everything Nova stores stays on this Mac.")
        SettingsCard(title: "What Nova stores", symbol: "internaldrive") {
            VStack(alignment: .leading, spacing: 4) {
                Text("• API keys and tokens: macOS Keychain only")
                Text("• Chat history and automation settings: ~/Library/Application Support/Nova")
                Text("• Preferences: macOS user defaults")
                Text("• WhatsApp: read-only, only the chats you add; nothing is copied")
            }
            .font(.callout).foregroundStyle(.secondary)
            Text("Text is sent only to the AI provider you choose, and only for chat, summaries and drafts.")
                .font(.caption).foregroundStyle(.secondary)
        }
        SettingsCard(title: "Clear data", symbol: "trash") {
            HStack {
                Button("Clear chat history") { coordinator.chat.clear() }
                Button("Remove all secrets…", role: .destructive) { confirmSecrets = true }
                Button("Reset app data…", role: .destructive) { confirmReset = true }
            }
        }
        .confirmationDialog("Remove every API key and token Nova stored in the Keychain?", isPresented: $confirmSecrets) {
            Button("Remove all secrets", role: .destructive) {
                KeychainManager.shared.deleteAll()
                coordinator.ai.keysChanged()
            }
        }
        .confirmationDialog("Reset Nova? This removes all settings, history, automations and secrets, then restarts Nova.",
                            isPresented: $confirmReset) {
            Button("Reset and restart", role: .destructive) { coordinator.resetAppData() }
        }
    }
}

struct AdvancedSettings: View {
    let coordinator: AppCoordinator

    var body: some View {
        SettingsHeader(title: "Advanced", subtitle: "")
        SettingsCard(title: "Local socket", symbol: "point.3.filled.connected.trianglepath.dotted") {
            if let error = coordinator.agentSocketError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning).font(.callout)
            } else {
                Label("Listening for agents", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success).font(.callout)
            }
            CommandBox(command: NovaPaths.socketPath)
            Text("Logs: Console.app → search “app.nova.companion”.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Reveal data folder") { NSWorkspace.shared.open(NovaPathsApp.support) }
                Button("Simulate an agent session") { coordinator.runDemoSession() }
            }
        }
        SettingsCard(title: "Help", symbol: "questionmark.circle") {
            HStack {
                Button("Show onboarding again") { coordinator.showOnboarding() }
                Button("Send a test notification") {
                    Task {
                        _ = await coordinator.notifications.requestAuthorization()
                        coordinator.notifications.post(.agentCompleted, title: "Test notification", body: "Notifications from Nova are working.")
                    }
                }
                Button("Play all sounds") { Task { await coordinator.sound.playAll() } }
            }
        }
    }
}

struct AboutSettings: View {
    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        HStack(spacing: 16) {
            Image(nsImage: MascotAssets.head).resizable().aspectRatio(contentMode: .fit).frame(width: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text("Nova").font(.largeTitle.weight(.bold))
                Text("Your AI companion in the notch · version \(version)").foregroundStyle(.secondary)
            }
        }
        SettingsCard(title: "Credits", symbol: "heart") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nova character art: created for this project.")
                Text("Brand icons: Simple Icons (CC0). Trademarks belong to their owners.")
                Text("Sounds: synthesized by Nova; no audio assets.")
                Text("Built with Swift, SwiftUI and AppKit. No servers, no tracking.")
            }
            .font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String

    var body: some View {
        HStack {
            Text(title).frame(width: 150, alignment: .leading)
            Slider(value: $value, in: range).frame(maxWidth: 220)
            Text(format(value)).monospacedDigit().foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
        }
    }
}

/// Routines: say the name (or a phrase) and Nova runs the steps. Steps that
/// send, type, click, quit or lock still wait for your “go”.
private struct RoutinesCard: View {
    let coordinator: AppCoordinator

    var body: some View {
        @Bindable var store = coordinator.routines
        SettingsCard(title: "Routines", symbol: "list.number") {
            Text("Say a routine's name (or one of its phrases) and Nova runs the steps. Or say “make a routine called gym: open Spotify, timer 45 minutes”.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach($store.routines) { $routine in
                RoutineEditor(routine: $routine, coordinator: coordinator) {
                    store.routines.removeAll { $0.id == routine.id }
                }
                Divider()
            }
            Button("New routine") {
                store.routines.append(Routine(name: "New routine", phrases: [], steps: [], enabled: true))
            }
        }
    }
}

private struct RoutineEditor: View {
    @Binding var routine: Routine
    let coordinator: AppCoordinator
    let delete: () -> Void

    enum StepKind: String, CaseIterable, Identifiable {
        case openApp = "Open app", website = "Open website", search = "Search Google", timer = "Timer (minutes)",
             shortcut = "Run shortcut", agenda = "Today's calendar", status = "Agent status", check = "System check",
             play = "Play music", pause = "Pause music", mute = "Mute"
        var id: String { rawValue }
        var needsValue: Bool { [.openApp, .website, .search, .timer, .shortcut].contains(self) }
    }

    @ViewState private var kind = StepKind.openApp
    @ViewState private var value = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: $routine.enabled).labelsHidden()
                TextField("Name", text: $routine.name).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Spacer()
                Button("Run") { coordinator.runRoutineNow(routine) }.disabled(routine.intents.isEmpty)
                Button("Delete", role: .destructive, action: delete)
            }
            TextField("Also start it with (comma separated)", text: Binding(
                get: { routine.phrases.joined(separator: ", ") },
                set: { routine.phrases = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                .textFieldStyle(.roundedBorder)
            ForEach(Array(routine.steps.enumerated()), id: \.offset) { index, step in
                HStack {
                    Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                    Text(step.intent.map(AppCoordinator.describe) ?? "Unknown step").font(.callout)
                    if let intent = step.intent, VoiceSafety.needsConfirmation(intent) {
                        Text("asks first").font(.caption2).foregroundStyle(Theme.warning)
                    }
                    Spacer()
                    if index > 0 {
                        Button { routine.steps.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }.buttonStyle(.borderless)
                    }
                    Button { routine.steps.remove(at: index) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            HStack {
                Picker("Add step", selection: $kind) { ForEach(StepKind.allCases) { Text($0.rawValue).tag($0) } }
                    .frame(maxWidth: 240)
                if kind.needsValue { TextField(kind == .timer ? "10" : "Name or text", text: $value).textFieldStyle(.roundedBorder).frame(maxWidth: 180) }
                Button("Add") { add() }.disabled(kind.needsValue && value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func add() {
        let v = value.trimmingCharacters(in: .whitespaces)
        let intent: VoiceIntent? = switch kind {
        case .openApp: .openApp(v)
        case .website: .openWebsite(v)
        case .search: .webSearch(engine: .google, query: v)
        case .timer: Int(v).map { .timer(seconds: max(1, $0) * 60) }
        case .shortcut: .runShortcut(v)
        case .agenda: .agenda(.today)
        case .status: .status
        case .check: .systemCheck
        case .play: .music(.play)
        case .pause: .music(.pause)
        case .mute: .mute(true)
        }
        if let intent, let step = RoutineStep(intent) { routine.steps.append(step) }
        value = ""
    }
}

