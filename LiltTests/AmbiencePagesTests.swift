import Foundation
import Testing
@testable import Lilt

/// Each ambience sound plays its YouTube Music track on a page of its own, made when the sound
/// goes on and let go when it goes off, so several can play at once and none costs anything idle.
@MainActor
struct AmbiencePagesTests {
    /// An ambience service on fake pages, with defaults of its own.
    private func withAmbience(_ body: (AmbienceService, () -> [FakeBridge]) throws -> Void) rethrows {
        var made: [FakeBridge] = []
        let ambience = AmbienceService(defaults: isolatedDefaults("AmbiencePagesTests"))
        ambience.makePlayer = { let page = FakeBridge(); made.append(page); return page }
        try body(ambience, { made })
    }

    private func report(_ page: FakeBridge, time: Double, duration: Double) {
        page.onEvent?(.state(PlaybackSnapshot(videoId: nil, isPlaying: true, currentTime: time, duration: duration, title: "", artist: "")))
    }

    @Test func eachSoundGetsItsOwnPage() throws {
        try withAmbience { ambience, made in
            ambience.toggle(.rain)
            ambience.toggle(.fire)
            #expect(made().count == 2)
            #expect(made()[0].calls == ["load:\(AmbienceService.Sound.rain.videoId)"])
            #expect(made()[1].calls == ["load:\(AmbienceService.Sound.fire.videoId)"])
            #expect(ambience.loading == [.rain, .fire])
        }
    }

    @Test func aSoundSwitchedOffLetsItsPageGo() throws {
        try withAmbience { ambience, made in
            ambience.toggle(.ocean)
            ambience.toggle(.ocean)
            #expect(made().count == 1)
            #expect(made()[0].calls.last == "unload")
            #expect(made()[0].onEvent == nil)
            #expect(ambience.loading.isEmpty)
            // On again: a fresh page, not the old one.
            ambience.toggle(.ocean)
            #expect(made().count == 2)
        }
    }

    @Test func soundingStopsTheLoadingPulse() throws {
        try withAmbience { ambience, made in
            ambience.toggle(.wind)
            made()[0].onEvent?(.playing(videoId: AmbienceService.Sound.wind.videoId))
            #expect(ambience.loading.isEmpty)
        }
    }

    /// The page would finish the track and autoplay something else; it goes back to the start
    /// just before.
    @Test func loopsBeforeTheEnd() throws {
        try withAmbience { ambience, made in
            ambience.toggle(.deep)
            let page = made()[0]
            report(page, time: 1000, duration: 3600)
            #expect(!page.calls.contains("seek"))
            report(page, time: 3599, duration: 3600)
            #expect(page.calls.last == "seek")
            // And if it reaches the end all the same, the track is loaded again.
            page.onEvent?(.ended(videoId: nil))
            #expect(page.calls.last == "load:\(AmbienceService.Sound.deep.videoId)")
        }
    }

    @Test func withoutPagesNothingPlays() throws {
        try withAmbience { ambience, made in
            ambience.makePlayer = nil
            ambience.toggle(.rain)
            #expect(made().isEmpty)
            #expect(ambience.active == [.rain])
        }
    }
}
