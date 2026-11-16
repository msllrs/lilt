import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Settings ▸ Appearance ▸ Always show song lengths: with it on, a row keeps its length with the
/// pointer away from the panel, where it otherwise fades out and the list reads as titles alone.
/// The row is drawn with the pointer away and compared, over where the length sits, with the
/// same row under the pointer.
@MainActor
struct AlwaysShowLengthsTests {
    private static let track = Track(id: "schism", title: "Schism", artist: "Tool", durationText: "6:47")
    private static let size = CGSize(width: 320, height: 56)

    private func render(pointerInside: Bool, alwaysShows: Bool) async -> NSBitmapImageRep {
        let auth = AuthService()
        let rest = PanelRest(schedule: { _, _ in {} }, isButtonDown: { false })
        if !pointerInside { rest.pointerExited() }
        let view = TrackRow(track: Self.track, isCurrent: false, isPlaying: false) {}
            .environment(auth)
            .environment(PlayerService(auth: auth, makeBridge: { FakeBridge() }))
            .environment(YTMusicClient(auth: auth, persists: false))
            .environment(NavigationModel())
            .environment(rest)
            .environment(\.alwaysShowsLengths, alwaysShows)
            .frame(width: Self.size.width, height: Self.size.height)
            .background(Color.white)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: Self.size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: Self.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.close() }
        // Past Motion.quick's fade.
        for _ in 0..<20 { try? await Task.sleep(for: .milliseconds(20)) }
        hosting.layoutSubtreeIfNeeded()
        let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    /// How many pixels in the trailing quarter, where the length sits, aren't the white behind.
    private func inkAtTheEnd(_ rep: NSBitmapImageRep) -> Int {
        var ink = 0
        for x in Int(Double(rep.pixelsWide) * 0.75)..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if c.redComponent + c.greenComponent + c.blueComponent < 2.7 { ink += 1 }
            }
        }
        return ink
    }

    @Test func theLengthFadesWithThePointerAwayByDefault() async {
        let under = inkAtTheEnd(await render(pointerInside: true, alwaysShows: false))
        let away = inkAtTheEnd(await render(pointerInside: false, alwaysShows: false))
        #expect(under > 20, "the harness sees the length under the pointer (\(under) inked pixels)")
        #expect(away < under / 4, "away from the panel the length is gone (\(away) vs \(under))")
    }

    @Test func turnedOnTheLengthStaysWithThePointerAway() async {
        let under = inkAtTheEnd(await render(pointerInside: true, alwaysShows: true))
        let away = inkAtTheEnd(await render(pointerInside: false, alwaysShows: true))
        #expect(under > 20)
        #expect(away >= under * 9 / 10, "the length stays (\(away) vs \(under))")
    }
}
