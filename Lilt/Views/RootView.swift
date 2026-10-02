import SwiftUI

struct RootView: View {
    @Environment(PlayerService.self) private var player
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        Group {
            // Mini player: the column is gone entirely, not merely faded, so nothing can show
            // through the short window.
            if navigation.isMiniPlayer {
                Color.clear
            } else {
                NavigationColumn()
                    .transition(.opacity)
            }
        }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                if player.current != nil {
                    // Mini: the platter's content sits directly in the window with the window's
                    // own inset, no card inside a card.
                    // Mini: no inset at all; the platter's own glass and corners are the window.
                    NowPlayingBar()
                        .padding(.horizontal, navigation.isMiniPlayer ? 0 : Theme.Space.panelInset)
                        .padding(.bottom, navigation.isMiniPlayer ? 0 : Theme.Space.panelInset)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Theme.Motion.standard, value: player.current?.id)
            .animation(Theme.Motion.standard, value: navigation.isMiniPlayer)
            .background {
                if !navigation.isMiniPlayer {
                    GlassBackground().ignoresSafeArea()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: navigation.isMiniPlayer ? Theme.Radius.panel : Theme.Radius.window, style: .continuous))
    }
}

/// A stack of screens with a subtle horizontal hand-off. NavigationStack swaps views instantly
/// on macOS; here the search root stays alive underneath and pages ease in from the right by a
/// few points, fading, and back out the same way.
private struct NavigationColumn: View {
    @Environment(NavigationModel.self) private var navigation
    @Environment(ScrollTracker.self) private var scrollTracker

    /// How far a screen travels while entering or leaving.
    private static let travel: CGFloat = 20
    /// Softness at the far end of the hand-off. Off: blurring a full column of artwork every
    /// frame is what made the hand-off stutter. Slide and fade are cheap; this isn't.
    private static let blur: CGFloat = 0
    /// The outgoing screen gets out of the way faster than the incoming one arrives, so the two
    /// never read as a double exposure on the glass.
    private static let exit: Animation = .easeOut(duration: 0.12)
    private static let enter: Animation = .easeOut(duration: 0.2)

    var body: some View {
        let path = navigation.path
        ZStack {
            SearchScreen()
                .parked(path.isEmpty ? nil : .leading, travel: Self.travel, blur: Self.blur, animation: Self.exit, value: path)
            ForEach(Array(path.enumerated()), id: \.element.id) { index, item in
                let isTop = index == path.count - 1
                Group {
                    if item.kind == .library {
                        LibraryScreen()
                    } else {
                        BrowseScreen(item: item)
                    }
                }
                .parked(isTop ? nil : .leading, travel: Self.travel, blur: Self.blur, animation: Self.exit, value: path)
                .transition(.offset(x: Self.travel).combined(with: .opacity).animation(Self.enter))
            }
        }
        .animation(Self.enter, value: path)
        // The back button stays put while pages slide beneath it; it only fades in and out.
        .overlay(alignment: .topLeading) {
            if !path.isEmpty {
                BackButton()
                    .frame(height: Theme.Size.headerRow)
                    .padding(.top, Theme.Space.panelInset)
                    .padding(.leading, Theme.Space.panelInset)
                    .transition(.opacity.animation(Self.enter))
            }
        }
        .onChange(of: path.last?.id, initial: true) { _, top in
            scrollTracker.activeKey = top ?? ScrollTracker.searchKey
        }
    }
}

private struct BackButton: View {
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        Button {
            navigation.pop()
        } label: {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.pressable(scale: 0.88))
        .keyboardShortcut("[", modifiers: .command)
        .help("Back")
    }
}

private extension View {
    /// Keeps a screen mounted but slid aside and inert while another one is on top.
    @ViewBuilder
    func parked<V: Equatable>(_ edge: HorizontalEdge?, travel: CGFloat, blur: CGFloat, animation: Animation, value: V) -> some View {
        let parked = edge != nil
        self
            .offset(x: edge == .leading ? -travel : edge == .trailing ? travel : 0)
            .blur(radius: parked ? blur : 0)
            // Fade the screen as one flattened layer rather than row by row.
            .compositingGroup()
            .opacity(parked ? 0 : 1)
            .animation(animation, value: value)
            .allowsHitTesting(!parked)
            .accessibilityHidden(parked)
    }
}
