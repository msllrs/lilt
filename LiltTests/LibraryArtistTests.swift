import Foundation
import Testing
@testable import Lilt

/// The library's artists are the ones you subscribe to and the artists of songs you've saved.
/// The second feed marks its rows MUSIC_PAGE_TYPE_LIBRARY_ARTIST with an MPLA id (the channel
/// id with MPLA before it); they're artists like any other, opening the artist's own page. The
/// row is a real one from FEmusic_library_corpus_track_artists.
struct LibraryArtistTests {
    private let row: [String: Any] = ["musicResponsiveListItemRenderer": [
        "flexColumns": [
            ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Slipknot"]]]]],
            ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "116 songs"]]]]],
        ],
        "navigationEndpoint": ["browseEndpoint": [
            "browseEndpointContextSupportedConfigs": ["browseEndpointContextMusicConfig": ["pageType": "MUSIC_PAGE_TYPE_LIBRARY_ARTIST"]],
            "browseId": "MPLAUCh9xZWuDWSMeedunotdYYrQ",
        ]],
    ]]

    @Test func anArtistOfSavedSongsIsAnArtist() throws {
        let items = SearchParser.libraryItems(from: ["contents": [row]])
        let artist = try #require(items.first)
        #expect(artist.kind == .artist)
        #expect(artist.id == "UCh9xZWuDWSMeedunotdYYrQ", "the artist's own page, the same id a subscription has")
        #expect(artist.title == "Slipknot")
    }
}
