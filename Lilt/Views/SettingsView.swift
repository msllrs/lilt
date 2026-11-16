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
                Toggle("Gapless playback", isOn: $player.isGapless)
            } header: {
                Text("Playback")
            } footer: {
                Text("Keeps the next song loaded in the background so it starts the moment the current one ends. Uses more memory.")
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
            DiagnosticsSection()
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }
}

/// The panel's surface, and the disc in lists and page headers. The window style edits the same
/// `ArtworkStyle.panel` the panel draws from (and saves), so the open panel restyles at once.
/// Each style is a card showing the panel in miniature on its real surface, its platter in the
/// playing cover's colour. With Reduce Motion on the disc rests whatever this says; with Reduce
/// Transparency on, Glass shows as Solid, and its card says so. Player glass frosts the platter's
/// clear glass, from frosted through to clear like the search field; Reduce Transparency keeps
/// it frosted. Theme sets the whole app light or dark, or follows the system; the previews here
/// redraw in it with the rest.
private struct AppearanceSection: View {
    @AppStorage(AppTheme.key) private var theme = AppTheme.system
    @AppStorage(SpinningArtwork.spinsKey) private var spinsPlayingCover = true
    @AppStorage(PanelRest.enabledKey) private var fadesWhenNotInUse = PanelRest.enabledByDefault
    @AppStorage(TrackRow.alwaysShowsLengthsKey) private var alwaysShowsLengths = false
    @Bindable private var style = ArtworkStyle.shared
    @Environment(PlayerService.self) private var player
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The cover's dominant colour, as the platter takes it.
    private var accent: Color? {
        guard let url = player.displayArtworkURL else { return nil }
        return ImageCache.shared.accent(for: url, saturationBoost: style.palette.accentSaturation)
    }

    private var artwork: NSImage? {
        guard let url = player.displayArtworkURL else { return nil }
        return ImageCache.shared.cached(url) ?? ImageCache.shared.anyVariant(for: url)
    }

    var body: some View {
        Section {
            Picker("Theme", selection: $theme) {
                ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: theme) { theme.apply() }
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                // The picker carries this name for VoiceOver itself.
                Text("Window style")
                    .accessibilityHidden(true)
                InterpolatedColor(accent) { accent in
                    WindowStylePicker(selection: $style.windowStyle, accent: accent, artwork: artwork)
                }
                if reduceTransparency {
                    Text("Glass is shown as Solid while Reduce Transparency is on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Slider(value: Binding(get: { style.playerClarity.value }, set: { style.playerClarity = PlayerClarity($0) })) {
                    Text("Player glass")
                } minimumValueLabel: {
                    Text("Frosted")
                } maximumValueLabel: {
                    Text("Clear")
                }
                .disabled(reduceTransparency)
                if reduceTransparency {
                    Text("The player is frosted while Reduce Transparency is on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Spin the cover of the playing song", isOn: $spinsPlayingCover)
            Toggle(isOn: $alwaysShowsLengths) {
                Text("Always show song lengths")
                Text("Otherwise lengths show only while the pointer is over the panel.")
            }
            Toggle(isOn: $fadesWhenNotInUse) {
                Text("Fade when not in use")
                Text("A few seconds after the pointer leaves, the list dims so the panel sits quietly on the edge. The player stays as it is.")
            }
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

/// Lilt's own log, kept on this Mac (see `Diagnostics`), and the switch for keeping YouTube
/// Music's raw responses beside it while a bug in how a page reads is being traced.
private struct DiagnosticsSection: View {
    @AppStorage(Diagnostics.recordsResponsesKey) private var recordsResponses = false

    var body: some View {
        Section {
            Toggle("Keep YouTube Music responses", isOn: $recordsResponses)
            LabeledContent("Log") {
                Button("Show in Finder") { AppDelegate.shared?.showDiagnostics() }
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Lilt keeps a log of what it did on this Mac, to trace a problem after it happens. Nothing is sent anywhere. Keeping responses also saves the pages YouTube Music sends, your library included, until you turn it off.")
                .foregroundStyle(.secondary)
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
