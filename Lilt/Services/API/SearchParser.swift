import Foundation

/// Turns an InnerTube `search` response into `Track`s. Tolerant by design: it collects every
/// `musicResponsiveListItemRenderer` anywhere in the payload and keeps the ones that have a
/// video id, so shelf reshuffles on YouTube's side don't break it.
enum SearchParser {
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
        let columns = JSON.array(item["flexColumns"]) ?? []
        func runs(_ index: Int) -> [[String: Any]] {
            let path: [Any] = [index, "musicResponsiveListItemFlexColumnRenderer", "text", "runs"]
            return JSON.array(JSON.value(at: path, in: columns))?.compactMap(JSON.dict) ?? []
        }

        let titleRuns = runs(0)
        guard let title = JSON.string(titleRuns.first?["text"]), !title.isEmpty else { return nil }

        let videoId = JSON.string(JSON.value(at: ["playlistItemData", "videoId"], in: item))
            ?? JSON.string(JSON.value(at: ["navigationEndpoint", "watchEndpoint", "videoId"], in: titleRuns.first))
            ?? JSON.string(JSON.value(at: [
                "overlay", "musicItemThumbnailOverlayRenderer", "content", "musicPlayButtonRenderer",
                "playNavigationEndpoint", "watchEndpoint", "videoId",
            ], in: item))
        guard let videoId else { return nil }

        let subtitle = runs(1)
        let artists = subtitle.filter { pageType(of: $0) == "MUSIC_PAGE_TYPE_ARTIST" }.compactMap { JSON.string($0["text"]) }
        let album = subtitle.first { pageType(of: $0) == "MUSIC_PAGE_TYPE_ALBUM" }.flatMap { JSON.string($0["text"]) }
        let texts = subtitle.compactMap { JSON.string($0["text"]) }
        let fallbackArtist = texts.first { !$0.contains("•") && $0 != "Song" && $0 != "Video" }
        let duration = texts.last { $0.wholeMatch(of: /\d+:\d{2}(:\d{2})?/) != nil }

        let thumbs = JSON.array(JSON.value(at: ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"], in: item))
        let artwork = JSON.string(JSON.dict(thumbs?.last)?["url"]).flatMap { artworkURL($0, size: 240) }

        return Track(
            id: videoId,
            title: title,
            artist: artists.isEmpty ? (fallbackArtist ?? "") : artists.joined(separator: ", "),
            album: album,
            durationText: duration,
            artworkURL: artwork
        )
    }

    private static func pageType(of run: [String: Any]) -> String? {
        JSON.string(JSON.value(at: [
            "navigationEndpoint", "browseEndpoint", "browseEndpointContextSupportedConfigs",
            "browseEndpointContextMusicConfig", "pageType",
        ], in: run))
    }

    /// Google thumbnails encode their size in the URL; request a square at `size` points.
    static func artworkURL(_ raw: String, size: Int) -> URL? {
        guard raw.contains("googleusercontent.com") else { return URL(string: raw) }
        let resized = raw.replacing(/=w\d+-h\d+/) { _ in "=w\(size)-h\(size)" }
        return URL(string: resized)
    }
}
