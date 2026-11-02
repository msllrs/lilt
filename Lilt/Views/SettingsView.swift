import ServiceManagement
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
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }
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
