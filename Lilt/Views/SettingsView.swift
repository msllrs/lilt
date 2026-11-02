import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(YTMusicClient.self) private var music
    @Environment(PlayerService.self) private var player
    @State private var account: AccountInfo?

    var body: some View {
        @Bindable var player = player
        Form {
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
