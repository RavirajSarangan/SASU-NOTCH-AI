import AppKit
import SwiftUI

/// Small rotating arc used for in-progress states.
///
/// The rotation is a Core Animation animation on its own layer, so the window
/// server spins it with no per-frame work in Nova (a SwiftUI repeating
/// animation would re-run at the display's 120 Hz for every spinner).
struct Spinner: View {
    var color: Color = Theme.cyan
    var size: CGFloat = 11
    var lineWidth: CGFloat = 1.6

    @Environment(\.novaStyle) private var style

    var body: some View {
        Group {
            if IsolatedHostSwitch.enabled {
                SpinnerLayer(color: NSColor(color), lineWidth: lineWidth, spinning: !style.paused)
            } else {
                // Snapshots can't draw NSViews: a still arc.
                Circle()
                    .trim(from: 0, to: 0.68)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

private struct SpinnerLayer: NSViewRepresentable {
    let color: NSColor
    let lineWidth: CGFloat
    let spinning: Bool

    func makeNSView(context: Context) -> SpinnerView { SpinnerView() }

    func updateNSView(_ view: SpinnerView, context: Context) {
        view.update(color: color, lineWidth: lineWidth, spinning: spinning)
    }
}

final class SpinnerView: NSView {
    private let arc = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        arc.fillColor = nil
        arc.lineCap = .round
        arc.strokeEnd = 0.68
        layer?.addSublayer(arc)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let inset = arc.lineWidth / 2
        arc.frame = bounds
        arc.path = CGPath(ellipseIn: bounds.insetBy(dx: inset, dy: inset), transform: nil)
    }

    func update(color: NSColor, lineWidth: CGFloat, spinning: Bool) {
        arc.strokeColor = color.cgColor
        arc.lineWidth = lineWidth
        needsLayout = true
        let key = "spin"
        if spinning, arc.animation(forKey: key) == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi   // clockwise in AppKit's flipped-up coordinates
            spin.duration = 1.25
            spin.repeatCount = .infinity
            spin.isRemovedOnCompletion = false
            arc.add(spin, forKey: key)
        } else if !spinning {
            arc.removeAnimation(forKey: key)
        }
    }
}
