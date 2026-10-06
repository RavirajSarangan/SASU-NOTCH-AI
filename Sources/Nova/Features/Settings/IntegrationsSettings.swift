import AppKit
import NovaKit
import SwiftUI

struct IntegrationsSettings: View {
    let coordinator: AppCoordinator

    var body: some View {
        SettingsHeader(title: "Integrations", subtitle: "Read-only summaries of your developer services. Tokens are stored only in your Keychain.")
        ForEach(IntegrationKind.allCases) { kind in
            IntegrationCard(manager: coordinator.integrations, google: coordinator.google, kind: kind) {
                coordinator.openSettings(.automations)
            }
        }
    }
}

private struct IntegrationCard: View {
    @Bindable var manager: IntegrationManager
    let google: GoogleAuth
    let kind: IntegrationKind
    var openGoogle: () -> Void

    @ViewState private var token = ""
    @ViewState private var busy = false
    @ViewState private var message: String?

    var body: some View {
        let connected = manager.isConnected(kind)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                LogoTile(mark: kind.brand, size: 24)
                Text(kind.displayName).font(.headline)
                Spacer()
                if connected {
                    Label(manager.snapshots[kind]?.headline ?? "Connected", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.success).font(.caption)
                }
            }
            if kind == .firebase {
                firebaseBody(connected: connected)
            } else if connected {
                if kind == .supabase, !manager.supabaseProjects.isEmpty {
                    Picker("Project", selection: Binding(get: { manager.config.supabaseProjectRef ?? manager.supabaseProjects.first?.ref ?? "" },
                                                         set: { manager.config.supabaseProjectRef = $0; Task { await manager.refresh(.supabase) } })) {
                        ForEach(manager.supabaseProjects) { Text($0.name).tag($0.ref) }
                    }
                    .frame(maxWidth: 320)
                }
                HStack {
                    Button("Refresh") { Task { await manager.refresh(kind) } }
                    Button("Disconnect", role: .destructive) { manager.disconnect(kind) }
                }
                if let error = manager.errors[kind] { Text(error).font(.caption).foregroundStyle(Theme.warning) }
            } else {
                if kind == .n8n {
                    TextField("n8n URL, e.g. https://n8n.mydomain.com", text: Binding(
                        get: { manager.config.n8nBaseURL ?? "" }, set: { manager.config.n8nBaseURL = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
                if kind == .vercel {
                    TextField("Team ID (optional, for team projects)", text: Binding(
                        get: { manager.config.vercelTeamID ?? "" }, set: { manager.config.vercelTeamID = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    SecureField(kind.tokenHelp.label, text: $token).textFieldStyle(.roundedBorder)
                    Button(busy ? "Testing…" : "Connect") { Task { await connect() } }
                        .disabled(token.isEmpty || busy || (kind == .n8n && (manager.config.n8nBaseURL ?? "").isEmpty))
                }
                Link("Where do I get this?", destination: URL(string: kind.tokenHelp.url)!).font(.caption)
                if kind == .stripe {
                    Text("Use a restricted key with read access only. Nova never reads card or customer details.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func firebaseBody(connected: Bool) -> some View {
        if !google.isSignedIn {
            Text("Firebase uses your Google sign-in.").font(.callout).foregroundStyle(.secondary)
            Button("Set up Google…", action: openGoogle)
        } else if connected {
            if !manager.firebaseProjects.isEmpty {
                Picker("Project", selection: Binding(get: { manager.config.firebaseProjectID ?? manager.firebaseProjects.first?.projectId ?? "" },
                                                     set: { manager.config.firebaseProjectID = $0; Task { await manager.refresh(.firebase) } })) {
                    ForEach(manager.firebaseProjects) { Text($0.displayName).tag($0.projectId) }
                }
                .frame(maxWidth: 320)
            }
            if let error = manager.errors[.firebase] {
                Text(error).font(.caption).foregroundStyle(Theme.warning)
                Button("Reconnect Google (grants Firebase access)") { Task { await google.signIn(); await manager.refresh(.firebase) } }
            }
            Button("Turn off", role: .destructive) { manager.disconnect(.firebase) }
        } else {
            Text("Shows Firestore, Functions and Hosting status. You may need to reconnect Google once to grant read-only Firebase access.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Turn on Firebase") { Task { try? await manager.connect(.firebase, token: "") } }
        }
    }

    private func connect() async {
        busy = true
        defer { busy = false }
        do {
            try await manager.connect(kind, token: token)
            token = ""
            message = "Connected."
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Settings → General → apps shown in the notch dock.
struct NotchAppsSettings: View {
    let launcher: AppLauncherService

    @ViewState private var installed: [LauncherApp] = []

    var body: some View {
        SettingsHeader(title: "Notch apps", subtitle: "Apps in the dock on Home. Click to open or switch; right-click for more.")
        VStack(alignment: .leading, spacing: 6) {
            ForEach(launcher.apps) { app in
                HStack(spacing: 10) {
                    Image(nsImage: app.icon).resizable().frame(width: 22, height: 22)
                    Text(app.name)
                    Spacer()
                    Button { launcher.move(app.bundleID, by: -1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless)
                    Button { launcher.move(app.bundleID, by: 1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless)
                    Button(role: .destructive) { launcher.unpin(app.bundleID) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            Menu("Add app…") {
                ForEach(installed.filter { app in !launcher.apps.contains { $0.bundleID == app.bundleID } }) { app in
                    Button(app.name) { launcher.pin(app.bundleID) }
                }
            }
            .frame(maxWidth: 200)
        }
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { installed = launcher.installedApps() }
    }
}
