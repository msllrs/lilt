import Foundation

/// Warms something for a row (fetches its page ahead, say) once the pointer has rested on it,
/// not as soon as it arrives. Rows slide under a resting pointer all through a scroll, and
/// warming each on arrival fetched and parsed one page after another the user never meant.
@MainActor
final class HoverWarmer {
    /// Longer than a row takes to pass under the pointer in a scroll, short enough that a pointer
    /// heading for a row to click it still finds the page warm.
    static let dwell: Duration = .milliseconds(250)

    private let warm: @MainActor () -> Void
    private var pending: Task<Void, Never>?

    init(warm: @escaping @MainActor () -> Void) {
        self.warm = warm
    }

    /// Feed it the row's `onHover`.
    func hovering(_ isHovering: Bool) {
        pending?.cancel()
        pending = nil
        guard isHovering else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.dwell)
            guard !Task.isCancelled, let self else { return }
            pending = nil
            warm()
        }
    }

    deinit { pending?.cancel() }
}
