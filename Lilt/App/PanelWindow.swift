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
        #if NATIVE_FRAME
        // The experiment: a real titled window, so the system supplies the shape (27.5pt corners
        // on macOS 26, a hair under ours), the shadow, the border and resizing. Not a utility
        // panel, whose corners are only 15pt. Still non-activating, so play doesn't steal focus.
        let styleMask: NSWindow.StyleMask = [.titled, .fullSizeContentView, .resizable, .nonactivatingPanel]
        #else
        let styleMask: NSWindow.StyleMask = [.borderless, .resizable, .utilityWindow, .nonactivatingPanel]
        #endif
        super.init(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false)
        title = "Lilt"
        #if NATIVE_FRAME
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        #endif
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isFloatingPanel = false
        // Any click makes the panel key (still without activating the app), so shortcuts and
        // typing work right after tapping a row or play, not only after clicking the field.
        becomesKeyOnlyIfNeeded = false
        backgroundColor = .clear
        isOpaque = false
        #if NATIVE_FRAME
        hasShadow = true
        #else
        hasShadow = false
        #endif
        animationBehavior = .utilityWindow
        collectionBehavior = [.managed, .fullScreenAuxiliary]
        let margin = Theme.Size.shadowMargin * 2
        minSize = NSSize(width: Theme.Size.panelMinWidth + margin, height: Theme.Size.panelMinHeight + margin)
        maxSize = NSSize(width: Theme.Size.panelMaxWidth + margin, height: .greatestFiniteMagnitude)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The frame includes a transparent shadow margin that may hang off the screen, but the
    /// visible panel inside it must stay on screen. AppKit's default would push the whole frame
    /// inward (wrong gap); no constraint at all let the window drift off entirely.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let screen = screen ?? self.screen ?? NSScreen.main else { return frameRect }
        return AppDelegate.onScreen(frameRect, near: screen)
    }

    /// A non-activating panel receives key events without Lilt being the active app, and in that
    /// state the menu bar (and its shortcuts) still belong to the previous app. Handle Lilt's own
    /// shortcuts here so they work straight from the panel.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleShortcut(event) { return }
        if event.type == .leftMouseDown { endEditingIfClickedAway(event) }
        super.sendEvent(event)
    }

    /// AppKit leaves a text field focused when you click somewhere inert. Here a click anywhere
    /// outside the field ends editing, so the caret goes away and Space goes back to playback.
    private func endEditingIfClickedAway(_ event: NSEvent) {
        guard let editor = firstResponder as? NSTextView,
              let hit = contentView?.hitTest(event.locationInWindow) else { return }
        let field = editor.delegate as? NSView
        let inside = hit === editor || hit.isDescendant(of: editor) || (field.map { hit === $0 || hit.isDescendant(of: $0) } ?? false)
        if !inside { makeFirstResponder(nil) }
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard let delegate = AppDelegate.shared else { return false }
        // Transport keys. Space only when nothing is taking text (the search field is first
        // responder while you type into it); the arrows need ⌘ so lists keep theirs.
        let isTyping = firstResponder is NSTextView
        switch (event.keyCode, modifiers) {
        case (49, []) where !isTyping: // Space
            delegate.player.togglePlayPause()
            return true
        case (124, [.command]): // →
            delegate.player.next()
            return true
        case (123, [.command]): // ←
            delegate.player.previous()
            return true
        default:
            break
        }
        guard modifiers.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch (key, modifiers) {
        case ("s", [.command, .shift]):
            delegate.player.toggleShuffle()
            return true
        case ("r", [.command, .shift]):
            delegate.player.cycleRepeat()
            return true
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
        // The window frame includes the shadow margin; the visible panel keeps `screenInset`.
        let visible = screen.visibleFrame
        let inset = Theme.Size.screenInset - Theme.Size.shadowMargin
        let width = Theme.Size.panelWidth + Theme.Size.shadowMargin * 2
        return NSRect(
            x: visible.maxX - width - inset,
            y: visible.minY + inset,
            width: width,
            height: visible.height - inset * 2
        )
    }
}
