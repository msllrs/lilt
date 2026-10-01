import SwiftUI

struct RootView: View {
    @Environment(PlayerService.self) private var player
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        NavigationColumn()
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

/// A stack of screens with a subtle horizontal hand-off. NavigationStack swaps views instantly
/// on macOS; here the search root stays alive underneath and pages ease in from the right by a
/// few points, fading, and back out the same way.
private struct NavigationColumn: View {
    @Environment(NavigationModel.self) private var navigation

    /// How far a screen travels while entering or leaving.
    private static let travel: CGFloat = 28

    var body: some View {
        let path = navigation.path
        ZStack {
            SearchScreen()
                .parked(path.isEmpty ? nil : .leading, travel: Self.travel)
            ForEach(Array(path.enumerated()), id: \.element.id) { index, item in
                let isTop = index == path.count - 1
                BrowseScreen(item: item)
                    .parked(isTop ? nil : .leading, travel: Self.travel)
                    .transition(.offset(x: Self.travel).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.standard, value: path)
    }
}

private extension View {
    /// Keeps a screen mounted but slid aside and inert while another one is on top.
    @ViewBuilder
    func parked(_ edge: HorizontalEdge?, travel: CGFloat) -> some View {
        let parked = edge != nil
        self
            .offset(x: edge == .leading ? -travel : edge == .trailing ? travel : 0)
            .opacity(parked ? 0 : 1)
            .allowsHitTesting(!parked)
            .accessibilityHidden(parked)
    }
}
