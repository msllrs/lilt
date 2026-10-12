import Testing
@testable import Lilt

struct TrackLabelTests {
    private func track(title: String, artist: String) -> Track { Track(id: "id", title: title, artist: artist) }

    @Test func titleAndArtist() {
        #expect(TrackLabel.text(for: track(title: "Boring Angel", artist: "Oneohtrix Point Never")) == "Boring Angel – Oneohtrix Point Never")
    }

    @Test func blankPartsDropOut() {
        #expect(TrackLabel.text(for: track(title: "Boring Angel", artist: " ")) == "Boring Angel")
        #expect(TrackLabel.text(for: track(title: "", artist: "Oneohtrix Point Never")) == "Oneohtrix Point Never")
        #expect(TrackLabel.text(for: track(title: " ", artist: "")) == nil)
    }

    @Test func noTrackIsNoLabel() {
        #expect(TrackLabel.text(for: nil) == nil)
    }
}
