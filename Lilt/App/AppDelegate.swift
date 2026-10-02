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
    /// Window height (margins included) to return to when leaving mini.
    private var expandedHeight: CGFloat {
        get {
            let saved = UserDefaults.standard.double(forKey: Self.expandedHeightKey)
            return saved > 0 ? saved : PanelWindow.edgeFrame(on: NSScreen.main ?? NSScreen.screens[0]).height
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.expandedHeightKey) }
    }
    private var miniEverApplied = false

    /// The content transition is pure SwiftUI (column fades, glass contracts). The window frame
    /// changes only when nothing visible is affected, and never in the same update as the mode
    /// flip, or SwiftUI animates the layout's height change and the platter rides up the window.
    private func observeMiniPlayer() {
        navigation.miniPlayerDidChange = nil
        // Launch: the saved mode may be mini; size the window for it straight away.
        if navigation.isMiniPlayer { resizeWindow(mini: true) }
        miniEverApplied = true
    }

    /// Entry point for the platter button, menu and shortcut. Deferred one run loop so the mode
    /// change is never in the same SwiftUI transaction as the button's press-release spring,
    /// which would otherwise animate the icon's position change with a bounce.
    func setMiniPlayer(_ mini: Bool) {
        DispatchQueue.main.async { [weak self] in self?.applyMiniPlayerChange(mini) }
    }

    private func applyMiniPlayerChange(_ mini: Bool) {
        guard mini != navigation.isMiniPlayer else { return }
        if mini {
            navigation.isMiniPlayer = true
            // Shrink after the fade: the region being removed is transparent by then.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
                guard let self, self.navigation.isMiniPlayer else { return }
                self.resizeWindow(mini: true)
            }
        } else {
            // Grow first, unanimated; the column fades in on the next run loop.
            resizeWindow(mini: false)
            DispatchQueue.main.async { [weak self] in self?.navigation.isMiniPlayer = false }
        }
    }

    // MARK: Up-next list

    /// Opens or closes the queue below the scrubber. In mini the window is the platter, so it
    /// grows (unanimated, into transparent space above) before the list animates in, and
    /// shrinks only after the list has animated out; expanded, the platter just grows upward.
    func setQueueVisible(_ visible: Bool) {
        guard visible != navigation.isQueueVisible else { return }
        if visible, navigation.isMiniPlayer { resizeWindow(mini: true, queueVisible: true) }
        withAnimation(Theme.Motion.standard) { navigation.isQueueVisible = visible }
        if !visible, navigation.isMiniPlayer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, navigation.isMiniPlayer, !navigation.isQueueVisible else { return }
                resizeWindow(mini: true)
            }
        }
        autoHideQueueIfEmpty()
    }

    /// An empty list only needs a moment to say so; then it folds away on its own.
    private var queueAutoHide: Task<Void, Never>?
    private func autoHideQueueIfEmpty() {
        queueAutoHide?.cancel()
        guard navigation.isQueueVisible, player.upcoming.isEmpty else { return }
        queueAutoHide = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self, navigation.isQueueVisible, player.upcoming.isEmpty else { return }
            setQueueVisible(false)
        }
    }

    /// The queue changed length while showing: in mini, follow it (grow now, shrink after).
    func queueDidChange() {
        autoHideQueueIfEmpty()
        guard navigation.isMiniPlayer, navigation.isQueueVisible, let panel else { return }
        let target = miniHeight(queueVisible: true)
        if target > panel.frame.height {
            resizeWindow(mini: true, queueVisible: true)
        } else if target < panel.frame.height {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, navigation.isMiniPlayer, navigation.isQueueVisible else { return }
                resizeWindow(mini: true, queueVisible: true)
            }
        }
    }

    /// Window height for the mini player: the platter plus its inset and the shadow margin,
    /// using the platter's eventual size rather than whatever it's animating through.
    private func miniHeight(queueVisible: Bool) -> CGFloat {
        let margin = Theme.Size.shadowMargin
        let platter = queueVisible
            ? navigation.platterBaseHeight + Theme.Space.sm + QueueList.height(forCount: player.upcoming.count)
            : navigation.platterHeight
        return platter + Theme.Space.panelInset + margin * 2
    }

    private func resizeWindow(mini: Bool, queueVisible: Bool? = nil) {
        guard let panel else { return }
        let margin = Theme.Size.shadowMargin
        let current = panel.frame
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
        if mini {
            if current.height >= Theme.Size.panelMinHeight + margin * 2 { expandedHeight = current.height }
            // The platter keeps its inset below it, so it doesn't move when the column goes.
            let height = miniHeight(queueVisible: queueVisible ?? navigation.isQueueVisible)
            panel.minSize = NSSize(width: Theme.Size.panelMinWidth + margin * 2, height: height)
            let target = NSRect(x: current.minX, y: current.minY, width: current.width, height: height)
            panel.setFrame(Self.onScreen(target, near: screen), display: true)
        } else {
            panel.minSize = NSSize(width: Theme.Size.panelMinWidth + margin * 2, height: Theme.Size.panelMinHeight + margin * 2)
            let target = NSRect(x: current.minX, y: current.minY, width: current.width, height: expandedHeight)
            panel.setFrame(Self.onScreen(target, near: screen), display: true)
            panel.contentView?.layoutSubtreeIfNeeded()
        }
    }

    // MARK: Manual resize (edge strips drawn inside the visible panel)

    var panelFrame: NSRect { panel?.frame ?? .zero }

    /// Applies a frame from the edge strips, honouring the window's min/max sizes and keeping the
    /// anchored edge fixed when a size is clamped.
    func setPanelFrame(_ proposed: NSRect, clampToSizes: Bool) {
        guard let panel else { return }
        var f = proposed
        if clampToSizes {
            let minW = panel.minSize.width, maxW = panel.maxSize.width
            let minH = panel.minSize.height, maxH = panel.maxSize.height
            if f.width < minW { if f.minX != panel.frame.minX { f.origin.x = panel.frame.maxX - minW }; f.size.width = minW }
            if f.width > maxW { if f.minX != panel.frame.minX { f.origin.x = panel.frame.maxX - maxW }; f.size.width = maxW }
            if f.height < minH { if f.minY != panel.frame.minY { f.origin.y = panel.frame.maxY - minH }; f.size.height = minH }
            if f.height > maxH { if f.minY != panel.frame.minY { f.origin.y = panel.frame.maxY - maxH }; f.size.height = maxH }
        }
        panel.setFrame(f, display: true)
    }

    func panelDidResizeManually() {
        guard let panel, !navigation.isMiniPlayer else { return }
        expandedHeight = panel.frame.height
    }

    /// A manual resize while expanded is the new expanded height.
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel, (notification.object as? NSWindow) === panel, !navigation.isMiniPlayer else { return }
        expandedHeight = panel.frame.height
    }

    func toggleMiniPlayer() { setMiniPlayer(!navigation.isMiniPlayer) }
    func openLibrary() { navigation.open(NavigationModel.library) }

    /// Nudges a window frame so its *visible panel* (the frame minus the shadow margin) lies
    /// within the screen's visible area. The margin itself may hang off screen.
    static func onScreen(_ frame: NSRect, near screen: NSScreen) -> NSRect {
        let margin = Theme.Size.shadowMargin
        let visible = screen.visibleFrame
        var panel = frame.insetBy(dx: margin, dy: margin)
        panel.size.height = min(panel.height, visible.height)
        panel.size.width = min(panel.width, visible.width)
        if panel.maxY > visible.maxY { panel.origin.y = visible.maxY - panel.height }
        if panel.minY < visible.minY { panel.origin.y = visible.minY }
        if panel.maxX > visible.maxX { panel.origin.x = visible.maxX - panel.width }
        if panel.minX < visible.minX { panel.origin.x = visible.minX }
        return panel.insetBy(dx: -margin, dy: -margin)
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
        guard url != dockArtworkURL else { return }
        dockArtworkURL = url
        guard let url else {
            // Nothing playing: the app icon from the bundle, not a redrawn stand-in.
            NSApp.applicationIconImage = nil
            return
        }
        Task { [weak self] in
            // The row thumbnail is 240px; the Dock tile wants more, so ask for a larger rendition
            // of the same cover (Google thumbnails take the size in the URL).
            let large = ImageCache.sized(url, 544)
            var image = await ImageCache.shared.load(large)
            if image == nil { image = await ImageCache.shared.load(url) }
            guard let image, self?.dockArtworkURL == url else { return }
            NSApp.applicationIconImage = DiscIcon.tile(artwork: image, edgeLuminance: ImageCache.shared.edgeLuminance(for: large))
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
        guard let panel else { return }
        // Never show it somewhere you can't see it.
        panel.setFrame(Self.onScreen(panel.frame, near: panel.screen ?? NSScreen.main ?? NSScreen.screens[0]), display: false)
        panel.makeKeyAndOrderFront(nil)
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
