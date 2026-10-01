import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(PlayerService.self) private var player

    var body: some View {
        Form {
            Section("Account") {
                if auth.isSignedIn {
                    LabeledContent("YouTube Music", value: "Signed in")
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
                        (NSApp.delegate as? AppDelegate)?.showPanel()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }
}
