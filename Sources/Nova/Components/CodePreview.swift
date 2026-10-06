import SwiftUI

/// Miniature editor: file tab, line numbers, diff highlighting and a
/// blinking caret on the last added line.
struct CodePreview: View {
    let preview: SessionPreview
    var accent: Color = Theme.cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabBar
            Rectangle().fill(Theme.hairline).frame(height: 1)
            if preview.lines.isEmpty, !preview.notes.isEmpty {
                ActivityList(notes: preview.notes)
                    .padding(10)
                Spacer(minLength: 0)
            } else if preview.lines.isEmpty {
                Text("Waiting for the next session…")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(preview.lines) { line in
                        row(line, showCaret: line.id == caretLineID)
                    }
                }
                .padding(.vertical, 5)
                Spacer(minLength: 0)
            }
        }
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var caretLineID: String? {
        preview.lines.last(where: { $0.kind == .added })?.id
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            Text(preview.languageBadge)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .padding(.horizontal, 3)
                .padding(.vertical, 1.5)
                .background(accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
            Text(preview.fileName)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
            if preview.lines.contains(where: { $0.kind != .context }) {
                Circle().fill(Theme.warning).frame(width: 5, height: 5)
            }
            Spacer(minLength: 6)
            Text(preview.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
    }

    private func row(_ line: SessionPreview.CodeLine, showCaret: Bool) -> some View {
        let (tint, marker): (Color, String) = switch line.kind {
        case .context: (.clear, " ")
        case .removed: (Theme.error, "−")
        case .added: (Theme.success, "+")
        }
        return HStack(spacing: 6) {
            Text("\(line.number)")
                .foregroundStyle(Theme.textSecondary.opacity(0.45))
                .frame(width: 18, alignment: .trailing)
            Text(marker)
                .foregroundStyle(tint)
                .frame(width: 7)
            HStack(spacing: 0) {
                Text(SyntaxHighlighter.highlight(line.text))
                    .strikethrough(line.kind == .removed, color: Theme.error.opacity(0.6))
                    .opacity(line.kind == .removed ? 0.6 : 1)
                if showCaret { Caret() }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10, design: .monospaced))
        .frame(height: 15)
        .background(tint.opacity(line.kind == .context ? 0 : 0.11))
        .overlay(alignment: .leading) {
            if line.kind != .context { Rectangle().fill(tint).frame(width: 2) }
        }
    }
}

private struct Caret: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.55)) { timeline in
            let on = Int(timeline.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
            Rectangle()
                .fill(Theme.cyan)
                .frame(width: 1.5, height: 11)
                .opacity(on ? 1 : 0)
                .padding(.leading, 1)
        }
    }
}

/// Tiny tokenizer good enough for a glanceable preview.
enum SyntaxHighlighter {
    private static let keywords: Set<String> = [
        "func", "let", "var", "return", "try", "await", "async", "throws", "struct", "class", "enum",
        "import", "export", "const", "function", "if", "else", "private", "some", "self",
    ]

    static func highlight(_ code: String) -> AttributedString {
        var result = AttributedString()
        for match in code.matches(of: /"[^"]*"|[A-Za-z_][A-Za-z0-9_]*|[0-9.]+|\s+|./) {
            let token = String(match.output)
            var piece = AttributedString(token)
            piece.foregroundColor = color(for: token)
            result += piece
        }
        return result
    }

    private static func color(for token: String) -> Color {
        if token.hasPrefix("\"") { return Color(hex: 0x9BE38B) }
        if keywords.contains(token) { return Color(hex: 0xC792FF) }
        if token.first?.isNumber == true { return Theme.warning }
        if token.first?.isUppercase == true { return Color(hex: 0x7DD3FC) }
        if token.hasPrefix("#") || token.hasPrefix("-") { return Theme.cyan }
        return Theme.textPrimary.opacity(0.88)
    }
}
