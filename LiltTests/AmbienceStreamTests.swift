import Testing
import WebKit
@testable import Lilt

/// The feed is played by a page of its own, not AVPlayer: AVFoundation can't read these mounts
/// (see `StreamPage`), so the drawer's switch listens to the page instead.
@MainActor
struct AmbienceStreamTests {
    @Test func aFeedPlaysOnItsPage() {
        let page = FakeStreamPage()
        let ambience = AmbienceService(defaults: isolatedDefaults("AmbienceStreamTests"))
        ambience.makeStreamPage = { page }
        ambience.streamVolume = 0.4
        ambience.streamURL = "https://www.liveatc.net/play/rjtt_app.pls"
        ambience.setStreaming(true)

        #expect(page.loaded.map(\.url.absoluteString) == ["https://d.liveatc.net/rjtt_app"])
        #expect(page.loaded.map(\.volume) == [0.4])
        #expect(ambience.streamState == .connecting)

        page.send(.playing)
        #expect(ambience.streamState == .playing)

        page.send(.waiting)
        #expect(ambience.streamState == .connecting, "a feed that slips behind buffers again")
    }

    @Test func aFeedThatFailsStaysFailed() {
        let page = FakeStreamPage()
        let ambience = AmbienceService(defaults: isolatedDefaults("AmbienceStreamTests"))
        ambience.makeStreamPage = { page }
        ambience.streamURL = "https://d.liveatc.net/ksfo_twr"
        ambience.setStreaming(true)

        page.send(.failed("MEDIA_ERR_SRC_NOT_SUPPORTED: 4"))
        #expect(ambience.streamState == .failed)

        page.send(.waiting)
        #expect(ambience.streamState == .failed, "the switch goes red until the listener tries again")
    }

    @Test func stoppingStopsItsPage() {
        let page = FakeStreamPage()
        let ambience = AmbienceService(defaults: isolatedDefaults("AmbienceStreamTests"))
        ambience.makeStreamPage = { page }
        ambience.streamURL = "https://d.liveatc.net/ksfo_twr"
        ambience.setStreaming(true)
        ambience.setStreaming(false)

        #expect(page.stopped)
        #expect(ambience.streamState == .off)
    }

    @Test func aNewURLReplacesThePage() {
        let first = FakeStreamPage(), second = FakeStreamPage()
        let ambience = AmbienceService(defaults: isolatedDefaults("AmbienceStreamTests"))
        var pages = [first, second]
        ambience.makeStreamPage = { pages.removeFirst() }
        ambience.streamURL = "https://d.liveatc.net/ksfo_twr"
        ambience.setStreaming(true)
        ambience.streamURL = "https://d.liveatc.net/katl_twr"

        #expect(first.stopped)
        #expect(second.loaded.map(\.url.absoluteString) == ["https://d.liveatc.net/katl_twr"])
    }

    @Test func aPageWithoutAMountNeverStartsAPage() {
        let ambience = AmbienceService(defaults: isolatedDefaults("AmbienceStreamTests"))
        var made = false
        ambience.makeStreamPage = { made = true; return FakeStreamPage() }
        ambience.streamURL = "https://www.liveatc.net/search/?icao=rjtt"
        ambience.setStreaming(true)

        #expect(!made)
        #expect(ambience.streamState == .failed)
    }

    @Test func theLevelGoesToThePage() {
        let page = FakeStreamPage()
        let ambience = AmbienceService(defaults: isolatedDefaults("AmbienceStreamTests"))
        ambience.makeStreamPage = { page }
        ambience.streamURL = "https://d.liveatc.net/ksfo_twr"
        ambience.setStreaming(true)
        ambience.streamVolume = 0.25

        #expect(page.volumes == [0.25])
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
    private(set) var volumes: [Float] = []
    private(set) var stopped = false

    func load(_ url: URL, volume: Float) {
        loaded.append(Load(url: url, volume: volume))
    }

    func setVolume(_ volume: Float) {
        volumes.append(volume)
    }

    func stop() {
        stopped = true
        onEvent = nil
    }

    func send(_ event: StreamEvent) {
        onEvent?(event)
    }
}
