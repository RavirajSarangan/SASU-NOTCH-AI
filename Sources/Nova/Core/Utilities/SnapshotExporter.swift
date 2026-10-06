#if DEBUG
import AppKit
import NovaKit
import SwiftUI

/// Debug tool: renders the notch in each state to PNGs without needing
/// Screen Recording permission.
///   swift run Nova --snapshot /path/to/dir
@MainActor
enum SnapshotExporter {
    /// Landing-page mode: transparent around the notch, buttons shown enabled.
    static var landing = false
    static var backdrop: Color { landing ? .clear : Color(white: 0.32) }

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--landing-screens"), args.indices.contains(flag + 1) {
            landing = true
            PermissionRequestView.startArmed = true
            export(to: URL(fileURLWithPath: args[flag + 1]))
            return true
        }
        if args.contains("--bench-rig") { benchmarkRig(); return true }
        guard let flag = args.firstIndex(of: "--snapshot"), args.indices.contains(flag + 1) else { return false }
        export(to: URL(fileURLWithPath: args[flag + 1]))
        return true
    }

    static func export(to directory: URL) {
        IsolatedHostSwitch.enabled = false   // ImageRenderer can't draw embedded NSViews
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let screens: [(String, NotchGeometry)] = [
            ("notch", NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchWidth: 185, notchHeight: 32, hasNotch: true)),
            ("plain", .fallback),
        ]
        // (file suffix, state, tab, focused agent)
        let variants: [(String, NotchState, NovaTab, String)] = [
            ("idle", .idle, .home, "claude"), ("hover", .hover, .home, "claude"),
            ("compact", .compact, .home, "claude"), ("sleep", .sleep, .home, "claude"),
            ("home", .expandedHome, .home, "claude"), ("home-gemini", .expandedHome, .home, "gemini"),
            ("home-cursor", .expandedHome, .home, "cursor"), ("chat", .aiChat, .chat, "claude"),
            ("notification", .notification, .home, "claude"),
        ]

        for (screenName, geometry) in screens {
            for (suffix, state, tab, agent) in variants {
                let coordinator = AppCoordinator()
                coordinator.state.geometry = geometry
                coordinator.state.notchState = state
                coordinator.state.selectedTab = tab
                coordinator.state.agents = AgentSummary.mocks
                coordinator.integrations.loadPreview()
                coordinator.spotify.loadPreview()
                coordinator.launcher.loadDemo()
                if suffix == "chat" {
                    coordinator.chat.messages = [
                        AIMessage(role: .user, text: "How do I debounce a search field in SwiftUI?"),
                        AIMessage(role: .assistant, text: "Use **`task(id:)`** with a short sleep. It cancels itself whenever the text changes:\n\n```swift\n.task(id: query) {\n    try? await Task.sleep(for: .milliseconds(300))\n    await search(query)\n}\n```\n\nNo Combine needed."),
                    ]
                }
                coordinator.state.focusedAgentID = agent
                coordinator.state.banner = NotchBanner(title: "Rate limit reached",
                                                       subtitle: "Retrying in a few seconds.",
                                                       expression: .dizzy)
                let size = coordinator.state.size
                let view = NotchRootView(coordinator: coordinator)
                    .frame(width: NotchLayout.canvasSize.width, height: NotchLayout.canvasSize.height)
                    .background(SnapshotExporter.backdrop)
                    .frame(width: max(size.width + 60, 200), height: size.height + 40, alignment: .top)
                    .clipped()
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.cgImage else { continue }
                let rep = NSBitmapImageRep(cgImage: image)
                let url = directory.appendingPathComponent("\(screenName)-\(suffix).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                print("wrote \(url.path)")
            }
        }

        // Live-data screens: permission requests at each risk level, and a session.
        let commands = [("low", "Edit", nil as String?, "/Users/me/project/Sources/App.swift"),
                        ("medium", "Bash", "npm install left-pad" as String?, nil as String?),
                        ("high", "Bash", "rm -rf ~/project/build && git push --force" as String?, nil as String?)]
        for (name, tool, command, file) in commands {
            let coordinator = AppCoordinator()
            coordinator.state.geometry = screens[0].1
            var event = AgentEvent(agent: .claude, sessionId: "snap", event: .permissionRequest, tool: tool,
                                   command: command, workingDirectory: "/Users/me/project", filePath: file, requestId: name)
            if name == "low" {
                event.edit = EditPreview.diff(old: "func load() async throws -> [Item] {\n    let data = try await api.get(\"/items\")\n    return try decode(data)\n}",
                                              new: "func load() async throws -> [Item] {\n    let data = try await api.get(\"/items\", timeout: 10)\n    guard !data.isEmpty else { return [] }\n    return try decode(data)\n}",
                                              file: file)
            }
            if let request = AgentPermissionRequest(event: event, now: Date()) {
                coordinator.permissions.enqueue(request)
                if name == "medium" { coordinator.permissions.enqueue(AgentPermissionRequest(event: event, now: Date())!) }
            }
            coordinator.state.notchState = .permissionRequest
            coordinator.updatePermissionLayout()
            render(NotchRootView(coordinator: coordinator), state: coordinator.state, to: directory, name: "permission-\(name)")
        }
        do {
            // An agent's question, answered in the notch.
            let coordinator = AppCoordinator()
            coordinator.state.geometry = screens[0].1
            var event = AgentEvent(agent: .claude, sessionId: "snap", event: .permissionRequest, tool: "AskUserQuestion",
                                   workingDirectory: "/Users/me/portfolio", requestId: "question")
            event.questions = [AgentQuestion(question: "Which database should I set up?", header: "Database", options: [
                .init(label: "Postgres", description: "Relational, best for most apps"),
                .init(label: "SQLite", description: "A single file, simplest to start"),
                .init(label: "Supabase", description: "Hosted Postgres with auth and storage"),
            ]), AgentQuestion(question: "Which features?", header: "Features", multiSelect: true,
                              options: [.init(label: "Auth"), .init(label: "Billing")])]
            if let request = AgentPermissionRequest(event: event, now: Date()) { coordinator.permissions.enqueue(request) }
            coordinator.state.notchState = .permissionRequest
            coordinator.updatePermissionLayout()
            render(NotchRootView(coordinator: coordinator), state: coordinator.state, to: directory, name: "permission-question")
        }
        do {
            let coordinator = AppCoordinator()
            coordinator.state.geometry = screens[0].1
            coordinator.sessions.start()
            let cwd = "/Users/me/project"
            let steps: [(AgentEvent.Kind, String?, String?)] = [
                (.sessionStart, nil, nil), (.prompt, nil, "Add retry with backoff to the API client"),
                (.toolStart, "Read", "Reading Models.swift"), (.toolEnd, "Read", nil),
                (.toolStart, "Edit", "Editing APIClient.swift"), (.toolEnd, "Edit", nil),
                (.toolStart, "Bash", "Running swift test"),
            ]
            for (kind, tool, text) in steps {
                coordinator.sessions.ingest(AgentEvent(agent: .claude, sessionId: "live", event: kind, tool: tool,
                                                       description: text, workingDirectory: cwd,
                                                       filePath: tool == "Edit" ? cwd + "/Sources/APIClient.swift" : nil))
            }
            coordinator.state.agents = coordinator.sessions.summaries()
            coordinator.integrations.loadPreview()
            coordinator.spotify.loadPreview()
            coordinator.launcher.loadDemo()
            coordinator.state.notchState = .agentSession
            render(NotchRootView(coordinator: coordinator), state: coordinator.state, to: directory, name: "session")
            coordinator.state.notchState = .expandedHome
            render(NotchRootView(coordinator: coordinator), state: coordinator.state, to: directory, name: "home-live")
            // Busy: a second Claude session in another project, many tools, a long project name.
            let other = "/Users/me/a-really-long-project-name-for-layout"
            for i in 0..<8 {
                coordinator.sessions.ingest(AgentEvent(agent: .claude, sessionId: "busy", event: .toolStart, tool: "Bash",
                                                       description: "Running step \(i)", workingDirectory: other))
                coordinator.sessions.ingest(AgentEvent(agent: .claude, sessionId: "busy", event: .toolEnd, tool: "Bash", workingDirectory: other))
            }
            coordinator.sessions.ingest(AgentEvent(agent: .claude, sessionId: "busy", event: .toolStart, tool: "Bash",
                                                   description: "Running ls", workingDirectory: other))
            coordinator.state.agents = coordinator.sessions.summaries()
            coordinator.state.focusedAgentID = "busy"
            render(NotchRootView(coordinator: coordinator), state: coordinator.state, to: directory, name: "home-busy")
            coordinator.music.partyUntil = Date().addingTimeInterval(30)
            coordinator.state.agents = AgentKind.allCases.map { AgentSummary.live($0, session: nil) }
            render(NotchRootView(coordinator: coordinator), state: coordinator.state, to: directory, name: "home-dance")
            coordinator.music.partyUntil = nil
            coordinator.state.integrationFocus = .service(.github)
            coordinator.state.notchState = .integrationView
            render(NotchRootView(coordinator: coordinator), state: coordinator.state, to: directory, name: "integration-github")
            coordinator.state.focusedAgentID = "cursor"
            coordinator.state.notchState = .expandedHome
            render(NotchRootView(coordinator: coordinator), state: coordinator.state, to: directory, name: "home-disconnected")
            coordinator.sessions.stop()
        }

        // Chat bubbles (the live ScrollView/TextField can't be rendered offscreen).
        let bubbles = VStack(alignment: .leading, spacing: 10) {
            MessageBubble(message: AIMessage(role: .user, text: "How do I debounce a search field in SwiftUI?"))
            MessageBubble(message: AIMessage(role: .assistant, text: "Use **`task(id:)`** with a short sleep. It cancels itself whenever the text changes:\n\n```swift\n.task(id: query) {\n    try? await Task.sleep(for: .milliseconds(300))\n    await search(query)\n}\n```\n\nNo *Combine* needed."))
        }
        .padding(16)
        .frame(width: 560)
        .background(Theme.panel)
        let bubbleRenderer = ImageRenderer(content: bubbles)
        bubbleRenderer.scale = 2
        if let image = bubbleRenderer.cgImage {
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                .write(to: directory.appendingPathComponent("chat-bubbles.png"))
        }

        // Automations: brief tab, reply draft review, greeting review.
        do {
            let coordinator = AppCoordinator()
            coordinator.state.geometry = screens[0].1
            coordinator.google.previewSignedIn = true
            coordinator.brief.loadPreview()
            coordinator.state.selectedTab = .brief
            coordinator.state.notchState = .expandedHome
            render(NotchRootView(coordinator: coordinator), state: coordinator.state, to: directory, name: "brief")
            coordinator.whatsapp.loadPreview()
            coordinator.state.notchState = .integrationView
            render(NotchRootView(coordinator: coordinator), state: coordinator.state, to: directory, name: "review-draft")
            let other = AppCoordinator()
            other.state.geometry = screens[0].1
            other.whatsapp.loadPreview(greetings: true)
            other.state.notchState = .integrationView
            render(NotchRootView(coordinator: other), state: other.state, to: directory, name: "review-greetings")
        }

        // Onboarding pages.
        do {
            let coordinator = AppCoordinator()
            for page in OnboardingPage.allCases {
                let renderer = ImageRenderer(content: OnboardingView(coordinator: coordinator, startPage: page))
                renderer.scale = 1.5
                if let image = renderer.cgImage {
                    try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                        .write(to: directory.appendingPathComponent("onboarding-\(page.rawValue).png"))
                }
            }
        }

        // Mood gallery: the moods people actually see, at a readable size.
        let moods: [NovaExpression] = [.idle, .listening, .thinking, .coding, .happy, .success, .warning, .error, .sleepy, .sleeping]
        let gallery = LazyVGrid(columns: Array(repeating: GridItem(.fixed(200)), count: 5), spacing: 14) {
            ForEach(moods, id: \.self) { expression in
                VStack(spacing: 6) {
                    MoodPreview(expression: expression)
                        .frame(width: 150, height: 150)
                        .frame(width: 200, height: 170)
                    Text(expression.rawValue.capitalized).font(.headline).foregroundStyle(.white)
                }
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(16)
        .background(Theme.background)
        let galleryRenderer = ImageRenderer(content: gallery)
        galleryRenderer.scale = 2
        if let image = galleryRenderer.cgImage {
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                .write(to: directory.appendingPathComponent("moods.png"))
        }

        // Expression sheet for the character itself.
        let sheet = LazyVGrid(columns: Array(repeating: GridItem(.fixed(110)), count: 6), spacing: 8) {
            ForEach(NovaExpression.allCases, id: \.self) { expression in
                VStack(spacing: 2) {
                    NovaCharacterView(art: .body, expression: expression, cursor: CursorTrackingService(), anchor: .zero)
                        .frame(width: 100, height: 130)
                    Text(expression.rawValue).font(.caption).foregroundStyle(.white)
                }
            }
        }
        .padding(12)
        .background(Color(white: 0.2))
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        if let image = renderer.cgImage {
            let url = directory.appendingPathComponent("expressions.png")
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
            print("wrote \(url.path)")
        }
        exportNova2(to: directory)
        for (name, phase, transcript, reply) in [("voice-listening", VoiceService.Phase.listening, "What are my agents doing", ""),
                                                 ("voice-reply", .speaking, "What are my agents doing",
                                                  "Claude Code is working: Running swift test. Gemini CLI needs your approval.")] {
            let coordinator = AppCoordinator()
            coordinator.state.geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchWidth: 185, notchHeight: 32, hasNotch: true)
            coordinator.voice.loadPreview(phase, transcript: transcript, reply: reply)
            coordinator.state.notchState = .voice
            coordinator.state.voiceExpression = phase == .listening ? .listening : .happy
            render(NotchRootView(coordinator: coordinator), state: coordinator.state, to: directory, name: name)
        }
    }

    /// Times Nova 2 frames drawn offscreen (engine step + Canvas render) at real sizes.
    static func benchmarkRig() {
        for (label, side, headOnly) in [("notch head 34pt", 34.0, true), ("Home 160pt", 160.0, false)] {
            var engine = RigEngine(seed: 5)
            var input = RigInputs(mood: .coding)
            input.typingActivity = 0.6
            input.look = RigPoint(x: 0.3, y: 0.1)
            let frames = 240
            let start = CFAbsoluteTimeGetCurrent()
            for i in 0..<frames {
                let frame = engine.step(dt: 1.0 / 30, input)
                let view = Canvas { context, size in
                    var o = NovaRigRenderer.Options()
                    o.headOnly = headOnly
                    o.minimal = side < 70
                    o.variant = headOnly ? .peek : .pearl
                    o.time = Double(i) / 30
                    NovaRigRenderer.draw(frame, in: &context, size: size, options: o)
                }.frame(width: side, height: side)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                _ = renderer.cgImage
            }
            let ms = (CFAbsoluteTimeGetCurrent() - start) / Double(frames) * 1000
            print(String(format: "%@: %.2f ms per frame (≈ %.1f%% of one core at 30 fps)", label, ms, ms * 30 / 10))
        }
    }

    /// Nova 2 turnaround sheet: bodies, all 18 moods, sizes, skins and scene backgrounds.
    static func exportNova2(to directory: URL) {
        let sheet = VStack(alignment: .leading, spacing: 14) {
            Text("Nova 2 — bodies").font(.headline).foregroundStyle(.white)
            HStack(spacing: 10) {
                Nova2Still(mood: .happy, variant: .pearl).frame(width: 200, height: 200)
                Nova2Still(mood: .notification, variant: .peek).frame(width: 200, height: 200)
                Nova2Still(mood: .listening, variant: .orbit).frame(width: 200, height: 200)
                Nova2Still(mood: .idle, variant: .pearl, music: RigMusic(beat: 8, energy: 0.3)).frame(width: 200, height: 200)
            }
            Text("All 18 moods").font(.headline).foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(132)), count: 6), spacing: 8) {
                ForEach(RigMood.allCases, id: \.self) { mood in
                    VStack(spacing: 2) {
                        Nova2Still(mood: mood).frame(width: 128, height: 128)
                        Text(mood.rawValue).font(.caption).foregroundStyle(.white)
                    }
                }
            }
            Text("Sizes (24, 34, 54, 110, 160 pt) and skins").font(.headline).foregroundStyle(.white)
            HStack(alignment: .bottom, spacing: 12) {
                Nova2Still(mood: .idle, headOnly: true, background: false).frame(width: 24, height: 24).background(.black)
                Nova2Still(mood: .idle, headOnly: true, background: false).frame(width: 34, height: 34).background(.black)
                Nova2Still(mood: .notification, variant: .peek, background: false).frame(width: 54, height: 54)
                Nova2Still(mood: .idle, background: false).frame(width: 110, height: 110)
                Nova2Still(mood: .happy, background: false).frame(width: 160, height: 160)
                ForEach(RigSkin.order, id: \.self) { id in
                    Nova2Still(mood: id == "gold" ? .success : .idle, skin: id, background: false).frame(width: 110, height: 110)
                }
            }
            Text("Scene backgrounds").font(.headline).foregroundStyle(.white)
            HStack(spacing: 8) {
                ForEach([RigMood.idle, .coding, .thinking, .success, .error, .warning, .sleeping], id: \.self) { mood in
                    Nova2Still(mood: mood, scene: true).frame(width: 150, height: 150)
                }
                Nova2Still(mood: .idle, scene: true, guardAlert: true).frame(width: 150, height: 150)
            }
        }
        .padding(16)
        .background(Color(white: 0.16))
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        if let image = renderer.cgImage {
            let url = directory.appendingPathComponent("nova2.png")
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
            print("wrote \(url.path)")
        }
    }
}

/// A settled Nova 2 for snapshots (Reduce Motion snaps every joint to its target).
private struct Nova2Still: View {
    var mood: RigMood
    var variant: RigVariant = .pearl
    var skin = "aurora"
    var headOnly = false
    var music: RigMusic?
    var background = true
    var scene = false
    var guardAlert = false

    var body: some View {
        var engine = RigEngine(seed: 1)
        var input = RigInputs(mood: mood)
        input.variant = variant
        input.reduceMotion = true
        input.music = music
        input.guardAlert = guardAlert
        input.look = RigPoint(x: 0.15, y: 0.2)
        var frame = engine.step(dt: 1.0 / 30, input)
        frame.blink = 1
        if guardAlert { frame.shield = 0.45 }
        let sceneState = SceneState()
        let rigScene = RigScene.scene(for: frame.mood, dancing: frame.dancing, guardAlert: guardAlert)
        return Canvas { context, size in
            if scene {
                sceneState.draw(scene: rigScene, time: 12.3, beat: nil, in: &context, size: size)
            } else if background {
                context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14), with: .color(.hex(0x141B47)))
            }
            var o = NovaRigRenderer.Options()
            o.variant = headOnly ? .peek : variant
            o.headOnly = headOnly
            o.skin = RigSkin.named(skin)
            o.minimal = min(size.width, size.height) < 70
            o.time = 1.2
            NovaRigRenderer.draw(frame, in: &context, size: size, options: o)
        }
        .clipShape(RoundedRectangle(cornerRadius: scene ? 14 : 0))
    }
}

/// A settled (non-animating) Nova for snapshots: eases the mood fully in first.
private struct MoodPreview: View {
    let expression: NovaExpression

    var body: some View {
        let controller = NovaAnimationController()
        var frame = NovaFrame()
        for i in 0..<60 { frame = controller.frame(at: Double(i) / 30, gazeTarget: CGPoint(x: 0.15, y: 0.35), expression: expression, reduceMotion: false) }
        frame.blink = 1
        return ZStack {
            Image(nsImage: MascotAssets.body).resizable().interpolation(.high)
            Canvas { context, size in NovaCharacterRenderer.drawEyes(in: &context, size: size, frame: frame) }
        }
        .aspectRatio(1 / NovaArt.body.aspect, contentMode: .fit)
    }
}

extension SnapshotExporter {
    static func render(_ root: NotchRootView, state: AppState, to directory: URL, name: String) {
        let size = state.size
        let view = root
            .frame(width: NotchLayout.canvasSize.width, height: NotchLayout.canvasSize.height)
            .background(SnapshotExporter.backdrop)
            .frame(width: max(size.width + 60, 200), height: size.height + 40, alignment: .top)
            .clipped()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        let url = directory.appendingPathComponent("\(name).png")
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
    }
}

/// Debug tool: plays every sound cue in turn.  swift run Nova --sound-test
@MainActor
enum SoundTester {
    static func run(_ sound: SoundService) async {
        await sound.playAll(printing: true)
    }
}
#endif
