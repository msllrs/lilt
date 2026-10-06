import AppKit
import SwiftUI

/// The hit area of a sheet-style grab handle. An AppKit view rather than a SwiftUI gesture:
/// the window moves by its background, and AppKit decides that by asking the view under the
/// pointer, which for SwiftUI content is the hosting view, which says yes. This view says no
/// and handles the click and the pull itself (as ResizeEdges does for the window edges).
struct GrabHandle: NSViewRepresentable {
    /// A click, or a pull shorter than `pull`.
    var onToggle: () -> Void
    /// A pull of at least `pull` points: true when upwards.
    var onPull: (_ up: Bool) -> Void
    var pull: CGFloat = 12
    var toolTip: String?

    func makeNSView(context: Context) -> GrabHandleView { GrabHandleView() }

    func updateNSView(_ view: GrabHandleView, context: Context) {
        view.onToggle = onToggle
        view.onPull = onPull
        view.pull = pull
        view.toolTip = toolTip
    }
}

final class GrabHandleView: NSView {
    var onToggle: () -> Void = {}
    var onPull: (Bool) -> Void = { _ in }
    var pull: CGFloat = 12
    private var start: NSPoint?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        start = NSEvent.mouseLocation
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        self.start = nil
        // Screen coordinates: y grows upwards.
        let travel = NSEvent.mouseLocation.y - start.y
        if abs(travel) < pull { onToggle() } else { onPull(travel > 0) }
    }
}
