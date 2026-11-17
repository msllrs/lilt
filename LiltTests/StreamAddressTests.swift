import Testing
@testable import Lilt

/// A listener pastes what the site gives them, which is a player page or a playlist rather than
/// the mount: LiveATC's are behind a bot check and their `.pls` is unreadable to AVPlayer, so the
/// mount behind both is played instead.
struct StreamAddressTests {
    @Test func playlistBecomesItsMount() {
        #expect(StreamAddress.stream(from: "https://www.liveatc.net/play/rjtt_app.pls")?.absoluteString == "https://d.liveatc.net/rjtt_app")
        #expect(StreamAddress.stream(from: "https://www.liveatc.net/play/kjfk9_s.pls")?.absoluteString == "https://d.liveatc.net/kjfk9_s")
    }

    @Test func playerPageBecomesItsMount() {
        #expect(StreamAddress.stream(from: "https://www.liveatc.net/hlisten.php?mount=rjtt_app&icao=rjtt")?.absoluteString == "https://d.liveatc.net/rjtt_app")
        #expect(StreamAddress.stream(from: "https://www.liveatc.net/hlisten.php?icao=rjtt&mount=rjtt_app")?.absoluteString == "https://d.liveatc.net/rjtt_app")
    }

    @Test func theMountItselfIsLeftAlone() {
        #expect(StreamAddress.stream(from: "https://d.liveatc.net/rjtt_app")?.absoluteString == "https://d.liveatc.net/rjtt_app")
    }

    @Test func anyOtherStreamIsLeftAlone() {
        #expect(StreamAddress.stream(from: "https://example.com:8000/live.mp3")?.absoluteString == "https://example.com:8000/live.mp3")
        #expect(StreamAddress.stream(from: "http://stream.example.org/radio")?.absoluteString == "http://stream.example.org/radio")
    }

    @Test func aPageWithoutAMountIsNoStream() {
        #expect(StreamAddress.stream(from: "https://www.liveatc.net/search/?icao=rjtt") == nil)
    }

    @Test func pastedAroundWhitespace() {
        #expect(StreamAddress.stream(from: "  https://d.liveatc.net/rjtt_app\n")?.absoluteString == "https://d.liveatc.net/rjtt_app")
    }

    @Test func notAnHTTPAddressIsNoStream() {
        #expect(StreamAddress.stream(from: "") == nil)
        #expect(StreamAddress.stream(from: "rjtt_app") == nil)
        #expect(StreamAddress.stream(from: "ftp://example.com/live.mp3") == nil)
    }
}
