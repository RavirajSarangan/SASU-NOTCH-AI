import NovaKit
import SwiftUI

/// A Nova 2 colour palette. A skin is only data.
struct RigSkin: Sendable {
    var name: String
    var fur1, fur2, rim, glow1, glow2, visor1, visor2, eye, collar: Color

    static let aurora = RigSkin(name: "Aurora", fur1: .hex(0xFFFFFF), fur2: .hex(0xE4E1FA), rim: .hex(0xA99CF5), glow1: .hex(0x5FE3FF),
                                glow2: .hex(0x8B6CFF), visor1: .hex(0x1C1F38), visor2: .hex(0x05060D), eye: .hex(0x78CFFF), collar: .hex(0x22264A))
    static let midnight = RigSkin(name: "Midnight", fur1: .hex(0x5A5F78), fur2: .hex(0x2B2F47), rim: .hex(0x53E7FF), glow1: .hex(0x53E7FF),
                                  glow2: .hex(0x2F86FF), visor1: .hex(0x0E1426), visor2: .hex(0x000000), eye: .hex(0x86F4FF), collar: .hex(0x0B0E1A))
    static let sakura = RigSkin(name: "Sakura", fur1: .hex(0xFFF7F9), fur2: .hex(0xF7D6E1), rim: .hex(0xFF9EC2), glow1: .hex(0xFFC4D8),
                                glow2: .hex(0xFF7FAF), visor1: .hex(0x2B1A25), visor2: .hex(0x0C0609), eye: .hex(0xFFEBD9), collar: .hex(0x3B2331))
    static let neon = RigSkin(name: "Neon", fur1: .hex(0x34343F), fur2: .hex(0x16161D), rim: .hex(0xFF4FD8), glow1: .hex(0x4FFFA8),
                              glow2: .hex(0xFF4FD8), visor1: .hex(0x101017), visor2: .hex(0x000000), eye: .hex(0x4FFFA8), collar: .hex(0x000000))
    static let gold = RigSkin(name: "Gold", fur1: .hex(0xFFFDF6), fur2: .hex(0xEEE3C8), rim: .hex(0xE2B04E), glow1: .hex(0xFFE08A),
                              glow2: .hex(0xE8A93C), visor1: .hex(0x201B12), visor2: .hex(0x060504), eye: .hex(0xFFD978), collar: .hex(0xB98A2E))

    static let all: [String: RigSkin] = ["aurora": aurora, "midnight": midnight, "sakura": sakura, "neon": neon, "gold": gold]
    static let order = ["aurora", "midnight", "sakura", "neon", "gold"]
    static func named(_ id: String) -> RigSkin { all[id] ?? aurora }
}

enum RigColors {
    static let amber = Color.hex(0xFFB454), coral = Color.hex(0xFF7A8A), mint = Color.hex(0x5BE49B)
    static let cyan = Color.hex(0x53E7FF), pink = Color.hex(0xFF9EC2), violet = Color.hex(0xA36CFF)

    static func tint(_ t: RigTint, _ fallback: Color) -> Color {
        switch t {
        case .none: fallback
        case .amber: amber
        case .coral: coral
        case .mint: mint
        }
    }
}

extension Color {
    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// A short-lived particle in design space (240 × 240).
struct RigParticle {
    enum Kind { case star, heart, drop, ring, check, note }
    var kind: Kind
    var x, y: Double
    var vx = 0.0, vy = 0.0, gravity = 0.0
    var life: Double
    var maxLife: Double
    var size = 5.0
    var color: Color
}

/// Draws Nova 2 from a `RigFrame`, back to front, in a 240 × 240 design
/// space scaled to the view. Mirrors docs/character/index.html.
enum NovaRigRenderer {
    struct Options {
        var variant: RigVariant = .pearl
        var skin: RigSkin = .aurora
        /// Small sizes: no tufts, no shine, thicker eyes.
        var minimal = false
        /// Head only (the notch).
        var headOnly = false
        var showFX = true
        var time = 0.0
    }

    /// The design-space rectangle shown.
    static func viewBox(_ o: Options) -> CGRect {
        o.headOnly ? CGRect(x: 44, y: 10, width: 152, height: 140) : CGRect(x: -12, y: -12, width: 264, height: 260)
    }

    static func draw(_ f: RigFrame, particles: [RigParticle] = [], in context: inout GraphicsContext, size: CGSize, options o: Options) {
        let box = viewBox(o)
        let scale = min(size.width / box.width, size.height / box.height)
        var ctx = context
        ctx.translateBy(x: (size.width - box.width * scale) / 2, y: (size.height - box.height * scale) / 2)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        Drawing(f: f, o: o, s: o.skin, glowScale: scale).character(&ctx)
        if o.showFX, !o.headOnly, let fx = f.fx { Drawing.symbol(fx, skin: o.skin, in: &ctx, time: o.time) }
        for p in particles { Drawing.particle(p, in: &ctx) }
    }

    private struct Drawing {
        let f: RigFrame
        let o: Options
        let s: RigSkin
        let glowScale: CGFloat

        var p: RigPose { f.pose }

        func furShading(_ r: CGRect) -> GraphicsContext.Shading {
            .radialGradient(Gradient(stops: [.init(color: s.fur1, location: 0), .init(color: s.fur2, location: 0.72), .init(color: s.rim, location: 1)]),
                            center: CGPoint(x: r.minX + r.width * 0.36, y: r.minY + r.height * 0.28),
                            startRadius: 0, endRadius: max(r.width, r.height) * 0.78)
        }

        func fur(_ path: Path, in ctx: inout GraphicsContext) { ctx.fill(path, with: furShading(path.boundingRect)) }

        func glowShading(_ r: CGRect) -> GraphicsContext.Shading {
            .linearGradient(Gradient(colors: [s.glow2, s.glow1]), startPoint: CGPoint(x: r.minX, y: r.maxY), endPoint: CGPoint(x: r.minX + r.width * 0.4, y: r.minY))
        }

        /// Fill with a soft bloom behind it. The bloom is a radial-gradient halo,
        /// not a blurred offscreen layer, so a frame stays cheap to draw.
        func glow(_ path: Path, _ shading: GraphicsContext.Shading, color: Color? = nil, in ctx: inout GraphicsContext) {
            if !o.minimal, let color {
                let b = path.boundingRect
                let r = max(b.width, b.height) / 2 + 3
                let halo = Path(ellipseIn: CGRect(x: b.midX - r * 1.6, y: b.midY - r * 1.6, width: r * 3.2, height: r * 3.2))
                ctx.fill(halo, with: .radialGradient(Gradient(colors: [color.opacity(0.45), color.opacity(0)]),
                                                     center: CGPoint(x: b.midX, y: b.midY), startRadius: r * 0.4, endRadius: r * 1.6))
            }
            ctx.fill(path, with: shading)
        }

        func glow(_ path: Path, _ color: Color, in ctx: inout GraphicsContext) {
            glow(path, .color(color), color: color, in: &ctx)
        }

        static func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Path {
            Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        }

        // MARK: Character

        func character(_ ctx: inout GraphicsContext) {
            switch o.variant {
            case .peek: peek(&ctx)
            case .pearl, .orbit: fullBody(&ctx)
            }
        }

        func fullBody(_ ctx: inout GraphicsContext) {
            let lift = min(max(-p.dy / 40, 0), 0.6)
            if o.variant == .orbit {
                let ring = Self.ellipse(120 + p.bx, 224, 44 * (1 - lift * 0.4), 7)
                ctx.stroke(ring, with: .color(s.glow1.opacity(0.25)), lineWidth: 8)
                ctx.stroke(ring, with: .color(s.glow1.opacity(0.7)), lineWidth: 3)
                ctx.fill(Self.ellipse(120 + p.bx, 224, 26, 4), with: .color(s.glow1.opacity(0.25)))
            } else if !o.headOnly {
                ctx.fill(Self.ellipse(120 + p.bx, 226, 54 * (1 - lift * 0.5), 7), with: .color(.black.opacity(0.28 * (1 - lift))))
            }

            var b = ctx
            b.translateBy(x: p.bx, y: p.dy)
            b.translateBy(x: 120, y: 228)
            b.rotate(by: .degrees(p.lean))
            b.scaleBy(x: 1 / p.sy.squareRoot(), y: p.sy)
            b.translateBy(x: -120, y: -228)

            let leftRaised = abs(p.pawL) > 90, rightRaised = abs(p.pawR) > 90
            if !o.headOnly {
                if o.variant == .pearl {
                    tail(&b)
                    fur(Self.ellipse(120, 188, 45, 36), in: &b)
                    b.fill(Self.ellipse(120, 194, 25, 19), with: .color(.white.opacity(0.35)))
                    b.fill(Self.ellipse(120, 153, 46, 8), with: .color(.black.opacity(0.13)))
                    for side in [-1.0, 1.0] {
                        fur(Self.ellipse(120 + side * 23, 218, 15, 9), in: &b)
                        if !o.minimal { glow(Self.ellipse(120 + side * 23, 220, 3.6, 3.6), s.glow1, in: &b) }
                    }
                } else {
                    var body = Path()
                    body.move(to: CGPoint(x: 90, y: 160))
                    body.addCurve(to: CGPoint(x: 120, y: 214), control1: CGPoint(x: 86, y: 196), control2: CGPoint(x: 106, y: 214))
                    body.addCurve(to: CGPoint(x: 150, y: 160), control1: CGPoint(x: 134, y: 214), control2: CGPoint(x: 154, y: 196))
                    body.closeSubpath()
                    fur(body, in: &b)
                    b.fill(Self.ellipse(120, 152, 44, 8), with: .color(.black.opacity(0.14)))
                }
                var arms = b
                if o.variant == .orbit { arms.translateBy(x: 0, y: 4) }
                if !leftRaised { arm(-1, p.pawL, in: &arms) }
                if !rightRaised { arm(1, p.pawR, in: &arms) }
                collar(&b)
                if f.laptop { laptop(&b) }
            }
            var h = b
            h.translateBy(x: 0, y: p.hy)
            h.translateBy(x: 120, y: 150)
            h.rotate(by: .degrees(p.tilt))
            h.translateBy(x: -120, y: -150)
            head(&h)
            if !o.headOnly {
                if leftRaised { arm(-1, p.pawL, in: &b) }
                if rightRaised { arm(1, p.pawR, in: &b) }
            }
        }

        func peek(_ ctx: inout GraphicsContext) {
            var h = ctx
            h.translateBy(x: p.bx, y: (o.headOnly ? 0 : 34) + p.dy + p.hy)
            h.translateBy(x: 120, y: 150)
            h.rotate(by: .degrees(p.tilt + p.lean))
            h.translateBy(x: -120, y: -150)
            head(&h)
            guard !o.headOnly else { return }
            ctx.fill(Path(roundedRect: CGRect(x: 6, y: 186, width: 228, height: 54), cornerRadius: 22), with: .color(.black))
            ctx.fill(Path(CGRect(x: 6, y: 186, width: 228, height: 10)), with: .color(.black))
            let lifts = [min(max((p.pawL - 12) * 0.1, -4), 16), min(max(-(p.pawR + 12) * 0.1, -4), 16)]
            for (i, side) in [-1.0, 1.0].enumerated() {
                let x = 120 + side * 34 + p.bx, y = 186 - lifts[i]
                fur(Self.ellipse(x, y, 12, 9), in: &ctx)
                if !o.minimal { glow(Self.ellipse(x, y + 3, 3, 3), s.glow1, in: &ctx) }
            }
        }

        func tail(_ ctx: inout GraphicsContext) {
            var t = ctx
            t.translateBy(x: 150, y: 206)
            t.rotate(by: .degrees(p.tail))
            var path = Path()
            path.move(to: .zero)
            path.addCurve(to: CGPoint(x: 34, y: -56), control1: CGPoint(x: 40, y: 2), control2: CGPoint(x: 52, y: -36))
            t.stroke(path, with: furShading(CGRect(x: 0, y: -60, width: 50, height: 62)), style: StrokeStyle(lineWidth: 17, lineCap: .round))
            let tip = Self.ellipse(34, -58, 11, 11)
            if o.minimal { t.fill(tip, with: glowShading(tip.boundingRect)) } else { glow(tip, glowShading(tip.boundingRect), color: s.glow1, in: &t) }
        }

        func arm(_ side: Double, _ angle: Double, in ctx: inout GraphicsContext) {
            var a = ctx
            a.translateBy(x: 120 + side * 31, y: 170)
            a.rotate(by: .degrees(angle))
            // Raised arms reach a little further so the paws clear the cheeks.
            let reach = min(max((abs(angle) - 60) / 60, 0), 1) * 0.3
            a.scaleBy(x: 1, y: 1 + reach)
            fur(Self.ellipse(0, 17, 10.5, 18), in: &a)
            if !o.minimal { glow(Self.ellipse(0, 31, 3.6, 3.6), s.glow1, in: &a) }
        }

        func collar(_ ctx: inout GraphicsContext) {
            var c = Path()
            c.move(to: CGPoint(x: 82, y: 148))
            c.addQuadCurve(to: CGPoint(x: 158, y: 148), control: CGPoint(x: 120, y: 166))
            c.addLine(to: CGPoint(x: 156, y: 160))
            c.addQuadCurve(to: CGPoint(x: 84, y: 160), control: CGPoint(x: 120, y: 180))
            c.closeSubpath()
            ctx.fill(c, with: .color(s.collar))
            let chestColor = RigColors.tint(f.chestTint, s.glow1)
            let chest = min(max(p.chest, 0), 3)
            if chest > 1.05 {
                ctx.fill(Self.ellipse(120, 167, 8 + chest * 5, 8 + chest * 5), with: .color(chestColor.opacity((chest - 1) * 0.25)))
            }
            var tri = Path()
            tri.move(to: CGPoint(x: 113, y: 163)); tri.addLine(to: CGPoint(x: 127, y: 163)); tri.addLine(to: CGPoint(x: 120, y: 174)); tri.closeSubpath()
            glow(tri, chestColor.opacity(min(0.55 + chest * 0.45, 1)), in: &ctx)
        }

        func laptop(_ ctx: inout GraphicsContext) {
            var base = Path()
            base.move(to: CGPoint(x: 84, y: 206)); base.addLine(to: CGPoint(x: 156, y: 206))
            base.addLine(to: CGPoint(x: 164, y: 216)); base.addLine(to: CGPoint(x: 76, y: 216)); base.closeSubpath()
            ctx.fill(base, with: .color(s.collar))
            ctx.fill(Path(roundedRect: CGRect(x: 92, y: 200, width: 56, height: 7), cornerRadius: 2), with: .color(s.glow1.opacity(0.55)))
        }

        func ear(_ angle: Double, in ctx: inout GraphicsContext) {
            var e = ctx
            e.translateBy(x: 72, y: 84)
            e.rotate(by: .degrees(-angle))
            e.translateBy(x: -72, y: -84)
            var outer = Path()
            outer.move(to: CGPoint(x: 54, y: 92))
            outer.addCurve(to: CGPoint(x: 66, y: 16), control1: CGPoint(x: 46, y: 60), control2: CGPoint(x: 52, y: 32))
            outer.addCurve(to: CGPoint(x: 106, y: 62), control1: CGPoint(x: 82, y: 30), control2: CGPoint(x: 98, y: 48))
            outer.closeSubpath()
            fur(outer, in: &e)
            var inner = Path()
            inner.move(to: CGPoint(x: 64, y: 80))
            inner.addCurve(to: CGPoint(x: 69, y: 30), control1: CGPoint(x: 60, y: 60), control2: CGPoint(x: 63, y: 42))
            inner.addCurve(to: CGPoint(x: 95, y: 62), control1: CGPoint(x: 79, y: 41), control2: CGPoint(x: 89, y: 52))
            inner.closeSubpath()
            e.fill(inner, with: glowShading(inner.boundingRect))
        }

        func head(_ ctx: inout GraphicsContext) {
            let turn = p.turn, vx = 120 + turn * 11, ex = 120 + turn * 15, vy = 100.0
            var ears = ctx
            ears.translateBy(x: -turn * 4, y: 0)
            ear(p.earL, in: &ears)
            var right = ears
            right.translateBy(x: 240, y: 0)
            right.scaleBy(x: -1, y: 1)
            ear(p.earR, in: &right)

            if !o.minimal {
                var tufts = Path()
                tufts.addLines([CGPoint(x: 54, y: 112), CGPoint(x: 40, y: 108), CGPoint(x: 50, y: 118), CGPoint(x: 38, y: 120), CGPoint(x: 54, y: 128)])
                tufts.closeSubpath()
                tufts.addLines([CGPoint(x: 186, y: 112), CGPoint(x: 200, y: 108), CGPoint(x: 190, y: 118), CGPoint(x: 202, y: 120), CGPoint(x: 186, y: 128)])
                tufts.closeSubpath()
                fur(tufts, in: &ctx)
            }
            fur(Self.ellipse(120, 96, 70 - abs(turn) * 4, 58), in: &ctx)
            fur(Self.ellipse(120 - turn * 2, 42, 15, 9), in: &ctx)

            if f.headphones {
                var band = Path()
                band.move(to: CGPoint(x: 54 - turn * 3, y: 92))
                band.addCurve(to: CGPoint(x: 186 - turn * 3, y: 92), control1: CGPoint(x: 54 - turn * 3, y: 14), control2: CGPoint(x: 186 - turn * 3, y: 14))
                ctx.stroke(band, with: .color(s.collar), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            }

            let visor = Self.ellipse(vx, vy, 51, 37)
            ctx.fill(visor, with: .linearGradient(Gradient(colors: [s.visor1, s.visor2]), startPoint: CGPoint(x: vx, y: vy - 37), endPoint: CGPoint(x: vx, y: vy + 37)))
            ctx.stroke(visor, with: .color(s.rim.opacity(0.35)), lineWidth: 1.5)
            if !o.minimal {
                var shine = Path()
                shine.move(to: CGPoint(x: vx - 36 - turn * 6, y: vy - 14))
                shine.addQuadCurve(to: CGPoint(x: vx - 4 - turn * 6, y: vy - 32), control: CGPoint(x: vx - 26 - turn * 6, y: vy - 30))
                ctx.stroke(shine, with: .color(.white.opacity(0.32)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            if let sweep = f.shield {
                var c = ctx
                c.clip(to: visor)
                c.translateBy(x: vx, y: vy)
                c.rotate(by: .degrees(20))
                c.translateBy(x: -vx, y: -vy)
                c.fill(Path(CGRect(x: vx - 80 + sweep * 160, y: 40, width: 16, height: 120)), with: .color(.white.opacity(0.35)))
                ctx.stroke(Self.ellipse(vx, vy, 53, 39), with: .color(RigColors.coral.opacity(0.4 + 0.3 * sin(sweep * 2 * .pi))), lineWidth: 2)
            }

            var eyesCtx = ctx
            eyesCtx.translateBy(x: 0, y: vy)
            eyesCtx.scaleBy(x: 1, y: max(f.blink, 0.06))
            eyesCtx.translateBy(x: 0, y: -vy)
            eyes(in: &eyesCtx, x0: ex, y: vy)

            if f.headphones {
                for side in [-1.0, 1.0] {
                    let x = 120 + side * 68 - turn * 3
                    ctx.fill(Path(roundedRect: CGRect(x: x - 11, y: 78, width: 22, height: 40), cornerRadius: 10), with: .color(s.collar))
                    glow(Path(roundedRect: CGRect(x: x - 4, y: 86, width: 8, height: 24), cornerRadius: 4), s.glow1.opacity(0.85), in: &ctx)
                }
            }
        }

        /// The eye shapes (fills and strokes), matching the prototype.
        func eyes(in ctx: inout GraphicsContext, x0: Double, y y0: Double) {
            let color = RigColors.tint(f.eyeTint, s.eye)
            let d = 19.0, ox = p.gx * 7, y = y0 + p.gy * 5
            let w = o.minimal ? 13.0 : 11, h = o.minimal ? 24.0 : 22, sw = o.minimal ? 6.5 : 5
            var fills = Path(), strokes = Path(), thin = Path()
            let xs = [x0 - d + ox, x0 + d + ox]
            func pill(_ x: Double, _ yy: Double, _ ww: Double, _ hh: Double) {
                fills.addRoundedRect(in: CGRect(x: x - ww / 2, y: yy - hh / 2, width: ww, height: hh), cornerSize: CGSize(width: min(ww, hh) / 2, height: min(ww, hh) / 2))
            }
            switch f.eyes {
            case .arc:
                for x in xs { strokes.move(to: CGPoint(x: x - 9, y: y + 4)); strokes.addQuadCurve(to: CGPoint(x: x + 9, y: y + 4), control: CGPoint(x: x, y: y - 9)) }
            case .closed:
                for x in xs { strokes.move(to: CGPoint(x: x - 9, y: y + 1)); strokes.addQuadCurve(to: CGPoint(x: x + 9, y: y + 1), control: CGPoint(x: x, y: y + 7)) }
            case .half: for x in xs { pill(x, y + 4, w, h * 0.45) }
            case .focus: for x in xs { pill(x, y + 1, w, h * 0.62) }
            case .tall: for x in xs { pill(x, y - 1, w + 1, h + 4) }
            case .wide: for x in xs { fills.addEllipse(in: CGRect(x: x - 10, y: y - 10, width: 20, height: 20)) }
            case .lookup: for x in xs { pill(x + 3, y - 6, w, h * 0.8) }
            case .x:
                for x in xs {
                    strokes.move(to: CGPoint(x: x - 7, y: y - 7)); strokes.addLine(to: CGPoint(x: x + 7, y: y + 7))
                    strokes.move(to: CGPoint(x: x + 7, y: y - 7)); strokes.addLine(to: CGPoint(x: x - 7, y: y + 7))
                }
            case .flat:
                for (i, x) in xs.enumerated() {
                    let s = i == 0 ? -1.0 : 1
                    pill(x, y + 4, w + 2, h * 0.42)
                    thin.move(to: CGPoint(x: x - 8, y: y - 6 - s * 2)); thin.addLine(to: CGPoint(x: x + 8, y: y - 6 + s * 2))
                }
            case .uneven:
                pill(xs[0], y, w, h)
                fills.addEllipse(in: CGRect(x: xs[1] - 6, y: y + 2 - 6, width: 12, height: 12))
            case .dots:
                for (i, dx) in [-20.0, 0, 20].enumerated() {
                    let a = 0.25 + 0.75 * (0.5 + 0.5 * sin(o.time * 5 - Double(i) * 1.1))
                    ctx.fill(Self.ellipse(x0 + dx, y, 5.5 * a + 1.5, 5.5 * a + 1.5), with: .color(color.opacity(a)))
                }
            case .spiral:
                for x in xs {
                    thin.move(to: CGPoint(x: x, y: y))
                    for k in 0...36 {
                        let a = Double(k) / 36 * 4 * .pi, r = 1 + Double(k) / 36 * 7
                        thin.addLine(to: CGPoint(x: x + cos(a + o.time * 4) * r, y: y + sin(a + o.time * 4) * r))
                    }
                }
            case .hum:
                for i in 0...28 {
                    let u = Double(i) / 28, xx = x0 - 34 + u * 68
                    let pt = CGPoint(x: xx, y: y + sin(u * 14 + o.time * 9) * 8 * sin(u * .pi))
                    i == 0 ? strokes.move(to: pt) : strokes.addLine(to: pt)
                }
            case .pill: for x in xs { pill(x, y, w, h) }
            }
            if !o.minimal { ctx.drawLayer { l in
                l.addFilter(.blur(radius: 3 * glowScale))
                l.fill(fills, with: .color(color))
                l.stroke(strokes, with: .color(color), style: StrokeStyle(lineWidth: sw, lineCap: .round, lineJoin: .round))
                l.stroke(thin, with: .color(color), style: StrokeStyle(lineWidth: f.eyes == .spiral ? 3 : sw * 0.6, lineCap: .round))
            } }
            ctx.fill(fills, with: .color(color))
            ctx.stroke(strokes, with: .color(color), style: StrokeStyle(lineWidth: sw, lineCap: .round, lineJoin: .round))
            ctx.stroke(thin, with: .color(color), style: StrokeStyle(lineWidth: f.eyes == .spiral ? 3 : sw * 0.6, lineCap: .round))
            if f.eyes == .wide, !o.minimal {
                for x in xs { ctx.fill(Self.ellipse(x + 3, y - 3, 3, 3), with: .color(.white.opacity(0.85))) }
            }
        }

        // MARK: Symbols and particles

        static func star(_ x: Double, _ y: Double, _ r: Double) -> Path {
            let k = r * 0.32
            var p = Path()
            p.move(to: CGPoint(x: x, y: y - r))
            p.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x + k, y: y - k))
            p.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x + k, y: y + k))
            p.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x - k, y: y + k))
            p.addQuadCurve(to: CGPoint(x: x, y: y - r), control: CGPoint(x: x - k, y: y - k))
            return p
        }

        static func heart(_ x: Double, _ y: Double, _ r: Double) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: x, y: y + r * 0.9))
            p.addCurve(to: CGPoint(x: x, y: y - r * 0.4), control1: CGPoint(x: x - r * 1.6, y: y - r * 0.2), control2: CGPoint(x: x - r * 0.7, y: y - r * 1.4))
            p.addCurve(to: CGPoint(x: x, y: y + r * 0.9), control1: CGPoint(x: x + r * 0.7, y: y - r * 1.4), control2: CGPoint(x: x + r * 1.6, y: y - r * 0.2))
            return p
        }

        static func text(_ s: String, size: CGFloat, color: Color, at point: CGPoint, in ctx: inout GraphicsContext, mono: Bool = false) {
            let font: Font = mono ? .system(size: size, weight: .bold, design: .monospaced) : .system(size: size, weight: .heavy, design: .rounded)
            ctx.draw(Text(s).font(font).foregroundColor(color), at: point)
        }

        static func symbol(_ fx: RigFX, skin s: RigSkin, in ctx: inout GraphicsContext, time: Double) {
            let g = s.glow1
            switch fx {
            case .dots:
                for (i, (x, y, r)) in [(186.0, 46.0, 4.0), (198, 34, 5.5), (214, 20, 7.5)].enumerated() {
                    ctx.fill(ellipse(x, y, r, r), with: .color(g.opacity(0.25 + 0.75 * (0.5 + 0.5 * sin(time * 5 - Double(i))))))
                }
            case .code: text("</>", size: 15, color: g, at: CGPoint(x: 198, y: 40), in: &ctx, mono: true)
            case .waves:
                var a = Path(); a.move(to: CGPoint(x: 200, y: 70)); a.addQuadCurve(to: CGPoint(x: 200, y: 94), control: CGPoint(x: 208, y: 82))
                var b = Path(); b.move(to: CGPoint(x: 210, y: 62)); b.addQuadCurve(to: CGPoint(x: 210, y: 102), control: CGPoint(x: 223, y: 82))
                ctx.stroke(a, with: .color(g.opacity(0.9)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                ctx.stroke(b, with: .color(g.opacity(0.55)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            case .bang:
                ctx.fill(ellipse(196, 40, 13, 13), with: .color(RigColors.amber))
                text("!", size: 18, color: .hex(0x1A1206), at: CGPoint(x: 196, y: 40), in: &ctx)
            case .sweat:
                var d = Path(); d.move(to: CGPoint(x: 188, y: 64)); d.addQuadCurve(to: CGPoint(x: 188, y: 78), control: CGPoint(x: 178, y: 76))
                d.addQuadCurve(to: CGPoint(x: 188, y: 64), control: CGPoint(x: 198, y: 76))
                ctx.fill(d, with: .color(RigColors.cyan.opacity(0.9)))
            case .zzz:
                for (i, (x, y, sz)) in [(186.0, 56.0, 14.0), (198, 40, 18), (212, 20, 23)].enumerated() {
                    let a = 0.35 + 0.65 * (0.5 + 0.5 * sin(time * 2 - Double(i)))
                    text(i == 2 ? "Z" : "z", size: sz, color: g.opacity(a), at: CGPoint(x: x, y: y), in: &ctx)
                }
            case .question: text("?", size: 30, color: g, at: CGPoint(x: 200, y: 42), in: &ctx)
            case .badge:
                ctx.fill(ellipse(190, 38, 15, 15), with: .color(RigColors.coral.opacity(0.25)))
                ctx.fill(ellipse(190, 38, 9, 9), with: .color(RigColors.coral))
            case .stars:
                for (i, (dx, r)) in [(-36.0, 7.0), (36, 6), (0, 5)].enumerated() {
                    let a = time * 2 + Double(i) * 2.1
                    ctx.fill(star(120 + dx * cos(a) + 0, 26 + 8 * sin(a), r), with: .color(i == 1 ? g : RigColors.amber))
                }
            }
        }

        static func particle(_ p: RigParticle, in ctx: inout GraphicsContext) {
            let a = min(max(p.life / p.maxLife, 0), 1)
            let c = p.color.opacity(a)
            switch p.kind {
            case .star: ctx.fill(star(p.x, p.y, p.size), with: .color(c))
            case .heart: ctx.fill(heart(p.x, p.y, 6), with: .color(c))
            case .drop: ctx.fill(ellipse(p.x, p.y, 2.5, 4), with: .color(c))
            case .ring: ctx.stroke(ellipse(p.x, p.y, p.size, p.size), with: .color(c), lineWidth: 3)
            case .check:
                var path = Path(); path.move(to: CGPoint(x: p.x - 7, y: p.y)); path.addLine(to: CGPoint(x: p.x - 2, y: p.y + 5)); path.addLine(to: CGPoint(x: p.x + 7, y: p.y - 5))
                ctx.stroke(path, with: .color(c), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            case .note: text("♪", size: 22, color: c, at: CGPoint(x: p.x, y: p.y), in: &ctx)
            }
        }
    }
}
