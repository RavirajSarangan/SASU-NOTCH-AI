import AppKit
import Observation

/// Tracks the global mouse position. Mouse-moved global monitors do not need
/// Accessibility permission.
@Observable
@MainActor
final class CursorTrackingService {
    /// Mouse location in screen coordinates (origin bottom-left).
    private(set) var location: CGPoint = NSEvent.mouseLocation

    @ObservationIgnored var onMove: ((CGPoint) -> Void)?
    /// Clicks delivered to *other* apps (used for click-outside-to-close).
    @ObservationIgnored var onOutsideClick: ((CGPoint) -> Void)?

    @ObservationIgnored private var monitors: [Any] = []

    func start() {
        guard monitors.isEmpty else { return }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            self?.update()
        }) { monitors.append(global) }

        if let local = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.update()
            return event
        }) { monitors.append(local) }

        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.onOutsideClick?(NSEvent.mouseLocation)
        }) { monitors.append(clicks) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func update() {
        let point = NSEvent.mouseLocation
        guard point != location else { return }
        location = point
        onMove?(point)
    }

    /// Direction from `anchor` to `point` as a unit-disk vector in SwiftUI
    /// orientation (+y is down). `reach` is the distance at which the eyes
    /// hit their limit.
    nonisolated static func gaze(from anchor: CGPoint, to point: CGPoint, reach: CGFloat = 320) -> CGPoint {
        let dx = (point.x - anchor.x) / reach
        let dy = -(point.y - anchor.y) / reach
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 1 else { return CGPoint(x: dx, y: dy) }
        return CGPoint(x: dx / length, y: dy / length)
    }
}
