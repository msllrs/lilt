import AppKit
import SwiftUI

/// The hit area of a sheet-style grab handle. An AppKit view rather than a SwiftUI gesture:
/// the window moves by its background, and AppKit decides that by asking the view under the
/// pointer, which for SwiftUI content is the hosting view, which says yes. This view says no
/// and handles the click and the pull itself.
struct GrabHandle: NSViewRepresentable {
    /// A click: a release within `pull` points of where the mouse went down.
    var onToggle: () -> Void
    /// The pointer has moved since the mouse went down, by this many points (up is positive).
    var onDrag: (_ travel: CGFloat) -> Void
    /// A pull of at least `pull` points has ended, with the pointer's speed in points per second.
    var onRelease: (_ travel: CGFloat, _ velocity: CGFloat) -> Void
    var pull: CGFloat = 12
    var toolTip: String?

    func makeNSView(context: Context) -> GrabHandleView { GrabHandleView() }

    func updateNSView(_ view: GrabHandleView, context: Context) {
        view.onToggle = onToggle
        view.onDrag = onDrag
        view.onRelease = onRelease
        view.pull = pull
        view.toolTip = toolTip
    }
}

final class GrabHandleView: NSView {
    var onToggle: () -> Void = {}
    var onDrag: (CGFloat) -> Void = { _ in }
    var onRelease: (CGFloat, CGFloat) -> Void = { _, _ in }
    var pull: CGFloat = 12
    private var start: NSPoint?
    /// The last two samples, for the release speed.
    private var previous: (y: CGFloat, time: TimeInterval)?
    private var latest: (y: CGFloat, time: TimeInterval)?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Screen coordinates: y grows upwards, so a pull up is positive.
    private func travel() -> CGFloat { start.map { NSEvent.mouseLocation.y - $0.y } ?? 0 }

    override func mouseDown(with event: NSEvent) {
        start = NSEvent.mouseLocation
        latest = (NSEvent.mouseLocation.y, event.timestamp)
        previous = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard start != nil else { return }
        previous = latest
        latest = (NSEvent.mouseLocation.y, event.timestamp)
        onDrag(travel())
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        let travel = travel()
        var velocity: CGFloat = 0
        if let previous, let latest, latest.time > previous.time {
            velocity = (latest.y - previous.y) / CGFloat(latest.time - previous.time)
        }
        start = nil; previous = nil; latest = nil
        if abs(travel) < pull { onToggle() } else { onRelease(travel, velocity) }
    }
}
