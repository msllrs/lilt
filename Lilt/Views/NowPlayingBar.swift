import SwiftUI

struct NowPlayingBar: View {
    @Environment(PlayerService.self) private var player
    @Environment(NavigationModel.self) private var navigation
    @Environment(ScrollTracker.self) private var scrollTracker
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous) }
    private var platter: PlatterStyle { ArtworkStyle.shared.platter }

    /// 0 when nothing scrolls beneath the platter, 1 once rows are passing under it.
    private var glassVisibility: CGFloat {
        min(max(scrollTracker.activeRemainingBelow / 24, 0), 1)
    }

    /// A wash of the current artwork's colour.
    private var tint: Color? {
        guard platter.tintOpacity > 0, let url = player.displayArtworkURL else { return nil }
        return ImageCache.shared.tint(for: url, saturationBoost: platter.tintSaturation)
    }

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.md) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.displayTitle)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    ArtistLink(name: player.displayArtist, item: player.current?.artistItem)
                }
                Spacer(minLength: 0)
            }

            scrubber

            HStack(spacing: Theme.Space.xl) {
                TransportButton(symbol: "backward.fill", size: Theme.Size.controlIcon, enabled: player.current != nil) {
                    player.previous()
                }
                TransportButton(symbol: player.isPlaying ? "pause.fill" : "play.fill", size: Theme.Size.playIcon, enabled: player.current != nil) {
                    player.togglePlayPause()
                }
                TransportButton(symbol: "forward.fill", size: Theme.Size.controlIcon, enabled: player.hasNext) {
                    player.next()
                }
            }
        }
        .padding(Theme.Space.barPadding)
        .background {
            // Glass, tint, edge and shadow only earn their place when rows pass beneath; at the
            // end of a list the platter is bare.
            ZStack {
                Color.clear
                    .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.panel, style: .continuous))
                    .shadow(
                        color: .black.opacity(platter.shadowOpacity),
                        radius: platter.shadowRadius,
                        y: platter.shadowOffsetY
                    )
                if let tint {
                    shape.fill(tint.opacity(platter.tintOpacity))
                }
            }
            .opacity(glassVisibility)
        }
        .overlay {
            // Hairline on the outside of the shape so it never eats into the glass.
            shape.inset(by: -0.5).stroke(
                (colorScheme == .dark ? Color.white : Color.black)
                    .opacity(platter.borderOpacity * (colorScheme == .dark ? 1.6 : 1) * glassVisibility),
                lineWidth: 1
            )
        }
        .animation(Theme.Motion.quick, value: glassVisibility)
        .animation(Theme.Motion.standard, value: player.displayArtworkURL)
    }

    /// Artwork opens the album when we know which one it is.
    @ViewBuilder
    private var artwork: some View {
        let view = ArtworkView(url: player.displayArtworkURL, size: Theme.Size.barArtwork, radius: Theme.Radius.barArtwork, context: .player)
        if let album = player.current?.albumItem {
            Button { navigation.open(album) } label: { view }
                .buttonStyle(.plain)
                .help(album.title)
        } else {
            view
        }
    }

    private var scrubber: some View {
        VStack(spacing: Theme.Space.xs) {
            Scrubber(
                value: .constant(isScrubbing ? scrubValue : player.currentTime),
                range: 0...max(player.duration, 1)
            ) { value, ended in
                scrubValue = value
                if ended {
                    player.seek(to: value)
                    isScrubbing = false
                } else {
                    isScrubbing = true
                }
            }
            .frame(height: 12)
            HStack {
                Text(timeString(isScrubbing ? scrubValue : player.currentTime))
                Spacer()
                Text(timeString(player.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

private struct TransportButton: View {
    let symbol: String
    let size: CGFloat
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}
