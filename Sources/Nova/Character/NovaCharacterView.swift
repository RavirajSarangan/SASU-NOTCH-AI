import SwiftUI

/// Nova: pose art for each mood (or the hero art), live eyes that follow the
/// cursor and change shape with the mood, a short body reaction when the
/// mood changes, and small effects around it (hearts, Zs, sparkles…).
struct NovaCharacterView: View {
    var art: NovaArt = .body
    var expression: NovaExpression
    var cursor: CursorTrackingService
    /// Screen-space point the eyes look *from* (roughly the visor center).
    var anchor: CGPoint
    var paused = false
    /// Frame-rate cap; small notch heads don't need 60 fps.
    var maxFPS: Double? = nil
    var showsEffects = true

    @ViewState private var controller = NovaAnimationController()
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.novaStyle) private var style
    @Environment(\.novaLive) private var live

    private var reduceMotion: Bool { systemReduceMotion || style.motion == 0 }

    /// Effects may extend this far beyond the art on each side.
    private static let effectBleed: CGFloat = 0.3

    var body: some View {
        if style.nova2 {
            NovaRigView(art: art == .head ? .head : .body, expression: expression, cursor: cursor, anchor: anchor,
                        paused: paused, maxFPS: maxFPS, showsEffects: showsEffects)
        } else {
            classic
        }
    }

    @ViewBuilder private var classic: some View {
        let resolved = art.resolved(for: expression, poses: style.poses)
        let fps = reduceMotion ? 20 : maxFPS
        TimelineView(.animation(minimumInterval: fps.map { 1 / $0 }, paused: paused || style.paused)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let target = style.eyeTracking ? CursorTrackingService.gaze(from: anchor, to: cursor.location) : CGPoint(x: 0, y: 0.2)
            let frame = controller.frame(at: time, gazeTarget: target, expression: expression,
                                         reduceMotion: reduceMotion, motion: style.motion, reactions: style.reactions)
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    Image(nsImage: resolved.image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                    Canvas { context, size in
                        NovaCharacterRenderer.drawEyes(in: &context, size: size, frame: frame, geometry: resolved.eyes)
                    }
                }
                .frame(width: size.width, height: size.height)
                .id(resolved)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
                .scaleEffect(x: frame.body.scaleX, y: frame.body.scaleY * frame.breath, anchor: .bottom)
                .rotationEffect(.degrees(frame.body.tilt), anchor: .bottom)
                .offset(x: frame.body.dx * size.width, y: frame.body.dy * size.height)
                .animation(.spring(duration: 0.35, bounce: 0.25), value: resolved)
                // Overlay so the larger effects canvas never affects layout.
                .overlay {
                    if showsEffects, style.effects, case .pose(let pose) = resolved {
                        let bleedX = size.width * Self.effectBleed, bleedY = size.height * Self.effectBleed
                        Canvas { context, _ in
                            let artRect = CGRect(x: bleedX, y: bleedY + frame.body.dy * size.height,
                                                 width: size.width, height: size.height)
                            NovaEffectsRenderer.draw(in: &context, art: artRect, pose: pose, frame: frame)
                        }
                        .frame(width: size.width + 2 * bleedX, height: size.height + 2 * bleedY)
                        .allowsHitTesting(false)
                    }
                }
            }
            .aspectRatio(1 / resolved.aspect, contentMode: .fit)
        }
        .accessibilityElement()
        .accessibilityLabel("Nova")
        .accessibilityValue(expression.spokenDescription)
        .accessibilityAddTraits(.isImage)
    }
}
