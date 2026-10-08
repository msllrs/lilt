import SwiftUI

/// The platter's hidden drawer, opened with an option-click on the cover: a bed of generated
/// ambience under the music, and a live air traffic control feed beside it.
struct AmbiencePanel: View {
    /// Fixed, so the mini window can be sized for it before it has laid out (see QueueList).
    static let height: CGFloat = 1 + Theme.Space.sm + 28 + Theme.Space.sm + 28
    /// The station name's box. With the sliders giving way, both rows fit the platter at the
    /// panel's minimum width (a 236pt content area) and never widen it.
    static let stationWidth: CGFloat = 104

    /// The cover's colour, interpolated by the platter; the active sounds take it.
    var accent: Color?

    @Environment(AmbienceService.self) private var ambience
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHoveringStation = false

    private var tint: Color {
        let mono = colorScheme == .dark ? Color.white : Color.black
        return accent.map { mono.mix(with: $0, by: ArtworkStyle.shared.platter.controlsTint) } ?? mono
    }
    private var dim: Color { accent.map { Color.secondary.mix(with: $0, by: ArtworkStyle.shared.platter.controlsTint) } ?? .secondary }

    var body: some View {
        @Bindable var ambience = ambience
        VStack(spacing: Theme.Space.sm) {
            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(height: 1)
            // The bed: each sound a toggle, one level for all of them.
            HStack(spacing: Theme.Space.xs) {
                ForEach(AmbienceService.Sound.allCases) { sound in
                    let on = ambience.active.contains(sound)
                    Button { ambience.toggle(sound) } label: {
                        Image(systemName: sound.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(on ? tint : dim)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(tint.opacity(on ? 0.14 : 0)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.pressable(scale: 0.88))
                    .help(sound.name)
                }
                Spacer(minLength: Theme.Space.sm)
                level($ambience.volume, help: "Ambience level")
            }
            // The tower: the airplane switches the feed on and off, under the rain button; the
            // name beside it picks the station; a level at the end.
            HStack(spacing: Theme.Space.xs) {
                Button { ambience.setStreaming(!ambience.isStreaming) } label: {
                    Image(systemName: "airplane")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ambience.isStreaming ? tint : dim)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(tint.opacity(ambience.isStreaming ? 0.14 : 0)))
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable(scale: 0.88))
                .help(ambience.isStreaming ? "Stop the feed" : "Listen to the feed")
                Menu {
                    ForEach(AmbienceService.stations) { station in
                        Button(station.name) { ambience.station = station }
                    }
                } label: {
                    // A fixed box the name scrolls in on hover, so a long one can't widen the
                    // platter.
                    MarqueeText(text: ambience.station.name, isActive: isHoveringStation, font: .caption, color: AnyShapeStyle(ambience.isStreaming ? tint : dim))
                        .frame(width: Self.stationWidth, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                // A menu button sizes itself to its widest item, not its label, which widened
                // the platter as the drawer came and went; it gets the label's width and no more.
                .frame(width: Self.stationWidth, alignment: .leading)
                .clipped()
                .onHover { isHoveringStation = $0 }
                .help("Choose a station")
                Spacer(minLength: Theme.Space.sm)
                level($ambience.streamVolume, help: "Feed level")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .clipped()
    }

    /// The scrubber's own line slider, at a small width.
    private func level(_ value: Binding<Float>, help: String) -> some View {
        Scrubber(
            value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Float($0) }),
            range: 0...1,
            onEditing: { v, _ in value.wrappedValue = Float(v) },
            tint: accent.map { NSColor($0) }
        )
        .frame(minWidth: 44, maxWidth: 72)
        .frame(height: 16)
        .help(help)
    }
}
