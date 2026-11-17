import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Song rows at rest draw without masks. A mask is drawn off screen and composited every frame
/// the row moves, so a screenful of them, one per title fade, cover and line of text, was paid
/// for on every frame of a scroll while none of them changed a pixel: the fade under the queue
/// button is only for a hovered row without a length, the spindle hole is only for the playing
/// song's disc, and the edge fade only for text that runs past its edge. Counted in the layers
/// the rows are drawn into.
@MainActor
struct RowMaskTests {
    private static let width: CGFloat = 320

    private func masks(in view: some View, height: CGFloat) async -> Int {
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

    @Test func rowsAtRestDrawWithoutMasks() async {
        let songs = (0..<5).map { Track(id: "mask-\($0)", title: "Song \($0)", artist: "Tool", durationText: "3:0\($0)") }
        let count = await masks(in: VStack(spacing: 0) { ForEach(songs) { TrackRow(track: $0, isCurrent: false, isPlaying: false) {} } }, height: 300)
        #expect(count == 0, "five resting rows, no masks (\(count))")
    }

    @Test func rowsWithoutLengthsAtRestDrawWithoutMasks() async {
        let songs = (0..<5).map { Track(id: "mask-nolength-\($0)", title: "Song \($0)", artist: "Tool") }
        let count = await masks(in: VStack(spacing: 0) { ForEach(songs) { TrackRow(track: $0, isCurrent: false, isPlaying: false) {} } }, height: 300)
        #expect(count == 0, "five resting rows, no masks (\(count))")
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
