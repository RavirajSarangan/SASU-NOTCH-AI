import SwiftUI

/// Colored status indicator; pulses when `live`.
struct StatusDot: View {
    var color: Color
    var live = false
    var size: CGFloat = 7

    @ViewState private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background {
                if live && !reduceMotion {
                    Circle()
                        .fill(color.opacity(0.45))
                        .scaleEffect(pulsing ? 2.4 : 1)
                        .opacity(pulsing ? 0 : 1)
                }
            }
            .shadow(color: color.opacity(0.6), radius: live ? 3 : 0)
            .onAppear {
                guard live else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulsing = true }
            }
    }
}
