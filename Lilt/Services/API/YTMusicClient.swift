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
    /// Fetches the next page of a long list by its continuation token. Tests stand in here.
    @ObservationIgnored private let fetchContinuation: @MainActor (_ token: String) async throws -> JSONObject
    /// Calls that change the account (likes, playlist edits), standable in for by tests.
    @ObservationIgnored private let write: @MainActor (_ endpoint: String, _ body: [String: Any]) async throws -> JSONObject
    /// Fetches the up-next panel for a video, which names its artist and album. Tests stand in here.
    @ObservationIgnored private let fetchNext: @MainActor (_ videoId: String) async throws -> JSONObject
    /// Fetches a watch playlist's queue panel by its id (and the song it grows from, for a
    /// song's mix). Read-only; tests stand in here.
    @ObservationIgnored private let fetchWatch: @MainActor (_ playlistId: String, _ videoId: String?) async throws -> JSONObject
    @ObservationIgnored private var pageCache: [String: BrowsePage] = [:]
    /// When each kept page was last known to match the server, read against `now()`. A page
    /// without one (never fetched whole, or Liked Music after a like) is due.
    @ObservationIgnored private var pageFetched: [String: Date] = [:]
    @ObservationIgnored private var homeCache: (sections: [HomeSection], fetched: Date)?
    @ObservationIgnored private var libraryCache: (content: LibraryContent, fetched: Date)?
    /// The library fetch on its way, which another ask for the library joins.
    @ObservationIgnored private var libraryFetch: Task<LibraryContent, Error>?
    /// Which account the API answers for. Tests stand in here.
    @ObservationIgnored private let fetchAccount: (@MainActor () async throws -> AccountInfo?)?
    /// Fetches a home feed: the selected account's for nil, else the channel with that page id
    /// (`.some(nil)` the primary account). Tests stand in here.
    @ObservationIgnored private let fetchHome: @MainActor (_ pageId: String??) async throws -> JSONObject
    /// Runs a search: the query, and the filter it's narrowed by (nil for every kind). Tests
    /// stand in here.
    @ObservationIgnored private let fetchSearch: @MainActor (_ query: String, _ params: String?) async throws -> JSONObject
    /// Whether the caches come from and go to disk. Tests keep everything in memory.
    @ObservationIgnored private let persists: Bool

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
        guard persists else { return }
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
    /// How long a page opened again is shown as kept, with nothing asked for.
    private static let pageTTL: TimeInterval = homeTTL

    init(
        auth: AuthService,
        fetchPage: (@MainActor (_ browseId: String) async throws -> JSONObject)? = nil,
        fetchContinuation: (@MainActor (_ token: String) async throws -> JSONObject)? = nil,
        write: (@MainActor (_ endpoint: String, _ body: [String: Any]) async throws -> JSONObject)? = nil,
        fetchNext: (@MainActor (_ videoId: String) async throws -> JSONObject)? = nil,
        fetchWatch: (@MainActor (_ playlistId: String, _ videoId: String?) async throws -> JSONObject)? = nil,
        persists: Bool = true,
        library: LibraryContent? = nil,
        fetchAccount: (@MainActor () async throws -> AccountInfo?)? = nil,
        fetchHome: (@MainActor (_ pageId: String??) async throws -> JSONObject)? = nil,
        fetchSearch: (@MainActor (_ query: String, _ params: String?) async throws -> JSONObject)? = nil
    ) {
        let client = InnerTubeClient(auth: auth)
        self.client = client
        self.fetchSearch = fetchSearch ?? { query, params in
            var body: [String: Any] = ["query": query]
            if let params { body["params"] = params }
            return try await client.post("search", body: body)
        }
        self.fetchHome = fetchHome ?? { pageId in
            try await client.post("browse", body: ["browseId": "FEmusic_home"], pageIdOverride: pageId)
        }
        self.fetchPage = fetchPage ?? { browseId in try await client.post("browse", body: ["browseId": browseId]) }
        self.fetchContinuation = fetchContinuation ?? { token in try await client.post("browse", body: ["continuation": token]) }
        self.write = write ?? { endpoint, body in try await client.post(endpoint, body: body) }
        self.fetchNext = fetchNext ?? { videoId in
            try await client.post("next", body: ["videoId": videoId, "enablePersistentPlaylistPanel": true, "isAudioOnly": true])
        }
        // As ytmusicapi's get_watch_playlist(radio=True) asks: the playlist id, "wAEB" for a
        // radio, the persistent queue panel, audio only.
        self.fetchWatch = fetchWatch ?? { playlistId, videoId in
            var body: [String: Any] = [
                "playlistId": playlistId, "params": "wAEB",
                "enablePersistentPlaylistPanel": true, "isAudioOnly": true, "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
            ]
            if let videoId { body["videoId"] = videoId }
            return try await client.post("next", body: body)
        }
        self.persists = persists
        self.fetchAccount = fetchAccount
        if persists { restore() }
        if let library { libraryCache = (library, .now) }
    }

    func search(_ query: String) async throws -> SearchResults {
        async let songsResponse = fetchSearch(query, Self.songsFilter)
        async let mixedResponse = fetchSearch(query, nil)
        let results = await Self.readSearch(mixed: try await mixedResponse, songs: try await songsResponse)
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
        // The other channels' feeds set off as soon as the account names them, alongside the
        // active one and each other; one that fails is left out.
        let others = Task { [weak self] () -> [HomeSection] in
            guard let self else { return [] }
            let channels = (try? await account())?.alternatives ?? []
            let feeds = channels.map { channel in Task { await self.homeSections(of: channel) } }
            var sections: [HomeSection] = []
            for feed in feeds { sections += await feed.value }
            return sections
        }
        let active: JSONObject
        do { active = try await fetchHome(nil) } catch { others.cancel(); throw error }
        var sections = await Self.readHome(active)
        sections.append(contentsOf: await others.value)
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

    /// Another channel's home shelves, each labelled with its name; none if it couldn't load.
    private func homeSections(of channel: AccountInfo.Alternative) async -> [HomeSection] {
        guard let response = try? await fetchHome(.some(channel.pageId)) else { return [] }
        return await Self.readHome(response).map { section in
            HomeSection(title: "\(section.title) · \(channel.name)", items: section.items)
        }
    }

    /// Which Google account the API is answering for, and the other channels on the login.
    /// The menu endpoint names the active account; the switchable channels only appear in the
    /// separate accounts list.
    func account() async throws -> AccountInfo? {
        let info = if let fetchAccount { try await fetchAccount() } else { try await fetchAccountFromAPI() }
        if let info {
            cachedAccount = info
            persist()
        }
        return info
    }

    private func fetchAccountFromAPI() async throws -> AccountInfo? {
        async let menu = client.post("account/account_menu", body: [:])
        async let list = client.post("account/accounts_list", body: [:])
        return await Self.readAccount(menu: try await menu, list: try await list)
    }

    // Responses read off the main actor, like a page's (see `read(_:for:)`): a search is two
    // responses walked whole, and home a dozen shelves of tiles.

    @concurrent private nonisolated static func readSearch(mixed: JSONObject, songs: JSONObject) async -> SearchResults {
        var results = SearchParser.browseItems(from: mixed.value)
        results.songs = SearchParser.tracks(from: songs.value)
        return results
    }

    @concurrent private nonisolated static func readHome(_ response: JSONObject) async -> [HomeSection] {
        SearchParser.home(from: response.value)
    }

    @concurrent private nonisolated static func readAccount(menu: JSONObject, list: JSONObject) async -> AccountInfo? {
        guard var info = SearchParser.account(from: menu.value) else { return nil }
        info.alternatives = SearchParser.accountAlternatives(from: list.value)
        return info
    }

    /// Switch to another account on this login and forget everything cached for the old one.
    func switchAccount(pageId: String?) {
        client.pageId = pageId
        pageCache = [:]
        pageFetched = [:]
        // A page on its way is the old account's; a new ask mustn't join it.
        pageFetches = [:]
        homeCache = nil
        libraryCache = nil
        // The old account's library mustn't be what the new one's screen joins.
        libraryFetch?.cancel()
        libraryFetch = nil
        cachedAccount = nil
        ownPlaylists = []
        ownPlaylistsTask = nil
        ownPlaylistsFetched = nil
        addedTo = [:]
        if persists { try? FileManager.default.removeItem(at: Self.persistedURL) }
        accountGeneration += 1
    }

    /// Signed out: no account, nothing cached for it.
    func signedOut() { switchAccount(pageId: nil) }

    /// Bumps whenever the account changes, so screens can reload.
    private(set) var accountGeneration = 0

    /// The signed-in library: playlists (with Liked Music first), saved albums, and artists.
    /// Asked for while a fetch is on its way (the library button's hover, then the screen it
    /// opens), it waits for that fetch rather than fetching, parsing and saving it all again; a
    /// refresh asked for fetches anyway.
    func library(forceRefresh: Bool = false) async throws -> LibraryContent {
        if !forceRefresh, let cached = libraryCache, Date.now.timeIntervalSince(cached.fetched) < Self.homeTTL {
            Self.prefetchArtwork(of: cached.content)
            return cached.content
        }
        if !forceRefresh, let libraryFetch { return try await libraryFetch.value }
        let fetch = Task { try await fetchLibrary() }
        libraryFetch = fetch
        defer { if libraryFetch == fetch { libraryFetch = nil } }
        return try await fetch.value
    }

    /// One of the library's feeds with every page of it, `pageLimit` pages more at most, or why
    /// its first page couldn't be had. A later page failing keeps the pages before it, and the
    /// feed isn't complete.
    private func feed(_ browseId: String) async -> Result<LibraryFeed, Error> {
        let first: JSONObject
        do { first = try await fetchPage(browseId) } catch { return .failure(error) }
        var (items, token) = await Self.readLibraryPage(first)
        var feed = LibraryFeed(pages: [items])
        var asked = Set<String>()
        while let next = token, asked.count < Self.pageLimit, asked.insert(next).inserted {
            guard let page = try? await fetchContinuation(next) else {
                feed.isComplete = false
                break
            }
            (items, token) = await Self.readLibraryPage(page)
            feed.pages.append(items)
        }
        return .success(feed)
    }

    /// A library page's items and the token for the page after it, read off the main actor:
    /// both walk the whole response, and a library opening reads a few dozen of them.
    @concurrent private nonisolated static func readLibraryPage(_ response: JSONObject) async -> (items: [BrowseItem], token: String?) {
        (SearchParser.libraryItems(from: response.value), SearchParser.libraryContinuationToken(in: response.value))
    }

    private struct LibraryFeed {
        /// Each page's items, as read.
        var pages: [[BrowseItem]]
        var isComplete = true

        /// The items of every page, each once.
        var items: [BrowseItem] {
            var seen = Set<String>()
            return pages.joined().filter { seen.insert($0.id).inserted }
        }
    }

    /// A feed that fails leaves its shelf as it was (or empty, with nothing before) and the
    /// library stale, so the next ask fetches it again; only every feed failing is a failure.
    private func fetchLibrary() async throws -> LibraryContent {
        async let playlistsFeed = feed("FEmusic_liked_playlists")
        async let albumsFeed = feed("FEmusic_liked_albums")
        async let artistsFeed = feed("FEmusic_library_corpus_track_artists")
        // Artists you've subscribed to live under a separate id from artists of saved tracks.
        async let subscriptionsFeed = feed("FEmusic_library_corpus_artists")
        let feeds = await [playlistsFeed, albumsFeed, artistsFeed, subscriptionsFeed]
        let responses = feeds.map { try? $0.get() }
        if responses.allSatisfy({ $0 == nil }), case .failure(let error) = feeds[0] { throw error }
        let (playlists, albums, artists, subscriptions) = (responses[0], responses[1], responses[2], responses[3])
        let before = libraryCache?.content
        var content = LibraryContent()
        // The playlists feed includes a "New playlist" tile and the liked-music auto playlist;
        // drop anything without a real playlist id and make sure Liked Music leads.
        var lists = playlists.map { $0.items.filter { $0.kind == .playlist && $0.id != "VLSE" } } ?? before?.playlists ?? []
        if let liked = lists.firstIndex(where: { $0.id == "VLLM" }) {
            lists.insert(lists.remove(at: liked), at: 0)
        } else {
            lists.insert(BrowseItem(id: "VLLM", kind: .playlist, title: "Liked Music", subtitle: "Auto playlist", artworkURL: nil), at: 0)
        }
        content.playlists = lists
        content.albums = albums.map { $0.items.filter { $0.kind == .album } } ?? before?.albums ?? []
        if let artists, let subscriptions {
            var seenArtists = Set<String>()
            content.artists = (artists.items + subscriptions.items)
                .filter { $0.kind == .artist && seenArtists.insert($0.id).inserted }
        } else {
            content.artists = before?.artists ?? ([artists, subscriptions].compactMap { $0 }.flatMap(\.items).filter { $0.kind == .artist })
        }
        let complete = responses.allSatisfy { $0?.isComplete == true }
        libraryCache = (content, complete ? .now : .distantPast)
        persist()
        Self.prefetchArtwork(of: content)
        ImageCache.shared.prefetch((content.playlists + content.albums + content.artists).prefix(24).map(\.artworkURL))
        return content
    }

    /// Artist/album links for a track that arrived without them (home feed, radio continuation):
    /// the ones already looked up, or the lookup on its way, which a row's warming shares.
    func links(forVideoId videoId: String) async throws -> TrackLinks? {
        if let known = resolvedLinks[videoId] { return known }
        return try await linkLookup(videoId).value
    }

    // MARK: Mixes

    /// A song's mix: the RDAMVM watch playlist seeded by it, which YouTube Music starts with
    /// the song itself.
    static func mixId(forSong videoId: String) -> String { "RDAMVM" + videoId }

    /// An album's or playlist's mix: RDAMPL plus the playlist (an album's audio playlist,
    /// OLAK5uy…; a playlist's id without its VL browse prefix). An id that is a mix already
    /// is left as it is.
    static func mixId(forList playlistId: String) -> String {
        let id = playlistId.hasPrefix("VL") ? String(playlistId.dropFirst(2)) : playlistId
        return id.hasPrefix("RDAM") || id.hasPrefix("RDEM") ? id : "RDAMPL" + id
    }

    /// The mix id for a page: an artist's from its Mix button, an album's or playlist's from
    /// the playlist behind it. Nil when the page didn't say.
    static func mixId(for page: BrowsePage) -> String? {
        switch page.item.kind {
        case .artist: page.radioId
        case .album, .playlist: page.playlistId.map(mixId(forList:))
        case .library: nil
        }
    }

    /// The first page of a song's mix.
    func mix(for track: Track) async throws -> Mix {
        try await mix(playlistId: Self.mixId(forSong: track.id), videoId: track.id)
    }

    /// The first page of an album's, playlist's or artist's mix. A playlist's id is in its
    /// browse id; albums and artists need their page (cached when it's been seen).
    func mix(for item: BrowseItem) async throws -> Mix {
        var id: String?
        if item.kind == .playlist, item.id.hasPrefix("VL") {
            id = Self.mixId(forList: item.id)
        } else if item.kind != .library {
            if let cached = cachedPage(for: item) { id = Self.mixId(for: cached) }
            if id == nil { id = Self.mixId(for: try await page(for: item)) }
        }
        guard let id else { throw URLError(.resourceUnavailable) }
        return try await mix(playlistId: id, videoId: nil)
    }

    private func mix(playlistId: String, videoId: String?) async throws -> Mix {
        let response = try await fetchWatch(playlistId, videoId)
        guard let mix = SearchParser.mix(from: response.value, playlistId: playlistId), !mix.tracks.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        ImageCache.shared.prefetch(mix.tracks.prefix(12).map(\.artworkURL))
        return mix
    }

    /// Links looked up for rows that arrived without them, by video id. A lookup that found
    /// nothing is kept too (all nil), so the same song isn't asked about again.
    private(set) var resolvedLinks: [String: TrackLinks] = [:]
    @ObservationIgnored private var linkTasks: [String: Task<TrackLinks?, Error>] = [:]

    /// Looks up a song's artist and album ahead of its menu, which can't wait on the network
    /// while it's open. Once per song: nothing happens if the row already has both ids or the
    /// lookup is done or in flight. A failed request isn't kept, so a later hover tries again.
    /// Returns the lookup in flight, if any, for tests to wait on.
    @discardableResult
    func warmLinks(for track: Track) -> Task<Void, Never>? {
        guard track.artistId == nil || track.albumId == nil, resolvedLinks[track.id] == nil else { return nil }
        let lookup = linkLookup(track.id)
        return Task { _ = try? await lookup.value }
    }

    /// A song's links from `next`, kept once found; the one lookup on its way is joined.
    private func linkLookup(_ videoId: String) -> Task<TrackLinks?, Error> {
        if let inFlight = linkTasks[videoId] { return inFlight }
        let task = Task {
            defer { linkTasks[videoId] = nil }
            let links = SearchParser.links(from: try await fetchNext(videoId).value, videoId: videoId)
            resolvedLinks[videoId] = links ?? TrackLinks()
            return links
        }
        linkTasks[videoId] = task
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
        // The song now leads Liked Music, which the kept copy doesn't show, so the next visit
        // asks again. An unlike needs nothing: `isLiked` already hides the row.
        if liked { for id in Self.likedMusicIds { pageFetched[id] = nil } }
    }

    /// Liked Music's browse id and its playlist id.
    private static let likedMusicIds = ["VLLM", "LM"]

    /// Records a like made another way (the playing track's own heart), so rows agree.
    func noteLiked(_ liked: Bool, track: Track) { likeChanges[track.id] = liked }

    /// Your own playlists, for Add to Playlist. Fetched ahead of the menus that need them (a
    /// menu can't wait on the network while it's open), and again once they're a few minutes
    /// old, so a playlist made on the phone turns up while Lilt is still running.
    private(set) var ownPlaylists: [OwnPlaylist] = []
    @ObservationIgnored private var ownPlaylistsTask: Task<Void, Never>?
    @ObservationIgnored private var ownPlaylistsFetched: Date?
    private static let ownPlaylistsTTL: TimeInterval = 5 * 60

    /// Starts fetching your playlists unless a fetch is under way or the list is fresh. The
    /// dialog's request is keyed by a song, but the playlists it lists are the same for any
    /// song. The list there is stays in the menu until the new one is in.
    func warmOwnPlaylists(videoId: String, now: Date = .now) {
        guard ownPlaylistsTask == nil else { return }
        if let fetched = ownPlaylistsFetched, now.timeIntervalSince(fetched) < Self.ownPlaylistsTTL { return }
        let generation = accountGeneration
        ownPlaylistsTask = Task {
            let response = try? await write("playlist/get_add_to_playlist", ["videoIds": [videoId]])
            // Asked for the account before a switch: its playlists aren't this one's.
            guard generation == accountGeneration else { return }
            if let response {
                ownPlaylists = SearchParser.ownPlaylists(from: response.value)
                ownPlaylistsFetched = now
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

    /// The clock the kept pages' ages are read against; tests set their own.
    @ObservationIgnored var now: () -> Date = { .now }

    /// A page opened again. One fetched in the last five minutes is the kept copy, with nothing
    /// asked for. After that only its first page is asked for, and a first page whose songs are
    /// as they were keeps the rest of the kept list, under the first page's header (Liked Music
    /// is newest first, so a song liked on the phone shows there). A changed
    /// first page with a longer list kept gathers the whole list again before it's returned, so
    /// a list on screen never shrinks to regrow; with nothing longer kept, the first page is
    /// returned and the screen gathers the rest as it shows it. `forceRefresh`, a refresh you
    /// asked for, always gathers the whole list afresh.
    func revisitedPage(for item: BrowseItem, forceRefresh: Bool = false) async throws -> BrowsePage {
        if !forceRefresh, let kept = pageCache[item.id], let fetched = pageFetched[item.id],
           now().timeIntervalSince(fetched) < Self.pageTTL {
            return kept
        }
        let first = try await page(for: item)
        guard first.continuation != nil else { return first }
        let kept = pageCache[item.id]
        let keptIsLonger = (kept?.tracks.count ?? 0) > first.tracks.count
        if !forceRefresh, let kept, keptIsLonger,
           kept.tracks.prefix(first.tracks.count).map(\.rowId) == first.tracks.map(\.rowId) {
            var renewed = first
            renewed.tracks = kept.tracks
            renewed.continuation = kept.continuation
            pageCache[item.id] = renewed
            pageFetched[item.id] = now()
            return renewed
        }
        guard forceRefresh || keptIsLonger else { return first }
        let whole = try await wholeList(from: first)
        pageFetched[item.id] = now()
        return whole
    }

    /// Browse pages on their way, by id, which another ask for the same page joins.
    @ObservationIgnored private var pageFetches: [String: Task<BrowsePage, Error>] = [:]

    /// The first page from the server, for a page warmed ahead of opening, an artist's releases
    /// beside an album, or `revisitedPage(for:)` to judge a kept list by. It's kept for
    /// `cachedPage(for:)` to draw a first frame from, unless a longer list is kept and the first
    /// page still has more to come: page one alone never replaces the rest, which
    /// `revisitedPage(for:)` keeps or gathers again. An ask for a page already on its way (a hover
    /// warming it, then the page opening) joins that request rather than making another; a
    /// failed one isn't kept, so the next ask tries again.
    func page(for item: BrowseItem) async throws -> BrowsePage {
        if let inFlight = pageFetches[item.id] { return try await inFlight.value }
        let generation = accountGeneration
        let task = Task {
            defer { if generation == accountGeneration { pageFetches[item.id] = nil } }
            let response = try await fetchPage(item.id)
            let page = await Self.read(response, for: item)
            if generation == accountGeneration {
                let keptIsLonger = (pageCache[item.id]?.tracks.count ?? 0) > page.tracks.count
                if !keptIsLonger || page.continuation == nil {
                    pageCache[item.id] = page
                    pageFetched[item.id] = now()
                }
            }
            ImageCache.shared.prefetch(
                [page.item.artworkURL] + page.tracks.prefix(20).map(\.artworkURL)
                    + page.sections.flatMap { $0.items.prefix(8).map(\.artworkURL) }
            )
            return page
        }
        pageFetches[item.id] = task
        return try await task.value
    }

    /// The most pages a list is followed for: thousands of songs at a hundred a page, and an
    /// end to a server that never stops handing out tokens.
    static let pageLimit = 100

    /// The page with its next page of songs added, and the token for the one after (nil at the
    /// end). Cached whole, so going back draws as much of the list as has come in. A server
    /// that hands back the token it was asked with has nothing more to give.
    func nextPage(of page: BrowsePage) async throws -> BrowsePage {
        guard let token = page.continuation else { return page }
        let response = try await fetchContinuation(token)
        var next = await Self.read(response, after: page)
        if next.continuation == token { next.continuation = nil }
        pageCache[page.item.id] = next
        return next
    }

    /// A page read from its response, off the main actor: walking a big list's JSON held the
    /// main thread for hundreds of milliseconds, a frozen scroll for every page warmed under it.
    @concurrent private nonisolated static func read(_ response: JSONObject, for item: BrowseItem) async -> BrowsePage {
        SearchParser.browsePage(from: response.value, for: item)
    }

    /// The page with a continuation's songs added and its token for the page after, read off
    /// the main actor like a first page.
    @concurrent private nonisolated static func read(_ response: JSONObject, after page: BrowsePage) async -> BrowsePage {
        var next = page
        SearchParser.appendTracks(in: response.value, to: &next)
        next.continuation = SearchParser.continuationToken(in: response.value)
        return next
    }

    /// The page with the rest of its list gathered, `pageLimit` pages more at most.
    func wholeList(from page: BrowsePage) async throws -> BrowsePage {
        var page = page
        var pages = 0
        while page.continuation != nil, pages < Self.pageLimit {
            try Task.checkCancellation()
            page = try await nextPage(of: page)
            pages += 1
        }
        return page
    }

    /// The page with every one of its songs, for playing a list without opening it.
    func fullPage(for item: BrowseItem) async throws -> BrowsePage {
        try await wholeList(from: page(for: item))
    }
}
