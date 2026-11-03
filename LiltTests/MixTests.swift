import Foundation
import Testing
@testable import Lilt

/// Start Mix plays YouTube Music's radio for a song, album, playlist or artist: the watch
/// playlist each grows from, fetched with `next` and read off its queue panel. Every request
/// here goes to a fake.
@MainActor
struct MixTests {
    private let schism = Track(id: "tuw1ziytBDk", title: "Schism", artist: "Tool")

    /// A trimmed `next` answer for RDAMVMtuw1ziytBDk, in the shape InnerTube returns it: the
    /// queue panel under the watch-next tabs, with a song wrapped beside its video counterpart
    /// and one that can't be played.
    static let panelJSON = #"""
    {
      "contents": {
        "singleColumnMusicWatchNextResultsRenderer": {
          "tabbedRenderer": {
            "watchNextTabbedResultsRenderer": {
              "tabs": [{
                "tabRenderer": {
                  "title": "Up next",
                  "content": {
                    "musicQueueRenderer": {
                      "content": {
                        "playlistPanelRenderer": {
                          "title": "Mix – Schism",
                          "playlistId": "RDAMVMtuw1ziytBDk",
                          "isInfinite": true,
                          "contents": [
                            {
                              "playlistPanelVideoRenderer": {
                                "videoId": "tuw1ziytBDk",
                                "title": { "runs": [{ "text": "Schism" }] },
                                "lengthText": { "runs": [{ "text": "6:48" }] },
                                "thumbnail": { "thumbnails": [
                                  { "url": "https://lh3.googleusercontent.com/schism=w60-h60-l90-rj", "width": 60, "height": 60 },
                                  { "url": "https://lh3.googleusercontent.com/schism=w120-h120-l90-rj", "width": 120, "height": 120 }
                                ] },
                                "longBylineText": { "runs": [
                                  { "text": "Tool", "navigationEndpoint": { "browseEndpoint": { "browseId": "UC1wUBAGOHrkF6S3d5kZpwRA",
                                    "browseEndpointContextSupportedConfigs": { "browseEndpointContextMusicConfig": { "pageType": "MUSIC_PAGE_TYPE_ARTIST" } } } } },
                                  { "text": " • " },
                                  { "text": "Lateralus", "navigationEndpoint": { "browseEndpoint": { "browseId": "MPREb_lateralus",
                                    "browseEndpointContextSupportedConfigs": { "browseEndpointContextMusicConfig": { "pageType": "MUSIC_PAGE_TYPE_ALBUM" } } } } },
                                  { "text": " • " },
                                  { "text": "2001" }
                                ] },
                                "selected": true
                              }
                            },
                            {
                              "playlistPanelVideoWrapperRenderer": {
                                "primaryRenderer": {
                                  "playlistPanelVideoRenderer": {
                                    "videoId": "VtNxCk5Ag7w",
                                    "title": { "runs": [{ "text": "Parabola" }] },
                                    "lengthText": { "runs": [{ "text": "6:04" }] },
                                    "longBylineText": { "runs": [
                                      { "text": "Tool", "navigationEndpoint": { "browseEndpoint": { "browseId": "UC1wUBAGOHrkF6S3d5kZpwRA",
                                        "browseEndpointContextSupportedConfigs": { "browseEndpointContextMusicConfig": { "pageType": "MUSIC_PAGE_TYPE_ARTIST" } } } } }
                                    ] }
                                  }
                                },
                                "counterpart": [{
                                  "counterpartRenderer": {
                                    "playlistPanelVideoRenderer": {
                                      "videoId": "parabola-video",
                                      "title": { "runs": [{ "text": "Parabola (Official Video)" }] }
                                    }
                                  }
                                }]
                              }
                            },
                            {
                              "playlistPanelVideoRenderer": {
                                "videoId": "unplayable1",
                                "title": { "runs": [{ "text": "Not here" }] },
                                "unplayableText": { "runs": [{ "text": "Video unavailable" }] }
                              }
                            },
                            {
                              "playlistPanelVideoRenderer": {
                                "videoId": "nspxAG12Cpc",
                                "title": { "runs": [{ "text": "Sober" }] },
                                "longBylineText": { "runs": [{ "text": "Tool" }, { "text": " • " }, { "text": "Undertow" }] }
                              }
                            }
                          ],
                          "continuations": [{ "nextRadioContinuationData": { "continuation": "CBEScont" } }]
                        }
                      }
                    }
                  }
                }
              }]
            }
          }
        }
      }
    }
    """#

    static func panel() throws -> JSONObject {
        JSONObject(value: try JSONSerialization.jsonObject(with: Data(panelJSON.utf8)) as! [String: Any])
    }

    // MARK: Ids

    @Test func eachKindHasItsMixId() {
        #expect(YTMusicClient.mixId(forSong: "tuw1ziytBDk") == "RDAMVMtuw1ziytBDk")
        #expect(YTMusicClient.mixId(forList: "OLAK5uy_lateralus") == "RDAMPLOLAK5uy_lateralus", "an album's audio playlist")
        #expect(YTMusicClient.mixId(forList: "VLPLtool") == "RDAMPLPLtool", "a playlist's browse id loses its VL")
        #expect(YTMusicClient.mixId(forList: "RDAMPLPLtool") == "RDAMPLPLtool", "a mix already is left alone")

        var album = BrowsePage(item: BrowseItem(id: "MPREb_lateralus", kind: .album, title: "Lateralus", subtitle: "", artworkURL: nil))
        album.playlistId = "OLAK5uy_lateralus"
        #expect(YTMusicClient.mixId(for: album) == "RDAMPLOLAK5uy_lateralus")
        var artist = BrowsePage(item: BrowseItem(id: "UC1wUBAGOHrkF6S3d5kZpwRA", kind: .artist, title: "Tool", subtitle: "", artworkURL: nil))
        #expect(YTMusicClient.mixId(for: artist) == nil, "an artist's radio isn't derived from its channel")
        artist.radioId = "RDEMtool"
        #expect(YTMusicClient.mixId(for: artist) == "RDEMtool")
    }

    /// The artist header's Mix button, as `get_artist` reads it for radioId.
    @Test func anArtistPageNamesItsMix() {
        let response: [String: Any] = ["header": ["musicImmersiveHeaderRenderer": [
            "title": ["runs": [["text": "Tool"]]],
            "startRadioButton": ["buttonRenderer": ["navigationEndpoint": ["watchPlaylistEndpoint": ["playlistId": "RDEMtool", "params": "wAEB"]]]],
        ]]]
        let item = BrowseItem(id: "UC1wUBAGOHrkF6S3d5kZpwRA", kind: .artist, title: "Tool", subtitle: "", artworkURL: nil)
        #expect(SearchParser.browsePage(from: response, for: item).radioId == "RDEMtool")
    }

    // MARK: Parsing

    @Test func theQueuePanelBecomesSongs() throws {
        let mix = try #require(SearchParser.mix(from: try Self.panel().value, playlistId: "RDAMVMtuw1ziytBDk"))
        #expect(mix.title == "Mix – Schism")
        #expect(mix.playlistId == "RDAMVMtuw1ziytBDk")
        #expect(mix.tracks.map(\.id) == ["tuw1ziytBDk", "VtNxCk5Ag7w", "nspxAG12Cpc"], "no video counterpart, nothing unplayable")
        let first = try #require(mix.tracks.first)
        #expect(first.title == "Schism" && first.artist == "Tool")
        #expect(first.artistId == "UC1wUBAGOHrkF6S3d5kZpwRA")
        #expect(first.album == "Lateralus" && first.albumId == "MPREb_lateralus")
        #expect(first.durationText == "6:48")
        #expect(first.artworkURL?.absoluteString == "https://lh3.googleusercontent.com/schism=w240-h240-l90-rj")
        #expect(mix.tracks[2].artist == "Tool", "an unlinked byline still names the artist")
        #expect(mix.tracks[2].artistId == nil)
    }

    @Test func aResponseWithoutAPanelIsNoMix() {
        #expect(SearchParser.mix(from: ["contents": [:]], playlistId: "RDAMVMx") == nil)
    }

    // MARK: Fetching

    @Test func aSongsMixAsksForItsRadioWithTheSong() async throws {
        var asked: [(String, String?)] = []
        let music = YTMusicClient(auth: AuthService(), fetchWatch: { playlistId, videoId in
            asked.append((playlistId, videoId))
            return try Self.panel()
        })
        let mix = try await music.mix(for: schism)
        #expect(asked.count == 1)
        #expect(asked.first?.0 == "RDAMVMtuw1ziytBDk" && asked.first?.1 == "tuw1ziytBDk")
        #expect(mix.tracks.first?.id == schism.id)
    }

    @Test func aPlaylistsMixNeedsNoPage() async throws {
        var asked: [String] = []
        let music = YTMusicClient(
            auth: AuthService(),
            fetchPage: { _ in Issue.record("a playlist's id is in its browse id"); return JSONObject(value: [:]) },
            fetchWatch: { playlistId, _ in asked.append(playlistId); return try Self.panel() }
        )
        _ = try await music.mix(for: BrowseItem(id: "VLPLtool", kind: .playlist, title: "Tool", subtitle: "", artworkURL: nil))
        #expect(asked == ["RDAMPLPLtool"])
    }

    @Test func anAlbumsMixGoesByItsAudioPlaylist() async throws {
        var asked: [String] = []
        let music = YTMusicClient(
            auth: AuthService(),
            fetchPage: { _ in JSONObject(value: ["header": ["musicResponsiveHeaderRenderer": [
                "title": ["runs": [["text": "Lateralus"]]],
                "buttons": [["musicPlayButtonRenderer": ["playNavigationEndpoint": ["watchPlaylistEndpoint": ["playlistId": "OLAK5uy_lateralus"]]]]],
            ]]]) },
            fetchWatch: { playlistId, videoId in
                #expect(videoId == nil)
                asked.append(playlistId)
                return try Self.panel()
            }
        )
        _ = try await music.mix(for: BrowseItem(id: "MPREb_lateralus", kind: .album, title: "Lateralus", subtitle: "", artworkURL: nil))
        #expect(asked == ["RDAMPLOLAK5uy_lateralus"])
    }

    @Test func anArtistWithoutAMixButtonHasNoMix() async {
        let music = YTMusicClient(
            auth: AuthService(),
            fetchPage: { _ in JSONObject(value: [:]) },
            fetchWatch: { _, _ in Issue.record("there's no id to ask for"); return try Self.panel() }
        )
        await #expect(throws: (any Error).self) {
            try await music.mix(for: BrowseItem(id: "UCnobody", kind: .artist, title: "Nobody", subtitle: "", artworkURL: nil))
        }
    }

    @Test func anEmptyPanelIsAFailure() async {
        let music = YTMusicClient(auth: AuthService(), fetchWatch: { _, _ in
            JSONObject(value: ["contents": ["playlistPanelRenderer": ["contents": []]]])
        })
        await #expect(throws: (any Error).self) { try await music.mix(for: schism) }
    }
}
