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
        notices?.post("\(track.title) from Up Next", label: "Removed", icon: .artwork(track.artworkURL), action: .undo {
            withAnimation(Theme.Motion.settle) { _ = player.insertUpcoming(track, at: offset) }
            AppDelegate.shared?.queueDidChange()
        })
    }

    // MARK: Mixes

    /// Start Mix for a song: its radio replaces the queue. Playback starting is the
    /// confirmation, so only a failure posts a notice. Returns the fetch, for tests to wait on.
    @discardableResult
    static func startMix(for track: Track, player: PlayerService, music: YTMusicClient, notices: NoticeCenter?) -> Task<Void, Never> {
        startMix(named: track.title, artwork: track.artworkURL, player: player, notices: notices) { try await music.mix(for: track) }
    }

    /// Start Mix for an album, playlist or artist.
    @discardableResult
    static func startMix(for item: BrowseItem, player: PlayerService, music: YTMusicClient, notices: NoticeCenter?) -> Task<Void, Never> {
        startMix(named: item.title, artwork: item.artworkURL, player: player, notices: notices) { try await music.mix(for: item) }
    }

    /// Nothing shows while the mix loads. It plays as a list of its own, so Up Next reads
    /// "Up next from Mix – Schism" (the panel's name for it, or one made the same way).
    private static func startMix(named name: String, artwork: URL?, player: PlayerService, notices: NoticeCenter?, fetch: @escaping @MainActor () async throws -> Mix) -> Task<Void, Never> {
        Task {
            guard let mix = try? await fetch(), !mix.tracks.isEmpty else {
                notices?.post(name, label: "Couldn't start mix", icon: .symbol("exclamationmark.triangle"))
                return
            }
            let source = BrowseItem(id: mix.playlistId, kind: .playlist, title: mix.title ?? "Mix – \(name)", subtitle: "Mix", artworkURL: artwork)
            player.playMix(mix.tracks, source: source)
            AppDelegate.shared?.queueDidChange()
        }
    }

    // MARK: Library

    /// Like or Unlike from a menu; Undo sets it back the same way. Said at once, and said again
    /// if YouTube Music didn't take it.
    static func setLiked(_ liked: Bool, _ track: Track, player: PlayerService, music: YTMusicClient, notices: NoticeCenter?) {
        let name = liked ? track.title : "\(track.title) from Liked"
        setLiked(liked, track, player: player, music: music) {
            notices?.post(name, label: liked ? "Couldn't like" : "Couldn't remove", icon: .symbol("exclamationmark.triangle"))
        }
        notices?.post(
            name,
            label: liked ? "Liked" : "Removed",
            icon: .symbol(liked ? "hand.thumbsup.fill" : "hand.thumbsup.slash"),
            action: .undo { setLiked(!liked, track, player: player, music: music) }
        )
    }

    /// Adds a song to one of your playlists. The notice waits for YouTube's answer, which names
    /// the entry it made; Undo takes that entry out. Nothing went in (it was there already), no Undo.
    static func add(_ track: Track, to playlist: OwnPlaylist, music: YTMusicClient, notices: NoticeCenter?) {
        Task {
            do {
                let added = try await music.add(track, to: playlist)
                postAdded(added, key: track.id, named: track.title, artwork: track.artworkURL, to: playlist, music: music, notices: notices)
            } catch {
                postFailure("\(track.title) to \(playlist.title)", label: "Couldn't add", notices: notices)
            }
        }
    }

    /// Adds an album's or playlist's songs to one of yours, the same way.
    static func add(_ item: BrowseItem, to playlist: OwnPlaylist, music: YTMusicClient, notices: NoticeCenter?) {
        Task {
            do {
                let added = try await music.add(item, to: playlist)
                postAdded(added, key: item.id, named: item.title, artwork: item.artworkURL, to: playlist, music: music, notices: notices)
            } catch {
                postFailure("\(item.title) to \(playlist.title)", label: "Couldn't add", notices: notices)
            }
        }
    }

    /// An edit YouTube Music didn't take, named as its confirmation would have been.
    private static func postFailure(_ name: String, label: String, notices: NoticeCenter?) {
        notices?.post(name, label: label, icon: .symbol("exclamationmark.triangle"))
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
        let name = source.map { "\(track.title) from \($0.title)" } ?? track.title
        Task {
            do {
                try await music.removeFromPlaylist(track)
                notices?.post(name, label: "Removed", icon: .artwork(track.artworkURL))
            } catch {
                postFailure(name, label: "Couldn't remove", notices: notices)
            }
        }
    }

    /// Saves an album or playlist to your library, or takes it out, confirmed once YouTube has;
    /// Undo sets it back the same way.
    static func setSaved(_ saved: Bool, page: BrowsePage, music: YTMusicClient, notices: NoticeCenter?) async {
        let name = "\(page.item.title) \(saved ? "to" : "from") Library"
        guard (try? await music.setSaved(saved, page: page)) != nil else {
            postFailure(name, label: saved ? "Couldn't save" : "Couldn't remove", notices: notices)
            return
        }
        notices?.post(
            name,
            label: saved ? "Saved" : "Removed",
            icon: .symbol(saved ? "bookmark.fill" : "bookmark.slash"),
            action: .undo { Task { try? await music.setSaved(!saved, page: page) } }
        )
    }

    // MARK: Links

    static func copyLink(_ url: URL?, named name: String, notices: NoticeCenter?) {
        guard url != nil else { return }
        copy(url)
        notices?.post(name, label: "Copied", icon: .symbol("link"))
    }
}
