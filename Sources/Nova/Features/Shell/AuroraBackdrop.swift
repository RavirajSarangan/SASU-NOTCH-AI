import SwiftUI

/// Animated night-sky strip: twinkling stars, drifting aurora waves, a slowly
/// rising planet and the occasional shooting star. Drawn procedurally.
struct AuroraBackdrop: View {
    var paused = false
    /// Overall brightness so foreground text stays readable.
    var intensity: Double = 0.85

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.novaStyle) private var style

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused || reduceMotion || style.paused)) { timeline in
            let t = reduceMotion ? 12.0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                Self.draw(in: &context, size: size, time: t)
            }
            .opacity(intensity)
        }
        .allowsHitTesting(false)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: TimeInterval) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [Color(hex: 0x080A1C), Color(hex: 0x0B1033), Color(hex: 0x101A4A)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

        // Stars.
        for i in 0..<42 {
            let s = Double(i)
            let x = fract(sin(s * 12.9898) * 43758.5453) * size.width
            let y = fract(sin(s * 78.233) * 12543.123) * size.height * 0.75
            let twinkle = 0.25 + 0.75 * abs(sin(t * (0.6 + fract(s * 0.37)) + s))
            let r = 0.5 + fract(s * 0.731) * 0.9
            var star = context
            star.opacity = twinkle * 0.8
            star.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                      with: .color(i % 7 == 0 ? Theme.violet : .white))
        }

        // Planet rising on the right, with a rim light.
        let rise = CGFloat((sin(t / 9) + 1) / 2)
        let planetR = size.height * 0.62
        let planetC = CGPoint(x: size.width * 0.74, y: size.height * (1.02 - 0.12 * rise) + planetR * 0.35)
        let planet = Path(ellipseIn: CGRect(x: planetC.x - planetR, y: planetC.y - planetR, width: 2 * planetR, height: 2 * planetR))
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 14))
            glow.fill(planet, with: .color(Theme.blue.opacity(0.35)))
        }
        context.fill(planet, with: .radialGradient(
            Gradient(colors: [Color(hex: 0x6F7BFF), Color(hex: 0x2A2F7A), Color(hex: 0x14173F)]),
            center: CGPoint(x: planetC.x - planetR * 0.3, y: planetC.y - planetR * 0.45),
            startRadius: 0, endRadius: planetR * 1.2))
        context.stroke(planet, with: .linearGradient(
            Gradient(colors: [Theme.cyan.opacity(0.8), .clear]),
            startPoint: CGPoint(x: planetC.x, y: planetC.y - planetR), endPoint: planetC), lineWidth: 1.2)

        // Aurora waves: three layers drifting at different speeds.
        let layers: [(amp: CGFloat, base: CGFloat, speed: Double, colors: [Color], alpha: Double)] = [
            (0.16, 0.72, 0.18, [Theme.violet, Theme.blue, Theme.cyan], 0.55),
            (0.12, 0.80, -0.12, [Color(hex: 0x4B3BFF), Theme.cyan, Theme.blue], 0.5),
            (0.09, 0.90, 0.25, [Theme.blue, Theme.cyan, Color(hex: 0x8FF3FF)], 0.7),
        ]
        for layer in layers {
            var wave = Path()
            wave.move(to: CGPoint(x: 0, y: size.height))
            let steps = 48
            for i in 0...steps {
                let u = Double(i) / Double(steps)
                let y = layer.base
                    + layer.amp * CGFloat(sin(u * 2 * .pi * 1.2 + t * layer.speed))
                    + layer.amp * 0.5 * CGFloat(sin(u * 2 * .pi * 2.7 - t * layer.speed * 1.6))
                wave.addLine(to: CGPoint(x: CGFloat(u) * size.width, y: y * size.height))
            }
            wave.addLine(to: CGPoint(x: size.width, y: size.height))
            wave.closeSubpath()
            let shading = GraphicsContext.Shading.linearGradient(Gradient(colors: layer.colors),
                                                                startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
            context.drawLayer { glow in
                glow.opacity = layer.alpha * 0.6
                glow.addFilter(.blur(radius: 10))
                glow.fill(wave, with: shading)
            }
            var crisp = context
            crisp.opacity = layer.alpha * 0.55
            crisp.fill(wave, with: shading)
        }

        // Shooting star every ~7.5 s.
        let period = 7.5
        let phase = (t / period).truncatingRemainder(dividingBy: 1) * period
        if phase < 0.9 {
            let k = CGFloat(phase / 0.9)
            let head = CGPoint(x: size.width * (0.92 - 0.25 * k), y: size.height * (0.15 + 0.35 * k))
            let tail = CGPoint(x: head.x + size.width * 0.07, y: head.y - size.height * 0.1)
            var streak = Path()
            streak.move(to: tail)
            streak.addLine(to: head)
            var s = context
            s.opacity = Double(sin(k * .pi))
            s.stroke(streak, with: .linearGradient(Gradient(colors: [.clear, Theme.violet, .white]),
                                                  startPoint: tail, endPoint: head),
                     style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
    }

    private static func fract(_ x: Double) -> Double { x - floor(x) }
}
