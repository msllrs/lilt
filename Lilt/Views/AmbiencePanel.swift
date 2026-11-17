import SwiftUI

/// The platter's hidden drawer, opened with an option-click on the cover: a bed of generated
/// ambience under the music, and a live stream of the listener's choosing beside it.
struct AmbiencePanel: View {
    /// Fixed, so the mini window can be sized for it before it has laid out (see QueueList).
    static let height: CGFloat = 1 + Theme.Space.sm + 28 + Theme.Space.sm + 28
    /// The box a custom address gets: the menu's chevron and the URL field. A chosen feed shows
    /// just its name and chevron, as wide as they need.
    static let stationWidth: CGFloat = 104
    /// The chevron menu's box while a custom address is being entered.
    static let feedMenuWidth: CGFloat = 20

    /// The cover's colour, interpolated by the platter; the active sounds take it.
    var accent: Color?

    @Environment(AmbienceService.self) private var ambience
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// The URL field takes the caret when the listener picks Custom from the feeds.
    @FocusState private var isEditingURL: Bool
    /// Whether the listener is entering an address of their own; the field shows, even if the
    /// address happens to be one of the feeds.
    @State private var isCustomEntry = false

    /// The feed whose address is in the field, if any.
    private var selectedFeed: StreamFeed? {
        StreamFeed.allCases.first { $0.url == ambience.streamURL }
    }

    /// The platter's palette, for the window style on screen as the platter builds it: active
    /// sounds wear its control colour, idle ones its dim one.
    private var palette: CoverPalette {
        CoverPalette(accent: accent, colorScheme: colorScheme, surface: .platter, windowStyle: ArtworkStyle.shared.shownWindowStyle(reduceTransparency: reduceTransparency))
    }
    private var tint: Color { palette.control ?? palette.mono }
    private var dim: Color { palette.dimControl ?? .secondary }

    var body: some View {
        @Bindable var ambience = ambience
        VStack(spacing: Theme.Space.sm) {
            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(height: 1)
            // Both rows share a grid, so the two levels stand in one column and keep the same
            // width, whatever the platter's width.
            Grid(alignment: .leading, horizontalSpacing: Theme.Space.sm, verticalSpacing: Theme.Space.sm) {
                // The bed: each sound a toggle with a level of its own round it, and one level
                // for all of them at the end.
                GridRow {
                    HStack(spacing: Theme.Space.xs) {
                        ForEach(AmbienceService.Sound.allCases) { sound in
                            AmbienceSoundButton(sound: sound, tint: tint, dim: dim)
                        }
                    }
                    level($ambience.volume, help: "Level of all the sounds")
                        .frame(maxWidth: .infinity)
                }
                // The feed: the airplane switches it on and off, under the rain button; the
                // menu picks a feed and the field beside it takes any URL; a level at the end.
                GridRow {
                    HStack(spacing: Theme.Space.xs) {
                        Button { ambience.setStreaming(!ambience.isStreaming) } label: {
                            // Lit once the feed is actually playing; it pulses while it buffers
                            // (a live feed can take ten seconds or so) and goes red if the
                            // stream never answers.
                            let state = ambience.streamState
                            Image(systemName: "airplane")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(state == .failed ? Color.red : tint)
                                .symbolEffect(.pulse, isActive: state == .connecting)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(tint.opacity(ambience.isStreaming ? 0.14 : 0)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.pressable(scale: 0.88))
                        .disabled(ambience.streamURL.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help(ambience.streamState == .failed ? "This stream isn't answering" : ambience.isStreaming ? "Stop the stream" : "Listen to the stream")
                        // The feeds: a handful of busy airports, then the listener's own URL.
                        // A chosen feed shows its name in place of the address.
                        if let feed = selectedFeed, !isCustomEntry {
                            Menu { feedItems } label: {
                                HStack(spacing: Theme.Space.xs) {
                                    Text(feed.name)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .font(.caption)
                                .foregroundStyle(tint)
                                .frame(height: 28)
                                .contentShape(Rectangle())
                            }
                            .menuStyle(.button)
                            .buttonStyle(.plain)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .help("Pick a feed")
                        } else {
                            Menu { feedItems } label: {
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(tint)
                                    .frame(width: Self.feedMenuWidth, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .menuStyle(.button)
                            .buttonStyle(.plain)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .help("Pick a feed")
                            TextField("Stream URL", text: $ambience.streamURL)
                                .textFieldStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(tint)
                                .focused($isEditingURL)
                                .frame(width: Self.stationWidth - Self.feedMenuWidth - Theme.Space.xs, height: 28)
                                .help("An audio stream you're entitled to listen to here")
                        }
                    }
                    level($ambience.streamVolume, help: "Stream level")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .clipped()
    }

    /// The feed menu's items: the airports, then the listener's own address, the current choice
    /// ticked.
    @ViewBuilder private var feedItems: some View {
        ForEach(StreamFeed.allCases) { feed in
            Button {
                ambience.streamURL = feed.url
                isCustomEntry = false
                isEditingURL = false
            } label: {
                if selectedFeed == feed && !isCustomEntry {
                    Label(feed.name, systemImage: "checkmark")
                } else {
                    Text(feed.name)
                }
            }
        }
        Divider()
        Button {
            isCustomEntry = true
            isEditingURL = true
        } label: {
            if isCustomEntry || selectedFeed == nil {
                Label("Custom URL…", systemImage: "checkmark")
            } else {
                Text("Custom URL…")
            }
        }
    }

    /// The scrubber's own line slider, small and in the playhead's line colour. Its width comes
    /// from the grid column both rows share, so the two levels always match.
    private func level(_ value: Binding<Float>, help: String) -> some View {
        Scrubber(
            value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Float($0) }),
            range: 0...1,
            onEditing: { v, _ in value.wrappedValue = Float(v) },
            tint: NowPlayingBar.lineColor(palette, accent: accent).map { NSColor($0) }
        )
        .frame(minWidth: 44)
        .frame(height: 16)
        .help(help)
    }
}

/// One sound of the bed: a click switches it on or off, and a drag up or down sets its level,
/// drawn as a ring round the button while it plays.
struct AmbienceSoundButton: View {
    /// A drag this far sets the level from silent to full.
    static let travel: CGFloat = 64
    /// Less movement than this between press and release is a click.
    static let pull: CGFloat = 4

    let sound: AmbienceService.Sound
    let tint: Color
    let dim: Color

    @Environment(AmbienceService.self) private var ambience
    /// The level when the drag began.
    @State private var dragStart: Float?

    var body: some View {
        let on = ambience.active.contains(sound)
        let level = ambience.level(of: sound)
        Image(systemName: sound.symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(on ? tint : dim)
            // Pulses while its page loads, a few seconds, as the stream's does.
            .symbolEffect(.pulse, isActive: ambience.loading.contains(sound))
            .frame(width: 28, height: 28)
            .background(Circle().fill(tint.opacity(on ? 0.14 : 0)))
            .overlay {
                if on {
                    Circle()
                        .inset(by: Theme.Size.levelRing / 2)
                        .trim(from: 0, to: CGFloat(level))
                        .stroke(tint, style: StrokeStyle(lineWidth: Theme.Size.levelRing, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .transition(.opacity)
                }
            }
            .animation(Theme.Motion.symbol, value: on)
            // AppKit takes the press, so a drag sets the level rather than moving the window.
            .overlay {
                GrabHandle(
                    onToggle: { ambience.toggle(sound) },
                    onDrag: { travel in
                        guard abs(travel) >= Self.pull else { return }
                        let start = dragStart ?? level
                        dragStart = start
                        ambience.setLevel(start + Float(travel / Self.travel), for: sound)
                    },
                    onRelease: { _, _ in dragStart = nil },
                    pull: Self.pull,
                    toolTip: on ? "\(sound.name): drag up or down to set its level" : sound.name
                )
            }
            .accessibilityElement()
            .accessibilityLabel(sound.name)
            .accessibilityValue(on ? "\(Int(level * 100)) percent" : "Off")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { ambience.toggle(sound) }
            .accessibilityAdjustableAction { direction in
                let step: Float = direction == .increment ? 0.1 : -0.1
                ambience.setLevel(level + step, for: sound)
            }
    }
}
