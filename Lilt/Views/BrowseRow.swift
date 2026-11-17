import SwiftUI

/// A tappable artist, album or playlist.
struct BrowseRow: View {
    static let horizontalPadding = Theme.Space.rowPadding
    static let verticalPadding = Theme.Space.rowPadding
    /// The hover highlight, concentric with the artwork: its radius plus the padding between them.
    private static let highlight = RoundedRectangle(cornerRadius: Theme.Radius.rowArtwork + horizontalPadding, style: .continuous)

    let item: BrowseItem

    @Environment(NavigationModel.self) private var navigation
    @Environment(YTMusicClient.self) private var music
    @Environment(PlayerService.self) private var player
    @Environment(NoticeCenter.self) private var notices: NoticeCenter?
    @State private var isHovering = false
    /// Copy Link, Play Next and Add to Queue from the menu sweep a light across the row.
    @State private var shine = ShineTrigger()
    /// Where the cover is, for the hero morph's flight to the page.
    @State private var coverFrame = HeroFrameBox()
    /// Warms the row's page once the pointer rests on it.
    @State private var warmer: HoverWarmer?
    @Environment(\.heroTracking) private var tracksHeroes
    @Environment(\.pageKey) private var screen

    private var artworkRadius: CGFloat { item.kind == .artist ? Theme.Size.rowArtwork / 2 : Theme.Radius.rowArtwork }

    var body: some View {
        #if DEBUG
        let _ = RowBuildCounts.noteItem(item)
        #endif
        Button {
            if tracksHeroes {
                HeroFlight.shared.tapped(item, on: screen, frame: coverFrame.frame, radius: artworkRadius, path: navigation.path)
            }
            navigation.open(item)
        } label: {
            HStack(spacing: Theme.Space.md) {
                BrowseRowArtwork.Reader(item: item, radius: artworkRadius)
                    .heroSource(item.id, isHovering: isHovering, box: coverFrame)
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(text: item.title, isActive: isHovering, font: .body)
                    subtitle
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, Theme.Space.sm)
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .contentShape(Self.highlight)
            .background {
                Self.highlight
                    .fill(.fill.quaternary)
                    .opacity(isHovering ? 0.6 : 0)
            }
            .shine(trigger: shine, in: Self.highlight)
        }
        .buttonStyle(.plain)
        // The menu reads your playlists in a body of its own, so a change to them redraws the
        // menu, not every row on screen.
        .contextMenu { ItemMenu(item: item, perform: perform) }
        .onHover { hovering in
            isHovering = hovering
            // A fresh one each time the pointer arrives, so it warms the row's item as it is now.
            if hovering { warmer = HoverWarmer { [music, item] in Self.warm(item, music: music) } }
            warmer?.hovering(hovering)
        }
    }

    /// Once the pointer rests on the row, warms the cache so the page is ready by the time it's
    /// clicked. Only once: opening the page fetches it fresh anyway, so a warm copy needn't be
    /// fetched again here.
    private static func warm(_ item: BrowseItem, music: YTMusicClient) {
        if music.cachedPage(for: item) == nil { Task { _ = try? await music.page(for: item) } }
        // Your playlists, for Add to Playlist; any song will do to ask for them.
        if let song = music.cachedPage(for: item)?.tracks.first { music.warmOwnPlaylists(videoId: song.id) }
    }

    private func perform(_ action: RowAction) {
        switch action {
        case .play: Self.play(item, music: music, player: player)
        case .shuffle: withTracks { player.playShuffled($0, source: item) }
        case .startMix: RowMenu.startMix(for: item, player: player, music: music, notices: notices)
        // The queue actions wait for the page's songs; the row shines when they go in, with the
        // notice, and not at all if they never arrive.
        case .playNext: withTracks { RowMenu.playNext($0, named: item.title, artwork: item.artworkURL, player: player, notices: notices); shine.note(action) }
        case .addToQueue: withTracks { RowMenu.enqueue($0, named: item.title, artwork: item.artworkURL, player: player, notices: notices); shine.note(action) }
        case .goToArtist: if let artist = item.artistItem { navigation.open(artist) }
        case .copyLink:
            guard let url = RowMenu.webURL(for: item) else { return }
            RowMenu.copyLink(url, named: item.title, notices: notices)
            shine.note(action)
        default: break
        }
    }

    /// Every one of the page's tracks, a long list's later pages too, for playing it without
    /// opening it.
    private func withTracks(_ use: @escaping ([Track]) -> Void) {
        Self.withTracks(of: item, music: music, use)
    }

    private static func withTracks(of item: BrowseItem, music: YTMusicClient, _ use: @escaping ([Track]) -> Void) {
        Task {
            guard let page = try? await music.fullPage(for: item), !page.tracks.isEmpty else { return }
            use(page.tracks)
        }
    }

    /// Plays the album, playlist or artist's top songs from the start, without opening it.
    static func play(_ item: BrowseItem, music: YTMusicClient, player: PlayerService) {
        withTracks(of: item, music: music) { player.play($0, startingAt: 0, source: item) }
    }

    /// "Album • Artist • 2019" with the artist tappable, when we know who they are.
    @ViewBuilder
    private var subtitle: some View {
        if let artist = item.artist, let artistItem = item.artistItem, let range = item.subtitle.range(of: artist) {
            HStack(spacing: 0) {
                Text(item.subtitle[..<range.lowerBound])
                ArtistLink(name: artist, item: artistItem)
                Text(item.subtitle[range.upperBound...])
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else {
            MarqueeText(text: item.subtitle, isActive: isHovering, font: .caption, color: AnyShapeStyle(.secondary))
        }
    }
}

/// A row's cover, which doubles as its play button: hovering it offers to play the album,
/// playlist or artist's top songs right here, without opening the page.
private struct BrowseRowArtwork: View {
    let item: BrowseItem
    let radius: CGFloat
    /// The queue was started from this album or playlist (not merely a track it contains).
    let playingHere: Bool
    /// Only ever true for the row playing here.
    let isPlaying: Bool

    @Environment(PlayerService.self) private var player
    @Environment(YTMusicClient.self) private var music
    @State private var isHovering = false

    /// Reads the player for its row, so a song change or a pause reruns this small body in each
    /// row rather than the rows themselves, and only the row playing here hears whether it's
    /// playing: the rest hand the cover the same values and it isn't rebuilt.
    struct Reader: View {
        let item: BrowseItem
        let radius: CGFloat

        @Environment(PlayerService.self) private var player

        var body: some View {
            let playingHere = player.current != nil && player.sourceId == item.id
            BrowseRowArtwork(item: item, radius: radius, playingHere: playingHere, isPlaying: playingHere && player.isPlaying)
        }
    }

    var body: some View {
        let isDisc = playingHere && item.kind != .artist
        // The player is only read in the action, which doesn't tie the cover to it.
        Button {
            if playingHere {
                player.togglePlayPause()
            } else {
                BrowseRow.play(item, music: music, player: player)
            }
        } label: {
            // The album or playlist that's playing wears the same spinning record, and the same
            // notes, as the playing track's row.
            SpinningArtwork(
                url: item.artworkURL,
                size: Theme.Size.rowArtwork,
                restRadius: radius,
                isDisc: isDisc,
                isSpinning: isDisc && isPlaying
            )
            .playOverlay(
                isVisible: isHovering,
                symbol: isPlaying ? "pause.fill" : "play.fill",
                radius: isDisc ? Theme.Size.rowArtwork / 2 : radius,
                size: Theme.Size.rowArtwork
            )
            .overlay {
                if isDisc {
                    NoteEmitterView(isPlaying: isPlaying, center: CGPoint(x: 60, y: 60), artworkURL: item.artworkURL)
                        .frame(width: 120, height: 120)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isPlaying ? "Pause" : "Play")
    }
}

/// An artist, album or playlist row's right-click menu, with the playlists its songs could go in,
/// ticked where they already are.
private struct ItemMenu: View {
    let item: BrowseItem
    let perform: (RowAction) -> Void

    @Environment(YTMusicClient.self) private var music
    @Environment(NoticeCenter.self) private var notices: NoticeCenter?

    var body: some View {
        RowMenuItems(
            groups: RowMenu.item(item),
            playlists: music.ownPlaylists,
            addedTo: music.addedTo[item.id] ?? [],
            perform: perform,
            add: { playlist in RowMenu.add(item, to: playlist, music: music, notices: notices) }
        )
    }
}
