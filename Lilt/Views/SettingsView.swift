import ServiceManagement
import Sparkle
import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(YTMusicClient.self) private var music
    @Environment(PlayerService.self) private var player
    @State private var account: AccountInfo?

    var body: some View {
        @Bindable var player = player
        Form {
            GeneralSection()
            Section("Account") {
                if auth.isSignedIn {
                    LabeledContent("YouTube Music", value: account.map { "\($0.name) (\($0.email))" } ?? "Signed in")
                        .task { account = try? await music.account() }
                    Button("Sign Out", role: .destructive) { AppDelegate.shared?.signOut() }
                } else {
                    LabeledContent("YouTube Music", value: "Not signed in")
                    Button("Sign In…") {
                        auth.isPresentingLogin = true
                        AppDelegate.shared?.showPanel()
                    }
                }
            }
            Section {
                Picker("Gapless", selection: $player.gaplessMode) {
                    ForEach(PlayerService.GaplessMode.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Playback")
            } footer: {
                Text(player.gaplessMode.footer)
                    .foregroundStyle(.secondary)
            }
            AppearanceSection()
            DockSection()
            // Reached through AppDelegate rather than the environment, so this section stands
            // on its own.
            Section("Keyboard Shortcut") {
                if let shortcut = AppDelegate.shared?.showLiltShortcut {
                    LabeledContent("Show Lilt") {
                        ShortcutRecorder(shortcut: shortcut.combo, error: shortcut.error, onChange: shortcut.set, onRecordingChange: shortcut.setSuspended)
                    }
                }
            }
            NotificationsSection()
            UpdatesSection()
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }
}

/// The disc in lists and page headers. With Reduce Motion on it rests whatever this says.
private struct AppearanceSection: View {
    @AppStorage(SpinningArtwork.spinsKey) private var spinsPlayingCover = true

    var body: some View {
        Section {
            Toggle("Spin the cover of the playing song", isOn: $spinsPlayingCover)
        } header: {
            Text("Appearance")
        } footer: {
            Text("With Reduce Motion on, the cover stays still here and in the Dock.")
                .foregroundStyle(.secondary)
        }
    }
}

/// The spinning disc on the Dock tile. The spinner watches the stored rate, so a change shows
/// on the song already playing.
private struct DockSection: View {
    @AppStorage(DockSpin.key) private var framesPerSecond = DockSpin.standard.framesPerSecond

    var body: some View {
        let spin = DockSpin(framesPerSecond: framesPerSecond)
        Section {
            Picker("Spinning disc", selection: Binding(
                get: { spin },
                set: { framesPerSecond = $0.framesPerSecond }
            )) {
                ForEach(DockSpin.allCases) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Dock")
        } footer: {
            Text(spin.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// A banner when the song changes. Permission is asked for only when this is turned on; a
/// refusal turns it back off and says where to change that.
private struct NotificationsSection: View {
    @AppStorage(SongNotifier.enabledKey) private var enabled = false
    @State private var isDenied = false

    var body: some View {
        Section {
            Toggle("Show a notification when the song changes", isOn: Binding(get: { enabled }, set: setEnabled))
        } header: {
            Text("Notifications")
        } footer: {
            if isDenied {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Lilt isn't allowed to show notifications. Turn them on in System Settings ▸ Notifications.")
                    Button("Open Notifications…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(.link)
                }
                .foregroundStyle(.secondary)
            }
        }
        .task { if enabled { isDenied = await SongNotifier.isDenied() } }
    }

    private func setEnabled(_ on: Bool) {
        enabled = on
        guard on else { isDenied = false; return }
        Task {
            let allowed = await SongNotifier.requestAuthorization()
            isDenied = !allowed
            if !allowed { enabled = false }
        }
    }
}

/// Sparkle's own settings, read from and written to the updater so the menu's Check for
/// Updates… and this agree. Check Now is greyed while a check is already under way.
private struct UpdatesSection: View {
    @State private var updates = UpdaterState(AppDelegate.shared?.updater)

    var body: some View {
        @Bindable var updates = updates
        Section("Updates") {
            Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
            LabeledContent("Lilt \(updates.version)") {
                Button("Check Now") { updates.checkNow() }
                    .disabled(!updates.canCheck)
            }
        }
    }
}

/// Mirrors the parts of `SPUUpdater` Settings shows. `canCheckForUpdates` is key-value
/// observed: it goes false while a check (or an update) is in progress.
@MainActor
@Observable
private final class UpdaterState {
    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    private(set) var canCheck = false
    var checksAutomatically: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = checksAutomatically }
    }
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    init(_ controller: SPUStandardUpdaterController?) {
        self.controller = controller
        checksAutomatically = controller?.updater.automaticallyChecksForUpdates ?? false
        observation = controller?.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let can = change.newValue ?? false
            Task { @MainActor in self?.canCheck = can }
        }
    }

    /// The same check as the menu's, with Sparkle's own window for the answer (or the error, if
    /// the feed can't be read).
    func checkNow() { controller?.checkForUpdates(nil) }
}

/// Open at login, as the system has it. The switch reads `SMAppService` rather than a flag of
/// our own, so turning Lilt off in System Settings ▸ Login Items shows here too. (The main app
/// service needs no helper or entitlement, sandboxed or not.)
private struct GeneralSection: View {
    @State private var status = SMAppService.mainApp.status
    @State private var failure: String?

    var body: some View {
        Section {
            Toggle("Open at login", isOn: Binding(get: { status == .enabled || status == .requiresApproval }, set: setOpensAtLogin))
        } header: {
            Text("General")
        } footer: {
            if status == .requiresApproval {
                // Registered, but macOS wants the user's say-so before it counts.
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Allow Lilt in System Settings ▸ General ▸ Login Items to finish turning this on.")
                    Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.link)
                }
                .foregroundStyle(.secondary)
            } else if let failure {
                Text(failure).foregroundStyle(.secondary)
            }
        }
        // Coming back from System Settings, show what was decided there.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = SMAppService.mainApp.status
        }
    }

    private func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }
}

private extension PlayerService.GaplessMode {
    var footer: String {
        switch self {
        case .off:
            "Each song loads when the one before it ends."
        case .nativeQueue:
            "Puts the next song in YouTube Music's own Up Next, so its player moves on by itself. Only this session's queue changes, never your library."
        case .secondPlayer:
            "Keeps the next song loaded in a second player, so it starts the moment the current one ends. Uses more memory."
        case .chromeQueue:
            "An experiment: the player page identifies as Chrome so YouTube turns on its own gapless. Some songs may not play."
        }
    }
}
