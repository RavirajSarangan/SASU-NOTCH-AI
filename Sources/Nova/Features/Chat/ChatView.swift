import AppKit
import SwiftUI

struct ChatView: View {
    let coordinator: AppCoordinator
    @Bindable var chat: ChatViewModel

    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            header
            if !coordinator.ai.hasKey(chat.providerKind), chat.messages.isEmpty {
                if chat.providerKind.isLocal {
                    EmptyStateView(coordinator: coordinator, expression: .sleepy, title: "\(chat.providerKind.displayName) isn't running",
                                   message: chat.providerKind == .ollama ? "Start Ollama and pull a model, then open chat again." : "Start LM Studio's local server, then open chat again.")
                } else {
                    EmptyStateView(coordinator: coordinator, expression: .listening, title: "Add an API key to chat",
                                   message: "Open Settings → AI Providers and paste a key for \(chat.providerKind.displayName). It's stored in your Keychain.")
                }
            } else {
                messageList
                inputBar
            }
        }
        .onAppear { inputFocused = true }
        .task { await coordinator.ai.probeLocalServers() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(AIProviderKind.allCases) { kind in
                    Button {
                        chat.providerKind = kind
                    } label: {
                        Text(kind.displayName + (coordinator.ai.hasKey(kind) ? "" : kind.isLocal ? " (not running)" : " (no key)"))
                    }
                }
                Divider()
                Button("Settings…") { coordinator.openSettings() }
            } label: {
                HStack(spacing: 6) {
                    LogoTile(mark: chat.providerKind.brand, size: 18)
                    Text(chat.providerKind.displayName)
                        .font(.system(size: 12, weight: .semibold))
                    Text(chat.model)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Theme.textPrimary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
            if chat.messages.last?.role == .assistant, !chat.isStreaming {
                IconButton(systemName: "arrow.clockwise", label: "Regenerate") { chat.regenerate() }
            }
            IconButton(systemName: "trash", label: "Clear chat") { chat.clear() }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if chat.messages.isEmpty {
                        Text("Ask about code, writing or planning.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 30)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(chat.messages) { message in
                        MessageBubble(message: message, streaming: chat.isStreaming && message.id == chat.messages.last?.id)
                            .id(message.id)
                    }
                    if let by = chat.answeredBy, !chat.isStreaming {
                        Label("\(chat.providerKind.displayName) was busy, so \(by.displayName) answered.", systemImage: "arrow.triangle.branch")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let error = chat.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.error)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.never)
            .onChange(of: chat.messages.last?.text) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .premiumCard(glow: chat.providerKind.brand.tint)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message Nova…", text: $chat.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit { chat.send() }
            Button {
                chat.isStreaming ? chat.stop() : chat.send()
            } label: {
                Image(systemName: chat.isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(chat.isStreaming || chat.canSend ? Theme.cyan : Theme.textSecondary.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .disabled(!chat.isStreaming && !chat.canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }
}

struct MessageBubble: View {
    let message: AIMessage
    var streaming = false

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(MarkdownSegment.parse(message.text).enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let text):
                        Text(MarkdownSegment.attributed(text))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                    case .code(let language, let code):
                        CodeBlock(language: language, code: code)
                    }
                }
                if streaming && message.text.isEmpty {
                    Spinner(size: 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum MarkdownSegment {
    case text(String)
    case code(language: String, code: String)

    /// Splits on ``` fences. An unterminated fence (mid-stream) is treated as code.
    static func parse(_ source: String) -> [MarkdownSegment] {
        var segments: [MarkdownSegment] = []
        var remaining = Substring(source)
        while let open = remaining.range(of: "```") {
            let before = remaining[..<open.lowerBound]
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.text(String(before).trimmingCharacters(in: .newlines)))
            }
            let afterOpen = remaining[open.upperBound...]
            let langEnd = afterOpen.firstIndex(of: "\n") ?? afterOpen.endIndex
            let language = afterOpen[..<langEnd].trimmingCharacters(in: .whitespaces)
            let body = langEnd < afterOpen.endIndex ? afterOpen[afterOpen.index(after: langEnd)...] : ""
            if let close = body.range(of: "```") {
                segments.append(.code(language: language, code: String(body[..<close.lowerBound]).trimmingCharacters(in: .newlines)))
                remaining = body[close.upperBound...]
            } else {
                segments.append(.code(language: language, code: String(body)))
                remaining = ""
            }
        }
        if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.text(String(remaining).trimmingCharacters(in: .newlines)))
        }
        return segments
    }

    static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

struct CodeBlock: View {
    let language: String
    let code: String

    @ViewState private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(copied ? Theme.success : Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollView(.horizontal) {
                Text(SyntaxHighlighter.highlight(code))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .scrollIndicators(.never)
        }
        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
    }
}
