import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// For views that need a cache peek before their environment is available (initialisers).
    static var shared: AppDelegate? { NSApp.delegate as? AppDelegate }

    let auth = AuthService()
    private(set) lazy var player = PlayerService(auth: auth)
    private(set) lazy var music = YTMusicClient(auth: auth)
    let navigation = NavigationModel()
    let scrollTracker = ScrollTracker()
    let recents = RecentsStore()

    private var panel: PanelWindow?
    private var loginWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        player.linkResolver = { [music] videoId in try await music.links(forVideoId: videoId) }
        player.recents = recents
        navigation.recents = recents
        makePanel()
        showPanel()
        observeLoginPresentation()
        observeDockIcon()
        observeMiniPlayer()
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

    private static let expandedHeightKey = "expandedPanelHeight"
    private var isMiniApplied: Bool?
    private var appliedPlatterHeight: CGFloat = 0

    /// The column's height when not collapsed, kept separately so a relaunch in mini mode can
    /// never make the small frame the thing we "restore" to.
    private var expandedHeight: CGFloat {
        get {
            let saved = UserDefaults.standard.double(forKey: Self.expandedHeightKey)
            return saved >= Theme.Size.panelMinHeight ? saved : PanelWindow.edgeFrame(on: NSScreen.main ?? NSScreen.screens[0]).height
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.expandedHeightKey) }
    }

    private func observeMiniPlayer() {
        withObservationTracking {
            _ = navigation.isMiniPlayer
            _ = navigation.platterHeight
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyMiniPlayer()
                self?.observeMiniPlayer()
            }
        }
        applyMiniPlayer()
    }

    /// Shrinks the window to the platter (keeping its bottom edge where it is) or restores it,
    /// always landing fully on screen.
    private func applyMiniPlayer() {
        guard let panel else { return }
        let mini = navigation.isMiniPlayer
        // Re-run when entering/leaving mini, or when the platter's measured height changes while mini.
        guard mini != isMiniApplied || (mini && navigation.platterHeight != appliedPlatterHeight) else { return }
        let current = panel.frame
        if mini, isMiniApplied == false, current.height >= Theme.Size.panelMinHeight {
            expandedHeight = current.height
        }
        isMiniApplied = mini
        appliedPlatterHeight = navigation.platterHeight

        let height = mini ? navigation.platterHeight : expandedHeight
        panel.minSize = NSSize(width: Theme.Size.panelMinWidth, height: mini ? height : Theme.Size.panelMinHeight)
        var target = NSRect(x: current.minX, y: current.minY, width: current.width, height: height)
        target = Self.onScreen(target, near: panel.screen ?? NSScreen.main ?? NSScreen.screens[0])
        #if DEBUG
        NSLog("Lilt mini=%d platter=%.0f expanded=%.0f %@ -> %@", mini ? 1 : 0, navigation.platterHeight, expandedHeight, NSStringFromRect(current), NSStringFromRect(target))
        #endif
        panel.setFrame(target, display: true, animate: panel.isVisible)
    }

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

    func toggleMiniPlayer() { navigation.isMiniPlayer.toggle() }
    func openLibrary() { navigation.open(NavigationModel.library) }

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
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []

        let container = NSView(frame: window.contentLayoutRect)
        container.autoresizingMask = [.width, .height]

        // The audio engine lives in a 1x1 web view underneath the SwiftUI content. It must stay
        // in a window to keep playing, which is why the panel hides rather than closes.
        // Tucked well inside the rounded glass; at the corner it peeks out as a dot because the
        // borderless window is transparent there.
        let webView = player.bridge.webView
        webView.frame = NSRect(x: Theme.Radius.window, y: Theme.Radius.window, width: 1, height: 1)
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
