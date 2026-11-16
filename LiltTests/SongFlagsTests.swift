import Foundation
import Testing
@testable import Lilt

/// What YouTube Music marks on a song besides its name: an explicit badge, and greyed out
/// where it can't be played here (taken down, or not licensed in this country). The rows are
/// trimmed from real responses: a Liked Music row with its badge and an album row greyed out.
struct SongFlagsTests {
    private static func row(videoId: String, title: String, extra: [String: Any]) -> [String: Any] {
        var renderer: [String: Any] = [
            "playlistItemData": ["videoId": videoId],
            "flexColumns": [
                ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": title]]]]],
                ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Walter Heller"]]]]],
            ],
            "fixedColumns": [["musicResponsiveListItemFixedColumnRenderer": ["text": ["runs": [["text": "2:39"]]]]]],
        ]
        renderer.merge(extra) { $1 }
        return ["musicResponsiveListItemRenderer": renderer]
    }

    private static var explicitBadge: [String: Any] { ["badges": [[
        "musicInlineBadgeRenderer": [
            "accessibilityData": ["accessibilityData": ["label": "Explicit"]],
            "icon": ["iconType": "MUSIC_EXPLICIT_BADGE"],
        ],
    ]]] }
    private static var greyedOut: [String: Any] { ["musicItemRendererDisplayPolicy": "MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT"] }

    @Test func anExplicitSongIsMarked() throws {
        let track = try #require(SearchParser.track(from: JSON.dict(Self.row(videoId: "e1", title: "Bound 2", extra: Self.explicitBadge)["musicResponsiveListItemRenderer"])!))
        #expect(track.isExplicit == true)
        #expect(track.isUnavailable != true)
    }

    @Test func aGreyedOutSongIsUnavailable() throws {
        let track = try #require(SearchParser.track(from: JSON.dict(Self.row(videoId: "TFZt9De06kU", title: "Sailing By", extra: Self.greyedOut)["musicResponsiveListItemRenderer"])!))
        #expect(track.isUnavailable == true)
        #expect(track.isExplicit != true)
    }

    @Test func anOrdinarySongIsNeither() throws {
        let track = try #require(SearchParser.track(from: JSON.dict(Self.row(videoId: "o1", title: "Schism", extra: ["musicItemRendererDisplayPolicy": "MUSIC_ITEM_RENDERER_DISPLAY_POLICY_DEFAULT"])["musicResponsiveListItemRenderer"])!))
        #expect(track.isExplicit != true)
        #expect(track.isUnavailable != true)
    }

    /// Song cards on Home carry the badge under their subtitle.
    @Test func anExplicitSongCardIsMarked() throws {
        let response: [String: Any] = ["contents": ["musicCarouselShelfRenderer": [
            "header": ["musicCarouselShelfBasicHeaderRenderer": ["title": ["runs": [["text": "Quick picks"]]]]],
            "contents": [["musicTwoRowItemRenderer": [
                "title": ["runs": [["text": "Bound 2"]]],
                "subtitle": ["runs": [["text": "Kanye West"]]],
                "navigationEndpoint": ["watchEndpoint": ["videoId": "e2"]],
                "subtitleBadges": Self.explicitBadge["badges"]!,
            ]]],
        ]]]
        let song = try #require(SearchParser.home(from: response).first?.items.first)
        guard case .track(let track) = song else { Issue.record("expected a song, got \(song)"); return }
        #expect(track.isExplicit == true)
    }

    /// A queue saved before these flags existed still loads.
    @Test func aTrackSavedWithoutTheFlagsDecodes() throws {
        let json = Data(#"{"id":"v","title":"Schism","artist":"Tool"}"#.utf8)
        let track = try JSONDecoder().decode(Track.self, from: json)
        #expect(track.isExplicit == nil && track.isUnavailable == nil)
    }
}
