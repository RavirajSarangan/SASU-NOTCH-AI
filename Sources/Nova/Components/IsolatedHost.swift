import AppKit
import QuartzCore
import SwiftUI

/// Animated drawing that bypasses SwiftUI's update cycle.
///
/// A `TimelineView` tick makes AppKit lay out the whole notch window, which
/// cost most of Nova's CPU while a session was live. This view instead runs
/// its own display link, renders the SwiftUI `Canvas` drawing into an image
/// (about 0.15 ms) and hands it to its layer — no layout pass at all.
/// Snapshots (ImageRenderer) can't draw NSViews, so the exporter turns this
/// off and callers fall back to TimelineView + Canvas.
struct CanvasLayer: NSViewRepresentable {
    var fps: Double
    var paused: Bool
    var draw: @MainActor (inout GraphicsContext, CGSize, Double) -> Void
    /// Called every tick with the time and view size; return false to skip
    /// rendering this frame because nothing visible changed.
    var prepare: (@MainActor (Double, CGSize) -> Bool)? = nil
    /// Pointer position inside the view (nil when it leaves).
    var onHover: (@MainActor (CGPoint?) -> Void)?

    func makeNSView(context: Context) -> CanvasLayerView { CanvasLayerView() }

    func updateNSView(_ view: CanvasLayerView, context: Context) {
        view.draw = draw
        view.prepare = prepare
        view.onHover = onHover
        view.configure(fps: fps, paused: paused)
    }
}

@MainActor
final class CanvasLayerView: NSView {
    var draw: (@MainActor (inout GraphicsContext, CGSize, Double) -> Void)?
    var prepare: (@MainActor (Double, CGSize) -> Bool)?
    var onHover: (@MainActor (CGPoint?) -> Void)?
    private var link: CADisplayLink?
    private var fps = 30.0
    private var paused = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // clicks reach the SwiftUI view beneath

    func configure(fps: Double, paused: Bool) {
        self.fps = fps
        self.paused = paused
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: Float(fps / 2), maximum: Float(fps), preferred: Float(fps))
        link?.isPaused = paused
        if paused { render(time: CACurrentMediaTime()) }   // keep a still frame
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let l = displayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: Float(fps / 2), maximum: Float(fps), preferred: Float(fps))
        l.isPaused = paused
        l.add(to: .main, forMode: .common)
        link = l
        render(time: CACurrentMediaTime())
    }

    @objc private func tick(_ link: CADisplayLink) {
        if let prepare, !prepare(link.targetTimestamp, bounds.size), layer?.contents != nil { return }
        render(time: link.targetTimestamp)
    }

    /// One renderer per view, reused every frame (building one per frame was
    /// most of the cost).
    private var renderer: ImageRenderer<AnyView>?

    private func render(time: Double) {
        guard let draw, bounds.width > 1, bounds.height > 1 else { return }
        let size = bounds.size
        let content = AnyView(Canvas { context, s in draw(&context, s, time) }.frame(width: size.width, height: size.height))
        let renderer: ImageRenderer<AnyView>
        if let existing = self.renderer {
            renderer = existing
            renderer.content = content
        } else {
            renderer = ImageRenderer(content: content)
            renderer.isOpaque = false
            self.renderer = renderer
        }
        renderer.scale = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = renderer.cgImage
        CATransaction.commit()
    }

    // Hover (for petting) without taking clicks.
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        guard onHover != nil else { return }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) { onHover?(convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { onHover?(nil) }
}

/// Off while exporting snapshots: ImageRenderer can't draw NSViews.
@MainActor
enum IsolatedHostSwitch {
    static var enabled = true
}
