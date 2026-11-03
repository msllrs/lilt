import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Opening the library, hosted off screen with a saved library of a realistic size (360 rows)
/// and its covers already decoded, as the library button's hover leaves them: how long the main
/// thread is held from the push to the first frame, and then over the second after it, while
/// the page slides in on `pageEnter` and is first looked at.
@MainActor
struct LibraryArrivalTests {
    @Observable final class Model { var pushed = false }
    private static let size = CGSize(width: 320, height: 640)

    /// 40 playlists, 200 albums and 120 artists, each with a cover in the cache.
    static func library(playlists: Int = 40, albums: Int = 200, artists: Int = 120) -> LibraryContent {
        func url(_ id: String, hue: Double) -> URL {
            let url = URL(string: "https://lh3.googleusercontent.com/library-arrival-\(id)=w240-h240-l90-rj")!
            if ImageCache.shared.cached(url) == nil {
                let image = NSImage(size: NSSize(width: 240, height: 240), flipped: false) { rect in
                    NSColor(hue: hue, saturation: 0.7, brightness: 0.8, alpha: 1).setFill()
                    rect.fill()
                    return true
                }
                ImageCache.shared.store(image, for: url)
            }
            return url
        }
        var content = LibraryContent()
        content.playlists = (0..<playlists).map { i in
            BrowseItem(id: "VLPL-arrival-\(i)", kind: .playlist, title: "Playlist \(i)", subtitle: "Playlist • Tool • \(i * 3) songs", artworkURL: url("pl\(i)", hue: Double(i) / Double(playlists)))
        }
        content.albums = (0..<albums).map { i in
            var item = BrowseItem(id: "MPREb-arrival-\(i)", kind: .album, title: "Lateralus \(i)", subtitle: "Album • Tool • 2001", artworkURL: url("al\(i)", hue: Double(i) / Double(albums)))
            item.artist = "Tool"; item.artistId = "UC-tool"
            return item
        }
        content.artists = (0..<artists).map { i in
            BrowseItem(id: "UC-arrival-\(i)", kind: .artist, title: "Artist \(i)", subtitle: "Artist • \(i)K subscribers", artworkURL: url("ar\(i)", hue: Double(i) / Double(artists)))
        }
        return content
    }

    /// The navigation column's Current hand-off, reduced to the library page coming in over an
    /// empty root.
    private struct Column: View {
        let model: Model
        let music: YTMusicClient
        var body: some View {
            ZStack {
                Color.clear
                if model.pushed {
                    LibraryScreen(music: music)
                        .compositingGroup()
                        .transition(.offset(x: Theme.Motion.pageTravel).combined(with: .opacity).animation(Theme.Motion.pageEnter))
                }
            }
            .animation(Theme.Motion.pageEnter, value: model.pushed)
        }
    }

    /// The main thread's busy spells: a 1ms timer that notes when it gets to run. A gap between
    /// two beats is a spell the main thread was held (a frame's update, layout and commit).
    @MainActor final class Heartbeat {
        private(set) var beats: [Double] = []
        private var timer: Timer?
        private let clock = ContinuousClock()
        private let start: ContinuousClock.Instant
        init() {
            start = clock.now
            let timer = Timer(timeInterval: 0.001, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.beat() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        func now() -> Double {
            let d = clock.now - start
            return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        }
        private func beat() { beats.append(now()) }
        func stop() { timer?.invalidate() }
        /// Spells longer than `over` ms from `after` on: when each began and how long it was.
        func spells(after: Double, over: Double = 4) -> [(at: Double, ms: Double)] {
            zip(beats, beats.dropFirst()).filter { a, b in a >= after - over && b - a > over }.map { a, b in (a, b - a) }
        }
    }

    struct Arrival {
        /// From the push to the end of the first update: the first frame's main-thread work.
        var firstFrame: Double
        /// Every later spell over 4ms within the second after the push.
        var spells: [(at: Double, ms: Double)]
        var held: Double { spells.reduce(0) { $0 + $1.ms } }
    }

    private func arrive(_ content: LibraryContent) async throws -> Arrival {
        let auth = AuthService()
        let music = YTMusicClient(auth: auth, library: content, fetchAccount: { nil })
        let model = Model()
        let view = Column(model: model, music: music)
            .environment(auth)
            .environment(PlayerService(auth: auth, makeBridge: { FakeBridge() }))
            .environment(music)
            .environment(NavigationModel())
            .environment(ScrollTracker())
            .environment(CollapsedSections())
            .frame(width: Self.size.width, height: Self.size.height)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: Self.size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: Self.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))

        let heart = Heartbeat()
        defer { heart.stop() }
        try await Task.sleep(for: .milliseconds(50))
        let pushedAt = heart.now()
        model.pushed = true
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let firstFrame = heart.now() - pushedAt
        let afterFirst = heart.now()
        try await Task.sleep(for: .seconds(1))
        return Arrival(firstFrame: firstFrame, spells: heart.spells(after: afterFirst).map { ($0.at - pushedAt, $0.ms) })
    }

    /// Once the first frame is up, the page should cost the main thread next to nothing: the
    /// slide in is 12 frames at 60Hz, and the budget is three of them across the whole second.
    /// Measured on the sliced stack, the remaining 342 rows were built ten a frame after the
    /// first 18, each slice laying out the whole stack again: 630 to 920ms held in that second,
    /// in spells of 330 to 460ms, so the slide in stalled and the page sat unresponsive.
    @Test func libraryHoldsTheMainThreadOnlyForItsFirstFrame() async throws {
        let content = Self.library()
        _ = try await arrive(content) // type metadata, fonts and symbol images, once
        var runs: [Arrival] = []
        for _ in 0..<3 {
            let run = try await arrive(content)
            print(String(format: "LibraryArrival: first frame %.1fms, then %.1fms held in %d spells (%@)", run.firstFrame, run.held, run.spells.count,
                         run.spells.map { String(format: "%.0fms at %.0f", $0.ms, $0.at) }.joined(separator: ", ")))
            runs.append(run)
        }
        let held = runs.map(\.held).sorted()[1]
        let budget = 3 * 1000 / 60.0
        #expect(held <= budget, "the main thread was held \(held)ms in the second after the library's first frame (median of three), over a \(budget)ms budget")
    }
}
