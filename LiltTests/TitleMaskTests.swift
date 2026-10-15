import SwiftUI
import Testing
@testable import Lilt

/// The now-playing title fades out beneath the like button wherever that button shows: on hover,
/// and always once the track is liked (a liked thumb stays put after the pointer leaves).
struct TitleMaskTests {
    /// Where the title stops being fully opaque, as a fraction of its width.
    private func solidUntil(_ stops: [Gradient.Stop]) -> CGFloat {
        stops.filter { $0.color == .black }.map(\.location).max() ?? 1
    }

    @Test func idleUnlikedTitleRunsToTheEdge() {
        let stops = NowPlayingBar.titleMaskStops(width: 300, hovering: false, liked: false)
        #expect(solidUntil(stops) == 1)
    }

    @Test func hoverClearsRoomForTheLike() {
        let stops = NowPlayingBar.titleMaskStops(width: 300, hovering: true, liked: false)
        #expect(solidUntil(stops) < 1)
    }

    @Test func likedTrackClearsRoomWithoutHover() {
        let idle = NowPlayingBar.titleMaskStops(width: 300, hovering: false, liked: true)
        let hover = NowPlayingBar.titleMaskStops(width: 300, hovering: true, liked: true)
        #expect(solidUntil(idle) < 1)
        // Hovering a liked track changes nothing: the title doesn't shift as the pointer arrives.
        #expect(idle.map(\.location) == hover.map(\.location))
    }
}
