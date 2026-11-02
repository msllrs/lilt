import SwiftUI

/// Decides when a loading placeholder may be on screen, so a cached or quick page never flashes
/// a skeleton on its way in.
///
/// - A load shorter than `grace` shows no placeholder at all; the content simply arrives.
/// - A longer load shows the placeholder once `grace` has passed, and it then stays at least
///   `minimumShown`, even if the content lands sooner, so it never blinks off straight away.
///
/// Feed it the screen's loading state with `update(isLoading:)` (the `loadingGate` modifier does
/// it from a view) and read `showsPlaceholder`. The waits go through `sleep`, which tests replace
/// so they don't run in real time.
@MainActor @Observable
final class LoadingGate {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    /// Whether the placeholder is on screen. While it is, the content waits behind it.
    private(set) var showsPlaceholder = false

    @ObservationIgnored private var isLoading = false
    /// The placeholder is shown and its minimum time hasn't run out.
    @ObservationIgnored private var holding = false
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private let grace: Duration
    @ObservationIgnored private let minimumShown: Duration
    @ObservationIgnored private let appear: Animation?
    @ObservationIgnored private let sleep: Sleep

    init(
        grace: Duration = Theme.Loading.grace,
        minimumShown: Duration = Theme.Loading.minimumShown,
        appear: Animation? = Theme.Motion.quick,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.grace = grace
        self.minimumShown = minimumShown
        self.appear = appear
        self.sleep = sleep
    }

    func update(isLoading: Bool) {
        self.isLoading = isLoading
        if isLoading {
            guard timer == nil, !showsPlaceholder else { return }
            timer = Task { [weak self] in await self?.run() }
        } else if !showsPlaceholder {
            // Done inside the grace period: the placeholder never comes.
            timer?.cancel()
            timer = nil
        } else if !holding {
            showsPlaceholder = false
        }
        // Otherwise the placeholder is still holding; `run` lets it go when its time is up.
    }

    /// The screen went away (navigated off mid-load): stop waiting and forget the placeholder.
    func cancel() {
        timer?.cancel()
        timer = nil
        isLoading = false
        holding = false
        showsPlaceholder = false
    }

    private func run() async {
        do { try await sleep(grace) } catch { return }
        guard !Task.isCancelled else { return }
        holding = true
        withAnimation(appear) { showsPlaceholder = true }
        do { try await sleep(minimumShown) } catch { return }
        guard !Task.isCancelled else { return }
        holding = false
        timer = nil
        // The content lands without animation, as it would have with no gate in front of it.
        if !isLoading { showsPlaceholder = false }
    }
}

extension View {
    /// Drives `gate` from a loading flag while this view is on screen, and stops it when the
    /// view goes away.
    func loadingGate(_ gate: LoadingGate, isLoading: Bool) -> some View {
        onAppear { gate.update(isLoading: isLoading) }
            .onChange(of: isLoading) { _, loading in gate.update(isLoading: loading) }
            .onDisappear { gate.cancel() }
    }

    /// A placeholder that keeps its place in the layout while its gate hasn't let it show:
    /// invisible, still (no shimmer running) and silent to VoiceOver, so nothing shifts when it
    /// appears or when the content arrives in its place.
    func placeholderShown(_ shown: Bool) -> some View {
        modifier(PlaceholderReveal(shown: shown))
    }
}

private struct PlaceholderReveal: ViewModifier {
    let shown: Bool
    @Environment(\.screenIsParked) private var parked

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .environment(\.screenIsParked, parked || !shown)
            .accessibilityHidden(!shown)
    }
}

/// Content that shows a placeholder only when loading takes long enough to need one (see
/// `LoadingGate`). While `isLoading`, the placeholder holds the content's place, invisible
/// through the grace period; the content appears once loading is done and any placeholder
/// shown has had its minimum time.
struct DelayedPlaceholder<Content: View, Placeholder: View>: View {
    let isLoading: Bool
    @ViewBuilder var content: Content
    @ViewBuilder var placeholder: Placeholder

    @State private var gate = LoadingGate()

    var body: some View {
        // A real container, not a Group: the gate's appear/disappear hooks belong to this view,
        // not to whichever of the two children is current.
        ZStack {
            if isLoading || gate.showsPlaceholder {
                placeholder.placeholderShown(gate.showsPlaceholder)
            } else {
                content
            }
        }
        .loadingGate(gate, isLoading: isLoading)
    }
}
