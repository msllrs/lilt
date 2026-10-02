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
        // Any click makes the panel key (still without activating the app), so shortcuts and
        // typing work right after tapping a row or play, not only after clicking the field.
        becomesKeyOnlyIfNeeded = false
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
    /// state the menu bar (and its shortcuts) still belong to the previous app. Handle Lilt's own
    /// shortcuts here so they work straight from the panel.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleShortcut(event) { return }
        super.sendEvent(event)
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard modifiers.contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased(),
              let delegate = AppDelegate.shared else { return false }
        switch (key, modifiers) {
        case ("w", [.command]):
            delegate.hidePanel()
            return true
        case ("m", [.command, .shift]):
            // Plain ⌘M is the system's Minimize.
            delegate.toggleMiniPlayer()
            return true
        case ("l", [.command]):
            delegate.openLibrary()
            return true
        #if DEBUG
        case ("t", [.command, .option]):
            delegate.showTweakPanel()
            return true
        #endif
        default:
            // Everything else (⌘A, ⌘C, ⌘V…) goes to the menu as usual.
            return !NSApp.isActive && NSApp.mainMenu?.performKeyEquivalent(with: event) == true
        }
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
