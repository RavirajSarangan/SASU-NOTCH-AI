import SwiftUI

/// Brand logo inside a tinted squircle, with an optional status dot badge.
struct LogoTile: View {
    let mark: BrandMark
    var size: CGFloat = 22
    var status: Color?

    var body: some View {
        BrandLogo(mark: mark, size: size * 0.52)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(mark.tint.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(mark.tint.opacity(0.22), lineWidth: 0.5)
            )
            .overlay(alignment: .bottomTrailing) {
                if let status {
                    Circle()
                        .fill(status)
                        .frame(width: size * 0.3, height: size * 0.3)
                        .overlay(Circle().stroke(Theme.panel, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }
            }
    }
}
