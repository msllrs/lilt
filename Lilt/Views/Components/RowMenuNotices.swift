import SwiftUI

/// Row actions that confirm themselves with a notice, offering Undo where the action can be
/// taken back cleanly. Each does its work whether or not a notice shows: `notices` may be nil
/// (a view hosted without one) or silent (the panel out of sight, the mini player).
@MainActor
extension RowMenu {
    // MARK: Queue

    /// Play Next for one song or a whole list; Undo takes out exactly the entries it put in.
    static func playNext(_ tracks: [Track], named name: String, artwork: URL?, player: PlayerService, notices: NoticeCenter?) {
        let ids = player.playNext(tracks)
        AppDelegate.shared?.queueDidChange()
        notices?.post(name, label: "Next", icon: .artwork(artwork), action: ids.isEmpty ? nil : .undo {
            withAnimation(Theme.Motion.settle) { player.removeUpcoming(ids: ids) }
            AppDelegate.shared?.queueDidChange()
        })
    }

    static func playNext(_ track: Track, player: PlayerService, notices: NoticeCenter?) {
        playNext([track], named: track.title, artwork: track.artworkURL, player: player, notices: notices)
    }

    /// Add to Queue for one song or a whole list. With nothing playing the first song starts
    /// instead, and there's no Undo: taking it back would stop the music.
    static func enqueue(_ tracks: [Track], named name: String, artwork: URL?, player: PlayerService, notices: NoticeCenter?) {
        let ids = tracks.compactMap { player.enqueue($0) }
        AppDelegate.shared?.queueDidChange()
        let undoable = !ids.isEmpty && ids.count == tracks.count
        notices?.post(name, label: "Queued", icon: .artwork(artwork), action: undoable ? .undo {
            withAnimation(Theme.Motion.settle) { player.removeUpcoming(ids: ids) }
            AppDelegate.shared?.queueDidChange()
        } : nil)
    }

    static func enqueue(_ track: Track, player: PlayerService, notices: NoticeCenter?) {
        enqueue([track], named: track.title, artwork: track.artworkURL, player: player, notices: notices)
    }

    /// Takes an entry out of Up Next; Undo puts the song back where it was.
    static func removeFromQueue(_ id: UUID, player: PlayerService, notices: NoticeCenter?) {
        guard let offset = player.upcomingOffset(of: id), player.upcoming.indices.contains(offset) else { return }
        let track = player.upcoming[offset]
        withAnimation(Theme.Motion.settle) { player.removeUpcoming(at: offset) }
        AppDelegate.shared?.queueDidChange()
        notices?.post(track.title, label: "Removed", icon: .artwork(track.artworkURL), action: .undo {
            withAnimation(Theme.Motion.settle) { _ = player.insertUpcoming(track, at: offset) }
            AppDelegate.shared?.queueDidChange()
        })
    }

    // MARK: Library

    /// Like or Unlike from a menu; Undo sets it back the same way.
    static func setLiked(_ liked: Bool, _ track: Track, player: PlayerService, music: YTMusicClient, notices: NoticeCenter?) {
        setLiked(liked, track, player: player, music: music)
        notices?.post(
            track.title,
            // Unliking has no good single word; the struck-through thumb carries it.
            label: liked ? "Liked" : "Like removed",
            icon: .symbol(liked ? "hand.thumbsup.fill" : "hand.thumbsup.slash"),
            action: .undo { setLiked(!liked, track, player: player, music: music) }
        )
    }

    /// Adds a song to one of your playlists. The notice waits for YouTube's answer, which names
    /// the entry it made; Undo takes that entry out. Nothing went in (it was there already), no Undo.
    static func add(_ track: Track, to playlist: OwnPlaylist, music: YTMusicClient, notices: NoticeCenter?) {
        Task {
            guard let added = try? await music.add(track, to: playlist) else { return }
            postAdded(added, key: track.id, named: track.title, artwork: track.artworkURL, to: playlist, music: music, notices: notices)
        }
    }

    /// Adds an album's or playlist's songs to one of yours, the same way.
    static func add(_ item: BrowseItem, to playlist: OwnPlaylist, music: YTMusicClient, notices: NoticeCenter?) {
        Task {
            guard let added = try? await music.add(item, to: playlist) else { return }
            postAdded(added, key: item.id, named: item.title, artwork: item.artworkURL, to: playlist, music: music, notices: notices)
        }
    }

    private static func postAdded(_ added: [YTMusicClient.AddedSong], key: String, named name: String, artwork: URL?, to playlist: OwnPlaylist, music: YTMusicClient, notices: NoticeCenter?) {
        notices?.post("\(name) to \(playlist.title)", label: "Added", icon: .artwork(artwork), action: added.isEmpty ? nil : .undo {
            Task { try? await music.undoAdd(added, key: key, from: playlist) }
        })
    }

    /// Takes a song out of one of your playlists, confirmed once YouTube has. No Undo: adding it
    /// back would put it at the end under a new entry, and the row still on screen would name
    /// the old one.
    static func removeFromPlaylist(_ track: Track, in source: BrowseItem?, music: YTMusicClient, notices: NoticeCenter?) {
        Task {
            guard (try? await music.removeFromPlaylist(track)) != nil else { return }
            notices?.post(source.map { "\(track.title) from \($0.title)" } ?? track.title, label: "Removed", icon: .artwork(track.artworkURL))
        }
    }

    // MARK: Links

    static func copyLink(_ url: URL?, named name: String, notices: NoticeCenter?) {
        guard url != nil else { return }
        copy(url)
        notices?.post(name, label: "Copied", icon: .symbol("link"))
    }
}
