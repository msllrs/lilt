import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
        let webView = player.bridge.webView
        webView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        container.addSubview(webView)

        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        window.contentView = container
        if !window.setFrameUsingName(PanelWindow.autosaveName) {
            window.setFrame(PanelWindow.edgeFrame(on: screen), display: false)
        }
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
