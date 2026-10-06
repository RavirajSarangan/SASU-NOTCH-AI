import AppKit
import NovaKit
import ServiceManagement
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, nova, ai, usage, agents, integrations, automations, security, notifications, privacy, advanced, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .nova: "Nova"
        case .ai: "AI Providers"
        case .usage: "Usage & limits"
        case .agents: "Agents"
        case .integrations: "Integrations"
        case .automations: "Automations"
        case .security: "Security"
        case .notifications: "Notifications"
        case .privacy: "Privacy"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .nova: "face.smiling"
        case .ai: "sparkles"
        case .usage: "gauge.with.dots.needle.50percent"
        case .agents: "cpu"
        case .integrations: "square.grid.2x2"
        case .automations: "bolt.fill"
        case .security: "shield.lefthalf.filled"
        case .notifications: "bell.badge"
        case .privacy: "hand.raised"
        case .advanced: "wrench.and.screwdriver"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $coordinator.settingsSection) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch coordinator.settingsSection {
                    case .general: GeneralSettings(coordinator: coordinator)
                    case .appearance: AppearanceSettings(prefs: coordinator.prefs)
                    case .nova: NovaSettings(coordinator: coordinator)
                    case .ai: AIProvidersSettings(ai: coordinator.ai)
                    case .usage: UsageSettings(usage: coordinator.usage)
                    case .agents: AgentSettings(prefs: coordinator.prefs)
                    case .integrations: IntegrationsSettings(coordinator: coordinator)
                    case .automations: AutomationSettings(coordinator: coordinator)
                    case .security: SecuritySettings(coordinator: coordinator)
                    case .notifications: NotificationSettings(prefs: coordinator.prefs, service: coordinator.notifications)
                    case .privacy: PrivacySettings(coordinator: coordinator)
                    case .advanced: AdvancedSettings(coordinator: coordinator)
                    case .about: AboutSettings()
                    }
                }
                .padding(24)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 760, minHeight: 520)
        .onChange(of: coordinator.prefs.panelSize) { coordinator.applyPreferences() }
        .onChange(of: coordinator.prefs.screen) { coordinator.applyPreferences() }
        .onChange(of: coordinator.prefs.disabledAgents) { coordinator.applyPreferences() }
    }
}

/// One card per provider: key (Keychain), validate, default model.
struct AIProvidersSettings: View {
    let ai: AIService

    var body: some View {
        SettingsHeader(title: "AI Providers", subtitle: "Keys are stored only in your macOS Keychain. Nova talks to providers directly; there's no Nova server.")
        Picker("Default provider", selection: Binding(get: { ai.defaultProvider }, set: { ai.defaultProvider = $0 })) {
            ForEach(AIProviderKind.allCases) { Text($0.displayName).tag($0) }
        }
        .frame(maxWidth: 320)
        Toggle("If it's busy, try my other providers", isOn: Binding(get: { ai.tryOtherProviders }, set: { ai.tryOtherProviders = $0 }))
        Text("When a provider is overloaded (errors like 503), Nova tries a lighter model, then your other providers: free ones first. Add a free Groq key as a backup.")
            .font(.caption).foregroundStyle(.secondary)
        ForEach(AIProviderKind.allCases) { kind in
            ProviderKeyRow(ai: ai, kind: kind)
        }
        .task { await ai.probeLocalServers() }
    }
}

struct ProviderKeyRow: View {
    let ai: AIService
    let kind: AIProviderKind

    @ViewState private var draft = ""
    @ViewState private var status: String?
    @ViewState private var busy = false
    @ViewState private var models: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                LogoTile(mark: kind.brand, size: 22)
                Text(kind.displayName).font(.headline)
                if kind.isFree {
                    Text("Free").font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.success.opacity(0.18), in: Capsule())
                        .foregroundStyle(Theme.success)
                }
                Spacer()
                if kind.isLocal {
                    Label(ai.hasKey(kind) ? "Running" : "Not running", systemImage: ai.hasKey(kind) ? "checkmark.circle.fill" : "moon.zzz")
                        .foregroundStyle(ai.hasKey(kind) ? Theme.success : Theme.textSecondary).font(.caption)
                    Button("Check") { Task { await ai.probeLocalServers() } }.controlSize(.small)
                } else if ai.hasKey(kind) {
                    Label("Key saved", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.success).font(.caption)
                }
            }
            if let note = kind.freeNote, !kind.isLocal {
                HStack(spacing: 6) {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                    if let url = kind.keyPageURL, !ai.hasKey(kind) {
                        Link("Get a free key", destination: url).font(.caption)
                    }
                }
            }
            if kind.isLocal {
                if let url = kind.keyPageURL, !ai.hasKey(kind) {
                    Link(kind == .ollama ? "Download Ollama" : "Download LM Studio", destination: url).font(.caption)
                }
                Text(kind == .ollama ? "Start Ollama, then pull a model (for example `ollama pull llama3.2`). Chats stay on this Mac."
                                     : "Open LM Studio and start its local server (Developer tab). Chats stay on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
            HStack {
                SecureField(ai.hasKey(kind) ? "•••••••• (saved, paste to replace)" : "Paste API key", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button("Save") { save() }.disabled(draft.isEmpty)
                Button("Test") { Task { await test() } }.disabled(!ai.hasKey(kind) || busy)
                if ai.hasKey(kind) {
                    Button("Remove", role: .destructive) { try? ai.saveKey("", for: kind); status = "Removed" }
                }
            }
            }
            HStack {
                Text("Model").foregroundStyle(.secondary)
                if models.isEmpty {
                    TextField("Model", text: Binding(get: { ai.model(for: kind) }, set: { ai.setModel($0, for: kind) }))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                } else {
                    Picker("", selection: Binding(get: { ai.model(for: kind) }, set: { ai.setModel($0, for: kind) })) {
                        ForEach(models.contains(ai.model(for: kind)) ? models : [ai.model(for: kind)] + models, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }
                if busy { ProgressView().controlSize(.small) }
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private func save() {
        do {
            try ai.saveKey(draft, for: kind)
            draft = ""
            status = "Saved to Keychain"
            Task { await test() }
        } catch {
            status = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private func test() async {
        busy = true
        defer { busy = false }
        do {
            models = try await ai.refreshModels(for: kind)
            status = models.isEmpty ? "Key works, no models listed" : "Key works · \(models.count) models"
        } catch {
            status = error.localizedDescription
        }
    }
}

struct AgentSettings: View {
    @Bindable var prefs: NovaPreferences
    @ViewState private var installed = ClaudeHookStatus.isInstalled

    var body: some View {
        SettingsHeader(title: "Agents", subtitle: "Nova listens on a private local socket. Agents report to it; nothing leaves your Mac.")
        SettingsCard(title: "Monitor", symbol: "eye") {
            ForEach(AgentKind.allCases, id: \.self) { kind in
                Toggle(isOn: Binding(get: { !prefs.disabledAgents.contains(kind) },
                                     set: { on in if on { prefs.disabledAgents.remove(kind) } else { prefs.disabledAgents.insert(kind) } })) {
                    HStack(spacing: 8) {
                        LogoTile(mark: kind.brand, size: 20)
                        Text(kind.displayName)
                    }
                }
            }
        }
        SettingsCard(title: "Claude Code", symbol: "terminal") {
            Label(installed ? "Hook installed" : "Hook not installed",
                  systemImage: installed ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(installed ? Theme.success : Theme.textSecondary)
            Text("Run this from the Nova project folder (it backs up ~/.claude/settings.json first; add --dry-run to preview):")
                .font(.callout).foregroundStyle(.secondary)
            CommandBox(command: "scripts/install_claude_hook.sh")
            Text("When Nova isn't running, the hook does nothing. It never approves anything on its own: requests wait for your click, then fall back to Claude Code's own prompt after 2 minutes.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Check again") { installed = ClaudeHookStatus.isInstalled }
        }
        SettingsCard(title: "VS Code", symbol: "chevron.left.forwardslash.chevron.right") {
            Text("Shows tasks, debugging, saves and errors. Claude Code sessions inside VS Code are tagged automatically.")
                .font(.callout).foregroundStyle(.secondary)
            CommandBox(command: "scripts/install_vscode_extension.sh")
        }
        SettingsCard(title: "Codex · Cursor · Gemini CLI · Antigravity", symbol: "point.3.connected.trianglepath.dotted") {
            Text("No official hooks yet. Any script can report to Nova by sending JSON lines like {\"agent\":\"codex\",\"sessionId\":\"…\",\"event\":\"tool_start\"} to ~/Library/Application Support/Nova/nova.sock.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// Monospaced command with a copy button.
struct CommandBox: View {
    let command: String
    @ViewState private var copied = false

    var body: some View {
        HStack {
            Text(command).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Spacer()
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }
}

enum ClaudeHookStatus {
    static var isInstalled: Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains("nova-hook")
    }
}

struct SettingsHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.semibold))
            if !subtitle.isEmpty {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }
}
