import AppKit
import NovaKit
import ServiceManagement
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(coordinator: AppCoordinator) {
        if window == nil {
            let host = NSHostingController(rootView: OnboardingView(coordinator: coordinator))
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(Theme.background)
            window.setContentSize(NSSize(width: 760, height: 540))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}

enum OnboardingPage: Int, CaseIterable {
    case meet, notch, tools, keys, services, ready

    var isOptionalStep: Bool { self == .tools || self == .keys || self == .services }
}

struct OnboardingView: View {
    let coordinator: AppCoordinator

    @ViewState private var page: OnboardingPage
    @ViewState private var forward = true

    init(coordinator: AppCoordinator, startPage: OnboardingPage = .meet) {
        self.coordinator = coordinator
        _page = ViewState(initialValue: startPage)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            AuroraBackdrop(intensity: 0.32)
                .frame(height: 170)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    switch page {
                    case .meet: MeetPage(coordinator: coordinator)
                    case .notch: NotchPage(coordinator: coordinator)
                    case .tools: ToolsPage(coordinator: coordinator)
                    case .keys: KeysPage(coordinator: coordinator)
                    case .services: ServicesPage(coordinator: coordinator)
                    case .ready: ReadyPage(coordinator: coordinator)
                    }
                }
                .id(page)
                .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 48)
                .padding(.top, 36)

                footer
            }
        }
        .environment(\.novaStyle, coordinator.prefs.style)
        .preferredColorScheme(.dark)
        .frame(width: 760, height: 540)
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 7) {
                ForEach(OnboardingPage.allCases, id: \.self) { p in
                    Capsule()
                        .fill(p == page ? Theme.cyan : Color.white.opacity(0.2))
                        .frame(width: p == page ? 20 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.35), value: page)
            Spacer()
            if page != .meet {
                PillButton(title: "Back", style: .quiet) { go(-1) }
            }
            if page.isOptionalStep {
                PillButton(title: "Skip for now", style: .quiet) { go(1) }
            }
            PillButton(title: page == .ready ? "Open Nova" : (page == .meet ? "Get started" : "Continue"),
                       systemImage: page == .ready ? "checkmark" : "arrow.right", style: .primary) {
                page == .ready ? coordinator.finishOnboarding() : go(1)
            }
            .frame(width: page == .ready ? 190 : 150)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }

    private func go(_ delta: Int) {
        guard let next = OnboardingPage(rawValue: page.rawValue + delta) else { return }
        forward = delta > 0
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { page = next }
    }
}

private struct PageTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
            Text(subtitle).font(.system(size: 15)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
    }
}

// MARK: - Pages

private struct MeetPage: View {
    let coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 22) {
            NovaCharacterView(art: .body, expression: .idle, cursor: coordinator.cursor, anchor: NSEvent.mouseLocation)
                .frame(width: 220, height: 200)
            PageTitle(title: "Welcome to Nova", subtitle: "An AI companion that lives in your notch. It monitors your coding agents\nand services, and lets you act in one click.")
        }
    }
}

private struct NotchPage: View {
    let coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 26) {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6)
                // 0–2 s idle, 2–3.2 s hover strip, 3.2–6 s open panel.
                let (w, h, label): (CGFloat, CGFloat, String) = t < 2 ? (150, 22, "Resting")
                    : t < 3.2 ? (250, 46, "Hover to preview") : (330, 170, "Click to open · Esc to close")
                VStack(spacing: 14) {
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Color(hex: 0x1B2340), Color(hex: 0x2A1E4A)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 440, height: 230)
                        NotchShape(topRadius: 6, bottomRadius: h > 30 ? 18 : 10)
                            .fill(Color.black)
                            .frame(width: w, height: h)
                            .overlay(alignment: .topLeading) {
                                Image(nsImage: MascotAssets.head).resizable().aspectRatio(contentMode: .fit)
                                    .frame(width: 18).padding(.leading, 12).padding(.top, 3)
                            }
                            .overlay {
                                if h > 100 {
                                    VStack(spacing: 6) {
                                        ForEach(0..<3, id: \.self) { i in
                                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08 - Double(i) * 0.015))
                                                .frame(height: i == 0 ? 54 : 22)
                                        }
                                    }
                                    .padding(.horizontal, 14).padding(.top, 30).padding(.bottom, 12)
                                    .transition(.opacity)
                                }
                            }
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: w)
                    }
                    Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.cyan)
                        .animation(.easeInOut, value: label)
                }
            }
            PageTitle(title: "Lives in your notch", subtitle: "Always one glance away, never in the way of your menu bar.")
        }
    }
}

private struct ToolsPage: View {
    let coordinator: AppCoordinator
    @ViewState private var installed = ClaudeHookStatus.isInstalled

    var body: some View {
        VStack(spacing: 20) {
            PageTitle(title: "Connect your tools", subtitle: "See agent activity and approve commands from the notch.")
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    LogoTile(mark: .claude, size: 26)
                    Text("Claude Code").font(.headline).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Label(installed ? "Connected" : "Not connected", systemImage: installed ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.callout).foregroundStyle(installed ? Theme.success : Theme.textSecondary)
                }
                Text("Run in Terminal from the Nova folder:").font(.callout).foregroundStyle(.secondary)
                CommandBox(command: "scripts/install_claude_hook.sh")
                HStack {
                    LogoTile(mark: .vscode, size: 26)
                    Text("VS Code (optional)").font(.headline).foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
                CommandBox(command: "scripts/install_vscode_extension.sh")
                HStack {
                    Button("Check again") { installed = ClaudeHookStatus.isInstalled }
                    Button("Run a demo session") { coordinator.runDemoSession(); coordinator.open() }
                }
            }
            .padding(18)
            .premiumCard()
        }
    }
}

private struct KeysPage: View {
    let coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 18) {
            PageTitle(title: "Add an AI provider (optional)", subtitle: "Used for chat, the morning brief and reply drafts. Keys are stored in your Keychain.")
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(AIProviderKind.allCases) { kind in ProviderKeyRow(ai: coordinator.ai, kind: kind) }
                }
            }
            .frame(maxHeight: 280)
        }
    }
}

private struct ServicesPage: View {
    let coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 22) {
            PageTitle(title: "Connect services", subtitle: "Deployments, workflows, payments and service health. Read-only.")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(IntegrationKind.allCases) { kind in
                    HStack(spacing: 10) {
                        LogoTile(mark: kind.brand, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kind.displayName).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                            Text(coordinator.integrations.isConnected(kind) ? "Connected" : "Not connected")
                                .font(.system(size: 11))
                                .foregroundStyle(coordinator.integrations.isConnected(kind) ? Theme.success : Theme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .premiumCard(radius: 14, glow: kind.brand.tint)
                }
            }
            HStack {
                PillButton(title: "Set up services", systemImage: "square.grid.2x2", style: .secondary) { coordinator.openSettings(.integrations) }
                    .frame(width: 190)
                PillButton(title: "Morning brief & WhatsApp", systemImage: "sun.max", style: .secondary) { coordinator.openSettings(.automations) }
                    .frame(width: 240)
            }
        }
    }
}

private struct ReadyPage: View {
    let coordinator: AppCoordinator

    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @ViewState private var notificationsAllowed = false

    var body: some View {
        VStack(spacing: 18) {
            NovaCharacterView(art: .body, expression: .success, cursor: coordinator.cursor, anchor: NSEvent.mouseLocation)
                .frame(width: 200, height: 170)
            PageTitle(title: "You're ready", subtitle: "Hover over the notch to preview, click to open. Settings are in the menu bar.")
            HStack(spacing: 14) {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                    }
                Button(notificationsAllowed ? "Notifications allowed" : "Allow notifications") {
                    Task { notificationsAllowed = await coordinator.notifications.requestAuthorization() }
                }
                .disabled(notificationsAllowed)
            }
            .toggleStyle(.switch)
        }
        .task {
            await coordinator.notifications.refreshAuthorization()
            notificationsAllowed = coordinator.notifications.authorized
        }
    }
}
