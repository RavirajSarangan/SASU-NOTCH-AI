import AppKit
import NovaKit
import SwiftUI

extension SecurityStatus {
    var color: Color {
        switch self {
        case .ok: Theme.success
        case .warning: Theme.warning
        case .critical: Theme.error
        case .unknown: Theme.textSecondary
        }
    }
}

extension AlertSeverity {
    var color: Color {
        switch self {
        case .info: Theme.blue
        case .high: Theme.warning
        case .critical: Theme.error
        }
    }
}

/// Shield in the notch top bar, colored by the security score.
struct SecurityBadge: View {
    let coordinator: AppCoordinator

    var body: some View {
        let security = coordinator.security
        let color: Color = security.alerts.contains { $0.severity == .critical } ? Theme.error
            : (security.score ?? 100) >= 90 ? Theme.success : (security.score ?? 100) >= 70 ? Theme.warning : Theme.error
        Button { coordinator.openSecurity() } label: {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .help("Security score \(security.score.map(String.init) ?? "–")")
        .accessibilityLabel("Security")
        .accessibilityValue(security.score.map { "score \($0) of 100" } ?? "checking")
    }
}

/// Nova Guard: score, checks with fixes, and recent alerts.
struct SecurityDetailView: View {
    let coordinator: AppCoordinator

    var body: some View {
        let security = coordinator.security
        let g = coordinator.state.geometry
        let wing = NotchLayout.wingWidth(for: coordinator.state.size, geometry: g)

        VStack(spacing: 8) {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    IconButton(systemName: "chevron.left", label: "Back") { coordinator.backToHome() }
                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(Theme.cyan)
                    Text("Security").font(Theme.Typography.headline).foregroundStyle(Theme.textPrimary)
                }
                .frame(width: g.hasNotch ? wing - 14 : nil, alignment: .leading)
                Spacer(minLength: g.hasNotch ? g.notchWidth : 0)
                HStack(spacing: 6) {
                    if security.isScanning { Spinner(size: 11) }
                    IconButton(systemName: "arrow.clockwise", label: "Scan now") { Task { await security.scanPosture() } }
                    IconButton(systemName: "gearshape.fill", label: "Security settings") { coordinator.openSettings(.security) }
                }
            }
            .frame(height: g.notchHeight)

            HStack(alignment: .top, spacing: 8) {
                ScoreCard(score: security.score, lastScan: security.lastScan, checks: security.checks,
                          cameraOn: security.cameraOn, microphoneOn: security.microphoneOn)
                    .frame(width: 190)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let report = coordinator.lastSystemReport {
                            SectionTitle("System check")
                            Text(report.summary).font(Theme.Typography.footnote).foregroundStyle(Theme.textPrimary)
                            ForEach(Array(report.findings.enumerated()), id: \.offset) { _, finding in
                                HStack(alignment: .top, spacing: 7) {
                                    Circle().fill(finding.level == .critical ? Theme.error : finding.level == .warning ? Theme.warning : Theme.blue)
                                        .frame(width: 6, height: 6).padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(finding.title).font(Theme.Typography.footnote.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                        Text(finding.detail).font(Theme.Typography.micro).foregroundStyle(Theme.textSecondary)
                                    }
                                }
                            }
                        }
                        if !security.alerts.isEmpty {
                            SectionTitle("Recent alerts")
                            ForEach(security.alerts.prefix(8)) { alert in AlertRow(alert: alert, security: security) }
                        }
                        SectionTitle("Checks")
                        ForEach(security.checks.sorted { $0.status > $1.status }) { check in CheckRow(check: check, security: security) }
                        if security.checks.isEmpty {
                            Text("Scanning…").font(Theme.Typography.footnote).foregroundStyle(Theme.textSecondary)
                        }
                        if !security.actions.log.isEmpty {
                            SectionTitle("Actions Nova took")
                            ForEach(security.actions.log.prefix(6)) { action in ActionRow(action: action, actions: security.actions) }
                        }
                    }
                    .padding(12)
                }
                .scrollIndicators(.never)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .premiumCard()
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(Theme.Typography.micro).tracking(0.8).foregroundStyle(Theme.textSecondary)
    }
}

private struct ScoreCard: View {
    @ViewState private var shown = false
    let score: Int?
    let lastScan: Date?
    let checks: [SecurityCheck]
    let cameraOn: Bool
    let microphoneOn: Bool

    var body: some View {
        let value = shown ? Double(score ?? 0) / 100 : 0
        let color: Color = (score ?? 100) >= 90 ? Theme.success : (score ?? 100) >= 70 ? Theme.warning : Theme.error
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 7)
                Circle().trim(from: 0, to: value).stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(score.map(String.init) ?? "–").font(Theme.Typography.display).foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.6), value: score)
                    Text("of 100").font(Theme.Typography.micro).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 92, height: 92)
            .animation(.spring(duration: 1.0, bounce: 0.1), value: value)
            .onAppear { shown = true }
            Text(summary).font(Theme.Typography.footnote).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Label(cameraOn ? "On" : "Off", systemImage: "video.fill").foregroundStyle(cameraOn ? Theme.warning : Theme.textSecondary)
                Label(microphoneOn ? "On" : "Off", systemImage: "mic.fill").foregroundStyle(microphoneOn ? Theme.warning : Theme.textSecondary)
            }
            .font(Theme.Typography.caption)
            if let lastScan {
                Text("Checked \(lastScan.formatted(date: .omitted, time: .shortened))").font(Theme.Typography.micro).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .premiumCard(glow: color)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let critical = checks.filter { $0.status == .critical }.count
        let warnings = checks.filter { $0.status == .warning }.count
        if critical > 0 { return "\(critical) critical issue\(critical == 1 ? "" : "s") need attention" }
        if warnings > 0 { return "\(warnings) suggestion\(warnings == 1 ? "" : "s") to improve" }
        return checks.isEmpty ? "Checking your Mac…" : "Your Mac is well protected"
    }
}

private struct CheckRow: View {
    let check: SecurityCheck
    let security: SecurityMonitor

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: check.status == .ok ? "checkmark.circle.fill" : check.status == .critical ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(check.status.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(check.title).font(Theme.Typography.body).foregroundStyle(Theme.textPrimary)
                if check.status != .ok {
                    Text(check.detail).font(Theme.Typography.caption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if check.status != .ok, let admin = AdminFix.fix(forCheck: check.id) {
                PillButton(title: security.actions.runningFix == admin ? "Fixing…" : "Fix now", systemImage: "lock.fill", style: .primary) {
                    Task {
                        if await security.actions.runAdminFix(admin) { await security.scanPosture() }
                    }
                }
                .frame(width: 92)
                .help("Runs: \(admin.command)\nmacOS will ask for your password.")
                .disabled(security.actions.runningFix != nil)
            } else if check.status != .ok, let fix = check.fix, let url = URL(string: fix.rawValue) {
                PillButton(title: "Fix", systemImage: "arrow.up.right", style: .secondary) { NSWorkspace.shared.open(url) }
                    .frame(width: 70)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AlertRow: View {
    let alert: SecurityAlert
    let security: SecurityMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(alert.severity.color).frame(width: 7, height: 7)
                Text(alert.title).font(Theme.Typography.body.weight(.medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 4)
                Text(alert.date, format: .relative(presentation: .named)).font(Theme.Typography.micro).foregroundStyle(Theme.textSecondary)
            }
            Text(alert.detail).font(Theme.Typography.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
            HStack(spacing: 6) {
                if let fix = alert.fix, let url = URL(string: fix.rawValue) {
                    PillButton(title: "Open settings", style: .secondary) { NSWorkspace.shared.open(url) }.frame(width: 120)
                }
                if let path = alert.path {
                    PillButton(title: "Reveal", style: .quiet) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                }
                if alert.baselineKey != nil {
                    PillButton(title: "This was me", style: .quiet) { security.accept(alert) }
                }
            }
        }
        .padding(8)
        .background(alert.severity.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ActionRow: View {
    let action: GuardAction
    let actions: GuardActions

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: action.undone ? "arrow.uturn.backward.circle" : "shield.checkered")
                .font(.system(size: 11)).foregroundStyle(action.undone ? Theme.textSecondary : Theme.success)
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title).font(Theme.Typography.body).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(action.detail).font(Theme.Typography.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Text(action.date, format: .relative(presentation: .named)).font(Theme.Typography.micro).foregroundStyle(Theme.textSecondary)
            if action.undo != .none, !action.undone {
                PillButton(title: "Undo", style: .quiet) { Task { await actions.undo(action) } }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
