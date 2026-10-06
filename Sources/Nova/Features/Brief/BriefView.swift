import NovaKit
import SwiftUI

/// "Brief" tab: today's mail, LinkedIn and YouTube at a glance.
struct BriefView: View {
    let coordinator: AppCoordinator

    private var brief: BriefService { coordinator.brief }

    var body: some View {
        if !coordinator.google.isSignedIn {
            EmptyStateView(coordinator: coordinator, expression: .happy, title: "Connect Google for your morning brief",
                           message: "Read-only access to Gmail and YouTube. LinkedIn updates come from its emails. Settings → Automations.")
                .onTapGesture { coordinator.openSettings(.automations) }
        } else {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    MailCard(brief: brief.mail)
                    VStack(spacing: 8) {
                        LinkedInCard(digest: brief.linkedIn)
                        YouTubeCard(summary: brief.youtube, note: brief.youtubeNote)
                    }
                    .frame(width: 214)
                }
                .frame(height: 172)
                footer
            }
        }
    }

    private var footer: some View {
        let wa = coordinator.whatsapp
        return HStack(spacing: 8) {
            LogoTile(mark: BrandMark(logo: nil, fallbackSymbol: "message.fill", tint: Color(hex: 0x25D366)), size: 20)
            Text(waLine(wa))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer()
            if !wa.drafts.isEmpty || !wa.pendingGreetings.isEmpty {
                Button("Review") { coordinator.reviewAutomations() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
            }
            if brief.isRefreshing {
                Spinner(size: 11)
            } else {
                Text(brief.updatedAt.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Not updated yet")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                IconButton(systemName: "arrow.clockwise", label: "Refresh brief") { Task { await brief.refresh() } }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(Theme.panel, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.07)))
    }

    private func waLine(_ wa: WhatsAppService) -> String {
        if let problem = wa.access.message { return problem }
        if !wa.drafts.isEmpty { return "\(wa.drafts.count) reply draft\(wa.drafts.count == 1 ? "" : "s") waiting" }
        if !wa.pendingGreetings.isEmpty { return "Good morning to \(wa.pendingGreetings.count) going out soon" }
        let count = coordinator.automations.data.contacts.count
        return count == 0 ? "WhatsApp: pick contacts in Settings" : "WhatsApp: watching \(count) chat\(count == 1 ? "" : "s")"
    }
}

private struct MailCard: View {
    let brief: MailBrief?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.fill").font(.system(size: 10)).foregroundStyle(Color(hex: 0xEA4335))
                Text("MAIL").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.textSecondary)
                Spacer()
                if let brief {
                    Text("\(brief.unread) unread · \(brief.promotions) promo")
                        .font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                }
            }
            if let brief {
                Text(brief.overview)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        section("Reply", brief.needsReply, Theme.warning)
                        section("Important", brief.important, Theme.cyan)
                        section("Updates", brief.updates, Theme.textSecondary)
                    }
                }
                .scrollIndicators(.never)
            } else {
                Spacer()
                Text("Tap refresh to build today's brief").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(glow: Color(hex: 0xEA4335))
    }

    @ViewBuilder
    private func section(_ title: String, _ lines: [MailBrief.Line], _ tint: Color) -> some View {
        ForEach(lines.prefix(4)) { line in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(tint).frame(width: 5, height: 5)
                Text(line.sender).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(line.summary).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            .help("\(title): \(line.sender), \(line.summary)")
        }
    }
}

private struct LinkedInCard: View {
    let digest: LinkedInDigest?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("in").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 15, height: 15).background(Color(hex: 0x0A66C2), in: RoundedRectangle(cornerRadius: 3))
                Text("LINKEDIN").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.textSecondary)
            }
            if let digest, !digest.isEmpty {
                HStack(spacing: 10) {
                    stat("\(digest.messages.count)", "msgs")
                    stat(digest.profileViews.map(String.init) ?? "–", "views")
                    stat("\(digest.invitations.count)", "invites")
                }
                Text(digest.messages.first.map { "\($0.sender): \($0.preview)" } ?? digest.postActivity.first ?? digest.viewers.first.map { "\($0) viewed your profile" } ?? "")
                    .font(.system(size: 10)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            } else {
                Text("No LinkedIn emails this week").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(radius: 16, glow: Color(hex: 0x0A66C2))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
            Text(label).font(.system(size: 9)).foregroundStyle(Theme.textSecondary)
        }
    }
}

private struct YouTubeCard: View {
    let summary: YouTubeSummary?
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "play.rectangle.fill").font(.system(size: 11)).foregroundStyle(Color(hex: 0xFF3B30))
                Text("YOUTUBE · 7D").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.textSecondary)
            }
            if let summary {
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(summary.views7d.formatted(.number.notation(.compactName)))
                            .font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                        Text("\(summary.subscribersNet7d >= 0 ? "+" : "")\(summary.subscribersNet7d) subs")
                            .font(.system(size: 9)).foregroundStyle(summary.subscribersNet7d >= 0 ? Theme.success : Theme.error)
                    }
                    Sparkline(values: summary.dailyViews).frame(height: 24)
                }
                Text(summary.insight ?? summary.topVideos.first.map { "Top: \($0.title)" } ?? "")
                    .font(.system(size: 10)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            } else {
                Text(note ?? "Connect to see channel stats").font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .premiumCard(radius: 16, glow: Color(hex: 0xFF3B30))
    }
}

struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let maxValue = values.max(), maxValue > 0 else { return }
            var path = Path()
            for (i, value) in values.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                                    y: size.height * (1 - CGFloat(value / maxValue)))
                i == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            context.stroke(path, with: .linearGradient(Gradient(colors: [Theme.violet, Theme.cyan]),
                                                      startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}
