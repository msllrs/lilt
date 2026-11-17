import SwiftUI

/// The platter's hidden drawer, opened with an option-click on the cover: a bed of generated
/// ambience under the music, and a live stream of the listener's choosing beside it.
struct AmbiencePanel: View {
    /// Fixed, so the mini window can be sized for it before it has laid out (see QueueList).
    static let height: CGFloat = 1 + Theme.Space.sm + 28 + Theme.Space.sm + 28
    /// The stream field's box. With the sliders giving way, both rows fit the platter at the
    /// panel's minimum width (a 236pt content area) and never widen it.
    static let stationWidth: CGFloat = 104

    /// The cover's colour, interpolated by the platter; the active sounds take it.
    var accent: Color?

    @Environment(AmbienceService.self) private var ambience
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
            // The bed: each sound a toggle, one level for all of them.
            HStack(spacing: Theme.Space.xs) {
                ForEach(AmbienceService.Sound.allCases) { sound in
                    let on = ambience.active.contains(sound)
                    Button { ambience.toggle(sound) } label: {
                        Image(systemName: sound.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(on ? tint : dim)
                            // Pulses while its page loads, a few seconds, as the stream's does.
                            .symbolEffect(.pulse, isActive: ambience.loading.contains(sound))
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
            // The feed: the airplane switches it on and off, under the rain button; the field
            // beside it takes the stream's URL; a level at the end.
            HStack(spacing: Theme.Space.xs) {
                Button { ambience.setStreaming(!ambience.isStreaming) } label: {
                    // Lit once the feed is actually playing; it pulses while it buffers (a live
                    // feed can take ten seconds or so) and goes red if the stream never answers.
                    let state = ambience.streamState
                    Image(systemName: "airplane")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(state == .failed ? Color.red : state == .off ? dim : tint)
                        .symbolEffect(.pulse, isActive: state == .connecting)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(tint.opacity(ambience.isStreaming ? 0.14 : 0)))
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable(scale: 0.88))
                .disabled(ambience.streamURL.trimmingCharacters(in: .whitespaces).isEmpty)
                .help(ambience.streamState == .failed ? "This stream isn't answering" : ambience.isStreaming ? "Stop the stream" : "Listen to the stream")
                TextField("Stream URL", text: $ambience.streamURL)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(ambience.isStreaming ? tint : dim)
                    .frame(width: Self.stationWidth, height: 28)
                    .help("An audio stream you're entitled to listen to here")
                Spacer(minLength: Theme.Space.sm)
                level($ambience.streamVolume, help: "Stream level")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .clipped()
    }

    /// The scrubber's own line slider, at a small width, in the playhead's line colour above it.
    private func level(_ value: Binding<Float>, help: String) -> some View {
        Scrubber(
            value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Float($0) }),
            range: 0...1,
            onEditing: { v, _ in value.wrappedValue = Float(v) },
            tint: NowPlayingBar.lineColor(palette, accent: accent).map { NSColor($0) }
        )
        .frame(minWidth: 44, maxWidth: 72)
        .frame(height: 16)
        .help(help)
    }
}
