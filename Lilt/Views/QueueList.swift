import SwiftUI

/// What's up next, shown inside the platter below the scrubber. Rows drag to reorder and show
/// a remove button on hover; clicking one jumps to it.
struct QueueList: View {
    @Environment(PlayerService.self) private var player

    static let rowHeight: CGFloat = 36
    static let maxRows = 5

    /// The list's height for a given number of upcoming tracks (one row's worth when empty, for
    /// the placeholder), so the mini window can be sized before the list has laid out.
    static func height(forCount count: Int) -> CGFloat {
        CGFloat(max(1, min(count, maxRows))) * rowHeight
    }

    var body: some View {
        let upcoming = player.upcoming
        Group {
            if upcoming.isEmpty {
                Text("Nothing up next")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Identity by position: the same track can sit in the queue more than once.
                    ForEach(Array(upcoming.enumerated()), id: \.offset) { offset, track in
                        QueueRow(track: track) {
                            player.playUpcoming(at: offset)
                        } remove: {
                            withAnimation(Theme.Motion.standard) { player.removeUpcoming(at: offset) }
                            AppDelegate.shared?.queueDidChange()
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onMove { source, destination in
                        player.moveUpcoming(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, Self.rowHeight)
                .scrollIndicators(.never)
            }
        }
        .frame(height: Self.height(forCount: upcoming.count))
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
            ArtworkView(url: track.artworkURL, size: 28, radius: Theme.Radius.artwork(28), context: .row)
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
        .padding(.horizontal, Theme.Space.xs)
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
