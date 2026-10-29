import SwiftUI

/// What's up next, shown inside the platter below the scrubber: first the tracks you added
/// (drag to reorder, remove on hover), then, under a divider, what the running list plays after
/// them. Adds always land at the end of the first group, ahead of the second. Clicking any row
/// jumps to it.
struct QueueList: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.colorScheme) private var colorScheme
    /// The cover's colour, already interpolated by the platter; the list's text takes the same
    /// share of it as the platter's title and artist do.
    var accent: Color? = nil
    @State private var scrollEdges = ScrollEdges()

    private var tint: Double { ArtworkStyle.shared.platter.textTint }
    private var titleColor: Color {
        let mono = colorScheme == .dark ? Color.white : Color.black
        return accent.map { mono.mix(with: $0, by: tint) } ?? mono
    }
    private var secondaryColor: Color { accent.map { Color.secondary.mix(with: $0, by: tint * 0.5) } ?? .secondary }
    private var tertiaryColor: Color {
        let base = Color(nsColor: .tertiaryLabelColor)
        return accent.map { base.mix(with: $0, by: tint * 0.5) } ?? base
    }

    /// Whether the list has content hidden past each end.
    private struct ScrollEdges: Equatable {
        var moreAbove = false
        var moreBelow = false
    }

    /// A 28pt cover with the same gap between rows as the main lists keep between their 40pt
    /// covers (12pt), so the two read as one rhythm.
    static let rowHeight: CGFloat = 28 + (Theme.Size.row - Theme.Size.rowArtwork)
    static let maxRows = 5
    /// The horizontal inset a plain List keeps around its rows on macOS.
    static let tableInset: CGFloat = 8
    /// How far rows fade out at the top and bottom when the list scrolls.
    static let edgeFade: CGFloat = 14

    /// Hairline between the player and the list, plus the gap beneath it.
    static let dividerHeight: CGFloat = 1 + Theme.Space.sm

    /// The "Up next from …" line above the automatic group: room above it to set the group
    /// apart from the hand-queued rows, or just the line itself when it leads the list. Below
    /// it, the same gap to the first cover as a section title keeps in the main lists.
    static let groupLabelHeight: CGFloat = 20 + Theme.Space.xs
    static let leadingLabelHeight: CGFloat = 14 + Theme.Space.xs
    static func labelHeight(manual: Int) -> CGFloat { manual == 0 ? leadingLabelHeight : groupLabelHeight }

    /// A row's artwork is 28pt in a 40pt row: this much sits above and below it. The list ends
    /// at the last row's artwork, not its gutter, so the gap to the platter's edge below matches
    /// the one beside the covers.
    static let rowGutter: CGFloat = (rowHeight - 28) / 2

    /// The list's height for the two groups (one row's worth when both are empty, for the
    /// placeholder), so the mini window can be sized before the list has laid out. The label
    /// counts as part of the visible rows, which are capped at `maxRows`; past the cap, half of
    /// the last visible row shows, so it reads as a list that scrolls.
    static func height(manual: Int, automatic: Int) -> CGFloat {
        let rows = CGFloat(manual + automatic) * rowHeight + (automatic > 0 ? labelHeight(manual: manual) : 0)
        let cap = CGFloat(maxRows) * rowHeight
        let visible = rows > cap ? (CGFloat(maxRows) - 0.5) * rowHeight : max(rowHeight, rows)
        return dividerHeight + visible - rowGutter
    }

    /// The list plus the gap above it: what the platter grows by to show it in full.
    static func extent(manual: Int, automatic: Int) -> CGFloat {
        Theme.Space.sm + height(manual: manual, automatic: automatic)
    }

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(height: 1)
            rows
        }
    }

    private static func keyed(_ tracks: [Track]) -> [(key: String, track: Track)] {
        var seen: [String: Int] = [:]
        return tracks.map { track in
            let n = seen[track.id, default: 0]; seen[track.id] = n + 1
            return (key: n == 0 ? track.id : "\(track.id)#\(n)", track: track)
        }
    }

    private var rows: some View {
        let entries = player.upcomingEntries
        let automatic = player.automaticUpcoming
        let listHeight = Self.height(manual: entries.count, automatic: automatic.count) - Self.dividerHeight
        // The list itself runs a gutter taller; the container below cuts that off.
        let fullHeight = listHeight + Self.rowGutter
        // The List stays mounted when empty (the placeholder lays over it), so the last row's
        // removal animates like any other instead of the whole list being swapped out.
        return ScrollViewReader { proxy in
        List {
            // Each entry has its own identity (the same track can be queued twice), so rows
            // animate out and shuffle up instead of swapping their contents.
            ForEach(entries) { entry in
                QueueRow(track: entry.track, titleColor: titleColor, secondaryColor: secondaryColor) {
                    guard let offset = player.upcomingOffset(of: entry.id) else { return }
                    withAnimation(Theme.Motion.settle) { player.playUpcoming(at: offset) }
                } remove: {
                    guard let offset = player.upcomingOffset(of: entry.id) else { return }
                    withAnimation(Theme.Motion.settle) { player.removeUpcoming(at: offset) }
                    AppDelegate.shared?.queueDidChange()
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .onMove { source, destination in
                withAnimation(Theme.Motion.settle) { player.moveUpcoming(from: source, to: destination) }
            }
            if !automatic.isEmpty {
                Text(player.sourceTitle.map { "Up next from \($0)" } ?? "Up next")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tertiaryColor)
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .lineLimit(1)
                    // Flush with the covers below it, and the main lists' gap above them.
                    .frame(height: Self.labelHeight(manual: entries.count) - Theme.Space.xs, alignment: .bottom)
                    .padding(.bottom, Theme.Space.xs)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                // Keyed by track (a repeat gets a numbered key), so when the group shifts the
                // rows move rather than crossfading their text in place.
                ForEach(Array(Self.keyed(automatic).enumerated()), id: \.element.key) { offset, entry in
                    QueueRow(track: entry.track, titleColor: titleColor, secondaryColor: secondaryColor, play: {
                        withAnimation(Theme.Motion.settle) { player.playAutomatic(at: offset) }
                    }, remove: nil)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(0, for: .scrollContent)
        // A track added by hand goes in at the top of the list; a scrolled list would keep its
        // place and leave the new row cut off above the fade, so it scrolls to show it.
        .onChange(of: entries.count) { old, new in
            guard new > old, let first = entries.first else { return }
            withAnimation(Theme.Motion.settle) { proxy.scrollTo(first.id, anchor: .top) }
        }
        // The smallest row is the label; rows set their own height. At the row height, the
        // label was stretched to a full row and the gap beneath it ballooned.
        .environment(\.defaultMinListRowHeight, Self.leadingLabelHeight)
        .scrollIndicators(.never)
        // AppKit's table still insets rows by 8pt a side after the margins are zeroed;
        // pull it back so rows line up with the platter's artwork and controls.
        .padding(.horizontal, -Self.tableInset)
        // Rows fade out at an edge only when there's more beyond it: no top fade while
        // sitting at the top, no bottom fade once scrolled to the end. A few points of slack
        // beyond the end (the table's own trailing padding) don't count as more.
        .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
            ScrollEdges(
                moreAbove: geometry.contentOffset.y > 2,
                moreBelow: geometry.contentSize.height - (geometry.contentOffset.y + geometry.containerSize.height) > Self.rowGutter * 2
            )
        } action: { _, edges in
            withAnimation(Theme.Motion.quick) { scrollEdges = edges }
        }
        .mask {
            // The fade ends at the visible bottom edge (`listHeight`), not the list's own bottom
            // a gutter below it, or what shows is the middle of the fade: a cut.
            let height = fullHeight
            let top = scrollEdges.moreAbove ? Self.edgeFade / height : 0
            let visibleBottom = listHeight / height
            let bottomStart = scrollEdges.moreBelow ? (listHeight - Self.edgeFade) / height : 1
            LinearGradient(
                stops: [
                    .init(color: top > 0 ? .clear : .black, location: 0),
                    .init(color: .black, location: top),
                    .init(color: .black, location: bottomStart),
                    .init(color: scrollEdges.moreBelow ? .clear : .black, location: scrollEdges.moreBelow ? visibleBottom : 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: fullHeight)
        }
        .frame(height: listHeight, alignment: .top)
        .clipped()
        .overlay {
            if entries.isEmpty, automatic.isEmpty {
                Text("Nothing up next")
                    .font(.caption)
                    .foregroundStyle(tertiaryColor)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.settle, value: entries.count + automatic.count)
    }
}

private struct QueueRow: View {
    let track: Track
    /// Title and artist colours, carrying the platter's share of the cover's colour.
    let titleColor: Color
    let secondaryColor: Color
    let play: () -> Void
    /// Nil for the automatic group, which can't be edited.
    let remove: (() -> Void)?

    @Environment(PlayerService.self) private var player
    @Environment(YTMusicClient.self) private var music
    @Environment(NavigationModel.self) private var navigation
    @State private var isHovering = false

    var body: some View {
        // A plain tap gesture on List row content never fires on macOS (the table takes the
        // mouse-down for selection), so the row is a Button; the remove button sits beside it
        // as a sibling, not nested inside it.
        Button(action: play) {
            HStack(spacing: Theme.Space.sm) {
                // Same hover state as list rows: a play glyph over the cover.
                ArtworkView(url: track.artworkURL, size: 28, radius: Theme.Radius.artwork(28), context: .row)
                    .playOverlay(isVisible: isHovering, symbol: "play.fill", radius: Theme.Radius.artwork(28), size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.caption)
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.caption2)
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Room for the remove button.
                Color.clear.frame(width: 22, height: 22)
            }
            .frame(height: QueueList.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if let remove {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable(scale: 0.85))
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .help("Remove from queue")
            }
        }
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.artwork(28) + Theme.Space.xs, style: .continuous)
                .fill(.fill.quaternary)
                .opacity(isHovering ? 0.6 : 0)
        }
        .contextMenu {
            RowMenuItems(
                groups: RowMenu.queued(track, removable: remove != nil, isLiked: music.isLiked(track)),
                playlists: music.ownPlaylists,
                addedTo: music.addedTo[track.id] ?? [],
                perform: perform,
                add: { playlist in Task { try? await music.add(track, to: playlist) } }
            )
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering { music.warmOwnPlaylists(videoId: track.id) }
        }
    }

    private func perform(_ action: RowAction) {
        switch action {
        case .play: play()
        case .removeFromQueue: remove?()
        case .like, .unlike: RowMenu.setLiked(action == .like, track, player: player, music: music)
        case .goToArtist: RowMenu.open(track.artistItem, navigation: navigation)
        case .goToAlbum: RowMenu.open(track.albumItem, navigation: navigation)
        case .copyLink: RowMenu.copy(RowMenu.webURL(for: track))
        default: break
        }
    }
}
