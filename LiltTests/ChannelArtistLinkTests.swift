import Foundation
import Testing
@testable import Lilt

/// Uploads by a channel (mixes, live sets, most of YouTube proper) link their byline to a
/// `MUSIC_PAGE_TYPE_USER_CHANNEL` page rather than an artist page. The channel is still the
/// act you'd want to open, and the browse id is a UC… id like any artist's, so the parsers
/// must treat the run as the artist run wherever they lift one out of a byline.
struct ChannelArtistLinkTests {
    private static func run(_ text: String, pageType: String, browseId: String) -> [String: Any] {
        [
            "text": text,
            "navigationEndpoint": ["browseEndpoint": [
                "browseId": browseId,
                "browseEndpointContextSupportedConfigs": ["browseEndpointContextMusicConfig": ["pageType": pageType]],
            ]],
        ]
    }

    private static var channel: [String: Any] { run("Cercle", pageType: "MUSIC_PAGE_TYPE_USER_CHANNEL", browseId: "UC-cercle") }

    @Test func searchRowFromAChannelLinksTheChannelAsArtist() {
        let response: [String: Any] = ["contents": ["musicShelfRenderer": ["contents": [[
            "musicResponsiveListItemRenderer": [
                "playlistItemData": ["videoId": "vid1"],
                "flexColumns": [
                    ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Hania Rani live at Invalides"]]]]],
                    ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [
                        ["text": "Video"], ["text": " • "], Self.channel, ["text": " • "], ["text": "1:12:03"],
                    ]]]],
                ],
            ],
        ]]]]]
        let track = try! #require(SearchParser.tracks(from: response).first)
        #expect(track.artist == "Cercle")
        #expect(track.artistId == "UC-cercle", "the channel's UC id should be the track's artist id")
    }

    @Test func homeTileFromAChannelLinksTheChannelAsArtist() {
        let response: [String: Any] = ["contents": ["musicCarouselShelfRenderer": [
            "header": ["musicCarouselShelfBasicHeaderRenderer": ["title": ["runs": [["text": "Listen again"]]]]],
            "contents": [["musicTwoRowItemRenderer": [
                "navigationEndpoint": ["watchEndpoint": ["videoId": "vid2"]],
                "title": ["runs": [["text": "deep work music"]]],
                "subtitle": ["runs": [Self.channel, ["text": " • "], ["text": "2.1M views"]]],
                "thumbnailRenderer": [:],
            ]]],
        ]]]
        let sections = SearchParser.home(from: response)
        guard case let .track(track)? = sections.first?.items.first else {
            Issue.record("expected a track tile, got \(sections)"); return
        }
        #expect(track.artist == "Cercle")
        #expect(track.artistId == "UC-cercle")
    }

    @Test func nextResponseFromAChannelLinksTheChannelAsArtist() {
        let response: [String: Any] = ["contents": [["playlistPanelVideoRenderer": [
            "videoId": "vid3",
            "selected": true,
            "longBylineText": ["runs": [Self.channel, ["text": " • "], ["text": "3.4M views"]]],
        ]]]]
        let links = try! #require(SearchParser.links(from: response, videoId: "vid3"))
        #expect(links.artist == "Cercle")
        #expect(links.artistId == "UC-cercle")
    }

    @Test func albumCardFromAChannelLinksTheChannelAsArtist() {
        let response: [String: Any] = ["contents": ["musicCarouselShelfRenderer": [
            "header": ["musicCarouselShelfBasicHeaderRenderer": ["title": ["runs": [["text": "Albums"]]]]],
            "contents": [["musicTwoRowItemRenderer": [
                "navigationEndpoint": ["browseEndpoint": [
                    "browseId": "MPREb-x",
                    "browseEndpointContextSupportedConfigs": ["browseEndpointContextMusicConfig": ["pageType": "MUSIC_PAGE_TYPE_ALBUM"]],
                ]],
                "title": ["runs": [["text": "Live Sets"]]],
                "subtitle": ["runs": [["text": "Album • "], Self.channel]],
                "thumbnailRenderer": [:],
            ]]],
        ]]]
        let sections = SearchParser.home(from: response)
        guard case let .browse(item)? = sections.first?.items.first else {
            Issue.record("expected an album card, got \(sections)"); return
        }
        #expect(item.artist == "Cercle")
        #expect(item.artistId == "UC-cercle")
    }
}
