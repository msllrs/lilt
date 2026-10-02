import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(PlayerService.self) private var player
    @Environment(YTMusicClient.self) private var music
    @State private var account: AccountInfo?

    var body: some View {
        Form {
            Section("Account") {
                if auth.isSignedIn {
                    LabeledContent("YouTube Music", value: account.map { "\($0.name) (\($0.email))" } ?? "Signed in")
                        .task { account = try? await music.account() }
                    Button("Sign Out", role: .destructive) {
                        Task {
                            player.stop()
                            await auth.signOut()
                        }
                    }
                } else {
                    LabeledContent("YouTube Music", value: "Not signed in")
                    Button("Sign In…") {
                        auth.isPresentingLogin = true
                        AppDelegate.shared?.showPanel()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }
}
