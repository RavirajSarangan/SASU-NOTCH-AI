import NovaKit
import SwiftUI

/// An agent's questions (AskUserQuestion), answered in the notch. One
/// question at a time; single choice or several; "Reply in terminal" hands
/// it back to the agent's own prompt.
struct QuestionCardView: View {
    let coordinator: AppCoordinator
    let request: AgentPermissionRequest
    let questions: [AgentQuestion]
    var armed: Bool

    @ViewState private var page = 0
    @ViewState private var picks: [String: [String]] = [:]

    private var current: AgentQuestion { questions[min(page, questions.count - 1)] }
    private var isLast: Bool { page >= questions.count - 1 }
    private var currentAnswered: Bool { !(picks[current.question] ?? []).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !current.header.isEmpty {
                    Text(current.header)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.cyan)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.cyan.opacity(0.14), in: Capsule())
                }
                Text(current.question)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if questions.count > 1 {
                    Text("\(page + 1) of \(questions.count)")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if current.multiSelect {
                Text("Choose any that apply").font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
            }

            // A plain list when the options fit; scroll only when they don't.
            ViewThatFits(in: .vertical) {
                optionList
                ScrollView { optionList }.scrollIndicators(.never)
            }
            .id(page)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

            HStack(spacing: 8) {
                PillButton(title: "Reply in terminal", systemImage: "terminal", style: .quiet) {
                    coordinator.replyInTerminal(requestId: request.id)
                }
                Spacer(minLength: 0)
                if page > 0 {
                    PillButton(title: "Back", style: .secondary) { withAnimation(.spring(duration: 0.3)) { page -= 1 } }
                }
                PillButton(title: isLast ? (questions.count > 1 ? "Send answers" : "Send answer") : "Next",
                           systemImage: isLast ? "paperplane.fill" : nil, style: .primary) {
                    if isLast {
                        coordinator.answer(picks, requestId: request.id)
                    } else {
                        withAnimation(.spring(duration: 0.3)) { page += 1 }
                    }
                }
                .frame(width: 140)
                .disabled(!armed || !currentAnswered)
            }
        }
        .onChange(of: request.id) { page = 0; picks = [:] }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(request.agent.displayName) asks: \(current.question)")
    }

    private var optionList: some View {
        VStack(spacing: 5) {
            ForEach(Array(current.options.enumerated()), id: \.element) { index, option in
                OptionRow(option: option, index: index, multi: current.multiSelect,
                          selected: (picks[current.question] ?? []).contains(option.label)) {
                    toggle(option.label)
                }
            }
        }
    }

    private func toggle(_ label: String) {
        var chosen = picks[current.question] ?? []
        if current.multiSelect {
            if let i = chosen.firstIndex(of: label) { chosen.remove(at: i) } else { chosen.append(label) }
        } else {
            chosen = [label]
        }
        picks[current.question] = chosen
    }
}

private struct OptionRow: View {
    let option: AgentQuestion.Option
    let index: Int
    let multi: Bool
    let selected: Bool
    var action: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: multi ? (selected ? "checkmark.square.fill" : "square")
                                        : (selected ? "largecircle.fill.circle" : "circle"))
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Theme.cyan : Theme.textSecondary)
                // One line: label, then the description (full text on hover).
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(option.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .layoutPriority(1)
                    if !option.description.isEmpty {
                        Text(option.description)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Theme.cyan.opacity(0.12) : Color.white.opacity(hovering ? 0.07 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Theme.cyan.opacity(0.6) : Color.white.opacity(0.06))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .help(option.description)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
