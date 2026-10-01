import AppKit

/// A narrow, translucent column that lives on the edge of the screen.
///
/// Borderless so we own the shape (the system radius on a panel is fixed at 15pt, too tight for
/// concentric inner corners), and a non-activating utility panel so tiling/window managers leave
/// it alone and hitting play doesn't pull focus from whatever you were working in.
@MainActor
final class PanelWindow: NSPanel {
    static let autosaveName = "LiltPanel"

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "Lilt"
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
        minSize = NSSize(width: Theme.Size.panelMinWidth, height: Theme.Size.panelMinHeight)
        maxSize = NSSize(width: Theme.Size.panelMaxWidth, height: .greatestFiniteMagnitude)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// A non-activating panel receives key events without Lilt being the active app, and in that
    /// state AppKit never consults the main menu for ⌘ shortcuts. Do it here so ⌘W, ⌘⇧L and the
    /// debug ⌥⌘T work straight from the panel.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           !NSApp.isActive,
           NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return
        }
        super.sendEvent(event)
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
