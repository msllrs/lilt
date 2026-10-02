import SwiftUI

/// What's up next, shown inside the platter below the scrubber. Rows drag to reorder and show
/// a remove button on hover; clicking one jumps to it.
struct QueueList: View {
    @Environment(PlayerService.self) private var player
    @State private var scrollEdges = ScrollEdges()

    /// Whether the list has content hidden past each end.
    private struct ScrollEdges: Equatable {
        var moreAbove = false
        var moreBelow = false
    }

    static let rowHeight: CGFloat = 36
    static let maxRows = 5
    /// The horizontal inset a plain List keeps around its rows on macOS.
    static let tableInset: CGFloat = 8
    /// How far rows fade out at the top and bottom when the list scrolls.
    static let edgeFade: CGFloat = 14

    /// Hairline between the player and the list, plus the gap beneath it.
    static let dividerHeight: CGFloat = 1 + Theme.Space.sm

    /// The list's height for a given number of upcoming tracks (one row's worth when empty, for
    /// the placeholder), so the mini window can be sized before the list has laid out.
    static func height(forCount count: Int) -> CGFloat {
        dividerHeight + CGFloat(max(1, min(count, maxRows))) * rowHeight
    }

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(height: 1)
            rows
        }
    }

    private var rows: some View {
        let upcoming = player.upcoming
        return Group {
            if upcoming.isEmpty {
                Text("Nothing up next")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Each entry has its own identity (the same track can be queued twice), so
                    // rows animate out and shuffle up instead of swapping their contents.
                    ForEach(player.upcomingEntries) { entry in
                        QueueRow(track: entry.track) {
                            guard let offset = player.upcomingOffset(of: entry.id) else { return }
                            withAnimation(Theme.Motion.standard) { player.playUpcoming(at: offset) }
                        } remove: {
                            guard let offset = player.upcomingOffset(of: entry.id) else { return }
                            withAnimation(Theme.Motion.standard) { player.removeUpcoming(at: offset) }
                            AppDelegate.shared?.queueDidChange()
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onMove { source, destination in
                        withAnimation(Theme.Motion.standard) { player.moveUpcoming(from: source, to: destination) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(0, for: .scrollContent)
                .environment(\.defaultMinListRowHeight, Self.rowHeight)
                .scrollIndicators(.never)
                // AppKit's table still insets rows by 8pt a side after the margins are zeroed;
                // pull it back so rows line up with the platter's artwork and controls.
                .padding(.horizontal, -Self.tableInset)
                // Rows fade out at an edge only when there's more beyond it: no top fade while
                // sitting at the top, no bottom fade once scrolled to the end.
                .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
                    ScrollEdges(
                        moreAbove: geometry.contentOffset.y > 0.5,
                        moreBelow: geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 0.5
                    )
                } action: { _, edges in
                    withAnimation(Theme.Motion.quick) { scrollEdges = edges }
                }
                .mask {
                    let height = Self.height(forCount: upcoming.count) - Self.dividerHeight
                    let top = scrollEdges.moreAbove ? Self.edgeFade / height : 0
                    let bottom = scrollEdges.moreBelow ? Self.edgeFade / height : 0
                    LinearGradient(
                        stops: [
                            .init(color: top > 0 ? .clear : .black, location: 0),
                            .init(color: .black, location: top),
                            .init(color: .black, location: 1 - bottom),
                            .init(color: bottom > 0 ? .clear : .black, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .frame(height: Self.height(forCount: upcoming.count) - Self.dividerHeight)
        .animation(Theme.Motion.standard, value: upcoming.count)
    }
}

private struct QueueRow: View {
    let track: Track
    let play: () -> Void
    let remove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            // Same hover state as list rows: a play glyph over the cover.
            ArtworkView(url: track.artworkURL, size: 28, radius: Theme.Radius.artwork(28), context: .row)
                .playOverlay(isVisible: isHovering, symbol: "play.fill", radius: Theme.Radius.artwork(28), size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.caption)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.pressable(scale: 0.85))
            .opacity(isHovering ? 1 : 0)
            .help("Remove from queue")
        }
        .frame(height: QueueList.rowHeight)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.artwork(28) + Theme.Space.xs, style: .continuous)
                .fill(.fill.quaternary)
                .opacity(isHovering ? 0.6 : 0)
        }
        .onTapGesture(perform: play)
        .onHover { hovering in
            withAnimation(Theme.Motion.quick) { isHovering = hovering }
        }
    }
}
