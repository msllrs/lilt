import SwiftUI

struct RootView: View {
    @Environment(PlayerService.self) private var player

    var body: some View {
        SearchScreen()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.current != nil {
                    NowPlayingBar()
                        .padding(.horizontal, Theme.Space.md)
                        .padding(.bottom, Theme.Space.md)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Theme.Motion.standard, value: player.current?.id)
            .background { GlassBackground().ignoresSafeArea() }
    }
}
