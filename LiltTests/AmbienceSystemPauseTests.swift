import Foundation
import Testing
import WebKit
@testable import Lilt

/// Headphones coming out pause the music through the system. The bed under it goes quiet with
/// the music, its switches still on, and comes back when the music plays again.
@MainActor
struct AmbienceSystemPauseTests {
    private func withAmbience(_ body: (AmbienceService, () -> [FakeBridge], () -> [FakeStreamPage]) throws -> Void) rethrows {
        var sounds: [FakeBridge] = []
        var streams: [FakeStreamPage] = []
        let ambience = AmbienceService(defaults: isolatedDefaults("AmbienceSystemPauseTests"))
        ambience.makePlayer = { let page = FakeBridge(); sounds.append(page); return page }
        ambience.makeStreamPage = { let page = FakeStreamPage(); streams.append(page); return page }
        try body(ambience, { sounds }, { streams })
    }

    @Test func aSystemPauseHoldsTheSoundsAndTheFeed() throws {
        try withAmbience { ambience, sounds, streams in
            ambience.toggle(.rain)
            ambience.toggle(.fire)
            ambience.streamURL = "https://d.liveatc.net/ksfo_twr"
            ambience.setStreaming(true)
            streams()[0].send(.playing)

            ambience.holdForSystemPause()

            #expect(ambience.isHeldForSystemPause)
            #expect(sounds().allSatisfy { $0.calls.last == "pause" })
            #expect(streams()[0].stopped)
            #expect(ambience.active == [.rain, .fire], "the switches stay on")
            #expect(ambience.isStreaming)
            #expect(ambience.streamState == .off)

            ambience.releaseAfterSystemPause()

            #expect(!ambience.isHeldForSystemPause)
            #expect(sounds().allSatisfy { $0.calls.last == "play" })
            #expect(streams().count == 2, "the feed starts on a fresh page, at live")
            #expect(streams()[1].loaded.map(\.url.absoluteString) == ["https://d.liveatc.net/ksfo_twr"])
        }
    }

    @Test func aPageThatStartsWhileHeldIsPausedAgain() throws {
        try withAmbience { ambience, sounds, _ in
            ambience.toggle(.rain)
            ambience.holdForSystemPause()

            // Its page finished loading after the hold's first Pause, when it had no script yet.
            sounds()[0].onEvent?(.state(PlaybackSnapshot(
                videoId: nil, isPlaying: true, currentTime: 1, duration: 3600, title: "", artist: ""
            )))

            #expect(sounds()[0].calls.last == "pause")
        }
    }

    @Test func nothingOnMeansNothingToHold() throws {
        try withAmbience { ambience, _, _ in
            ambience.holdForSystemPause()
            #expect(!ambience.isHeldForSystemPause)
        }
    }

    @Test func switchingASoundOnWhileHeldBringsTheBedBack() throws {
        try withAmbience { ambience, sounds, _ in
            ambience.toggle(.rain)
            ambience.holdForSystemPause()

            ambience.toggle(.wind)

            #expect(!ambience.isHeldForSystemPause)
            #expect(sounds()[0].calls.last == "play")
            #expect(sounds().count == 2)
            #expect(sounds()[1].calls == ["load:\(AmbienceService.Sound.wind.videoId)"])
        }
    }

    @Test func switchingTheFeedOnWhileHeldBringsTheBedBack() throws {
        try withAmbience { ambience, sounds, streams in
            ambience.toggle(.rain)
            ambience.streamURL = "https://d.liveatc.net/ksfo_twr"
            ambience.holdForSystemPause()

            ambience.setStreaming(true)

            #expect(!ambience.isHeldForSystemPause)
            #expect(sounds()[0].calls.last == "play")
            #expect(streams().count == 1)
            #expect(streams()[0].loaded.map(\.url.absoluteString) == ["https://d.liveatc.net/ksfo_twr"])
        }
    }

    @Test func aFeedPickedWhileHeldWaitsForTheMusic() throws {
        try withAmbience { ambience, _, streams in
            ambience.streamURL = "https://d.liveatc.net/ksfo_twr"
            ambience.setStreaming(true)
            ambience.holdForSystemPause()

            ambience.streamURL = "https://d.liveatc.net/katl_twr"

            #expect(streams().count == 1, "nothing new sounds while the music is paused")
            #expect(ambience.isHeldForSystemPause)
            #expect(ambience.isStreaming)

            ambience.releaseAfterSystemPause()

            #expect(streams().count == 2)
            #expect(streams()[1].loaded.map(\.url.absoluteString) == ["https://d.liveatc.net/katl_twr"])
        }
    }

    @Test func turningEverythingOffClearsTheHold() throws {
        try withAmbience { ambience, _, _ in
            ambience.toggle(.rain)
            ambience.streamURL = "https://d.liveatc.net/ksfo_twr"
            ambience.setStreaming(true)
            ambience.holdForSystemPause()

            ambience.stopAll()

            #expect(!ambience.isHeldForSystemPause)
            #expect(!ambience.isOn)
        }
    }
}

@MainActor
private final class FakeStreamPage: StreamPaging {
    struct Load: Equatable {
        var url: URL
        var volume: Float
    }

    var webView: WKWebView? { nil }
    var onEvent: ((StreamEvent) -> Void)?

    private(set) var loaded: [Load] = []
    private(set) var stopped = false

    func load(_ url: URL, volume: Float) {
        loaded.append(Load(url: url, volume: volume))
    }

    func setVolume(_ volume: Float) {}

    func stop() {
        stopped = true
        onEvent = nil
    }

    func send(_ event: StreamEvent) {
        onEvent?(event)
    }
}
