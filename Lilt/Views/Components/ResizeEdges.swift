import AppKit
import SwiftUI

/// Invisible strips along the visible panel's edges that behave like a window's resize borders:
/// resize cursors on hover, and dragging changes the window frame. Needed because the real
/// window frame extends into a transparent shadow margin that passes clicks through.
struct ResizeEdges: View {
    private let thickness: CGFloat = 7

    var body: some View {
        ZStack {
            ResizeStrip(side: .trailing).frame(width: thickness).frame(maxWidth: .infinity, alignment: .trailing)
            ResizeStrip(side: .leading).frame(width: thickness).frame(maxWidth: .infinity, alignment: .leading)
            ResizeStrip(side: .bottom).frame(height: thickness).frame(maxHeight: .infinity, alignment: .bottom)
            ResizeStrip(side: .top).frame(height: thickness).frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// AppKit does the tracking: cursor rects and mouse drags are reliable here where SwiftUI's
/// hover/gesture on a non-activating panel are not.
private struct ResizeStrip: NSViewRepresentable {
    let side: Edge

    func makeNSView(context: Context) -> ResizeStripView { ResizeStripView(side: side) }
    func updateNSView(_ view: ResizeStripView, context: Context) { view.side = side }
}

final class ResizeStripView: NSView {
    var side: Edge
    private var startFrame: NSRect?
    private var startMouse: NSPoint?

    init(side: Edge) {
        self.side = side
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Dragging here must resize, not move the window.
    override var mouseDownCanMoveWindow: Bool { false }

    /// The window-edge cursor macOS itself uses on resizable borders, not the column splitter.
    private var cursor: NSCursor {
        switch side {
        case .leading: .frameResize(position: .left, directions: .all)
        case .trailing: .frameResize(position: .right, directions: .all)
        case .top: .frameResize(position: .top, directions: .all)
        case .bottom: .frameResize(position: .bottom, directions: .all)
        }
    }

    /// A tracking area rather than cursor rects: those only update for the key window, and this
    /// panel rarely is.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }

    override func mouseExited(with event: NSEvent) {
        if startFrame == nil { NSCursor.arrow.set() }
    }

    override func mouseDown(with event: NSEvent) {
        startFrame = window?.frame
        startMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startFrame, let startMouse, let delegate = AppDelegate.shared else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - startMouse.x, dy = now.y - startMouse.y
        var f = startFrame
        switch side {
        case .trailing: f.size.width += dx
        case .leading: f.origin.x += dx; f.size.width -= dx
        case .bottom: f.origin.y += dy; f.size.height -= dy
        case .top: f.size.height += dy
        }
        delegate.setPanelFrame(f, clampToSizes: true)
    }

    override func mouseUp(with event: NSEvent) {
        startFrame = nil
        startMouse = nil
        AppDelegate.shared?.panelDidResizeManually()
    }
}
