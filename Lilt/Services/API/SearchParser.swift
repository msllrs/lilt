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
        let artistRuns = subtitle.filter { pageType(of: $0) == "MUSIC_PAGE_TYPE_ARTIST" }
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
            albumId: albumRun.flatMap(browseId(of:))
        )
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
        let subtitle = flexRuns(item, 1).compactMap { JSON.string($0["text"]) }.joined()
        return BrowseItem(id: id, kind: kind, title: title, subtitle: subtitle, artworkURL: thumbnail(in: item, size: 240))
    }

    private static func browseItem(fromCard card: [String: Any]) -> BrowseItem? {
        let titleRun = JSON.dict(JSON.value(at: ["title", "runs", 0], in: card))
        guard let titleRun, let id = browseId(of: titleRun), let kind = kind(forPageType: pageType(of: titleRun)),
              let title = JSON.string(titleRun["text"]) else { return nil }
        let subtitle = (JSON.array(JSON.value(at: ["subtitle", "runs"], in: card)) ?? [])
            .compactMap { JSON.string(JSON.dict($0)?["text"]) }.joined()
        return BrowseItem(id: id, kind: kind, title: title, subtitle: subtitle, artworkURL: thumbnail(in: card, size: 240))
    }

    // MARK: Browse pages

    static func browsePage(from response: [String: Any], for item: BrowseItem) -> BrowsePage {
        var page = BrowsePage(item: item)

        // Header: whichever header renderer YouTube used for this page type.
        let headerKeys = [
            "musicResponsiveHeaderRenderer", "musicDetailHeaderRenderer", "musicImmersiveHeaderRenderer",
            "musicVisualHeaderRenderer", "musicEditablePlaylistDetailHeaderRenderer",
        ]
        if let header = headerKeys.lazy.compactMap({ JSON.findAll(key: $0, in: response).first }).first {
            if let title = runsText(JSON.value(at: ["title", "runs"], in: header)), !title.isEmpty {
                page.item.title = title
            }
            let subtitle = runsText(JSON.value(at: ["straplineTextOne", "runs"], in: header))
                ?? runsText(JSON.value(at: ["subtitle", "runs"], in: header))
            if let subtitle, !subtitle.isEmpty, item.kind != .artist {
                page.item.subtitle = subtitle
            }
            if let art = firstThumbnail(in: header, size: 480) {
                page.item.artworkURL = art
            }
        }

        // Tracks: album/playlist contents, or an artist's top songs.
        var seen = Set<String>()
        for raw in JSON.findAll(key: "musicResponsiveListItemRenderer", in: response) {
            guard var track = track(from: raw), seen.insert(track.id).inserted else { continue }
            if track.artist.isEmpty {
                track.artist = item.kind == .artist ? page.item.title : page.item.subtitle
            }
            if track.artworkURL == nil { track.artworkURL = page.item.artworkURL }
            if item.kind == .album {
                track.album = page.item.title
                track.albumId = item.id
            }
            page.tracks.append(track)
        }

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

    private static func browseItem(fromTwoRow two: [String: Any]) -> BrowseItem? {
        guard let id = browseId(of: two), let kind = kind(forPageType: pageType(of: two)),
              let title = runsText(JSON.value(at: ["title", "runs"], in: two)) else { return nil }
        let subtitle = runsText(JSON.value(at: ["subtitle", "runs"], in: two)) ?? ""
        let art = firstThumbnail(in: JSON.dict(two["thumbnailRenderer"]) ?? [:], size: 240)
        return BrowseItem(id: id, kind: kind, title: title, subtitle: subtitle, artworkURL: art)
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

    private static func thumbnail(in item: [String: Any], size: Int) -> URL? {
        let thumbs = JSON.array(JSON.value(at: ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"], in: item))
        return JSON.string(JSON.dict(thumbs?.last)?["url"]).flatMap { artworkURL($0, size: size) }
    }

    /// First `thumbnails` array anywhere under `node` (headers nest them in varying places).
    private static func firstThumbnail(in node: [String: Any], size: Int) -> URL? {
        for holder in JSON.findAll(key: "thumbnail", in: node) {
            if let list = JSON.array(holder["thumbnails"]), let url = JSON.string(JSON.dict(list.last)?["url"]) {
                return artworkURL(url, size: size)
            }
        }
        if let list = JSON.array(node["thumbnails"]), let url = JSON.string(JSON.dict(list.last)?["url"]) {
            return artworkURL(url, size: size)
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
