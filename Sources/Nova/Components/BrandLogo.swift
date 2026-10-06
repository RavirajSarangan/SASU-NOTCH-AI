import SwiftUI

/// A service's real logo (Simple Icons SVG, CC0) tinted in its brand color,
/// or an SF Symbol when no logo is available.
struct BrandMark: Sendable, Hashable {
    /// SVG file name in Resources/BrandIcons, without extension.
    var logo: String?
    var fallbackSymbol: String
    var tint: Color

    static let claude = BrandMark(logo: "claude", fallbackSymbol: "sparkle", tint: Color(hex: 0xD97757))
    static let openAI = BrandMark(logo: "openai", fallbackSymbol: "curlybraces", tint: Theme.textPrimary)
    static let cursor = BrandMark(logo: "cursor", fallbackSymbol: "cursorarrow.rays", tint: Theme.textPrimary)
    static let gemini = BrandMark(logo: "googlegemini", fallbackSymbol: "diamond", tint: Color(hex: 0x6F9BFF))
    // No freely licensed Antigravity logo exists yet.
    static let groq = BrandMark(logo: nil, fallbackSymbol: "bolt.fill", tint: Color(hex: 0xF55036))
    static let openRouter = BrandMark(logo: nil, fallbackSymbol: "arrow.triangle.branch", tint: Color(hex: 0x8B9CFF))
    static let ollama = BrandMark(logo: nil, fallbackSymbol: "laptopcomputer", tint: Color(hex: 0xEDEDED))
    static let lmStudio = BrandMark(logo: nil, fallbackSymbol: "cpu", tint: Color(hex: 0x7C8CFF))
    static let antigravity = BrandMark(logo: nil, fallbackSymbol: "arrow.up.forward.circle", tint: Theme.violet)
    static let github = BrandMark(logo: "github", fallbackSymbol: "arrow.triangle.branch", tint: Theme.textPrimary)
    static let vercel = BrandMark(logo: "vercel", fallbackSymbol: "triangle.fill", tint: Theme.textPrimary)
    static let n8n = BrandMark(logo: "n8n", fallbackSymbol: "point.3.connected.trianglepath.dotted", tint: Color(hex: 0xEA4B71))
    static let supabase = BrandMark(logo: "supabase", fallbackSymbol: "server.rack", tint: Color(hex: 0x3FCF8E))
    static let stripe = BrandMark(logo: "stripe", fallbackSymbol: "creditcard", tint: Color(hex: 0x8C83FF))
    static let firebase = BrandMark(logo: "firebase", fallbackSymbol: "flame.fill", tint: Color(hex: 0xFFC400))
    static let vscode = BrandMark(logo: "visualstudiocode", fallbackSymbol: "chevron.left.forwardslash.chevron.right", tint: Color(hex: 0x3EA6F5))
}

struct BrandLogo: View {
    let mark: BrandMark
    var size: CGFloat = 12

    var body: some View {
        Group {
            if let name = mark.logo,
               let image = ResourceBundle.image(name, ext: "svg", subdirectory: "BrandIcons", template: true) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: mark.fallbackSymbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .fontWeight(.semibold)
            }
        }
        .foregroundStyle(mark.tint)
        .frame(width: size, height: size)
    }
}
