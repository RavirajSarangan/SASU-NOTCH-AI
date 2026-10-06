import AppKit
import SwiftUI

/// Which Nova art to draw. Both share the same width and origin, so they
/// share eye geometry.
enum NovaArt: Hashable, Sendable {
    case body, head
    /// Full-body pose from the pose sheet.
    case pose(NovaPose)

    /// height / width of the image.
    var aspect: CGFloat {
        switch self {
        case .body: 803.0 / 588.0
        case .head: 543.0 / 588.0
        case .pose(let pose): pose.aspect
        }
    }

    @MainActor var image: NSImage {
        switch self {
        case .body: MascotAssets.body
        case .head: MascotAssets.head
        case .pose(let pose): MascotAssets.pose(pose)
        }
    }

    var eyes: EyeGeometry {
        if case .pose(let pose) = self { return pose.eyes }
        return .standard
    }

    /// The body art becomes the pose for the mood (when poses are on).
    func resolved(for expression: NovaExpression, poses: Bool) -> NovaArt {
        guard poses, self == .body else { return self }
        return .pose(expression.pose)
    }
}

/// Eye placement on the visor, measured from the source art, in units of
/// image width so it scales with the view.
struct EyeGeometry: Sendable {
    var left = CGPoint(x: 0.4233, y: 0.6194)
    var right = CGPoint(x: 0.7172, y: 0.7063)
    var width: CGFloat = 0.072
    var length: CGFloat = 0.18
    /// The face is turned slightly to the right, so the eyes lean.
    var tilt: Angle = .degrees(17)
    /// Maximum eye travel inside the visor.
    var travel: CGFloat = 0.03

    static let standard = EyeGeometry()
}

/// Draws Nova's eyes: one parametric shape (pill → squint → smile → closed)
/// with a soft glow, a gentle gradient and a small highlight.
enum NovaCharacterRenderer {
    static func drawEyes(in context: inout GraphicsContext, size: CGSize, frame: NovaFrame,
                         geometry g: EyeGeometry = .standard) {
        let unit = size.width
        let p = frame.eyes
        for (index, anchor) in [g.left, g.right].enumerated() {
            let openness = p.openness * (index == 1 ? p.rightEyeFactor : 1) * Double(frame.blink)
            let w = g.width * unit * CGFloat(p.scale)
            let fullHeight = g.length * unit * CGFloat(p.scale)
            let h = max(fullHeight * CGFloat(openness), w * 0.2)
            let center = CGPoint(x: anchor.x * unit + frame.gaze.x * g.travel * unit,
                                 y: anchor.y * unit + frame.gaze.y * g.travel * unit * 0.8)

            var eye = context
            eye.translateBy(x: center.x, y: center.y)
            eye.rotate(by: g.tilt)
            let shape = eyePath(width: w, height: h, topLid: p.topLid, smile: p.smile)

            // Soft glow.
            eye.drawLayer { glow in
                glow.addFilter(.blur(radius: w * 0.38))
                glow.opacity = 0.45 * p.glow
                glow.fill(shape, with: .color(p.tint.color))
            }
            // Body with a gentle vertical gradient.
            eye.fill(shape, with: .linearGradient(
                Gradient(colors: [p.tint.mixed(to: EyeTint(r: 1, g: 1, b: 1), 0.45).color, p.tint.color, p.tint.mixed(to: EyeTint(r: 0.2, g: 0.35, b: 0.9), 0.45).color]),
                startPoint: CGPoint(x: 0, y: -h / 2), endPoint: CGPoint(x: 0, y: h / 2)))
            // Small specular highlight near the top.
            if h > w * 0.9 && p.smile < 0.3 && p.topLid < 0.05 {
                let highlight = Path(roundedRect: CGRect(x: -w * 0.18, y: -h / 2 + w * 0.18, width: w * 0.36, height: w * 0.22),
                                     cornerRadius: w * 0.11)
                eye.fill(highlight, with: .color(.white.opacity(0.35)))
            }
        }
    }

    /// Pill, optionally squinted (flat top) and/or smiling (lower arc cut).
    static func eyePath(width w: CGFloat, height h: CGFloat, topLid: Double, smile: Double) -> Path {
        var shape = Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: min(w, h) / 2)
        if topLid > 0.01 {
            let cut = h * CGFloat(topLid)
            shape = shape.intersection(Path(CGRect(x: -w, y: -h / 2 + cut, width: w * 2, height: h)))
        }
        if smile > 0.01 {
            // An ellipse rising from below carves the pill into a soft "^".
            let s = CGFloat(smile)
            let cutter = Path(ellipseIn: CGRect(x: -w * 0.8, y: h * (0.62 - 0.55 * s), width: w * 1.6, height: h * 1.1))
            shape = shape.subtracting(cutter)
        }
        return shape
    }
}
