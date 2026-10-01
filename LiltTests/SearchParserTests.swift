import Foundation
import Testing
@testable import Lilt

struct SearchParserTests {
    private let fixture: [String: Any] = [
        "contents": [
            "tabbedSearchResultsRenderer": [
                "tabs": [[
                    "tabRenderer": ["content": ["sectionListRenderer": ["contents": [[
                        "musicShelfRenderer": ["contents": [
                            [
                                "musicResponsiveListItemRenderer": [
                                    "playlistItemData": ["videoId": "abc123"],
                                    "thumbnail": ["musicThumbnailRenderer": ["thumbnail": ["thumbnails": [
                                        ["url": "https://lh3.googleusercontent.com/x=w60-h60-l90-rj"],
                                    ]]]],
                                    "flexColumns": [
                                        ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [
                                            ["text": "Song Title"],
                                        ]]]],
                                        ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [
                                            ["text": "Artist Name", "navigationEndpoint": ["browseEndpoint": [
                                                "browseEndpointContextSupportedConfigs": ["browseEndpointContextMusicConfig": ["pageType": "MUSIC_PAGE_TYPE_ARTIST"]],
                                            ]]],
                                            ["text": " • "],
                                            ["text": "Album Name", "navigationEndpoint": ["browseEndpoint": [
                                                "browseEndpointContextSupportedConfigs": ["browseEndpointContextMusicConfig": ["pageType": "MUSIC_PAGE_TYPE_ALBUM"]],
                                            ]]],
                                            ["text": " • "],
                                            ["text": "3:45"],
                                        ]]]],
                                    ],
                                ],
                            ],
                            // Duplicate id should be dropped.
                            ["musicResponsiveListItemRenderer": [
                                "playlistItemData": ["videoId": "abc123"],
                                "flexColumns": [["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Dup"]]]]]],
                            ]],
                            // No video id (an artist row) should be dropped.
                            ["musicResponsiveListItemRenderer": [
                                "flexColumns": [["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Just An Artist"]]]]]],
                            ]],
                        ]],
                    ]]]]],
                ]],
            ],
        ],
    ]

    @Test func parsesSongsFromSearchResponse() {
        let tracks = SearchParser.tracks(from: fixture)
        #expect(tracks.count == 1)
        let track = try! #require(tracks.first)
        #expect(track.id == "abc123")
        #expect(track.title == "Song Title")
        #expect(track.artist == "Artist Name")
        #expect(track.album == "Album Name")
        #expect(track.durationText == "3:45")
        #expect(track.artworkURL?.absoluteString == "https://lh3.googleusercontent.com/x=w240-h240-l90-rj")
    }

    @Test func leavesNonGoogleArtworkAlone() {
        let url = SearchParser.artworkURL("https://i.ytimg.com/vi/abc/hqdefault.jpg", size: 240)
        #expect(url?.absoluteString == "https://i.ytimg.com/vi/abc/hqdefault.jpg")
    }
}
