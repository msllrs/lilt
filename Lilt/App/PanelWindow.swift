import AppKit

/// A narrow, translucent column that lives on the edge of the screen.
///
/// It is an `NSPanel` rather than a plain window on purpose: utility panels are ignored by tiling
/// window managers, and a non-activating panel lets you hit play without pulling focus away from
/// whatever you were working in. Clicking the search field still makes it key for typing.
@MainActor
final class PanelWindow: NSPanel {
    static let autosaveName = "LiltPanel"

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "Lilt"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isFloatingPanel = false
        becomesKeyOnlyIfNeeded = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.managed, .fullScreenAuxiliary]
        standardWindowButton(.zoomButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        minSize = NSSize(width: Theme.Size.panelMinWidth, height: Theme.Size.panelMinHeight)
        maxSize = NSSize(width: Theme.Size.panelMaxWidth, height: .greatestFiniteMagnitude)
    }

    /// Full-height column hugging the right edge of `screen`, inset from the edges.
    static func edgeFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let inset = Theme.Size.screenInset
        let width = Theme.Size.panelWidth
        return NSRect(
            x: visible.maxX - width - inset,
            y: visible.minY + inset,
            width: width,
            height: visible.height - inset * 2
        )
    }
}
