import NovaKit
import SwiftUI

struct SecuritySettings: View {
    let coordinator: AppCoordinator

    @ViewState private var confirmReset = false

    var body: some View {
        @Bindable var prefs = coordinator.prefs
        SettingsHeader(title: "Security", subtitle: "Nova Guard watches this Mac for risks and for anyone getting in. Everything stays on your Mac.")
        SettingsCard(title: "Monitoring", symbol: "shield.lefthalf.filled") {
            Toggle("Nova Guard", isOn: $prefs.securityEnabled)
            Group {
                Toggle("Security settings check (FileVault, Firewall, SIP, Gatekeeper, updates, screen lock, sharing)", isOn: $prefs.securityPosture)
                Toggle("Intrusion alerts (remote logins, Screen Sharing, failed logins, new users and admins)", isOn: $prefs.securityIntrusion)
                Toggle("New startup items and unverified apps", isOn: $prefs.securityPersistence)
                Toggle("Camera and microphone turning on", isOn: $prefs.securityCameraMic)
                Toggle("New apps accepting network connections", isOn: $prefs.securityPortAlerts)
                Toggle("Admin commands (sudo)", isOn: $prefs.securitySudoAlerts)
                Stepper("Alert after \(prefs.failedLoginThreshold) failed logins in 5 minutes", value: $prefs.failedLoginThreshold, in: 2...10)
            }
            .disabled(!prefs.securityEnabled)
        }
        SettingsCard(title: "Automatic protection", symbol: "bolt.shield.fill") {
            Toggle("Fix safe things automatically (block risky startup items, stop reverse shells; you can undo)", isOn: $prefs.securityAutoFix)
            Toggle("Always deny dangerous agent commands (reverse shells, curl | sh, Keychain dumps, SSH key changes)", isOn: $prefs.securityAgentDenyList)
            Toggle("Guard mode while you're away: deny high-risk agent commands when the Mac is locked or idle 5+ minutes", isOn: $prefs.securityAwayGuard)
            Text("Fixes that need admin rights (Firewall, stealth mode, Remote Login, Screen Sharing, updates) only run when you click Fix now and enter your password.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(!prefs.securityEnabled)
        SettingsCard(title: "Baseline", symbol: "checklist") {
            Text("Nova learns what's normal for this Mac (accounts, startup items, apps, open ports) and alerts on changes. Use \u{201C}This was me\u{201D} on an alert to accept it.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Scan now") { Task { await coordinator.security.scanPosture() } }
                Button("Clear alerts") { coordinator.security.clearAlerts() }
                Button("Reset baseline…") { confirmReset = true }
            }
        }
        .confirmationDialog("Re-learn what's normal for this Mac? Current accounts, startup items, apps and open ports become the new baseline.",
                            isPresented: $confirmReset) {
            Button("Reset baseline") { Task { await coordinator.security.resetBaseline() } }
        }
        SettingsCard(title: "What Nova Guard can and can't do", symbol: "info.circle") {
            VStack(alignment: .leading, spacing: 4) {
                Text("• It never changes system settings by itself: admin fixes run only after you click and enter your password.")
                Text("• Automatic fixes are limited to safe, undoable steps in your own account.")
                Text("• It's not an antivirus and can't promise complete protection: no app can. It watches the ways people most often get in.")
                Text("• Agent commands your agent auto-approves itself never reach Nova, so keep risky tools on \u{201C}ask\u{201D} in your agent's settings.")
                Text("• It runs without admin rights, so a few details (like other users' processes) may be missing.")
                Text("• It can only watch while Nova is running. Keep \u{201C}Launch at login\u{201D} on.")
            }
            .font(.callout).foregroundStyle(.secondary)
        }
        .onChange(of: prefs.securityEnabled) { coordinator.security.restart() }
        .onChange(of: prefs.failedLoginThreshold) { coordinator.security.restart() }
    }
}
