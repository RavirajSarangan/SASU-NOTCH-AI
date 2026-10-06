import SwiftUI

/// Vertical list of agent steps: done ✓, active (spinner), pending (dimmed).
struct StepTimeline: View {
    let steps: [SessionPreview.Step]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(steps) { step in
                HStack(spacing: 8) {
                    icon(for: step)
                        .frame(width: 13, height: 13)
                    Text(step.title)
                        .font(.system(size: 12, weight: step.state == .active ? .semibold : .medium))
                        .foregroundStyle(step.state == .pending ? Theme.textSecondary.opacity(0.55) : Theme.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private func icon(for step: SessionPreview.Step) -> some View {
        switch step.state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.success)
        case .active:
            Spinner(size: 11)
        case .pending:
            Image(systemName: step.symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary.opacity(0.5))
        }
    }
}
