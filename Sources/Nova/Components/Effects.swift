import SwiftUI

// In-house motion effects (no third-party packages: Pow and Vortex need
// Xcode's asset compiler, which this CLT-only build doesn't have). All of
// them run only briefly after a trigger and respect Reduce Motion.

/// Buttons shrink slightly when pressed: a tactile, native feel.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(.spring(duration: 0.22, bounce: 0.4), value: configuration.isPressed)
    }
}

/// A one-shot particle burst (confetti or sparkles) drawn with Canvas.
/// Each change of `trigger` fires a new burst that lasts `duration`.
struct ParticleBurst: View {
    enum Style { case confetti, sparkles }

    var trigger: Int
    var style: Style = .confetti
    var count = 26
    var duration: TimeInterval = 1.2

    @ViewState private var startedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let palette: [Color] = [Theme.cyan, Theme.violet, Theme.success, Color(hex: 0xFFB454), Color(hex: 0xFF6FB5)]

    var body: some View {
        Group {
            if let startedAt, !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                    let age = timeline.date.timeIntervalSince(startedAt)
                    Canvas { context, size in
                        guard age < duration else { return }
                        draw(in: &context, size: size, age: age)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) {
            startedAt = Date()
            let id = trigger
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(duration + 0.1))
                if trigger == id { startedAt = nil }   // stop the timeline: no idle cost
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, age: TimeInterval) {
        let origin = CGPoint(x: size.width / 2, y: size.height * 0.55)
        let fade = 1 - pow(age / duration, 2)
        for i in 0..<count {
            let seed = Double(i) * 12.9898
            let r1 = fract(sin(seed) * 43758.5453), r2 = fract(sin(seed * 1.7) * 24634.6345)
            let angle = -Double.pi / 2 + (r1 - 0.5) * .pi * 1.3
            let speed = 140 + r2 * 160
            let t = age
            let x = origin.x + CGFloat(cos(angle) * speed * t)
            let y = origin.y + CGFloat(sin(angle) * speed * t + 260 * t * t)   // gravity
            var c = context
            c.opacity = fade
            let color = Self.palette[i % Self.palette.count]
            switch style {
            case .confetti:
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(t * (4 + r1 * 8)))
                c.fill(Path(roundedRect: CGRect(x: -3, y: -1.5, width: 6, height: 3), cornerRadius: 1), with: .color(color))
            case .sparkles:
                let s = CGFloat(2 + r2 * 3) * CGFloat(fade)
                var star = Path()
                star.move(to: CGPoint(x: x, y: y - s * 2)); star.addLine(to: CGPoint(x: x + s * 0.5, y: y - s * 0.5))
                star.addLine(to: CGPoint(x: x + s * 2, y: y)); star.addLine(to: CGPoint(x: x + s * 0.5, y: y + s * 0.5))
                star.addLine(to: CGPoint(x: x, y: y + s * 2)); star.addLine(to: CGPoint(x: x - s * 0.5, y: y + s * 0.5))
                star.addLine(to: CGPoint(x: x - s * 2, y: y)); star.addLine(to: CGPoint(x: x - s * 0.5, y: y - s * 0.5))
                star.closeSubpath()
                c.fill(star, with: .color(color))
            }
        }
    }

    private func fract(_ x: Double) -> Double { x - floor(x) }
}

/// A short damped horizontal shake each time `trigger` changes.
struct ShakeEffect: ViewModifier {
    var trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let still = reduceMotion
        return content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, x in
            view.offset(x: still ? 0 : x)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0, duration: 0.01)
                SpringKeyframe(7, duration: 0.07)
                SpringKeyframe(-6, duration: 0.07)
                SpringKeyframe(4, duration: 0.07)
                SpringKeyframe(-2, duration: 0.07)
                SpringKeyframe(0, duration: 0.12)
            }
        }
    }
}

/// A soft light sweep across the view each time `trigger` changes.
struct ShineEffect: ViewModifier {
    var trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, .white.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(width: width * 0.35)
                        .rotationEffect(.degrees(18))
                        .keyframeAnimator(initialValue: -0.5, trigger: trigger) { view, p in
                            view.offset(x: p * width * 1.6)
                        } keyframes: { _ in
                            KeyframeTrack {
                                LinearKeyframe(-0.5, duration: 0.01)
                                CubicKeyframe(1.0, duration: 0.7)
                            }
                        }
                }
                .allowsHitTesting(false)
                .clipped()
            }
        }
    }
}

/// Fades and lifts content in, delayed by `index` (staggered entrance).
struct StaggeredAppear: ViewModifier {
    var index: Int
    @ViewState private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .blur(radius: shown || reduceMotion ? 0 : 3)
            .onAppear {
                withAnimation(.spring(duration: 0.45, bounce: 0.15).delay(Double(index) * 0.05)) { shown = true }
            }
    }
}

extension View {
    func shake(_ trigger: Int) -> some View { modifier(ShakeEffect(trigger: trigger)) }
    func shine(_ trigger: Int) -> some View { modifier(ShineEffect(trigger: trigger)) }
    func staggeredAppear(_ index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
}
