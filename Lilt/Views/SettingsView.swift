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
            DockSection()
            UpdatesSection()
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }
}

/// The spinning disc on the Dock tile. The spinner watches the stored rate, so a change shows
/// on the song already playing.
private struct DockSection: View {
    @AppStorage(DockSpin.key) private var framesPerSecond = DockSpin.standard.framesPerSecond

    var body: some View {
        Section("Dock") {
            Picker("Spinning disc", selection: Binding(
                get: { DockSpin(framesPerSecond: framesPerSecond) },
                set: { framesPerSecond = $0.framesPerSecond }
            )) {
                ForEach(DockSpin.allCases) { Text($0.title).tag($0) }
            }
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
