import AppKit
import NovaKit
import SwiftUI

/// What's happening around Nova, for Nova 2's body language. Set once near
/// the root (see `NotchRootView`); every Nova 2 view reads it.
struct NovaLiveContext {
    /// 0…1 while an agent is working.
    var agentActivity: Double?
    /// When the oldest pending approval arrived.
    var approvalSince: Date?
    var guardAlert = false
    /// Source of the current beat while music plays and dancing is on.
    var music: MusicTapService?
}

private struct NovaLiveContextKey: EnvironmentKey {
    static let defaultValue = NovaLiveContext()
}

extension EnvironmentValues {
    var novaLive: NovaLiveContext {
        get { self[NovaLiveContextKey.self] }
        set { self[NovaLiveContextKey.self] = newValue }
    }
}

/// Owns the rig engine for one on-screen Nova and turns its events into particles.
@MainActor
final class RigDriver {
    private var engine = RigEngine(seed: UInt64.random(in: 1...UInt64.max))
    private var lastTime: Double?
    private(set) var particles: [RigParticle] = []
    private(set) var frame = RigFrame()
    var pet = 0.0
    var lastHover: CGPoint?
    private var rendered: RigFrame?

    func markRendered() { rendered = frame }

    /// True when the new frame differs visibly (≥ ½ pixel) from the last one drawn.
    func needsRender(pixelsPerUnit: Double, effects: Bool) -> Bool {
        guard let last = rendered else { return true }
        if (effects && !particles.isEmpty) || frame.eyes != last.eyes || frame.fx != last.fx || frame.headphones != last.headphones
            || frame.shield != nil || frame.eyes == .dots || frame.eyes == .hum || frame.eyes == .spiral || frame.fx != nil && effects {
            return true
        }
        let a = frame.pose, b = last.pose
        let units = [abs(a.tilt - b.tilt) * 0.9, abs(a.turn - b.turn) * 15, abs(a.earL - b.earL) * 0.7, abs(a.earR - b.earR) * 0.7,
                     abs(a.gx - b.gx) * 7, abs(a.gy - b.gy) * 5, abs(a.sy - b.sy) * 120, abs(a.dy - b.dy), abs(a.hy - b.hy),
                     abs(a.bx - b.bx), abs(a.lean - b.lean) * 1.2, abs(a.tail - b.tail) * 0.9, abs(a.pawL - b.pawL) * 0.5,
                     abs(a.pawR - b.pawR) * 0.5, abs(a.chest - b.chest) * 6, abs(frame.blink - last.blink) * 22].max() ?? 0
        return units * pixelsPerUnit * 2 >= 0.5   // ×2 for Retina pixels
    }
    private var idleSeconds = 0.0, idleCheckedAt = -10.0
    private var lastNoteBar = Int.min

    func tick(time: Double, input base: RigInputs, skin: RigSkin) -> RigFrame {
        let dt = min(max(time - (lastTime ?? time), 0), 0.1)
        lastTime = time
        var input = base
        pet = max(0, pet - dt * 0.5)
        input.pet = pet
        if time - idleCheckedAt > 1 {
            idleCheckedAt = time
            idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        }
        input.idleSeconds = idleSeconds
        input.hour = Calendar.current.component(.hour, from: Date())
        frame = engine.step(dt: dt, input)

        let p = frame.pose
        for event in frame.events {
            switch event {
            case .burst:
                for i in 0..<12 {
                    let a = Double.random(in: 0..<(2 * .pi)), v = Double.random(in: 60...140)
                    particles.append(RigParticle(kind: .star, x: 120, y: 70 + p.dy, vx: cos(a) * v, vy: sin(a) * v - 40,
                                                 life: 0.9, maxLife: 0.9, size: .random(in: 4...8), color: i.isMultiple(of: 2) ? skin.glow1 : RigColors.amber))
                }
            case .drops:
                for i in 0..<10 {
                    let side = i.isMultiple(of: 2) ? 1.0 : -1
                    particles.append(RigParticle(kind: .drop, x: 120 + side * 60, y: 110, vx: side * .random(in: 60...120), vy: -.random(in: 60...100),
                                                 gravity: 300, life: 0.8, maxLife: 0.8, color: RigColors.cyan))
                }
            case .knock:
                let a = p.pawR * .pi / 180
                particles.append(RigParticle(kind: .ring, x: 151 - 31 * sin(a), y: 170 + 31 * cos(a) + p.dy, life: 0.5, maxLife: 0.5, size: 4, color: skin.glow1))
            case .stamp:
                particles.append(RigParticle(kind: .ring, x: 120, y: 168 + p.dy, life: 0.8, maxLife: 0.8, size: 6, color: RigColors.mint))
                particles.append(RigParticle(kind: .check, x: 152, y: 150, vy: -30, life: 1.2, maxLife: 1.2, color: RigColors.mint))
            case .pop, .chime, .boop:
                break   // The app's own mood sounds already cover these moments.
            }
        }
        if pet > 0.1, Double.random(in: 0...1) < dt * 3 * pet {
            particles.append(RigParticle(kind: .heart, x: 120 + .random(in: -30...30), y: 40, vx: .random(in: -10...10), vy: -35,
                                         life: 1.3, maxLife: 1.3, color: RigColors.pink))
        }
        if frame.dancing, let beat = input.music?.beat {
            let bar = Int(floor(beat / 4))
            if bar != lastNoteBar {
                lastNoteBar = bar
                particles.append(RigParticle(kind: .note, x: 182, y: 70, vx: 20, vy: -40, life: 1.4, maxLife: 1.4, color: skin.glow1))
            }
        }
        particles = particles.compactMap { var q = $0
            q.life -= dt
            guard q.life > 0 else { return nil }
            q.vy += q.gravity * dt
            q.x += q.vx * dt
            q.y += q.vy * dt
            if q.kind == .ring { q.size += 60 * dt }
            return q
        }
        return frame
    }
}

/// Nova 2: the code-drawn, rigged character. Same inputs as the classic view.
struct NovaRigView: View {
    var art: NovaArt = .body
    var expression: NovaExpression
    var cursor: CursorTrackingService
    var anchor: CGPoint
    var paused = false
    var maxFPS: Double?
    var showsEffects = true
    var variant: RigVariant?

    @ViewState private var driver = RigDriver()
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.novaStyle) private var style
    @Environment(\.novaLive) private var live

    private var reduceMotion: Bool { systemReduceMotion || style.motion == 0 }
    private var headOnly: Bool { art == .head }

    var body: some View {
        Group {
            if IsolatedHostSwitch.enabled { layerBody } else { timelineBody }
        }
        .aspectRatio(headOnly ? 152.0 / 140 : 264.0 / 260, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Nova")
        .accessibilityValue(expression.spokenDescription)
        .accessibilityAddTraits(.isImage)
    }

    /// Live app: drawn on its own display link, outside SwiftUI layout (cheap).
    private var layerBody: some View {
        let skin = RigSkin.named(style.skin)
        let driver = self.driver
        let effects = showsEffects && style.effects
        return CanvasLayer(fps: reduceMotion ? 20 : (maxFPS ?? 30), paused: paused || style.paused, draw: { context, size, time in
            let frame = driver.frame
            driver.markRendered()
            var o = renderOptions(skin: skin, time: time)
            o.minimal = min(size.width, size.height) < 70
            NovaRigRenderer.draw(frame, particles: effects ? driver.particles : [], in: &context, size: size, options: o)
        }, prepare: { time, size in
            _ = driver.tick(time: time, input: inputs(now: Date()), skin: skin)
            return driver.needsRender(pixelsPerUnit: min(size.width, size.height) / 240, effects: effects)
        }, onHover: { [style] point in
            guard style.reactions else { return }
            if let point, let last = driver.lastHover {
                driver.pet = min(1, driver.pet + min(hypot(point.x - last.x, point.y - last.y), 20) * 0.012)
            }
            driver.lastHover = point
        })
    }

    /// Snapshots: TimelineView + Canvas (ImageRenderer can't draw NSViews).
    private var timelineBody: some View {
        let fps = reduceMotion ? 20 : maxFPS
        let skin = RigSkin.named(style.skin)
        return TimelineView(.animation(minimumInterval: fps.map { 1 / $0 }, paused: paused || style.paused)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let frame = driver.tick(time: time, input: inputs(now: timeline.date), skin: skin)
            // Only plain values go into the Canvas closure (it isn't main-actor isolated).
            let particles = showsEffects && style.effects ? driver.particles : []
            let options = renderOptions(skin: skin, time: time)
            Canvas { context, size in
                var o = options
                o.minimal = min(size.width, size.height) < 70
                NovaRigRenderer.draw(frame, particles: particles, in: &context, size: size, options: o)
            }
        }
    }

    private func renderOptions(skin: RigSkin, time: Double) -> NovaRigRenderer.Options {
        var o = NovaRigRenderer.Options()
        o.variant = headOnly ? .peek : (variant ?? .pearl)
        o.skin = skin
        o.headOnly = headOnly
        o.showFX = showsEffects && style.effects
        o.time = time
        return o
    }

    private func inputs(now: Date) -> RigInputs {
        var input = RigInputs(mood: RigMood(rawValue: expression.rawValue) ?? .idle)
        input.variant = headOnly ? .peek : (variant ?? .pearl)
        input.reduceMotion = reduceMotion || !style.reactions
        if style.eyeTracking {
            let g = CursorTrackingService.gaze(from: anchor, to: cursor.location)
            input.look = RigPoint(x: g.x, y: g.y)
        }
        if let activity = live.agentActivity, expression == .coding || expression == .typing { input.typingActivity = activity }
        if let since = live.approvalSince { input.approvalAge = now.timeIntervalSince(since) }
        input.guardAlert = live.guardAlert
        input.music = live.music?.sample()
        return input
    }
}

// MARK: - Scene backgrounds

/// The animated background behind Nova 2, one per situation, crossfading
/// over 0.6 s. Drawn in a Canvas; paused with the rest of Nova.
struct SceneBackgroundView: View {
    @ViewState private var state = SceneState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if IsolatedHostSwitch.enabled {
            let state = self.state, scene = self.scene, music = self.music, still = reduceMotion
            CanvasLayer(fps: fps, paused: paused, draw: { context, size, time in
                state.draw(scene: scene, time: still ? 0 : time, beat: music?.sample()?.beat, in: &context, size: size)
            })
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
            SceneCanvas(scene: scene, music: music, paused: paused)
        }
    }

    var scene: RigScene
    var music: MusicTapService?
    var paused = false
    /// Frames per second; the always-visible notch strip uses fewer.
    var fps: Double = 12
}

private struct SceneCanvas: View {
    var scene: RigScene
    var music: MusicTapService?
    var paused = false

    @ViewState private var state = SceneState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: paused)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let beat = music?.sample()?.beat
            Canvas { context, size in
                state.draw(scene: scene, time: reduceMotion ? 0 : t, beat: beat, in: &context, size: size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Scene animation state. Only used from the Canvas renderer, one view at a time.
final class SceneState: @unchecked Sendable {
    private var current: RigScene?
    private var previous: RigScene?
    private var mix = 1.0
    private var lastTime: Double?
    private var confetti: [(x: Double, y: Double, vx: Double, vy: Double, r: Double, vr: Double, c: Color, life: Double)] = []
    private var rings: [(t0: Double, c: Color)] = []
    private var lastBeat = Int.min
    private let stars: [(x: Double, y: Double, r: Double, p: Double, z: Double)] = (0..<70).map { _ in
        (.random(in: 0...1), .random(in: 0...1), .random(in: 0.3...1.7), .random(in: 0...(2 * .pi)), .random(in: 0...1))
    }
    private let columns: [(y: Double, v: Double, chars: [String])] = (0..<26).map { _ in
        (.random(in: 0...1), .random(in: 0.05...0.13), (0..<14).map { _ in String("{}<>/=;()[]01λ$#".randomElement()!) })
    }
    private var columnOffset = 0.0

    /// Code-rain glyphs rendered once to images; drawing `Text` per glyph per
    /// frame (hundreds) was the single biggest CPU cost of the scenes.
    private static let glyphs: [String: Image] = {
        var out: [String: Image] = [:]
        let font = NSFont.monospacedSystemFont(ofSize: 26, weight: .regular)
        for ch in "{}<>/=;()[]01λ$#".map(String.init) {
            let image = NSImage(size: NSSize(width: 30, height: 30), flipped: false) { rect in
                let text = NSAttributedString(string: ch, attributes: [.font: font, .foregroundColor: NSColor(RigColors.cyan)])
                let size = text.size()
                text.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
                return true
            }
            out[ch] = Image(nsImage: image)
        }
        return out
    }()

    func draw(scene: RigScene, time t: Double, beat: Double?, in ctx: inout GraphicsContext, size: CGSize) {
        let dt = min(max(t - (lastTime ?? t), 0), 0.1)
        lastTime = t
        if scene != current {
            previous = current; current = scene; mix = previous == nil ? 1 : 0
            if scene == .success { spawnConfetti() }
        }
        mix = min(1, mix + dt / 0.6)
        columnOffset += dt
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.hex(0x0B1033)))
        if let previous, mix < 1 {
            var c = ctx; c.opacity = 1 - mix
            paint(previous, t: t, dt: dt, beat: beat, in: &c, size: size)
        }
        var c = ctx; c.opacity = mix
        paint(scene, t: t, dt: dt, beat: beat, in: &c, size: size)
    }

    private func spawnConfetti() {
        let colors = [RigColors.mint, RigColors.cyan, RigColors.amber, RigColors.pink, RigColors.violet]
        for i in 0..<90 {
            confetti.append((0.5 + .random(in: -0.1...0.1), 0.45, .random(in: -0.45...0.45), -.random(in: 0.3...1.4),
                             .random(in: 0...6.28), .random(in: -6...6), colors[i % colors.count], .random(in: 3...4.5)))
        }
    }

    private func background(_ a: Color, _ b: Color, in ctx: inout GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(Gradient(colors: [a, b]),
                 center: CGPoint(x: size.width / 2, y: size.height * 0.1), startRadius: 0, endRadius: size.height * 0.95))
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func paint(_ scene: RigScene, t: Double, dt: Double, beat: Double?, in ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height, u = min(w, h) / 400
        switch scene {
        case .aurora:
            background(.hex(0x22307A), .hex(0x0B1033), in: &ctx, size: size)
            var glow = ctx
            glow.blendMode = .plusLighter
            for (color, yy, ph) in [(RigColors.cyan, 0.30, 0.0), (RigColors.violet, 0.42, 2.0), (RigColors.mint, 0.55, 4.0)] {
                var path = Path()
                var x = -20.0
                while x <= w + 20 {
                    let y = h * yy + sin(x / w * 5 + t * 0.25 + ph) * 34 * u + sin(x / w * 11 - t * 0.4 + ph) * 10 * u
                    x < -19 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                    x += 12
                }
                for (lw, a) in [(70.0, 0.05), (36, 0.07), (12, 0.1)] {
                    glow.stroke(path, with: .color(color.opacity(a)), style: StrokeStyle(lineWidth: lw * u, lineCap: .round))
                }
            }
        case .code:
            background(.hex(0x14204F), .hex(0x070B22), in: &ctx, size: size)
            let cw = w / Double(columns.count)
            for (i, col) in columns.enumerated() {
                let y0 = ((col.y + col.v * columnOffset).truncatingRemainder(dividingBy: 1.6) - 0.3) * h
                for (j, ch) in col.chars.enumerated() {
                    let y = y0 + Double(j) * 15 * u
                    guard y > 0, y < h, let glyph = Self.glyphs[ch] else { continue }
                    var g = ctx
                    g.opacity = j == col.chars.count - 1 ? 0.5 : 0.09 + Double(j) * 0.008
                    let side = 15 * u
                    g.draw(glyph, in: CGRect(x: Double(i) * cw + cw * 0.5 - side / 2, y: y - side / 2, width: side, height: side))
                }
            }
        case .thinking:
            background(.hex(0x1E2766), .hex(0x090D2A), in: &ctx, size: size)
            for s in stars {
                let x = ((s.x - t * 0.004 * (1 + s.z * 3)).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
                let r = s.r * u * (1 + s.z)
                ctx.fill(Path(ellipseIn: CGRect(x: x * w - r, y: s.y * h - r, width: r * 2, height: r * 2)), with: .color(.hex(0xDDE3FF).opacity(0.25 + 0.35 * s.z)))
            }
            for i in 0..<3 {
                let a0 = t * 0.7 + Double(i) * 2 * .pi / 3
                for k in 0..<10 {
                    let a = a0 - Double(k) * 0.06, r = (6 - Double(k) * 0.45) * u
                    let c = CGPoint(x: w / 2 + cos(a) * w * 0.36, y: h * 0.42 + sin(a) * h * 0.12)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(RigColors.violet.opacity(0.5 - Double(k) * 0.045)))
                }
            }
        case .music:
            background(.hex(0x2A1E6E), .hex(0x0A0B2A), in: &ctx, size: size)
            let b = Int(floor(beat ?? t * 2))
            if b != lastBeat { lastBeat = b; rings.append((t, [RigColors.violet, RigColors.pink, RigColors.cyan, RigColors.amber][((b % 4) + 4) % 4])) }
            rings.removeAll { t - $0.t0 > 2 }
            for ring in rings {
                let a = (t - ring.t0) / 2, r = a * w * 0.65 + 40 * u
                ctx.stroke(Path(ellipseIn: CGRect(x: w / 2 - r, y: h * 0.48 - r, width: r * 2, height: r * 2)),
                           with: .color(ring.c.opacity((1 - a) * 0.5)), lineWidth: 3 * u * (1 - a) + 0.5)
            }
            let n = 28, bw = w / Double(n), phase = (beat ?? t * 2).truncatingRemainder(dividingBy: 1)
            for i in 0..<n {
                let v = 0.25 + 0.55 * pow(1 - phase, 2) * (0.5 + 0.5 * sin(Double(i) * 1.7 + t * 3)) + 0.1 * sin(Double(i) + t * 6)
                let bh = max(0, v) * h * 0.28
                ctx.fill(Path(CGRect(x: Double(i) * bw + bw * 0.18, y: h - bh, width: bw * 0.64, height: bh)),
                         with: .linearGradient(Gradient(colors: [RigColors.violet.opacity(0.55), RigColors.pink.opacity(0.55)]),
                                               startPoint: CGPoint(x: 0, y: h), endPoint: CGPoint(x: 0, y: h - bh)))
            }
        case .success:
            background(.hex(0x1D3A6B), .hex(0x081530), in: &ctx, size: size)
            confetti = confetti.compactMap { var p = $0
                p.life -= dt
                guard p.life > 0 else { return nil }
                p.vy += 0.9 * dt; p.x += p.vx * dt * 0.5; p.y += p.vy * dt * 0.6; p.r += p.vr * dt
                return p
            }
            if confetti.count < 20, Double.random(in: 0...1) < dt * 2 {
                for i in 0..<6 { confetti.append((.random(in: 0...1), -0.05, .random(in: -0.15...0.15), 0.1, 0, .random(in: -4...4), [RigColors.mint, RigColors.amber, RigColors.pink][i % 3], 3.5)) }
            }
            for p in confetti {
                var c = ctx
                c.opacity = min(1, p.life)
                c.translateBy(x: p.x * w, y: p.y * h)
                c.rotate(by: .radians(p.r))
                c.fill(Path(CGRect(x: -4 * u, y: -2 * u, width: 8 * u, height: 4 * u)), with: .color(p.c))
            }
            for s in stars.prefix(24) {
                let r = s.r * u * 1.5
                ctx.fill(Path(ellipseIn: CGRect(x: s.x * w - r, y: s.y * h * 0.8 - r, width: r * 2, height: r * 2)),
                         with: .color(RigColors.amber.opacity(0.3 + 0.3 * sin(t * 3 + s.p))))
            }
        case .error, .warning:
            let color = scene == .error ? RigColors.coral : RigColors.amber
            background(scene == .error ? .hex(0x3A1A3E) : .hex(0x3A2E3A), .hex(0x0D0B22), in: &ctx, size: size)
            let pulse = 0.5 + 0.5 * sin(t * (scene == .error ? 5 : 3))
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(Gradient(colors: [color.opacity(0.18 + 0.14 * pulse), .clear]),
                     center: CGPoint(x: w / 2, y: h * 0.45), startRadius: 0, endRadius: w * (0.35 + 0.1 * pulse)))
        case .guarding:
            background(.hex(0x0E2A4A), .hex(0x04101F), in: &ctx, size: size)
            let r = 22 * u, hh = r * 3.0.squareRoot(), scan = ((t * 0.35).truncatingRemainder(dividingBy: 1.3) - 0.15) * h
            var row = -1
            while Double(row) * hh * 0.5 < h + hh {
                var col = -1
                while Double(col) * r * 1.5 < w + r {
                    let cx = Double(col) * r * 1.5, cy = Double(row) * hh + (col % 2 != 0 ? hh / 2 : 0), d = abs(cy - scan)
                    var hex = Path()
                    for k in 0..<6 {
                        let a = Double(k) * .pi / 3, p = CGPoint(x: cx + cos(a) * r * 0.92, y: cy + sin(a) * r * 0.92)
                        k == 0 ? hex.move(to: p) : hex.addLine(to: p)
                    }
                    hex.closeSubpath()
                    let near = d < 60 * u
                    ctx.stroke(hex, with: .color((near ? RigColors.coral : RigColors.cyan).opacity(0.07 + max(0, 1 - d / (60 * u)) * 0.5)), lineWidth: 1.2 * u)
                    col += 1
                }
                row += 1
            }
            ctx.fill(Path(CGRect(x: 0, y: scan, width: w, height: 2 * u)), with: .color(RigColors.coral.opacity(0.6)))
        case .night:
            background(.hex(0x141A4A), .hex(0x03051A), in: &ctx, size: size)
            for s in stars {
                let r = s.r * u
                ctx.fill(Path(ellipseIn: CGRect(x: s.x * w - r, y: s.y * h * 0.75 - r, width: r * 2, height: r * 2)),
                         with: .color(.hex(0xF4F6FF).opacity(0.3 + 0.6 * (0.5 + 0.5 * sin(t * (1 + s.z * 2) + s.p)))))
            }
            let moon = Path(ellipseIn: CGRect(x: w * 0.18 - 26 * u, y: h * 0.17 - 26 * u, width: 52 * u, height: 52 * u))
            let bite = Path(ellipseIn: CGRect(x: w * 0.18 + 11 * u - 23 * u, y: h * 0.17 - 7 * u - 23 * u, width: 46 * u, height: 46 * u))
            ctx.fill(moon.subtracting(bite), with: .color(.hex(0xF8F1D8).opacity(0.9)))
            let sp = t.truncatingRemainder(dividingBy: 9) / 9
            if sp < 0.12 {
                let k = sp / 0.12
                var streak = Path()
                streak.move(to: CGPoint(x: w * (0.9 - k * 0.5), y: h * (0.08 + k * 0.2)))
                streak.addLine(to: CGPoint(x: w * (0.95 - k * 0.5), y: h * (0.05 + k * 0.2)))
                ctx.stroke(streak, with: .color(.white.opacity(1 - k)), lineWidth: 2 * u)
            }
        }
    }
}
