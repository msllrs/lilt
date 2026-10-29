import Testing
@testable import Lilt

/// A row's right-click menu offers what makes sense for the row and the list it's in.
struct RowMenuTests {
    private let song = Track(id: "v1", title: "Schism", artist: "Tool", album: "Lateralus", artistId: "UCtool", albumId: "MPREb-lateralus")
    private func page(_ id: String, _ kind: BrowseKind) -> BrowseItem { BrowseItem(id: id, kind: kind, title: "", subtitle: "", artworkURL: nil) }

    @Test func aSongInYourOwnPlaylistCanBeRemovedFromIt() {
        var mine = song
        mine.playlistEntry = PlaylistEntry(playlistId: "PLmine", setVideoId: "set1")
        let actions = RowMenu.track(mine, in: page("VLPLmine", .playlist)).flatMap { $0 }
        #expect(actions.contains(.removeFromPlaylist))
        #expect(actions.contains(.addToPlaylist))
    }

    @Test func someoneElsesPlaylistOffersNoRemove() {
        #expect(!RowMenu.track(song, in: page("VLPLtheirs", .playlist)).flatMap { $0 }.contains(.removeFromPlaylist))
    }

    @Test func aLikedTrackLeavesLikedMusicByBeingUnliked() {
        let actions = RowMenu.track(song, in: page("VLLM", .playlist)).flatMap { $0 }
        #expect(actions.contains(.unlike))
        #expect(!actions.contains(.removeFromPlaylist))
        #expect(!actions.contains(.like))
    }

    @Test func aLikedSongOffersUnlikeAnywhere() {
        #expect(RowMenu.track(song, in: nil, isLiked: true).flatMap { $0 }.contains(.unlike))
        #expect(RowMenu.track(song, in: nil, isLiked: false).flatMap { $0 }.contains(.like))
        #expect(RowMenu.track(song, in: nil, isLiked: nil).flatMap { $0 }.contains(.like))
    }

    @Test func aTrackElsewhereHasNothingToBeRemovedFrom() {
        for source in [nil, page("MPREb-other", .album), page("UCtool", .artist)] {
            let actions = RowMenu.track(song, in: source).flatMap { $0 }
            #expect(!actions.contains(.removeFromPlaylist))
            #expect(actions.contains(.like))
        }
    }

    @Test func goToAlbumIsLeftOffTheAlbumsOwnPage() {
        #expect(RowMenu.track(song, in: nil).flatMap { $0 }.contains(.goToAlbum))
        #expect(!RowMenu.track(song, in: page("MPREb-lateralus", .album)).flatMap { $0 }.contains(.goToAlbum))
        #expect(!RowMenu.track(Track(id: "v2", title: "Loose", artist: ""), in: nil).flatMap { $0 }.contains(.goToArtist))
    }

    @Test func pagesOfferWhatSuitsTheirKind() {
        let artist = RowMenu.item(page("UCtool", .artist)).flatMap { $0 }
        #expect(artist.contains(.play) && artist.contains(.copyLink))
        #expect(!artist.contains(.addToPlaylist))
        let album = RowMenu.item(page("MPREb-lateralus", .album)).flatMap { $0 }
        #expect(album.contains(.addToPlaylist) && album.contains(.addToQueue))
        #expect(RowMenu.item(page("library", .library)).isEmpty)
    }

    @Test func linksPointAtYouTubeMusic() {
        #expect(RowMenu.webURL(for: song)?.absoluteString == "https://music.youtube.com/watch?v=v1")
        #expect(RowMenu.webURL(for: page("VLPLmine", .playlist))?.absoluteString == "https://music.youtube.com/playlist?list=PLmine")
        #expect(RowMenu.webURL(for: page("MPREb-x", .album))?.absoluteString == "https://music.youtube.com/browse/MPREb-x")
    }
}

/// The up-next list's rows and the now-playing bar have menus of their own.
struct QueueAndPlatterMenuTests {
    private let song = Track(id: "v1", title: "Schism", artist: "Tool", album: "Lateralus", artistId: "UCtool", albumId: "MPREb-lateralus")

    @Test func onlyHandQueuedSongsComeOutOfTheQueue() {
        #expect(RowMenu.queued(song, removable: true, isLiked: nil).flatMap { $0 }.contains(.removeFromQueue))
        #expect(!RowMenu.queued(song, removable: false, isLiked: nil).flatMap { $0 }.contains(.removeFromQueue))
    }

    @Test func queuedSongsOfferTheSongsOwnActions() {
        let actions = RowMenu.queued(song, removable: false, isLiked: true).flatMap { $0 }
        #expect(actions.contains(.play) && actions.contains(.addToPlaylist) && actions.contains(.unlike))
        #expect(actions.contains(.goToArtist) && actions.contains(.goToAlbum) && actions.contains(.copyLink))
        #expect(!actions.contains(.addToQueue), "it's already queued")
    }

    @Test func theBarIsAboutTheSong() {
        let actions = RowMenu.nowPlaying(song, isLiked: false).flatMap { $0 }
        #expect(actions == [.like, .addToPlaylist, .goToArtist, .goToAlbum, .copyLink])
        #expect(RowMenu.nowPlaying(song, isLiked: true).flatMap { $0 }.first == .unlike)
    }
}
