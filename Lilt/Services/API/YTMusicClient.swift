import Foundation
import Observation

/// Typed YouTube Music operations on top of `InnerTubeClient`, with a small in-memory cache so
/// going back to a page is instant.
@MainActor
@Observable
final class YTMusicClient {
    /// InnerTube search filter for songs only.
    private static let songsFilter = "EgWKAQIIAWoMEA4QChADEAQQCRAF"

    @ObservationIgnored private let client: InnerTubeClient
    /// Fetches a browse page's raw response. Tests stand in for the network here.
    @ObservationIgnored private let fetchPage: @MainActor (_ browseId: String) async throws -> JSONObject
    /// Calls that change the account (likes, playlist edits), standable in for by tests.
    @ObservationIgnored private let write: @MainActor (_ endpoint: String, _ body: [String: Any]) async throws -> JSONObject
    /// Fetches the up-next panel for a video, which names its artist and album. Tests stand in here.
    @ObservationIgnored private let fetchNext: @MainActor (_ videoId: String) async throws -> JSONObject
    @ObservationIgnored private var pageCache: [String: BrowsePage] = [:]
    @ObservationIgnored private var homeCache: (sections: [HomeSection], fetched: Date)?
    @ObservationIgnored private var libraryCache: (content: LibraryContent, fetched: Date)?

    // Disk persistence so a relaunch starts warm: stale-while-revalidate.
    private struct Persisted: Codable {
        var home: [HomeSection]?
        var homeFetched: Date?
        var library: LibraryContent?
        var libraryFetched: Date?
        var account: AccountInfo?
    }
    private static let persistedURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("feeds.json")
    }()

    private func persist() {
        let data = Persisted(
            home: homeCache?.sections, homeFetched: homeCache?.fetched,
            library: libraryCache?.content, libraryFetched: libraryCache?.fetched,
            account: cachedAccount
        )
        try? JSONEncoder().encode(data).write(to: Self.persistedURL, options: .atomic)
    }

    private func restore() {
        guard let data = try? Data(contentsOf: Self.persistedURL),
              let saved = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        // Restored content is shown immediately but treated as stale so it refreshes behind.
        if let home = saved.home { homeCache = (home, saved.homeFetched ?? .distantPast) }
        if let library = saved.library { libraryCache = (library, saved.libraryFetched ?? .distantPast) }
        cachedAccount = saved.account
    }
    private static let homeTTL: TimeInterval = 5 * 60

    init(
        auth: AuthService,
        fetchPage: (@MainActor (_ browseId: String) async throws -> JSONObject)? = nil,
        write: (@MainActor (_ endpoint: String, _ body: [String: Any]) async throws -> JSONObject)? = nil,
        fetchNext: (@MainActor (_ videoId: String) async throws -> JSONObject)? = nil
    ) {
        let client = InnerTubeClient(auth: auth)
        self.client = client
        self.fetchPage = fetchPage ?? { browseId in try await client.post("browse", body: ["browseId": browseId]) }
        self.write = write ?? { endpoint, body in try await client.post(endpoint, body: body) }
        self.fetchNext = fetchNext ?? { videoId in
            try await client.post("next", body: ["videoId": videoId, "enablePersistentPlaylistPanel": true, "isAudioOnly": true])
        }
        restore()
    }

    func search(_ query: String) async throws -> SearchResults {
        async let songsResponse = client.post("search", body: ["query": query, "params": Self.songsFilter])
        async let mixedResponse = client.post("search", body: ["query": query])
        var results = SearchParser.browseItems(from: try await mixedResponse.value)
        results.songs = SearchParser.tracks(from: try await songsResponse.value)
        ImageCache.shared.prefetch(
            [results.top?.artworkURL] + results.songs.prefix(12).map(\.artworkURL)
                + (results.artists + results.albums + results.playlists).prefix(12).map(\.artworkURL)
        )
        return results
    }

    /// Synchronous cache reads, so screens can render cached content on their first frame
    /// instead of flashing a spinner.
    var cachedHome: [HomeSection]? { homeCache?.sections }
    var cachedLibrary: LibraryContent? { libraryCache?.content }
    private(set) var cachedAccount: AccountInfo?
    func cachedPage(for item: BrowseItem) -> BrowsePage? { pageCache[item.id] }

    /// The home feed, cached briefly so returning to the root is instant. Shelves from the other
    /// channels on this login are appended after the active one's, labelled with the channel.
    func home(forceRefresh: Bool = false) async throws -> [HomeSection] {
        if !forceRefresh, let cached = homeCache, Date.now.timeIntervalSince(cached.fetched) < Self.homeTTL {
            return cached.sections
        }
        async let active = client.post("browse", body: ["browseId": "FEmusic_home"])
        async let info = try? account()
        var sections = SearchParser.home(from: try await active.value)
        if let others = await info?.alternatives, !others.isEmpty {
            for other in others {
                guard let response = try? await client.post("browse", body: ["browseId": "FEmusic_home"], pageIdOverride: .some(other.pageId)) else { continue }
                let extra = SearchParser.home(from: response.value).map { section in
                    HomeSection(title: "\(section.title) · \(other.name)", items: section.items)
                }
                sections.append(contentsOf: extra)
            }
        }
        homeCache = (sections, .now)
        persist()
        ImageCache.shared.prefetch(sections.prefix(3).flatMap { section in
            section.items.prefix(10).map { item -> URL? in
                switch item {
                case .track(let t): t.artworkURL
                case .browse(let b): b.artworkURL
                }
            }
        })
        return sections
    }

    /// Which Google account the API is answering for, and the other channels on the login.
    /// The menu endpoint names the active account; the switchable channels only appear in the
    /// separate accounts list.
    func account() async throws -> AccountInfo? {
        async let menu = client.post("account/account_menu", body: [:])
        async let list = client.post("account/accounts_list", body: [:])
        guard var info = SearchParser.account(from: try await menu.value) else { return nil }
        info.alternatives = SearchParser.accountAlternatives(from: try await list.value)
        cachedAccount = info
        persist()
        return info
    }

    /// Switch to another account on this login and forget everything cached for the old one.
    func switchAccount(pageId: String?) {
        client.pageId = pageId
        pageCache = [:]
        homeCache = nil
        libraryCache = nil
        cachedAccount = nil
        try? FileManager.default.removeItem(at: Self.persistedURL)
        accountGeneration += 1
    }

    /// Signed out: no account, nothing cached for it.
    func signedOut() { switchAccount(pageId: nil) }

    /// Bumps whenever the account changes, so screens can reload.
    private(set) var accountGeneration = 0

    /// The signed-in library: playlists (with Liked Music first), saved albums, and artists.
    func library(forceRefresh: Bool = false) async throws -> LibraryContent {
        if !forceRefresh, let cached = libraryCache, Date.now.timeIntervalSince(cached.fetched) < Self.homeTTL {
            Self.prefetchArtwork(of: cached.content)
            return cached.content
        }
        async let playlists = client.post("browse", body: ["browseId": "FEmusic_liked_playlists"])
        async let albums = client.post("browse", body: ["browseId": "FEmusic_liked_albums"])
        async let artists = client.post("browse", body: ["browseId": "FEmusic_library_corpus_track_artists"])
        // Artists you've subscribed to live under a separate id from artists of saved tracks.
        async let subscriptions = client.post("browse", body: ["browseId": "FEmusic_library_corpus_artists"])
        var content = LibraryContent()
        // The playlists feed includes a "New playlist" tile and the liked-music auto playlist;
        // drop anything without a real playlist id and make sure Liked Music leads.
        var lists = SearchParser.libraryItems(from: try await playlists.value).filter { $0.kind == .playlist && $0.id != "VLSE" }
        if let liked = lists.firstIndex(where: { $0.id == "VLLM" }) {
            lists.insert(lists.remove(at: liked), at: 0)
        } else {
            lists.insert(BrowseItem(id: "VLLM", kind: .playlist, title: "Liked Music", subtitle: "Auto playlist", artworkURL: nil), at: 0)
        }
        content.playlists = lists
        content.albums = SearchParser.libraryItems(from: try await albums.value).filter { $0.kind == .album }
        var seenArtists = Set<String>()
        content.artists = (SearchParser.libraryItems(from: try await artists.value) + SearchParser.libraryItems(from: try await subscriptions.value))
            .filter { $0.kind == .artist && seenArtists.insert($0.id).inserted }
        libraryCache = (content, .now)
        persist()
        Self.prefetchArtwork(of: content)
        ImageCache.shared.prefetch((content.playlists + content.albums + content.artists).prefix(24).map(\.artworkURL))
        return content
    }

    /// Artist/album links for a track that arrived without them (home feed, radio continuation).
    func links(forVideoId videoId: String) async throws -> TrackLinks? {
        SearchParser.links(from: try await fetchNext(videoId).value, videoId: videoId)
    }

    /// Links looked up for rows that arrived without them, by video id. A lookup that found
    /// nothing is kept too (all nil), so the same song isn't asked about again.
    private(set) var resolvedLinks: [String: TrackLinks] = [:]
    @ObservationIgnored private var linkTasks: [String: Task<Void, Never>] = [:]

    /// Looks up a song's artist and album ahead of its menu, which can't wait on the network
    /// while it's open. Once per song: nothing happens if the row already has both ids or the
    /// lookup is done or in flight. A failed request isn't kept, so a later hover tries again.
    /// Returns the lookup in flight, if any, for tests to wait on.
    @discardableResult
    func warmLinks(for track: Track) -> Task<Void, Never>? {
        guard track.artistId == nil || track.albumId == nil, resolvedLinks[track.id] == nil else { return nil }
        if let inFlight = linkTasks[track.id] { return inFlight }
        let task = Task {
            do {
                resolvedLinks[track.id] = try await links(forVideoId: track.id) ?? TrackLinks()
            } catch {}
            linkTasks[track.id] = nil
        }
        linkTasks[track.id] = task
        return task
    }

    /// The song with any ids its row lacked filled in from a finished lookup, so its menu
    /// offers Go to Artist and Go to Album and they lead somewhere.
    func withLinks(_ track: Track) -> Track {
        guard let links = resolvedLinks[track.id] else { return track }
        var filled = track
        if filled.artistId == nil, let artistId = links.artistId {
            filled.artistId = artistId
            if filled.artist.isEmpty, let artist = links.artist { filled.artist = artist }
        }
        if filled.albumId == nil, let albumId = links.albumId {
            filled.albumId = albumId
            if filled.album == nil { filled.album = links.album }
        }
        return filled
    }

    /// The library changes rarely and is bounded, so every cover is fetched and decoded ahead
    /// of the scroll, not the first dozen: a fast scroll then finds them all in memory.
    private static func prefetchArtwork(of content: LibraryContent) {
        ImageCache.shared.prefetch((content.playlists + content.albums + content.artists).map(\.artworkURL))
    }

    /// Whether an album or playlist is in the library, as far as the cached library knows.
    func isSaved(_ item: BrowseItem) -> Bool {
        guard let library = libraryCache?.content else { return false }
        return (library.albums + library.playlists).contains { $0.id == item.id }
    }

    /// Adds the page's album or playlist to the library, or removes it. YouTube Music's library
    /// membership for both is the playlist "like", keyed by the playlist id (an album's audio
    /// playlist). The cached library is updated at once so the button and the library page agree
    /// without a refetch.
    func setSaved(_ saved: Bool, page: BrowsePage) async throws {
        guard let playlistId = page.playlistId else { throw URLError(.badURL) }
        _ = try await write(saved ? "like/like" : "like/removelike", ["target": ["playlistId": playlistId]])
        var content = libraryCache?.content ?? LibraryContent()
        let remove: (inout [BrowseItem]) -> Void = { $0.removeAll { $0.id == page.item.id } }
        remove(&content.albums); remove(&content.playlists)
        if saved {
            if page.item.kind == .album { content.albums.insert(page.item, at: 0) } else { content.playlists.insert(page.item, at: 0) }
        }
        libraryCache = (content, libraryCache?.fetched ?? .now)
        persist()
    }

    /// Likes changed in Lilt since the pages showing them were fetched, by video id.
    private(set) var likeChanges: [String: Bool] = [:]

    /// Whether a song is liked, counting changes made since its row was fetched.
    func isLiked(_ track: Track) -> Bool? { likeChanges[track.id] ?? track.isLiked }

    /// Likes or unlikes a song. Rows answer at once; a failed call puts them back.
    func setLiked(_ liked: Bool, track: Track) async throws {
        let before = likeChanges[track.id]
        likeChanges[track.id] = liked
        do {
            _ = try await write(liked ? "like/like" : "like/removelike", ["target": ["videoId": track.id]])
        } catch {
            likeChanges[track.id] = before
            throw error
        }
    }

    /// Records a like made another way (the playing track's own heart), so rows agree.
    func noteLiked(_ liked: Bool, track: Track) { likeChanges[track.id] = liked }

    /// Your own playlists, for Add to Playlist. Fetched once, ahead of the first menu that
    /// needs them (a menu can't wait on the network while it's open).
    private(set) var ownPlaylists: [OwnPlaylist] = []
    @ObservationIgnored private var ownPlaylistsTask: Task<Void, Never>?

    /// Starts fetching your playlists if nothing has yet. The dialog's request is keyed by a
    /// song, but the playlists it lists are the same for any song.
    func warmOwnPlaylists(videoId: String) {
        guard ownPlaylists.isEmpty, ownPlaylistsTask == nil else { return }
        ownPlaylistsTask = Task {
            if let response = try? await write("playlist/get_add_to_playlist", ["videoIds": [videoId]]) {
                ownPlaylists = SearchParser.ownPlaylists(from: response.value)
            }
            ownPlaylistsTask = nil
        }
    }

    /// Playlists each song or list has been added to from Lilt (or turned out to be in already),
    /// by video or browse id, so the menu can tick them.
    private(set) var addedTo: [String: Set<String>] = [:]

    /// A song that went into one of your playlists, by the entry the playlist gave it, so it can
    /// be taken out again.
    struct AddedSong: Hashable, Sendable {
        var videoId: String
        var entry: PlaylistEntry
    }

    /// Adds a song to one of your playlists. A song that's already there is left alone; that
    /// counts as done too. Returns what went in (nothing, when it was there already).
    @discardableResult
    func add(_ track: Track, to playlist: OwnPlaylist) async throws -> [AddedSong] {
        try await add(["action": "ACTION_ADD_VIDEO", "addedVideoId": track.id, "dedupeOption": "DEDUPE_OPTION_SKIP"], key: track.id, to: playlist)
    }

    /// Adds every song of an album or playlist to one of yours.
    @discardableResult
    func add(_ item: BrowseItem, to playlist: OwnPlaylist) async throws -> [AddedSong] {
        var page = cachedPage(for: item)
        if page == nil { page = try await self.page(for: item) }
        guard let listId = page?.playlistId else { throw URLError(.badURL) }
        return try await add(["action": "ACTION_ADD_PLAYLIST", "addedFullListId": listId, "dedupeOption": "DEDUPE_OPTION_SKIP"], key: item.id, to: playlist)
    }

    private func add(_ action: [String: Any], key: String, to playlist: OwnPlaylist) async throws -> [AddedSong] {
        let response = try await write("browse/edit_playlist", ["playlistId": playlist.id, "actions": [action]])
        addedTo[key, default: []].insert(playlist.id)
        return Self.addedSongs(in: response.value, playlistId: playlist.id)
    }

    /// The entries an edit_playlist add reports: one `playlistEditVideoAddedResultData` per song
    /// that went in, with the `setVideoId` the playlist now knows it by.
    static func addedSongs(in response: [String: Any], playlistId: String) -> [AddedSong] {
        (JSON.array(response["playlistEditResults"]) ?? []).compactMap { result in
            let data = JSON.dict(JSON.dict(result)?["playlistEditVideoAddedResultData"])
            guard let videoId = JSON.string(data?["videoId"]), let setVideoId = JSON.string(data?["setVideoId"]) else { return nil }
            return AddedSong(videoId: videoId, entry: PlaylistEntry(playlistId: playlistId, setVideoId: setVideoId))
        }
    }

    /// Takes back an add: the songs it put in come out, in one edit, and the menu stops ticking
    /// the playlist for `key`.
    func undoAdd(_ songs: [AddedSong], key: String, from playlist: OwnPlaylist) async throws {
        guard !songs.isEmpty else { return }
        _ = try await write("browse/edit_playlist", [
            "playlistId": playlist.id,
            "actions": songs.map { ["action": "ACTION_REMOVE_VIDEO", "setVideoId": $0.entry.setVideoId, "removedVideoId": $0.videoId] },
        ])
        addedTo[key]?.remove(playlist.id)
    }

    /// Playlist entries removed in Lilt since their pages were fetched.
    private(set) var removedEntries: Set<PlaylistEntry> = []

    /// Whether a song's row has been removed from the playlist it was fetched in.
    func isRemoved(_ track: Track) -> Bool { track.playlistEntry.map(removedEntries.contains) ?? false }

    /// Takes a song out of one of your playlists. The row goes at once; a failed call brings it back.
    func removeFromPlaylist(_ track: Track) async throws {
        guard let entry = track.playlistEntry else { return }
        removedEntries.insert(entry)
        do {
            _ = try await write("browse/edit_playlist", [
                "playlistId": entry.playlistId,
                "actions": [["action": "ACTION_REMOVE_VIDEO", "setVideoId": entry.setVideoId, "removedVideoId": track.id]],
            ])
        } catch {
            removedEntries.remove(entry)
            throw error
        }
    }

    /// Always asks the server: a playlist can change elsewhere (a song liked on the phone), and
    /// the cached copy is only for `cachedPage(for:)` to draw a first frame from.
    func page(for item: BrowseItem) async throws -> BrowsePage {
        let response = try await fetchPage(item.id)
        let page = SearchParser.browsePage(from: response.value, for: item)
        pageCache[item.id] = page
        ImageCache.shared.prefetch(
            [page.item.artworkURL] + page.tracks.prefix(20).map(\.artworkURL)
                + page.sections.flatMap { $0.items.prefix(8).map(\.artworkURL) }
        )
        return page
    }
}
