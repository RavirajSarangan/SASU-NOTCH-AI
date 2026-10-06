import SwiftUI

/// Small round icon-only button.
struct IconButton: View {
    let systemName: String
    let label: String
    var action: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(hovering ? 0.1 : 0.05), in: Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
