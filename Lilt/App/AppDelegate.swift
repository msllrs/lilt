import AppKit
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// For views that need a cache peek before their environment is available (initialisers).
    /// Set explicitly: under the SwiftUI app lifecycle `NSApp.delegate` is SwiftUI's wrapper, not us.
    private(set) static weak var shared: AppDelegate?

    let auth = AuthService()
    private(set) lazy var player = PlayerService(auth: auth)
    private(set) lazy var music = YTMusicClient(auth: auth)
    private var remoteCommands: RemoteCommandBridge?
    let navigation = NavigationModel()
    let scrollTracker = ScrollTracker()
    let recents = RecentsStore()
    /// Sparkle: checks the feed on its own schedule and on request from the menu.
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    let collapsedSections = CollapsedSections()
    let ambience = AmbienceService()

    private var panel: PanelWindow?
    private var loginWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.regular)
        player.linkResolver = { [music] videoId in try await music.links(forVideoId: videoId) }
        player.onLikeToggled = { [music] track, liked in music.noteLiked(liked, track: track) }
        player.recents = recents
        navigation.recents = recents
        if let url = player.displayArtworkURL { ImageCache.shared.restoreForLaunch(url) }
        makePanel()
        showPanel()
        revealOnceArtworkIsWarm()
        observeArtworkForLaunch()
        observeLoginPresentation()
        observeDockIcon()
        observeDockSpin()
        observeCurrentForDockMenu()
        observeWindowTitle()
        observeQueue()
        remoteCommands = RemoteCommandBridge(player: player)
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
        // The window is the container: its frame animates alongside the fade and the system
        // shadow follows it, instead of outlining an empty window until a later resize.
        navigation.isMiniPlayer = mini
        resizeWindow(mini: mini, animated: true)
    }

    // MARK: Up-next list

    /// Opens or closes the queue below the scrubber. In mini the window is the platter, so it
    /// and the list ride one spring; expanded, the platter just grows upward.
    func setQueueVisible(_ visible: Bool) {
        guard visible != navigation.isQueueVisible else { return }
        // The window is the platter: it and the list ride one spring, either way.
        if navigation.isMiniPlayer { resizeWindow(mini: true, queueReveal: visible ? 1 : 0, animated: true, curve: Theme.Motion.queueCurve) }
        withAnimation(.spring(Theme.Motion.queueSpring)) {
            navigation.isQueueVisible = visible
            navigation.queueReveal = visible ? 1 : 0
        }
        autoHideQueueIfEmpty()
    }

    /// What the platter grows by to show the whole list.
    private var queueExtent: CGFloat {
        QueueList.extent(manual: player.upcoming.count, automatic: player.automaticUpcoming.count)
    }

    /// Where a pull of `travel` points (up positive) from the settled state leaves the reveal.
    private func queueReveal(afterPull travel: CGFloat) -> CGFloat {
        let base: CGFloat = navigation.isQueueVisible ? 1 : 0
        return min(max(base + travel / queueExtent, 0), 1)
    }

    /// The grab handle is being pulled: the list follows the pointer, and in mini so does the
    /// window, with nothing animated in between.
    func dragQueue(by travel: CGFloat) {
        queueAutoHide?.cancel()
        let reveal = queueReveal(afterPull: travel)
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { navigation.queueReveal = reveal }
        if navigation.isMiniPlayer { resizeWindow(mini: true, queueReveal: reveal) }
    }

    /// The grab handle was let go: a flick decides by its direction, anything slower by which end
    /// is nearer; the list springs there.
    func settleQueue(travel: CGFloat, velocity: CGFloat) {
        let reveal = queueReveal(afterPull: travel)
        let open = abs(velocity) > 300 ? velocity > 0 : reveal > 0.5
        if open != navigation.isQueueVisible {
            setQueueVisible(open)
            return
        }
        // Back to where it was.
        if navigation.isMiniPlayer { resizeWindow(mini: true, queueReveal: open ? 1 : 0, animated: true, curve: Theme.Motion.queueCurve) }
        withAnimation(.spring(Theme.Motion.queueSpring)) { navigation.queueReveal = open ? 1 : 0 }
        autoHideQueueIfEmpty()
    }

    /// An empty list only needs a moment to say so; then it folds away on its own.
    private var queueAutoHide: Task<Void, Never>?
    private func autoHideQueueIfEmpty() {
        queueAutoHide?.cancel()
        guard navigation.isQueueVisible, player.upcoming.isEmpty, player.automaticUpcoming.isEmpty else { return }
        queueAutoHide = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self, navigation.isQueueVisible, player.upcoming.isEmpty, player.automaticUpcoming.isEmpty else { return }
            setQueueVisible(false)
        }
    }

    /// Watches the hand-queued segment itself, so the list also reacts when playback consumes
    /// it (the last queued track starting empties it, and the list folds away after a moment).
    private func observeQueue() {
        withObservationTracking {
            _ = player.manualCount
            _ = player.currentIndex
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.queueDidChange()
                self?.observeQueue()
            }
        }
    }

    /// The queue changed length while showing: in mini, the window follows it.
    func queueDidChange() {
        autoHideQueueIfEmpty()
        guard navigation.isMiniPlayer, navigation.isQueueVisible, let panel else { return }
        let target = miniHeight(reveal: 1)
        if target != panel.frame.height { resizeWindow(mini: true, queueReveal: 1, animated: true, curve: Theme.Motion.queueCurve) }
    }

    /// Window height for the mini player: the platter with the list shown as far as `reveal`
    /// says. Built from the platter's base height and the list's known extent rather than the
    /// measured height, which mid-animation is whatever it's passing through. The window is the
    /// platter: no inset below it, or the frame's shadow outlines a strip.
    private func miniHeight(reveal: CGFloat) -> CGFloat {
        navigation.platterBaseHeight + ambienceExtent + reveal * queueExtent
    }

    /// What the platter grows by to show the ambience drawer.
    private var ambienceExtent: CGFloat { navigation.isAmbienceVisible ? Theme.Space.sm + AmbiencePanel.height : 0 }

    /// Opens or closes the ambience drawer below the scrubber; in mini the window grows with it
    /// on the same spring as the list.
    func setAmbienceVisible(_ visible: Bool) {
        guard visible != navigation.isAmbienceVisible else { return }
        navigation.isAmbienceVisible = visible
        if navigation.isMiniPlayer { resizeWindow(mini: true, animated: true, curve: Theme.Motion.queueCurve) }
    }

    private func resizeWindow(mini: Bool, queueReveal: CGFloat? = nil, animated: Bool = false, curve: FrameCurve = Theme.Motion.frameCurve) {
        guard let panel else { return }
        let current = panel.frame
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let miniMin = NSSize(width: Theme.Size.panelMinWidth, height: 1)
        let fullMin = NSSize(width: Theme.Size.panelMinWidth, height: Theme.Size.panelMinHeight)
        // The expanded height is remembered when collapsing from a settled window, never from a
        // frame caught mid-animation (a collapse started during an expand would record a
        // half-grown height and the next expand would stop there).
        if mini, !navigation.isFrameAnimating, current.height >= Theme.Size.panelMinHeight { expandedHeight = current.height }
        let height = mini ? miniHeight(reveal: queueReveal ?? (navigation.isQueueVisible ? 1 : 0)) : expandedHeight
        let target = Self.onScreen(NSRect(x: current.minX, y: current.minY, width: current.width, height: height), near: screen)
        let cornerRadius = mini ? Theme.Radius.panel : Theme.Radius.window
        navigation.expandedFrameHeight = expandedHeight
        // The layout the window reveals: the expanded one, hanging from the bottom.
        pinHosting(height: max(current.height, target.height, expandedHeight))
        if animated {
            // Loosen the minimum first (setting a larger one would snap the frame), and tighten it
            // once the frame has arrived. The corner eases between the two radii on the same curve.
            panel.minSize = miniMin
            navigation.isFrameAnimating = true
            panel.animateNativeFrame(to: target, cornerRadius: cornerRadius, curve: curve) { [weak self] in
                guard let self else { return }
                panel.minSize = mini ? NSSize(width: miniMin.width, height: target.height) : fullMin
                lockNativeHeight(mini ? target.height : nil)
                if !mini { unpinHosting() }
                navigation.isFrameAnimating = false
            }
            return
        }
        panel.applyNativeCornerRadius(cornerRadius)
        lockNativeHeight(mini ? height : nil)
        if !mini { unpinHosting() }
        if mini {
            panel.minSize = NSSize(width: miniMin.width, height: height)
            panel.setFrame(target, display: true)
        } else {
            panel.minSize = fullMin
            panel.setFrame(target, display: true)
            panel.contentView?.layoutSubtreeIfNeeded()
        }
    }

    // MARK: Manual resize (edge strips drawn inside the visible panel)

    var panelFrame: NSRect { panel?.frame ?? .zero }
    private var panelHosting: NSView?

    /// Native frame: while the window animates between the column and the platter (and all
    /// through mini), the hosting view keeps the expanded height and hangs from the window's
    /// bottom edge, so the window reveals or hides a layout that never changes. Resizing it with
    /// the window laid the content out a frame late and the bottom-anchored platter twitched.
    private func pinHosting(height: CGFloat) {
        guard let hosting = panelHosting, let container = hosting.superview else { return }
        hosting.autoresizingMask = [.width, .maxYMargin]
        hosting.frame = NSRect(x: 0, y: 0, width: container.bounds.width, height: height)
    }

    /// In mini the window is the platter: the system resize must not be able to make it taller
    /// (that only shows empty material above the platter). Expanded, the height is free again.
    private func lockNativeHeight(_ height: CGFloat?) {
        guard let panel else { return }
        panel.maxSize = NSSize(width: Theme.Size.panelMaxWidth, height: height ?? .greatestFiniteMagnitude)
    }

    private func unpinHosting() {
        guard let hosting = panelHosting, let container = hosting.superview else { return }
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = container.bounds
    }

    /// A manual resize while expanded is the new expanded height.
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel, (notification.object as? NSWindow) === panel, !navigation.isMiniPlayer else { return }
        expandedHeight = panel.frame.height
    }

    /// Signs out of YouTube Music: playback stops, the web session and everything cached for
    /// the account go, and the login window comes up for the next one.
    func signOut() {
        Task { @MainActor in
            player.stop()
            await auth.signOut()
            music.signedOut()
            recents.clear()
            auth.isPresentingLogin = true
        }
    }

    func toggleMiniPlayer() { setMiniPlayer(!navigation.isMiniPlayer) }
    func openLibrary() { navigation.open(NavigationModel.library) }
    /// Fetches the screen on top again (⌘R).
    func refresh() { navigation.refresh() }

    /// Nudges a window frame so it lies within the screen's visible area.
    static func onScreen(_ frame: NSRect, near screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        var panel = frame
        panel.size.height = min(panel.height, visible.height)
        panel.size.width = min(panel.width, visible.width)
        if panel.maxY > visible.maxY { panel.origin.y = visible.maxY - panel.height }
        if panel.minY < visible.minY { panel.origin.y = visible.minY }
        if panel.maxX > visible.maxX { panel.origin.x = visible.maxX - panel.width }
        if panel.minX < visible.minX { panel.origin.x = visible.minX }
        return panel
    }


    // MARK: Dock

    /// Right-click menu on the Dock tile: what's playing, transport, and show.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        DockMenu.build(player: player, music: music, recents: recents, actions: DockMenu.Actions(
            open: { [weak self] item in
                guard let self else { return }
                showPanel()
                RowMenu.open(item, navigation: navigation)
            },
            show: { [weak self] in self?.showPanel() }
        ))
    }

    /// The Dock menu can't wait for anything once it's open, so what it offers for a song is
    /// fetched as the song starts: your playlists and the song's album and artist.
    private func observeCurrentForDockMenu() {
        withObservationTracking {
            _ = player.current?.id
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeCurrentForDockMenu()
            }
        }
        guard let track = player.current else { return }
        music.warmOwnPlaylists(videoId: track.id)
        music.warmLinks(for: track)
    }

    /// The Dock tile is a disc: generic when idle, the current cover when a track is loaded.
    private var dockArtworkURL: URL?
    private var dockTileStyle: DockTileStyle?
    private let dockSpinner = DockSpinner()

    private func observeDockSpin() {
        withObservationTracking {
            _ = player.isPlaying
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeDockSpin()
            }
        }
        dockSpinner.setPlaying(player.isPlaying)
    }

    private func observeDockIcon() {
        withObservationTracking {
            _ = player.current?.artworkURL
            _ = ArtworkStyle.shared.dockTile
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateDockIcon()
                self?.observeDockIcon()
            }
        }
        updateDockIcon()
    }

    /// The panel's title is the loaded track, as the Dock tile is its cover: that is what
    /// Mission Control, the Window menu and the Dock menu's window list call the panel. The Dock
    /// tile's own hover label is the bundle name, fixed when the app registers (a LaunchServices
    /// rename changes `lsappinfo` but not the tile); the track lives in the tile's menu instead.
    private func observeWindowTitle() {
        withObservationTracking {
            _ = player.current?.title
            _ = player.current?.artist
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeWindowTitle()
            }
        }
        panel?.title = TrackLabel.text(for: player.current) ?? "Lilt"
    }

    private func updateDockIcon() {
        let url = player.current?.artworkURL
        let style = ArtworkStyle.shared.dockTile
        guard url != dockArtworkURL || style != dockTileStyle else { return }
        dockArtworkURL = url
        dockTileStyle = style
        guard let url else {
            // Nothing playing: the app icon from the bundle, not a redrawn stand-in.
            dockSpinner.clear()
            NSApp.applicationIconImage = nil
            return
        }
        Task { [weak self] in
            // The row thumbnail is 240px; the Dock tile wants more, so ask for a larger rendition
            // of the same cover (Google thumbnails take the size in the URL).
            let large = ImageCache.sized(url, 544)
            var image = await ImageCache.shared.load(large, maxPixels: 512)
            if image == nil { image = await ImageCache.shared.load(url) }
            guard let image, self?.dockArtworkURL == url else { return }
            let accent = (ImageCache.shared.accent(for: large, saturationBoost: 1) ?? ImageCache.shared.tint(for: large, saturationBoost: 1)).map { NSColor($0) }
            let edgeLuminance = ImageCache.shared.edgeLuminance(for: large)
            guard DockSpinner.framesPerSecond > 0 else {
                self?.dockSpinner.clear()
                NSApp.applicationIconImage = DiscIcon.tile(artwork: image, edgeLuminance: edgeLuminance, accent: accent)
                return
            }
            self?.dockSpinner.show { angle in
                DiscIcon.tile(artwork: image, edgeLuminance: edgeLuminance, accent: accent, side: 128, scale: 2, angle: angle)
            }
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
        navigation.isPanelHidden = false
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
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
            .environment(ambience)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panelHosting = hosting
        // The hidden title bar still counts as a safe area; the column fills the whole window.
        hosting.safeAreaRegions = []

        let container = NSView(frame: window.contentLayoutRect)
        container.autoresizingMask = [.width, .height]

        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        // The audio engine lives in 1x1 web views underneath the SwiftUI content (a second one
        // holds the next song for gapless playback). They must stay in a window to keep playing,
        // which is why the panel hides rather than closes.
        // Tucked well inside the rounded glass; at the corner one peeks out as a dot because the
        // borderless window is transparent there.
        player.hostWebView = { [weak container] webView in
            webView.frame = NSRect(x: Theme.Radius.window, y: Theme.Radius.window, width: 1, height: 1)
            container?.addSubview(webView, positioned: .below, relativeTo: nil)
        }

        window.contentView = container
        if !window.setFrameUsingName(PanelWindow.autosaveName) {
            window.setFrame(PanelWindow.edgeFrame(on: screen), display: false)
        }
        // A saved frame can end up off screen (display changes, a mini-player relaunch); never
        // start hidden.
        window.setFrame(Self.onScreen(window.frame, near: window.screen ?? screen), display: false)
        window.setFrameAutosaveName(PanelWindow.autosaveName)
        panelOcclusion = Self.followOcclusion(of: window, into: navigation)
        panel = window
    }

    private var panelOcclusion: NSObjectProtocol?

    /// Keeps `isPanelOccluded` in step with whether any of `window` is on screen. Lilt's own
    /// hide parks the panel already, but the app hidden (⌘H), a window covering it or another
    /// Space leave `isPanelHidden` false, and the window's timelines tick on regardless.
    static func followOcclusion(of window: NSWindow, into navigation: NavigationModel) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak window, weak navigation] _ in
            MainActor.assumeIsolated {
                guard let window else { return }
                navigation?.isPanelOccluded = !window.occlusionState.contains(.visible)
            }
        }
    }

    /// No close button on the panel; ⌘W hides it and playback carries on.
    /// Whenever the current cover changes (and once at launch), keep it on disk for the next
    /// launch's first frame.
    private func observeArtworkForLaunch() {
        withObservationTracking {
            _ = player.displayArtworkURL
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeArtworkForLaunch()
            }
        }
        guard let url = player.displayArtworkURL else { return }
        Task { @MainActor in
            // The loaded image is passed along rather than re-read from the cache: when another
            // view started the same load first, this continuation can run before that one has
            // stored it.
            guard let image = await ImageCache.shared.load(url), player.displayArtworkURL == url else { return }
            ImageCache.shared.rememberForLaunch(image, for: url)
        }
    }

    /// The restored track is known before the first frame, but its artwork and the colours
    /// drawn from it (platter tint, shadows) land a few hundred milliseconds later, so the panel
    /// used to appear and then change. It now shows at zero alpha and becomes visible once that
    /// artwork is in the cache, or after 400ms, whichever is first.
    private func revealOnceArtworkIsWarm() {
        guard let panel else { return }
        guard let url = player.displayArtworkURL, ImageCache.shared.cached(url) == nil else { return }
        panel.alphaValue = 0
        // Whichever finishes first reveals; the other finds it already done.
        let reveal = { @MainActor [weak panel] in if let panel, panel.alphaValue == 0 { panel.alphaValue = 1 } }
        Task { @MainActor in _ = await ImageCache.shared.load(url); reveal() }
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(400)); reveal() }
    }

    /// Hidden by alpha, not ordered out: ordering out drops the window server's state for the
    /// header's blur backdrop and the materials, which then rebuild a frame or more after the
    /// next show, with rows under the header drawn sharp until they do. Invisible and inert, the
    /// window keeps that state warm.
    func hidePanel() {
        guard let panel else { return }
        navigation.isPanelHidden = true
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderBack(nil)
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
