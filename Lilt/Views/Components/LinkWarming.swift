import SwiftUI

extension View {
    /// Looks up a song's album and artist once the pointer has rested on its row, so the
    /// right-click menu can offer Go to Album and Go to Artist. Only after a short rest: a
    /// pointer brushing down a long list shouldn't ask about every row it passes.
    func warmsLinks(for track: Track?, whileHovering isHovering: Bool) -> some View {
        modifier(LinkWarming(track: track, isHovering: isHovering))
    }
}

private struct LinkWarming: ViewModifier {
    let track: Track?
    let isHovering: Bool

    @Environment(YTMusicClient.self) private var music
    @State private var pending: Task<Void, Never>?

    /// Long enough to pass over rows on the way somewhere, short enough to be done before a
    /// right-click on the row the pointer stopped at.
    private static let rest: Duration = .milliseconds(300)

    func body(content: Content) -> some View {
        content.onChange(of: isHovering) { _, hovering in
            pending?.cancel()
            pending = nil
            guard hovering, let track else { return }
            pending = Task {
                try? await Task.sleep(for: Self.rest)
                guard !Task.isCancelled else { return }
                music.warmLinks(for: track)
            }
        }
    }
}
