import AppKit
import SwiftUI

/// A narrow, translucent column that lives on the edge of the screen.
///
/// Borderless so we own the shape (the system radius on a panel is fixed at 15pt, too tight for
/// concentric inner corners), and a non-activating utility panel so tiling/window managers leave
/// it alone and hitting play doesn't pull focus from whatever you were working in.
@MainActor
final class PanelWindow: NSPanel {
    static let autosaveName = "LiltPanel"

    init(contentRect: NSRect) {
        // A real titled window, so the system supplies the shape, the shadow, the border and
        // resizing. Not a utility panel, whose corners are only 15pt. Still non-activating, so
        // play doesn't steal focus.
        let styleMask: NSWindow.StyleMask = [.titled, .fullSizeContentView, .resizable, .nonactivatingPanel]
        super.init(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false)
        title = "Lilt"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        // macOS 26 gives every titled window a 16pt continuous corner. The shape, clip and shadow
        // all follow the window's private radius, so set ours there; a future OS without the
        // selector just keeps the system corner.
        applyNativeCornerRadius(Theme.Radius.window)
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isFloatingPanel = false
        // Any click makes the panel key (still without activating the app), so shortcuts and
        // typing work right after tapping a row or play, not only after clicking the field.
        becomesKeyOnlyIfNeeded = false
        backgroundColor = .clear
        isOpaque = false
        // The frame clips in-process content to the window's corner; only behind-window blur
        // ignores it, which is why the sidebar material keeps a mask of its own at the same radius.
        hasShadow = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.managed, .fullScreenAuxiliary]
        minSize = NSSize(width: Theme.Size.panelMinWidth, height: Theme.Size.panelMinHeight)
        maxSize = NSSize(width: Theme.Size.panelMaxWidth, height: .greatestFiniteMagnitude)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The panel hides by alpha, so a plain order-front (the Dock menu's window entry, the
    /// Window menu) would bring forward an invisible window. Route it through the real show.
    override func makeKeyAndOrderFront(_ sender: Any?) {
        if let delegate = AppDelegate.shared, delegate.navigation.isPanelHidden {
            delegate.showPanel()
            return
        }
        super.makeKeyAndOrderFront(sender)
    }

    /// The window's corner: the panel radius while expanded, the platter's own in mini, where the
    /// window is the platter. `-[NSWindow _setCornerRadius:]`, reached through its implementation
    /// pointer because the argument is a CGFloat (KVC would box it, `perform` can't pass it).
    func applyNativeCornerRadius(_ radius: CGFloat) {
        // Cutting a running animation short still settles its bookkeeping (unpinning, flags).
        radiusLink?.invalidate(); radiusLink = nil
        let done = frameCompletion; frameCompletion = nil; done?()
        setNativeCornerRadius(radius)
    }

    private var nativeCornerRadius: CGFloat = Theme.Radius.window
    private var radiusLink: CADisplayLink?
    private var radiusFrom: CGFloat = 0, radiusTo: CGFloat = 0, radiusStart: CFTimeInterval = 0, radiusDuration: CFTimeInterval = 0

    private func setNativeCornerRadius(_ radius: CGFloat) {
        typealias Setter = @convention(c) (AnyObject, Selector, CGFloat) -> Void
        let selector = NSSelectorFromString("_setCornerRadius:")
        guard responds(to: selector), let imp = method(for: selector) else { return }
        nativeCornerRadius = radius
        unsafeBitCast(imp, to: Setter.self)(self, selector, radius)
        AppDelegate.shared?.navigation.frameCornerRadius = radius
        SidebarBackground.applyLiveCornerRadius(radius)
    }

    private var frameFrom = NSRect.zero, frameTo = NSRect.zero
    private var frameCompletion: (() -> Void)?
    private var frameCurve = Theme.Motion.frameCurve

    /// Springs the frame and the corner together from their current values, one display link
    /// driving both, so every refresh gets exactly one step of each. (NSWindow's own animator
    /// ticks on a timer that isn't locked to the display, which showed as uneven steps.) The
    /// platter's inset shrinks by the same amount the radius does, so corners stay concentric.
    func animateNativeFrame(to frame: NSRect, cornerRadius radius: CGFloat, curve: FrameCurve, completion: @escaping () -> Void) {
        radiusLink?.invalidate()
        frameFrom = self.frame; frameTo = frame
        radiusFrom = nativeCornerRadius; radiusTo = radius
        frameCurve = curve
        radiusStart = CACurrentMediaTime(); radiusDuration = curve.duration
        frameCompletion = completion
        let link = displayLink(target: self, selector: #selector(stepFrame(_:)))
        link.add(to: .main, forMode: .common)
        radiusLink = link
    }

    @objc private func stepFrame(_ link: CADisplayLink) {
        // Aim at the moment this step will be shown, not the moment it's computed.
        let elapsed = link.targetTimestamp - radiusStart
        let t = min(max(elapsed / radiusDuration, 0), 1)
        // The content's own curve, so the window and what it reveals move as one.
        let eased: Double = t >= 1 ? 1 : frameCurve.value(at: elapsed)
        let f = NSRect(
            x: frameFrom.minX + (frameTo.minX - frameFrom.minX) * eased,
            y: frameFrom.minY + (frameTo.minY - frameFrom.minY) * eased,
            width: frameFrom.width + (frameTo.width - frameFrom.width) * eased,
            height: frameFrom.height + (frameTo.height - frameFrom.height) * eased
        )
        setNativeCornerRadius(radiusFrom + (radiusTo - radiusFrom) * eased)
        // Just move the frame; the display cycle draws it once per refresh. Forcing a synchronous
        // display here cost 8-15ms a tick and skipped refreshes unevenly.
        setFrame(t >= 1 ? frameTo : f, display: false)
        if t >= 1 {
            link.invalidate(); radiusLink = nil
            let done = frameCompletion; frameCompletion = nil; done?()
        }
    }

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
        case ("r", [.command]):
            delegate.refresh()
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
