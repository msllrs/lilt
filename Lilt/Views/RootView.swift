import SwiftUI

struct RootView: View {
    @Environment(PlayerService.self) private var player
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.path) {
            SearchScreen()
                .navigationDestination(for: BrowseItem.self) { item in
                    BrowseScreen(item: item)
                }
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            if player.current != nil {
                NowPlayingBar()
                    .padding(.horizontal, Theme.Space.panelInset)
                    .padding(.bottom, Theme.Space.panelInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.standard, value: player.current?.id)
        .background { GlassBackground().ignoresSafeArea() }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous))
    }
}
