import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// How song rows show YouTube Music's marks: an explicit badge before the artist, unless
/// Settings ▸ Appearance ▸ Show explicit badges is off.
@MainActor
struct SongFlagRowTests {
    private static let width: CGFloat = 320

    private func host(_ view: some View) -> (NSWindow, NSHostingView<AnyView>) {
        let auth = AuthService()
        let root = AnyView(view
            .environment(auth)
            .environment(PlayerService(auth: auth, makeBridge: { FakeBridge() }))
            .environment(YTMusicClient(auth: auth, persists: false))
            .environment(NavigationModel())
            .frame(width: Self.width)
            .background(Color.white))
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: Self.width, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        return (window, hosting)
    }

    private func settle() async { for _ in 0..<10 { try? await Task.sleep(for: .milliseconds(20)) } }

    /// Inked pixels where the byline starts, just after the cover.
    private func inkAtTheBylineStart(_ track: Track, badges: Bool) async -> Int {
        let (window, hosting) = host(TrackRow(track: track, isCurrent: false, isPlaying: false) {}
            .environment(\.showsExplicitBadges, badges)
            .frame(height: 56))
        defer { window.close() }
        hosting.frame = CGRect(x: 0, y: 0, width: Self.width, height: 56)
        await settle()
        let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / rep.size.width
        let left = Int((Theme.Space.rowPadding + Theme.Size.rowArtwork + Theme.Space.md) * scale)
        var ink = 0
        for x in left..<(left + rep.pixelsWide / 32) {
            for y in (rep.pixelsHigh / 2)..<rep.pixelsHigh {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if c.redComponent + c.greenComponent + c.blueComponent < 2.7 { ink += 1 }
            }
        }
        return ink
    }

    @Test func anExplicitSongShowsItsBadge() async {
        let plain = Track(id: "p", title: "Bound 2", artist: "Kanye West")
        var explicit = plain
        explicit.isExplicit = true
        let without = await inkAtTheBylineStart(plain, badges: true)
        let with = await inkAtTheBylineStart(explicit, badges: true)
        let off = await inkAtTheBylineStart(explicit, badges: false)
        #expect(with > without + 20, "the badge draws before the artist (\(with) vs \(without))")
        #expect(off == without, "with badges off, the row is as an unmarked one (\(off) vs \(without))")
    }
}
