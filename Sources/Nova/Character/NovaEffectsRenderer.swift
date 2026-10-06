import SwiftUI

/// Animated decorations around Nova, one set per pose. Everything is a pure
/// function of time and the frame's `age`, so nothing is allocated per frame.
///
/// Coordinates are fractions of the *art* rect, which sits inside a larger
/// canvas (see `NovaCharacterView`) so effects can spill past the art.
enum NovaEffectsRenderer {
    static func draw(in context: inout GraphicsContext, art: CGRect, pose: NovaPose, frame f: NovaFrame) {
        let t = f.time
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: art.minX + x * art.width, y: art.minY + y * art.height) }
        let unit = art.width

        switch pose {
        case .idle:
            for i in 0..<2 {
                let phase = t * 0.7 + Double(i) * 2.1
                let c = p(1.12 + 0.06 * CGFloat(sin(phase)), 0.52 - CGFloat(i) * 0.24 + 0.05 * CGFloat(cos(phase * 1.3)))
                butterfly(in: &context, at: c, size: unit * (0.09 - CGFloat(i) * 0.02), flap: CGFloat(abs(sin(t * 9 + Double(i)))))
            }

        case .happy:
            for i in 0..<3 {
                let cycle = (t / 2.2 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let c = p(0.98 + 0.08 * CGFloat(sin(cycle * 6 + Double(i))), 0.45 - 0.45 * CGFloat(cycle))
                glyph(in: &context, opacity: sin(cycle * .pi)) { ctx in
                    ctx.fill(heart(center: c, size: unit * (0.07 + 0.03 * CGFloat(cycle))), with: .color(Color(hex: 0xFF6FB5)))
                }
            }

        case .thinking:
            let c = p(1.0, 0.12 + 0.03 * CGFloat(sin(t * 2.2)))
            glyph(in: &context, glow: Theme.blue) { ctx in
                ctx.draw(text("?", size: unit * 0.24, color: Color(hex: 0x7FA8FF)), at: c)
            }

        case .typing:
            let s = 0.6 + 0.4 * abs(sin(t * 3))
            glyph(in: &context, glow: Theme.cyan) { ctx in
                ctx.fill(sparkle(center: p(1.0, 0.3), radius: unit * 0.05 * CGFloat(s)), with: .color(Theme.cyan))
            }

        case .sleep:
            for i in 0..<3 {
                let phase = (t / 2.8 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let c = p(0.86 + 0.14 * CGFloat(phase), 0.05 - 0.35 * CGFloat(phase))
                glyph(in: &context, opacity: sin(phase * .pi), glow: Theme.blue) { ctx in
                    ctx.draw(text("Z", size: unit * (0.09 + 0.06 * CGFloat(phase)), color: Color(hex: 0x6F8CFF)), at: c)
                }
            }

        case .alert:
            let pulse = 0.7 + 0.3 * abs(sin(t * 6))
            let pink = Color(hex: 0xFF5C8A)
            glyph(in: &context, opacity: pulse, glow: pink) { ctx in
                ctx.draw(text("!", size: unit * 0.28, color: pink), at: p(1.0, 0.1))
                for i in 0..<3 {
                    let a = Angle.degrees(200 + Double(i) * 35).radians
                    let center = p(0.42, 0.4)
                    let r1 = unit * 0.5, r2 = unit * (0.58 + 0.03 * CGFloat(pulse))
                    var tick = Path()
                    tick.move(to: CGPoint(x: center.x + r1 * CGFloat(cos(a)), y: center.y + r1 * CGFloat(sin(a))))
                    tick.addLine(to: CGPoint(x: center.x + r2 * CGFloat(cos(a)), y: center.y + r2 * CGFloat(sin(a))))
                    ctx.stroke(tick, with: .color(pink), style: StrokeStyle(lineWidth: unit * 0.025, lineCap: .round))
                }
            }

        case .dizzy:
            let center = p(0.58, 0.04)
            for i in 0..<3 {
                let a = t * 3 + Double(i) * 2 * .pi / 3
                let c = CGPoint(x: center.x + unit * 0.32 * CGFloat(cos(a)), y: center.y + unit * 0.07 * CGFloat(sin(a)))
                let depth = 0.55 + 0.45 * sin(a)
                glyph(in: &context, opacity: depth, glow: Theme.warning) { ctx in
                    ctx.fill(star(center: c, radius: unit * 0.045), with: .color(Color(hex: 0xFFE08A)))
                }
            }

        case .success:
            let spots: [(CGFloat, CGFloat, CGFloat)] = [(1.02, 0.18, 0.07), (-0.04, 0.12, 0.05), (0.95, 0.62, 0.04)]
            for (i, s) in spots.enumerated() {
                let tw = 0.55 + 0.45 * abs(sin(t * 2.4 + Double(i) * 1.7))
                glyph(in: &context, glow: Theme.warning) { ctx in
                    ctx.fill(sparkle(center: p(s.0, s.1), radius: unit * s.2 * CGFloat(tw)), with: .color(Color(hex: 0xFFD978)))
                }
            }
            if f.age < 1.4 { confetti(in: &context, origin: p(0.5, 0.25), unit: unit, age: f.age) }

        case .listening:
            let cycle = (t / 2.4).truncatingRemainder(dividingBy: 1)
            glyph(in: &context, opacity: sin(cycle * .pi), glow: Theme.blue) { ctx in
                ctx.draw(text("♪", size: unit * 0.16, color: Color(hex: 0x6F8CFF)), at: p(1.0 + 0.04 * CGFloat(sin(t * 3)), 0.15 - 0.15 * CGFloat(cycle)))
            }

        case .loading:
            let c = p(1.04, 0.2)
            let r = unit * 0.075
            var ring = Path()
            ring.addArc(center: c, radius: r, startAngle: .radians(t * 5), endAngle: .radians(t * 5 + 4.4), clockwise: false)
            glyph(in: &context, glow: Theme.blue) { ctx in
                ctx.stroke(ring, with: .color(Color(hex: 0x6F8CFF)), style: StrokeStyle(lineWidth: unit * 0.02, lineCap: .round))
            }
        }
    }

    // MARK: - Helpers

    /// Draws `content` twice: a blurred glow pass and a crisp pass.
    private static func glyph(in context: inout GraphicsContext, opacity: Double = 1, glow: Color? = nil,
                              _ content: (inout GraphicsContext) -> Void) {
        guard opacity > 0.01 else { return }
        if glow != nil {
            context.drawLayer { layer in
                layer.opacity = opacity * 0.7
                layer.addFilter(.blur(radius: 4))
                content(&layer)
            }
        }
        context.drawLayer { layer in
            layer.opacity = opacity
            content(&layer)
        }
    }

    private static func text(_ string: String, size: CGFloat, color: Color) -> Text {
        Text(string).font(.system(size: size, weight: .heavy, design: .rounded)).foregroundStyle(color)
    }

    private static func heart(center c: CGPoint, size s: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y + s * 0.35))
        p.addCurve(to: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.1),
                   control1: CGPoint(x: c.x - s * 0.2, y: c.y + s * 0.15), control2: CGPoint(x: c.x - s * 0.5, y: c.y + s * 0.1))
        p.addArc(center: CGPoint(x: c.x - s * 0.25, y: c.y - s * 0.12), radius: s * 0.25, startAngle: .degrees(175), endAngle: .degrees(355), clockwise: false)
        p.addArc(center: CGPoint(x: c.x + s * 0.25, y: c.y - s * 0.12), radius: s * 0.25, startAngle: .degrees(185), endAngle: .degrees(5), clockwise: false)
        p.addCurve(to: CGPoint(x: c.x, y: c.y + s * 0.35),
                   control1: CGPoint(x: c.x + s * 0.5, y: c.y + s * 0.1), control2: CGPoint(x: c.x + s * 0.2, y: c.y + s * 0.15))
        return p
    }

    /// Four-point twinkle.
    private static func sparkle(center c: CGPoint, radius r: CGFloat) -> Path {
        var p = Path()
        let k = r * 0.22
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - k, y: c.y - k))
        return p
    }

    private static func star(center c: CGPoint, radius r: CGFloat) -> Path {
        var p = Path()
        for i in 0..<10 {
            let a = Double(i) * .pi / 5 - .pi / 2
            let rr = i.isMultiple(of: 2) ? r : r * 0.45
            let pt = CGPoint(x: c.x + rr * CGFloat(cos(a)), y: c.y + rr * CGFloat(sin(a)))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }

    private static func butterfly(in context: inout GraphicsContext, at c: CGPoint, size s: CGFloat, flap: CGFloat) {
        glyph(in: &context, glow: Theme.cyan) { ctx in
            var wings = Path()
            let w = s * (0.35 + 0.65 * flap)
            wings.addEllipse(in: CGRect(x: c.x - w, y: c.y - s * 0.55, width: w, height: s * 0.6))
            wings.addEllipse(in: CGRect(x: c.x, y: c.y - s * 0.55, width: w, height: s * 0.6))
            wings.addEllipse(in: CGRect(x: c.x - w * 0.7, y: c.y, width: w * 0.7, height: s * 0.45))
            wings.addEllipse(in: CGRect(x: c.x, y: c.y, width: w * 0.7, height: s * 0.45))
            ctx.fill(wings, with: .color(Color(hex: 0x7FE6FF).opacity(0.9)))
        }
    }

    /// Short confetti burst from `origin`, seeded so it's identical each time.
    private static func confetti(in context: inout GraphicsContext, origin: CGPoint, unit: CGFloat, age: TimeInterval) {
        let colors: [Color] = [Theme.cyan, Theme.violet, Color(hex: 0xFFD978), Color(hex: 0xFF6FB5), Theme.success]
        let fade = max(0, 1 - age / 1.4)
        for i in 0..<24 {
            let seed = Double(i) * 12.9898
            let angle = -.pi / 2 + (fract(sin(seed) * 43758.5453) - 0.5) * 2.4
            let speed = 0.9 + fract(sin(seed * 1.7) * 9871.13) * 0.8
            let x = origin.x + unit * CGFloat(cos(angle) * speed * age)
            let y = origin.y + unit * CGFloat(sin(angle) * speed * age + 1.1 * age * age)
            let spin = Angle.radians(age * 8 + seed)
            var piece = context
            piece.opacity = fade
            piece.translateBy(x: x, y: y)
            piece.rotate(by: spin)
            piece.fill(Path(CGRect(x: -unit * 0.012, y: -unit * 0.025, width: unit * 0.024, height: unit * 0.05)),
                       with: .color(colors[i % colors.count]))
        }
    }

    private static func fract(_ x: Double) -> Double { x - floor(x) }
}
