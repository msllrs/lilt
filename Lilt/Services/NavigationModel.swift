import Foundation
import Observation
import SwiftUI

/// Where you are in the column: the search text and the stack of opened pages. Persisted so a
/// relaunch brings you back to the same view.
@MainActor
@Observable
final class NavigationModel {
    private static let key = "navigationState"

    /// The library pseudo-page.
    static let library = BrowseItem(id: "library", kind: .library, title: "Library", subtitle: "", artworkURL: nil)

    var query: String { didSet { save() } }
    var path: [BrowseItem] { didSet { save() } }
    /// True while the native frame is animating between the column and the platter; the column
    /// holds its expanded layout until it ends. Not persisted.
    var isFrameAnimating = false
    /// The panel is hidden (alpha zero, kept alive for its window-server state). Every clock in
    /// the view tree pauses on it: a hidden window keeps its hosting view, and timelines in it
    /// kept ticking. Not persisted.
    var isPanelHidden = false
    /// The window server reports no part of the panel on screen: hidden with the app (⌘H),
    /// covered by other windows, on another Space, or the display asleep. Not persisted.
    var isPanelOccluded = false
    /// Nobody can see the panel, so its clocks pause. `isPanelHidden` counts at once, before
    /// the window server's report arrives. An ordered-out or covered window keeps ticking just
    /// like a transparent one.
    var isPanelOutOfSight: Bool { isPanelHidden || isPanelOccluded }
    /// The native frame's current corner radius while it eases between the panel's and the
    /// platter's. Behind-window surfaces mask themselves to it, since the frame's own clip
    /// doesn't reach them. Not persisted.
    var frameCornerRadius: CGFloat = Theme.Radius.window
    /// The expanded window height the native frame animates to, for a column that has never
    /// been laid out expanded (launched in mini). Not persisted.
    var expandedFrameHeight: CGFloat = 0
    /// The compact now-playing header's artwork colour and how far that header has arrived, so
    /// the back button beside it can catch its light on the facing edge. Not persisted.
    var leadingCast: Color? = nil
    var leadingCastAmount: Double = 0
    /// The album on top's cover accent, so the back button's glyph takes the same colour as the
    /// page's own controls; nil on any other page. Not persisted.
    var leadingTintAccent: Color? = nil
    /// Collapse the column to just the now-playing platter.
    var isMiniPlayer: Bool {
        didSet {
            save()
            // Runs synchronously after the write and before SwiftUI lays anything out, which is
            // when the window frame must change.
            if isMiniPlayer != oldValue { miniPlayerDidChange?(isMiniPlayer) }
        }
    }
    @ObservationIgnored var miniPlayerDidChange: ((Bool) -> Void)?
    /// Measured height of the platter, for sizing the mini-player window.
    var platterHeight: CGFloat = 140
    /// The platter's height without the queue list (title, controls, scrubber and padding).
    var platterBaseHeight: CGFloat = 140
    /// The ambience drawer is open below the scrubber (option-click on the cover). Not persisted.
    var isAmbienceVisible = false
    /// The up-next list is open below the scrubber. Toggled by double-clicking the platter;
    /// goes through `AppDelegate.setQueueVisible` so the mini window can grow first.
    var isQueueVisible = false
    /// How much of the up-next list is showing, 0 to 1: where `isQueueVisible` says once
    /// settled, and in between while the grab handle is being pulled or the list springs to an
    /// end. Not persisted.
    var queueReveal: CGFloat = 0
    /// Bumps when the screen on top should fetch its content again (⌘R). Every screen in the
    /// stack sees it; only the one on top answers. Not persisted.
    private(set) var refreshRequest = 0
    /// Receives every page opened, for the recents menu. Wired by the app.
    @ObservationIgnored weak var recents: RecentsStore?

    private struct Saved: Codable {
        var query: String
        var path: [BrowseItem]
        var isMiniPlayer: Bool?
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            query = saved.query
            // Drop any duplicate ids a previous build may have persisted.
            var seen = Set<String>()
            path = saved.path.filter { seen.insert($0.id).inserted }
            isMiniPlayer = saved.isMiniPlayer ?? false
        } else {
            query = ""
            path = []
            isMiniPlayer = false
        }
    }

    func open(_ item: BrowseItem) {
        // Opening a page from the mini player (artist name, album art) means wanting to see it.
        if isMiniPlayer { AppDelegate.shared?.setMiniPlayer(false) }
        // The same page can arrive with slightly different metadata (a search row versus the
        // player's byline), so identity is the browse id. Re-opening the current page is a
        // no-op; opening one further down the stack pops back to it rather than duplicating it,
        // since two screens with one identity render as nothing at all.
        if let existing = path.firstIndex(where: { $0.id == item.id }) {
            path.removeSubrange((existing + 1)...)
            return
        }
        path.append(item)
        recents?.recordViewed(item)
    }

    func refresh() { refreshRequest += 1 }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    private func save() {
        let data = try? JSONEncoder().encode(Saved(query: query, path: path, isMiniPlayer: isMiniPlayer))
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
