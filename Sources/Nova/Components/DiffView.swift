import AppKit
import NovaKit
import SwiftUI

/// Red/green line diff for an agent's edit. `maxLines` limits the compact
/// version; the full diff opens in its own window.
struct DiffView: View {
    let preview: EditPreview
    var maxLines: Int? = nil
    var onShowAll: (() -> Void)? = nil

    var body: some View {
        let lines = maxLines.map { Array(preview.lines.prefix($0)) } ?? preview.lines
        let hidden = preview.lines.count - lines.count
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: preview.isNewContent ? "doc.badge.plus" : "doc.text")
                    .foregroundStyle(Theme.textSecondary)
                Text(preview.file.map { ($0 as NSString).lastPathComponent } ?? "Change")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                DiffCounts(preview: preview)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.04))

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in DiffLineRow(line: line) }
            }
            .padding(.vertical, 4)

            if hidden > 0 || preview.truncated, let onShowAll {
                Button(action: onShowAll) {
                    Text(hidden > 0 ? "Show all \(preview.lines.count) lines" : "Show the full diff")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.cyan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.bottom, 6)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Change to \(preview.file ?? "a file"): \(preview.added) lines added, \(preview.removed) removed")
    }
}

/// "+12 −3" in green and red.
struct DiffCounts: View {
    let preview: EditPreview

    var body: some View {
        HStack(spacing: 4) {
            Text("+\(preview.added)").foregroundStyle(Theme.success)
            if preview.removed > 0 || !preview.isNewContent { Text("−\(preview.removed)").foregroundStyle(Theme.error) }
        }
        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
    }
}

private struct DiffLineRow: View {
    let line: EditPreview.Line

    var body: some View {
        switch line.kind {
        case .gap:
            Text("⋯").font(.system(size: 10)).foregroundStyle(Theme.textSecondary).padding(.leading, 10).frame(height: 14)
        default:
            HStack(spacing: 6) {
                Text(marker).foregroundStyle(color).frame(width: 8)
                Text(line.text.isEmpty ? " " : line.text)
                    .foregroundStyle(line.kind == .context ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .font(.system(size: 10.5, design: .monospaced))
            .padding(.horizontal, 10).padding(.vertical, 1)
            .background(color.opacity(line.kind == .context ? 0 : 0.12))
        }
    }

    private var marker: String { line.kind == .added ? "+" : line.kind == .removed ? "−" : " " }
    private var color: Color { line.kind == .added ? Theme.success : line.kind == .removed ? Theme.error : .clear }
}

/// A plain window with the full diff (the notch is too small for long ones).
@MainActor
enum DiffWindow {
    private static var window: NSWindow?

    static func show(_ preview: EditPreview, title: String) {
        let content = ScrollView { DiffView(preview: preview).padding(14) }
            .frame(minWidth: 560, minHeight: 360)
            .background(Theme.background)
            .preferredColorScheme(.dark)
        let controller = NSHostingController(rootView: content)
        let win = window ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                                     styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        win.contentViewController = controller
        win.title = title
        win.isReleasedWhenClosed = false
        win.center()
        window = win
        NSApp.activate()
        win.makeKeyAndOrderFront(nil)
    }
}
