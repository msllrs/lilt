import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// For views that need a cache peek before their environment is available (initialisers).
    /// Set explicitly: under the SwiftUI app lifecycle `NSApp.delegate` is SwiftUI's wrapper, not us.
    private(set) static weak var shared: AppDelegate?

    let auth = AuthService()
    private(set) lazy var player = PlayerService(auth: auth)
    private(set) lazy var music = YTMusicClient(auth: auth)
    let navigation = NavigationModel()
    let scrollTracker = ScrollTracker()
    let recents = RecentsStore()
    let collapsedSections = CollapsedSections()

    private var panel: PanelWindow?
    private var loginWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.regular)
        player.linkResolver = { [music] videoId in try await music.links(forVideoId: videoId) }
        player.recents = recents
        navigation.recents = recents
        makePanel()
        showPanel()
        observeLoginPresentation()
        observeDockIcon()
        observeMiniPlayer()
        refreshShadowAfterTransition()
        Task {
            await auth.refresh()
            if !auth.isSignedIn { auth.isPresentingLogin = true }
        }
        observeSignIn()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        player.persistNow()
    }

    // MARK: Mini player

    /// Mini mode is purely a content change; the window keeps its frame so nothing re-lays out
    /// under a live resize. The shadow follows the drawn shape, so it must be recomputed.
    private func observeMiniPlayer() {
        withObservationTracking {
            _ = navigation.isMiniPlayer
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshShadowAfterTransition()
                self?.observeMiniPlayer()
            }
        }
    }

    /// The window shadow is computed from the drawn pixels and cached, so it must be recomputed
    /// after the content changes shape: during and after the mini transition, and once the first
    /// layout has settled at launch.
    private func refreshShadowAfterTransition() {
        guard let panel else { return }
        for delay in [0.1, 0.3, 0.5, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { panel.invalidateShadow() }
        }
    }

    func toggleMiniPlayer() { navigation.isMiniPlayer.toggle() }
    func openLibrary() { navigation.open(NavigationModel.library) }

    /// Nudges a frame so it lies within the screen's visible area.
    static func onScreen(_ frame: NSRect, near screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        var f = frame
        f.size.height = min(f.height, visible.height)
        f.size.width = min(f.width, visible.width)
        if f.maxY > visible.maxY { f.origin.y = visible.maxY - f.height }
        if f.minY < visible.minY { f.origin.y = visible.minY }
        if f.maxX > visible.maxX { f.origin.x = visible.maxX - f.width }
        if f.minX < visible.minX { f.origin.x = visible.minX }
        return f
    }


    // MARK: Dock

    /// Right-click menu on the Dock tile: what's playing, transport, and show.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        if let track = player.current {
            let title = NSMenuItem(title: "\(track.title) — \(track.artist)", action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            menu.addItem(.separator())
            menu.addItem(withTitle: player.isPlaying ? "Pause" : "Play", action: #selector(dockTogglePlayPause), keyEquivalent: "")
            let next = menu.addItem(withTitle: "Next", action: #selector(dockNext), keyEquivalent: "")
            next.isEnabled = player.hasNext
            menu.addItem(withTitle: "Previous", action: #selector(dockPrevious), keyEquivalent: "")
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Show Lilt", action: #selector(dockShow), keyEquivalent: "")
        return menu
    }

    @objc private func dockTogglePlayPause() { player.togglePlayPause() }
    @objc private func dockNext() { player.next() }
    @objc private func dockPrevious() { player.previous() }
    @objc private func dockShow() { showPanel() }

    /// The Dock tile is a disc: generic when idle, the current cover when a track is loaded.
    private var dockArtworkURL: URL?

    private func observeDockIcon() {
        withObservationTracking {
            _ = player.current?.artworkURL
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateDockIcon()
                self?.observeDockIcon()
            }
        }
        updateDockIcon()
    }

    private func updateDockIcon() {
        let url = player.current?.artworkURL
        guard url != dockArtworkURL || NSApp.applicationIconImage == nil else { return }
        dockArtworkURL = url
        guard let url else {
            NSApp.applicationIconImage = DiscIcon.genericTile()
            return
        }
        Task { [weak self] in
            guard let image = await ImageCache.shared.load(url), self?.dockArtworkURL == url else { return }
            NSApp.applicationIconImage = DiscIcon.tile(artwork: image)
        }
    }

    /// A borderless non-activating panel doesn't become key on its own; when the user brings the
    /// app forward (Dock, ⌘-Tab, shortcut) they expect to type straight away.
    func applicationDidBecomeActive(_ notification: Notification) {
        guard let panel, panel.isVisible, loginWindow == nil else { return }
        panel.makeKey()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    /// The panel hides instead of closing so the hidden web view keeps playing.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === panel else { return true }
        sender.orderOut(nil)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === loginWindow else { return }
        loginWindow = nil
        auth.isPresentingLogin = false
    }

    private func observeSignIn() {
        withObservationTracking {
            _ = auth.isSignedIn
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.syncWarmUp()
                self?.observeSignIn()
            }
        }
        syncWarmUp()
    }

    private func syncWarmUp() {
        if auth.isSignedIn { player.warmUp() }
    }

    // MARK: Login window

    private func observeLoginPresentation() {
        withObservationTracking {
            _ = auth.isPresentingLogin
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.syncLoginWindow()
                self?.observeLoginPresentation()
            }
        }
        syncLoginWindow()
    }

    private func syncLoginWindow() {
        if auth.isPresentingLogin {
            if loginWindow == nil { makeLoginWindow() }
            loginWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else if let window = loginWindow {
            loginWindow = nil
            window.delegate = nil
            window.close()
        }
    }

    private func makeLoginWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 680),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to YouTube Music"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LoginView().environment(auth))
        window.center()
        window.delegate = self
        loginWindow = window
    }

    func showPanel() {
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makePanel() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let window = PanelWindow(contentRect: PanelWindow.edgeFrame(on: screen))
        window.delegate = self

        let root = RootView()
            .environment(auth)
            .environment(player)
            .environment(music)
            .environment(navigation)
            .environment(scrollTracker)
            .environment(recents)
            .environment(collapsedSections)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []

        let container = NSView(frame: window.contentLayoutRect)
        container.autoresizingMask = [.width, .height]

        // The audio engine lives in a 1x1 web view underneath the SwiftUI content. It must stay
        // in a window to keep playing, which is why the panel hides rather than closes.
        // Tucked well inside the rounded glass; at the corner it peeks out as a dot because the
        // borderless window is transparent there.
        let webView = player.bridge.webView
        webView.frame = NSRect(x: Theme.Size.shadowMargin + Theme.Radius.window, y: Theme.Size.shadowMargin + Theme.Radius.window, width: 1, height: 1)
        container.addSubview(webView)

        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        window.contentView = container
        if !window.setFrameUsingName(PanelWindow.autosaveName) {
            window.setFrame(PanelWindow.edgeFrame(on: screen), display: false)
        }
        // A saved frame can end up off screen (display changes, a mini-player relaunch); never
        // start hidden.
        window.setFrame(Self.onScreen(window.frame, near: window.screen ?? screen), display: false)
        window.setFrameAutosaveName(PanelWindow.autosaveName)
        panel = window
    }

    /// No close button on the panel; ⌘W hides it and playback carries on.
    func hidePanel() {
        panel?.orderOut(nil)
    }

    #if DEBUG
    private var tweakWindow: NSPanel?

    /// Floating sliders for tuning the artwork finish while the app runs.
    func showTweakPanel() {
        if tweakWindow == nil {
            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 860),
                styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.title = "Tweak Artwork"
            window.isReleasedWhenClosed = false
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.contentView = NSHostingView(rootView: TweakPanel().environment(scrollTracker))
            if let panelFrame = panel?.frame {
                window.setFrameTopLeftPoint(NSPoint(x: panelFrame.minX - 360 - Theme.Size.screenInset, y: panelFrame.maxY))
            } else {
                window.center()
            }
            tweakWindow = window
        }
        tweakWindow?.makeKeyAndOrderFront(nil)
    }
    #endif
}
