import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Song rows at rest draw only the mask their cover needs. A mask is drawn off screen and
/// composited every frame the row moves, so a screenful of title fades that changed no pixel,
/// one per row, was paid for on every frame of a scroll: the fade under the queue button is only
/// for a hovered row without a length. The cover's mask stays: besides the playing disc's
/// spindle hole, it draws the sleeve's light, keyline and shadow as one picture, and without it
/// the edges of every cover and the whole of a greyed-out one draw differently. Counted in the
/// layers the rows are drawn into.
@MainActor
struct RowMaskTests {
    private static let width: CGFloat = 320

    private func masks(in view: some View, height: CGFloat, hoveringAt hover: NSPoint? = nil) async -> Int {
        let auth = AuthService()
        let root = AnyView(view
            .environment(auth)
            .environment(PlayerService(auth: auth, makeBridge: { FakeBridge() }))
            .environment(YTMusicClient(auth: auth, persists: false))
            .environment(NavigationModel())
            .frame(width: Self.width, height: height, alignment: .top))
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(x: 0, y: 0, width: Self.width, height: height)
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: Self.width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.close() }
        for _ in 0..<15 {
            try? await Task.sleep(for: .milliseconds(20))
            hosting.layoutSubtreeIfNeeded()
        }
        // The pointer arrives over the row: each of SwiftUI's tracking areas hears it come in,
        // as the window would tell it.
        if let hover {
            for area in hosting.trackingAreas {
                let entered = NSEvent.enterExitEvent(
                    with: .mouseEntered, location: hover, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: area.hash, userData: nil
                )!
                (area.owner as? NSResponder)?.mouseEntered(with: entered)
            }
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(20))
                hosting.layoutSubtreeIfNeeded()
            }
        }
        var count = 0
        func walk(_ layer: CALayer) {
            if let mask = layer.mask {
                count += 1
                walk(mask)
            }
            layer.sublayers?.forEach(walk)
        }
        if let layer = hosting.layer { walk(layer) }
        return count
    }

    @Test func rowsAtRestDrawOnlyTheirCoversMasks() async {
        let songs = (0..<5).map { Track(id: "mask-\($0)", title: "Song \($0)", artist: "Tool", durationText: "3:0\($0)") }
        let count = await masks(in: VStack(spacing: 0) { ForEach(songs) { TrackRow(track: $0, isCurrent: false, isPlaying: false) {} } }, height: 300)
        #expect(count == songs.count, "five resting rows, five covers' masks and no title fades (\(count))")
    }

    @Test func rowsWithoutLengthsAtRestDrawOnlyTheirCoversMasks() async {
        let songs = (0..<5).map { Track(id: "mask-nolength-\($0)", title: "Song \($0)", artist: "Tool") }
        let count = await masks(in: VStack(spacing: 0) { ForEach(songs) { TrackRow(track: $0, isCurrent: false, isPlaying: false) {} } }, height: 300)
        #expect(count == songs.count, "five resting rows, five covers' masks and no title fades (\(count))")
    }

    /// Under the pointer, a row without a length fades its title out beneath the queue button,
    /// and a row with one doesn't need to: its title already stops short of the button.
    @Test func aHoveredRowWithoutALengthFadesItsTitle() async {
        let point = NSPoint(x: Self.width / 2, y: 28)
        let without = await masks(in: TrackRow(track: Track(id: "mask-hover", title: "Schism", artist: "Tool"), isCurrent: false, isPlaying: false) {}, height: 56, hoveringAt: point)
        let with = await masks(in: TrackRow(track: Track(id: "mask-hover-length", title: "Schism", artist: "Tool", durationText: "6:47"), isCurrent: false, isPlaying: false) {}, height: 56, hoveringAt: point)
        #expect(without == with + 1, "the title's fade is the one mask between them (\(without) vs \(with))")
    }

    @Test func thePlayingDiscKeepsItsHole() async {
        let song = Track(id: "mask-disc", title: "Schism", artist: "Tool", durationText: "6:47")
        let count = await masks(in: TrackRow(track: song, isCurrent: true, isPlaying: false) {}, height: 56)
        #expect(count >= 1, "the disc's spindle hole is a mask (\(count))")
    }

    @Test func textThatRunsPastItsEdgeKeepsItsFade() async {
        let count = await masks(in: MarqueeText(text: "A very long line of text that runs well past the edge of the row", isActive: false), height: 24)
        #expect(count >= 1, "the edge fade is a mask (\(count))")
    }
}
