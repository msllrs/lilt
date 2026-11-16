import Foundation

/// Turns InnerTube responses into `Track`s and `BrowseItem`s. Tolerant by design: it collects
/// renderers wherever they appear in the payload, so shelf reshuffles on YouTube's side don't
/// break it.
enum SearchParser {
    // MARK: Songs

    static func tracks(from response: [String: Any]) -> [Track] {
        var seen = Set<String>()
        var tracks: [Track] = []
        for item in JSON.findAll(key: "musicResponsiveListItemRenderer", in: response) {
            guard let track = track(from: item), seen.insert(track.id).inserted else { continue }
            tracks.append(track)
        }
        return tracks
    }

    static func track(from item: [String: Any]) -> Track? {
        let titleRuns = flexRuns(item, 0)
        guard let title = JSON.string(titleRuns.first?["text"]), !title.isEmpty else { return nil }

        let videoId = JSON.string(JSON.value(at: ["playlistItemData", "videoId"], in: item))
            ?? JSON.string(JSON.value(at: ["navigationEndpoint", "watchEndpoint", "videoId"], in: titleRuns.first))
            ?? JSON.string(JSON.value(at: [
                "overlay", "musicItemThumbnailOverlayRenderer", "content", "musicPlayButtonRenderer",
                "playNavigationEndpoint", "watchEndpoint", "videoId",
            ], in: item))
        guard let videoId else { return nil }

        let subtitle = flexRuns(item, 1)
        let artistRuns = subtitle.filter(isArtistRun)
        let albumRun = subtitle.first { pageType(of: $0) == "MUSIC_PAGE_TYPE_ALBUM" }
        let texts = subtitle.compactMap { JSON.string($0["text"]) }
        let fallbackArtist = texts.first { !$0.contains("•") && $0 != "Song" && $0 != "Video" }
        let fixed = JSON.string(JSON.value(at: [0, "musicResponsiveListItemFixedColumnRenderer", "text", "runs", 0, "text"], in: item["fixedColumns"]))
        let duration = fixed.flatMap { $0.wholeMatch(of: /\d+:\d{2}(:\d{2})?/) != nil ? $0 : nil }
            ?? texts.last { $0.wholeMatch(of: /\d+:\d{2}(:\d{2})?/) != nil }

        return Track(
            id: videoId,
            title: title,
            artist: artistRuns.isEmpty ? (fallbackArtist ?? "") : artistRuns.compactMap { JSON.string($0["text"]) }.joined(separator: ", "),
            album: albumRun.flatMap { JSON.string($0["text"]) },
            durationText: duration,
            artworkURL: thumbnail(in: item, size: 240),
            artistId: artistRuns.first.flatMap(browseId(of:)),
            albumId: albumRun.flatMap(browseId(of:)),
            isLiked: likeState(of: item),
            playlistEntry: playlistEntry(of: item),
            isExplicit: hasExplicitBadge(item["badges"]) ? true : nil,
            isUnavailable: JSON.string(item["musicItemRendererDisplayPolicy"]) == "MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT" ? true : nil
        )
    }

    /// Whether `badges` (a row's `badges`, a card's `subtitleBadges`) hold the explicit badge.
    static func hasExplicitBadge(_ badges: Any?) -> Bool {
        guard let badges else { return false }
        return JSON.findAll(key: "musicInlineBadgeRenderer", in: badges).contains {
            JSON.string(JSON.value(at: ["icon", "iconType"], in: $0)) == "MUSIC_EXPLICIT_BADGE"
        }
    }

    /// The playlists YouTube Music's "Save to playlist" dialog offers: the ones you can edit.
    /// YouTube's own lists, marked KEEP, are left out: "Episodes for Later" (SE) is for podcasts,
    /// and songs go into "Liked Music" (LM) by being liked.
    static func ownPlaylists(from response: [String: Any]) -> [OwnPlaylist] {
        JSON.findAll(key: "playlistAddToOptionRenderer", in: response).compactMap { option in
            let icons = JSON.array(option["additionalIcons"])?.compactMap(JSON.dict) ?? []
            guard !icons.contains(where: { JSON.string($0["iconType"]) == "KEEP" }),
                  let id = JSON.string(option["playlistId"]), id != "SE", id != "LM",
                  let title = runsText(JSON.value(at: ["title", "runs"], in: option)), !title.isEmpty else { return nil }
            return OwnPlaylist(id: id, title: title)
        }
    }

    /// Rows of a playlist you can edit carry their own "Remove from playlist" call; other
    /// playlists' rows don't, so its presence is what makes a song removable.
    static func playlistEntry(of item: [String: Any]) -> PlaylistEntry? {
        for edit in JSON.findAll(key: "playlistEditEndpoint", in: item) {
            guard let playlistId = JSON.string(edit["playlistId"]) else { continue }
            for action in JSON.array(edit["actions"])?.compactMap(JSON.dict) ?? [] where JSON.string(action["action"]) == "ACTION_REMOVE_VIDEO" {
                if let setVideoId = JSON.string(action["setVideoId"]) { return PlaylistEntry(playlistId: playlistId, setVideoId: setVideoId) }
            }
        }
        return nil
    }

    /// A row's like state. Playlist rows carry a like button with its status; search and other
    /// rows only carry the menu's liked-songs toggle, whose default action is what a click does:
    /// LIKE for a song you haven't liked, INDIFFERENT for one you have.
    static func likeState(of item: [String: Any]) -> Bool? {
        if let status = JSON.string(JSON.findAll(key: "likeButtonRenderer", in: item).first?["likeStatus"]) {
            return status == "LIKE"
        }
        for toggle in JSON.findAll(key: "toggleMenuServiceItemRenderer", in: item) {
            if let status = JSON.string(JSON.value(at: ["defaultServiceEndpoint", "likeEndpoint", "status"], in: toggle)) {
                return status != "LIKE"
            }
        }
        return nil
    }

    // MARK: Mixed search

    /// Parses an unfiltered search response into artists, albums and playlists (songs come from
    /// the dedicated songs-filtered request, which returns a full list rather than three).
    static func browseItems(from response: [String: Any]) -> SearchResults {
        var results = SearchResults()
        var seen = Set<String>()
        func add(_ item: BrowseItem?) {
            guard let item, seen.insert(item.id).inserted else { return }
            switch item.kind {
            case .artist: results.artists.append(item)
            case .album: results.albums.append(item)
            case .playlist: results.playlists.append(item)
            case .library: break
            }
        }
        // YouTube's top-result card gets its own slot above everything else.
        if let card = JSON.findAll(key: "musicCardShelfRenderer", in: response).first,
           let top = browseItem(fromCard: card) {
            results.top = top
            seen.insert(top.id)
        }
        for item in JSON.findAll(key: "musicResponsiveListItemRenderer", in: response) {
            add(browseItem(from: item))
        }
        return results
    }

    static func browseItem(from item: [String: Any]) -> BrowseItem? {
        guard let id = browseId(of: item), let kind = kind(forPageType: pageType(of: item)) else { return nil }
        let titleRuns = flexRuns(item, 0)
        guard let title = JSON.string(titleRuns.first?["text"]) else { return nil }
        return browseItem(id: id, kind: kind, title: title, subtitleRuns: flexRuns(item, 1), artwork: thumbnail(in: item, size: 240))
    }

    private static func browseItem(fromCard card: [String: Any]) -> BrowseItem? {
        let titleRun = JSON.dict(JSON.value(at: ["title", "runs", 0], in: card))
        guard let titleRun, let id = browseId(of: titleRun), let kind = kind(forPageType: pageType(of: titleRun)),
              let title = JSON.string(titleRun["text"]) else { return nil }
        let runs = (JSON.array(JSON.value(at: ["subtitle", "runs"], in: card)) ?? []).compactMap(JSON.dict)
        return browseItem(id: id, kind: kind, title: title, subtitleRuns: runs, artwork: thumbnail(in: card, size: 240))
    }

    /// Builds an item, lifting the linked artist out of the subtitle runs so it can be tapped.
    private static func browseItem(id: String, kind: BrowseKind, title: String, subtitleRuns: [[String: Any]], artwork: URL?) -> BrowseItem {
        let artistRun = subtitleRuns.first(where: isArtistRun)
        return BrowseItem(
            id: id,
            kind: kind,
            title: title,
            subtitle: subtitleRuns.compactMap { JSON.string($0["text"]) }.joined(),
            artworkURL: artwork,
            artist: artistRun.flatMap { JSON.string($0["text"]) },
            artistId: artistRun.flatMap(browseId(of:))
        )
    }

    // MARK: Browse pages

    /// The token for a long list's next page, in a page or in a continuation of one. Only the
    /// song list's own: a playlist's section list carries a token too, for its suggestions. Lists
    /// end in a `continuationItemRenderer` now; some shelves still send the older
    /// `nextContinuationData` beside their contents.
    static func continuationToken(in response: [String: Any]) -> String? {
        let lists = ["musicPlaylistShelfRenderer", "musicShelfRenderer", "musicPlaylistShelfContinuation", "musicShelfContinuation"]
            .flatMap { JSON.findAll(key: $0, in: response) }
        let rows = lists.compactMap { JSON.array($0["contents"]) }
            + JSON.findAll(key: "appendContinuationItemsAction", in: response).compactMap { JSON.array($0["continuationItems"]) }
        let tokenPath: [Any] = ["continuationItemRenderer", "continuationEndpoint", "continuationCommand", "token"]
        if let token = rows.lazy.compactMap({ $0.last.flatMap { JSON.string(JSON.value(at: tokenPath, in: $0)) } }).first {
            return token
        }
        return lists.lazy.compactMap { JSON.string(JSON.value(at: ["continuations", 0, "nextContinuationData", "continuation"], in: $0)) }.first
    }

    /// A list's rows as songs, after the songs the page has already. Rows leave out what the page
    /// says once for all of them (the artist, the cover, the album), so each is filled in from
    /// the page, the continuation's rows the same as the first page's.
    static func appendTracks(in response: [String: Any], to page: inout BrowsePage) {
        var seen = Set(page.tracks.map(\.id))
        let item = page.item
        for raw in JSON.findAll(key: "musicResponsiveListItemRenderer", in: response) {
            guard var track = track(from: raw), seen.insert(track.id).inserted else { continue }
            if track.artist.isEmpty {
                track.artist = item.kind == .artist ? item.title : item.subtitle
            }
            if track.artistId == nil {
                track.artistId = item.kind == .artist ? item.id : page.artistId
            }
            if track.artworkURL == nil { track.artworkURL = item.artworkURL }
            if item.kind == .album {
                track.album = item.title
                track.albumId = item.id
            }
            page.tracks.append(track)
        }
    }

    static func browsePage(from response: [String: Any], for item: BrowseItem) -> BrowsePage {
        var page = BrowsePage(item: item)
        if item.id.hasPrefix("VL") { page.playlistId = String(item.id.dropFirst(2)) }

        // Header: whichever header renderer YouTube used for this page type.
        let headerKeys = [
            "musicResponsiveHeaderRenderer", "musicDetailHeaderRenderer", "musicImmersiveHeaderRenderer",
            "musicVisualHeaderRenderer", "musicEditablePlaylistDetailHeaderRenderer",
        ]
        if let header = headerKeys.lazy.compactMap({ JSON.findAll(key: $0, in: response).first }).first {
            if let title = runsText(JSON.value(at: ["title", "runs"], in: header)), !title.isEmpty {
                page.item.title = title
            }
            let strapline = runsText(JSON.value(at: ["straplineTextOne", "runs"], in: header))
            let headerSubtitle = runsText(JSON.value(at: ["subtitle", "runs"], in: header))
            let subtitle = strapline ?? headerSubtitle
            if let subtitle, !subtitle.isEmpty, item.kind != .artist {
                page.item.subtitle = subtitle
            }
            // Albums put the artist in the strapline and "Album • 2013" in the subtitle; keep the
            // latter as the detail line, the way a playlist's subtitle already carries its year.
            if strapline != nil, let headerSubtitle, !headerSubtitle.isEmpty, item.kind == .album {
                page.detail = headerSubtitle
            }
            if let art = firstThumbnail(in: header, size: 480) {
                page.item.artworkURL = art
            }
            // The playlist to save: the header's play button carries it for albums (their audio
            // playlist) and playlists alike; a playlist's browse id is also just "VL" + the id.
            if let endpoint = JSON.findAll(key: "watchPlaylistEndpoint", in: header).first,
               let id = JSON.string(endpoint["playlistId"]) {
                page.playlistId = id
            }
            // Artist headers carry a Mix button (`startRadioButton`) leading to the artist's
            // radio, by a watch playlist endpoint or, on some layouts, a watch endpoint.
            if let radio = JSON.dict(JSON.value(at: ["startRadioButton", "buttonRenderer", "navigationEndpoint"], in: header)) {
                page.radioId = JSON.string(JSON.value(at: ["watchPlaylistEndpoint", "playlistId"], in: radio))
                    ?? JSON.string(JSON.value(at: ["watchEndpoint", "playlistId"], in: radio))
            }
            // Album headers link the artist in the strapline (or subtitle on older layouts).
            let artistRuns = (JSON.array(JSON.value(at: ["straplineTextOne", "runs"], in: header)) ?? [])
                + (JSON.array(JSON.value(at: ["subtitle", "runs"], in: header)) ?? [])
            page.artistId = artistRuns.compactMap(JSON.dict).first(where: isArtistRun).flatMap(browseId(of:))
        }

        // Tracks: album/playlist contents, or an artist's top songs.
        appendTracks(in: response, to: &page)
        page.continuation = continuationToken(in: response)

        // Artist pages: the songs shelf title links to the full songs playlist.
        for shelf in JSON.findAll(key: "musicShelfRenderer", in: response) {
            if let run = JSON.dict(JSON.value(at: ["title", "runs", 0], in: shelf)), let id = browseId(of: run) {
                page.allSongsId = id
                break
            }
        }

        // Carousels (albums, singles, related artists…).
        for shelf in JSON.findAll(key: "musicCarouselShelfRenderer", in: response) {
            let title = runsText(JSON.value(at: ["header", "musicCarouselShelfBasicHeaderRenderer", "title", "runs"], in: shelf)) ?? ""
            let items = (JSON.array(shelf["contents"]) ?? []).compactMap { entry -> BrowseItem? in
                guard let two = JSON.dict(JSON.dict(entry)?["musicTwoRowItemRenderer"]) else { return nil }
                return browseItem(fromTwoRow: two)
            }
            if !items.isEmpty { page.sections.append(BrowseSection(title: title, items: items)) }
        }
        return page
    }

    // MARK: Account

    /// From `account/account_menu`: the active account header and any switchable identities.
    static func account(from response: [String: Any]) -> AccountInfo? {
        guard let header = JSON.findAll(key: "activeAccountHeaderRenderer", in: response).first else { return nil }
        let name = runsText(JSON.value(at: ["accountName", "runs"], in: header)) ?? ""
        let email = runsText(JSON.value(at: ["email", "runs"], in: header)) ?? ""
        let photo = JSON.array(JSON.value(at: ["accountPhoto", "thumbnails"], in: header))
            .flatMap { JSON.string(JSON.dict($0.last)?["url"]) }.flatMap { artworkURL($0, size: 96) }
        return AccountInfo(name: name, email: email, photoURL: photo)
    }

    /// From `account/accounts_list`: every channel on the login that isn't the selected one.
    static func accountAlternatives(from response: [String: Any]) -> [AccountInfo.Alternative] {
        var alternatives: [AccountInfo.Alternative] = []
        for item in JSON.findAll(key: "accountItem", in: response) {
            guard let title = runsText(JSON.value(at: ["accountName", "runs"], in: item)),
                  (item["isSelected"] as? Bool) != true else { continue }
            let pageId = JSON.findAll(key: "pageIdToken", in: item).first.flatMap { JSON.string($0["pageId"]) }
            alternatives.append(.init(name: title, pageId: pageId))
        }
        return alternatives
    }

    // MARK: Library

    /// Every artist/album/playlist item in a library browse response, whether YouTube laid it
    /// out as a grid of tiles or a list of rows.
    static func libraryItems(from response: [String: Any]) -> [BrowseItem] {
        var seen = Set<String>()
        var items: [BrowseItem] = []
        for two in JSON.findAll(key: "musicTwoRowItemRenderer", in: response) {
            if let item = browseItem(fromTwoRow: two), seen.insert(item.id).inserted { items.append(item) }
        }
        for row in JSON.findAll(key: "musicResponsiveListItemRenderer", in: response) {
            if let item = browseItem(from: row), seen.insert(item.id).inserted { items.append(item) }
        }
        return items
    }

    // MARK: Track links

    /// From a `next` response: the queue entry for `videoId`, whose byline runs link the artist
    /// and album. Videos have no album and come back with just the artist.
    static func links(from response: [String: Any], videoId: String) -> TrackLinks? {
        let entries = JSON.findAll(key: "playlistPanelVideoRenderer", in: response)
        guard let entry = entries.first(where: { JSON.string($0["videoId"]) == videoId })
            ?? entries.first(where: { ($0["selected"] as? Bool) == true }) else { return nil }
        let runs = (JSON.array(JSON.value(at: ["longBylineText", "runs"], in: entry)) ?? []).compactMap(JSON.dict)
        let artistRun = runs.first(where: isArtistRun)
        let albumRun = runs.first { pageType(of: $0) == "MUSIC_PAGE_TYPE_ALBUM" }
        return TrackLinks(
            artist: artistRun.flatMap { JSON.string($0["text"]) },
            artistId: artistRun.flatMap(browseId(of:)),
            album: albumRun.flatMap { JSON.string($0["text"]) },
            albumId: albumRun.flatMap(browseId(of:))
        )
    }

    // MARK: Mixes

    /// From a `next` response for a watch playlist: the queue panel's songs, in order, and the
    /// name the panel gives the list. Songs that can't be played are left out. A song shown
    /// with a video counterpart sits in a wrapper whose primary renderer is the one queued; the
    /// counterpart (the video) isn't a song of its own.
    static func mix(from response: [String: Any], playlistId: String) -> Mix? {
        guard let panel = JSON.findAll(key: "playlistPanelRenderer", in: response).first else { return nil }
        var seen = Set<String>()
        var tracks: [Track] = []
        for entry in (JSON.array(panel["contents"]) ?? []).compactMap(JSON.dict) {
            let renderer = JSON.dict(entry["playlistPanelVideoRenderer"])
                ?? JSON.dict(JSON.value(at: ["playlistPanelVideoWrapperRenderer", "primaryRenderer", "playlistPanelVideoRenderer"], in: entry))
            guard let renderer, renderer["unplayableText"] == nil,
                  let track = track(fromPanel: renderer), seen.insert(track.id).inserted else { continue }
            tracks.append(track)
        }
        let title = JSON.string(panel["title"]) ?? runsText(JSON.value(at: ["title", "runs"], in: panel))
        return Mix(
            playlistId: JSON.string(panel["playlistId"]) ?? playlistId,
            title: title.flatMap { $0.isEmpty ? nil : $0 },
            tracks: tracks
        )
    }

    /// One queue panel entry: the title, the byline's artists and album, the length and cover.
    private static func track(fromPanel item: [String: Any]) -> Track? {
        guard let videoId = JSON.string(item["videoId"]),
              let title = runsText(JSON.value(at: ["title", "runs"], in: item)), !title.isEmpty else { return nil }
        let runs = (JSON.array(JSON.value(at: ["longBylineText", "runs"], in: item)) ?? []).compactMap(JSON.dict)
        let artistRuns = runs.filter(isArtistRun)
        let albumRun = runs.first { pageType(of: $0) == "MUSIC_PAGE_TYPE_ALBUM" }
        let fallbackArtist = runs.compactMap { JSON.string($0["text"]) }.first { !$0.contains("•") }
        let thumbs = JSON.array(JSON.value(at: ["thumbnail", "thumbnails"], in: item))
        return Track(
            id: videoId,
            title: title,
            artist: artistRuns.isEmpty ? (fallbackArtist ?? "") : artistRuns.compactMap { JSON.string($0["text"]) }.joined(separator: ", "),
            album: albumRun.flatMap { JSON.string($0["text"]) },
            durationText: JSON.string(JSON.value(at: ["lengthText", "runs", 0, "text"], in: item)),
            artworkURL: JSON.string(JSON.dict(thumbs?.last)?["url"]).flatMap { artworkURL($0, size: 240) },
            artistId: artistRuns.first.flatMap(browseId(of:)),
            albumId: albumRun.flatMap(browseId(of:)),
            isExplicit: hasExplicitBadge(item["badges"]) ? true : nil
        )
    }

    // MARK: Home

    /// The signed-in home feed: each carousel becomes a section of songs and pages.
    static func home(from response: [String: Any]) -> [HomeSection] {
        var sections: [HomeSection] = []
        for shelf in JSON.findAll(key: "musicCarouselShelfRenderer", in: response) {
            let title = runsText(JSON.value(at: ["header", "musicCarouselShelfBasicHeaderRenderer", "title", "runs"], in: shelf)) ?? ""
            var seen = Set<String>()
            let items = (JSON.array(shelf["contents"]) ?? []).compactMap { entry -> HomeItem? in
                guard let entry = JSON.dict(entry) else { return nil }
                let item: HomeItem?
                if let two = JSON.dict(entry["musicTwoRowItemRenderer"]) {
                    if let browse = browseItem(fromTwoRow: two) {
                        item = .browse(browse)
                    } else if let track = track(fromTwoRow: two) {
                        item = .track(track)
                    } else {
                        item = nil
                    }
                } else if let row = JSON.dict(entry["musicResponsiveListItemRenderer"]) {
                    if let track = track(from: row) {
                        item = .track(track)
                    } else if let browse = browseItem(from: row) {
                        item = .browse(browse)
                    } else {
                        item = nil
                    }
                } else {
                    item = nil
                }
                guard let item, seen.insert(item.id).inserted else { return nil }
                return item
            }
            if !title.isEmpty, !items.isEmpty {
                sections.append(HomeSection(title: title, items: items))
            }
        }
        return sections
    }

    /// A song or video tile (two-row item whose endpoint is a watch endpoint).
    private static func track(fromTwoRow two: [String: Any]) -> Track? {
        guard let videoId = JSON.string(JSON.value(at: ["navigationEndpoint", "watchEndpoint", "videoId"], in: two)),
              let title = runsText(JSON.value(at: ["title", "runs"], in: two)) else { return nil }
        let runs = (JSON.array(JSON.value(at: ["subtitle", "runs"], in: two)) ?? []).compactMap(JSON.dict)
        let artistRuns = runs.filter(isArtistRun)
        let texts = runs.compactMap { JSON.string($0["text"]) }
        let artist = artistRuns.isEmpty
            ? (texts.first { !$0.contains("•") && $0 != "Song" && $0 != "Video" } ?? "")
            : artistRuns.compactMap { JSON.string($0["text"]) }.joined(separator: ", ")
        return Track(
            id: videoId,
            title: title,
            artist: artist,
            artworkURL: firstThumbnail(in: JSON.dict(two["thumbnailRenderer"]) ?? [:], size: 240),
            artistId: artistRuns.first.flatMap(browseId(of:)),
            isExplicit: hasExplicitBadge(two["subtitleBadges"]) ? true : nil
        )
    }

    private static func browseItem(fromTwoRow two: [String: Any]) -> BrowseItem? {
        guard let id = browseId(of: two), let kind = kind(forPageType: pageType(of: two)),
              let title = runsText(JSON.value(at: ["title", "runs"], in: two)) else { return nil }
        let runs = (JSON.array(JSON.value(at: ["subtitle", "runs"], in: two)) ?? []).compactMap(JSON.dict)
        let art = firstThumbnail(in: JSON.dict(two["thumbnailRenderer"]) ?? [:], size: 240)
        return browseItem(id: id, kind: kind, title: title, subtitleRuns: runs, artwork: art)
    }

    // MARK: Helpers

    private static func flexRuns(_ item: [String: Any], _ index: Int) -> [[String: Any]] {
        let path: [Any] = [index, "musicResponsiveListItemFlexColumnRenderer", "text", "runs"]
        return JSON.array(JSON.value(at: path, in: item["flexColumns"]))?.compactMap(JSON.dict) ?? []
    }

    private static func runsText(_ runs: Any?) -> String? {
        guard let runs = JSON.array(runs) else { return nil }
        return runs.compactMap { JSON.string(JSON.dict($0)?["text"]) }.joined()
    }

    private static func pageType(of node: [String: Any]) -> String? {
        JSON.string(JSON.value(at: [
            "navigationEndpoint", "browseEndpoint", "browseEndpointContextSupportedConfigs",
            "browseEndpointContextMusicConfig", "pageType",
        ], in: node))
    }

    private static func browseId(of node: [String: Any]) -> String? {
        JSON.string(JSON.value(at: ["navigationEndpoint", "browseEndpoint", "browseId"], in: node))
    }

    private static func kind(forPageType pageType: String?) -> BrowseKind? {
        switch pageType {
        case "MUSIC_PAGE_TYPE_ARTIST", "MUSIC_PAGE_TYPE_USER_CHANNEL": .artist
        case "MUSIC_PAGE_TYPE_ALBUM": .album
        case "MUSIC_PAGE_TYPE_PLAYLIST": .playlist
        default: nil
        }
    }

    /// Whether a byline run links the act to open as the artist. Channel uploads (mixes, live
    /// sets, most of YouTube proper) link a user channel rather than an artist page, but the
    /// channel is still the artist and its browse id is a UC… id like any other, so both count.
    private static func isArtistRun(_ run: [String: Any]) -> Bool {
        kind(forPageType: pageType(of: run)) == .artist
    }

    private static func thumbnail(in item: [String: Any], size: Int) -> URL? {
        let thumbs = JSON.array(JSON.value(at: ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"], in: item))
        return JSON.string(JSON.dict(thumbs?.last)?["url"]).flatMap { artworkURL($0, size: size) }
    }

    /// The page's main artwork. Headers nest it in a few known places; check those in order so
    /// we never pick up the artist avatar (`straplineThumbnail`) an album header also carries.
    private static func firstThumbnail(in node: [String: Any], size: Int) -> URL? {
        let candidates: [[Any]] = [
            ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"],
            ["thumbnail", "croppedSquareThumbnailRenderer", "thumbnail", "thumbnails"],
            ["foregroundThumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"],
            ["thumbnail", "thumbnails"],
            ["thumbnails"],
        ]
        for path in candidates {
            if let list = JSON.array(JSON.value(at: path, in: node)),
               let url = JSON.string(JSON.dict(list.last)?["url"]) {
                return artworkURL(url, size: size)
            }
        }
        // Last resort: any thumbnail list that isn't the artist strapline.
        var fallback = node
        fallback["straplineThumbnail"] = nil
        for holder in JSON.findAll(key: "thumbnail", in: fallback) {
            if let list = JSON.array(holder["thumbnails"]), let url = JSON.string(JSON.dict(list.last)?["url"]) {
                return artworkURL(url, size: size)
            }
        }
        return nil
    }

    /// Google thumbnails encode their size in the URL; request a square at `size` points.
    static func artworkURL(_ raw: String, size: Int) -> URL? {
        guard raw.contains("googleusercontent.com") else { return URL(string: raw) }
        let resized = raw.replacing(/=w\d+-h\d+/) { _ in "=w\(size)-h\(size)" }
        return URL(string: resized)
    }
}
