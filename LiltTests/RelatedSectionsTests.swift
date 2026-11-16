import Foundation
import Testing
@testable import Lilt

/// An album page fills out with its artist's other albums and singles ("More from …") and the
/// artists their fans also like ("Related artists"), taken from the artist's page. Which is
/// which is told by what a section holds, not by its title, which is in the account's language.
@MainActor
struct RelatedSectionsTests {
    private static func items(_ kind: BrowseKind, _ ids: [String]) -> [BrowseItem] {
        ids.map { BrowseItem(id: $0, kind: kind, title: $0, subtitle: "") }
    }

    private let album = BrowsePage(item: BrowseItem(id: "MPREb-lateralus", kind: .album, title: "Lateralus", subtitle: "Tool"))

    /// The artist's page as it comes back for an account set to Japanese.
    private var japaneseArtist: BrowsePage {
        var page = BrowsePage(item: BrowseItem(id: "UC-tool", kind: .artist, title: "TOOL", subtitle: "アーティスト"))
        page.sections = [
            BrowseSection(title: "アルバム", items: Self.items(.album, ["MPREb-lateralus", "MPREb-aenima"])),
            BrowseSection(title: "シングルと EP", items: Self.items(.album, ["MPREb-schism"])),
            BrowseSection(title: "ファンにおすすめ", items: Self.items(.artist, ["UC-apc", "UC-deftones"])),
            BrowseSection(title: "収録プレイリスト", items: Self.items(.playlist, ["VLPL-metal"])),
            BrowseSection(title: "ライブラリから", items: Self.items(.album, ["MPREb-fear"]) + Self.items(.playlist, ["VLPL-mine"])),
        ]
        return page
    }

    @Test func sectionsAreToldApartByWhatTheyHold() {
        let related = BrowseScreen.relatedSections(from: japaneseArtist, excluding: album)
        #expect(related.map(\.title) == ["More from TOOL", "Related artists"])
        #expect(related.first?.items.map(\.id) == ["MPREb-aenima", "MPREb-schism"], "albums and singles, without the album being viewed")
        #expect(related.last?.items.map(\.id) == ["UC-apc", "UC-deftones"])
    }

    /// English, as before.
    @Test func englishTitlesStillWork() {
        var artist = japaneseArtist
        artist.sections = [
            BrowseSection(title: "Albums", items: Self.items(.album, ["MPREb-aenima"])),
            BrowseSection(title: "Fans might also like", items: Self.items(.artist, ["UC-apc"])),
            BrowseSection(title: "Featured on", items: Self.items(.playlist, ["VLPL-metal"])),
        ]
        #expect(BrowseScreen.relatedSections(from: artist, excluding: album).map(\.title) == ["More from TOOL", "Related artists"])
    }
}
