import Foundation
import Testing
@testable import Lilt

/// A playlist or library edit YouTube Music didn't take says so, where the one that took says
/// Added, Removed or Saved: before, a failure showed nothing, and a song that never went into a
/// playlist looked as if it might have.
@MainActor
struct EditFailureTests {
    private let schism: Track = {
        var track = Track(id: "tuw1ziytBDk", title: "Schism", artist: "Tool")
        track.playlistEntry = PlaylistEntry(playlistId: "PLmine", setVideoId: "set1")
        return track
    }()
    private let playlist = OwnPlaylist(id: "PLmine", title: "run")
    private let album = BrowseItem(id: "MPREb-lateralus", kind: .album, title: "Lateralus", subtitle: "Tool")

    private func offline() -> YTMusicClient {
        YTMusicClient(auth: AuthService(), write: { _, _ in throw URLError(.notConnectedToInternet) }, persists: false)
    }

    private func said(_ center: NoticeCenter) async -> String? {
        for _ in 0..<50 where center.current == nil { try? await Task.sleep(for: .milliseconds(10)) }
        return center.current?.spoken
    }

    @Test func aSongThatDidntGoInSaysSo() async {
        let center = NoticeCenter(clock: ManualNoticeClock())
        RowMenu.add(schism, to: playlist, music: offline(), notices: center)
        #expect(await said(center) == "Couldn't add Schism to run")
    }

    @Test func aSongThatDidntComeOutSaysSo() async {
        let center = NoticeCenter(clock: ManualNoticeClock())
        let source = BrowseItem(id: "VLPLmine", kind: .playlist, title: "run", subtitle: "Matt")
        RowMenu.removeFromPlaylist(schism, in: source, music: offline(), notices: center)
        #expect(await said(center) == "Couldn't remove Schism from run")
    }

    @Test func aSaveThatDidntTakeSaysSo() async {
        let center = NoticeCenter(clock: ManualNoticeClock())
        var page = BrowsePage(item: album)
        page.playlistId = "OLAK5uy_lateralus"
        await RowMenu.setSaved(true, page: page, music: offline(), notices: center)
        #expect(center.current?.spoken == "Couldn't save Lateralus to Library")
    }
}
