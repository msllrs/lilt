import Testing
@testable import Lilt

/// A loading placeholder waits out a grace period before it shows, and once shown stays a
/// minimum time. The gate's waits run on a hand-cranked sleep here, so nothing waits in real time.
@MainActor
struct LoadingGateTests {
    private let grace: Duration = .milliseconds(200)
    private let minimum: Duration = .milliseconds(300)

    private func makeGate(_ clock: ManualSleep) -> LoadingGate {
        LoadingGate(grace: grace, minimumShown: minimum, appear: nil, sleep: { try await clock.sleep($0) })
    }

    @Test func contentWithinTheGracePeriodShowsNoPlaceholder() async {
        let clock = ManualSleep()
        let gate = makeGate(clock)
        gate.update(isLoading: true)
        await clock.untilWaiting()
        #expect(clock.waiting == [grace], "loading starts the grace period")
        #expect(!gate.showsPlaceholder)

        gate.update(isLoading: false)
        await clock.untilIdle()
        #expect(!gate.showsPlaceholder, "content in time means no placeholder at all")
        #expect(clock.waiting.isEmpty, "the grace wait is dropped")
        #expect(clock.requested == [grace], "and nothing else is waited for")
    }

    @Test func slowContentShowsThePlaceholderAfterTheGracePeriod() async {
        let clock = ManualSleep()
        let gate = makeGate(clock)
        gate.update(isLoading: true)
        await clock.untilWaiting()
        #expect(!gate.showsPlaceholder, "nothing during the grace period")

        await clock.advance()
        #expect(gate.showsPlaceholder, "the placeholder shows once the grace period is over")
        #expect(clock.waiting == [minimum], "and starts its minimum time")
    }

    @Test func aShownPlaceholderHoldsForTheMinimumTime() async {
        let clock = ManualSleep()
        let gate = makeGate(clock)
        gate.update(isLoading: true)
        await clock.untilWaiting()
        await clock.advance()
        #expect(gate.showsPlaceholder)

        gate.update(isLoading: false)
        #expect(gate.showsPlaceholder, "content arriving early waits for the placeholder's minimum time")
        await clock.advance()
        #expect(!gate.showsPlaceholder, "then takes its place")
    }

    @Test func aPlaceholderStillLoadingAtItsMinimumGoesAsSoonAsContentArrives() async {
        let clock = ManualSleep()
        let gate = makeGate(clock)
        gate.update(isLoading: true)
        await clock.untilWaiting()
        await clock.advance()
        await clock.advance()
        #expect(gate.showsPlaceholder, "still loading, so the placeholder stays past its minimum")
        #expect(clock.waiting.isEmpty)

        gate.update(isLoading: false)
        #expect(!gate.showsPlaceholder, "the content replaces it straight away")
    }

    @Test func navigatingAwayWhileLoadingStopsTheGate() async {
        let clock = ManualSleep()
        let gate = makeGate(clock)
        gate.update(isLoading: true)
        await clock.untilWaiting()
        gate.cancel()
        await clock.untilIdle()
        #expect(clock.waiting.isEmpty, "the grace wait is cancelled")
        #expect(!gate.showsPlaceholder, "and no placeholder comes later")
        #expect(clock.requested == [grace])

        // Away while the placeholder was showing: it goes, and its hold is dropped.
        gate.update(isLoading: true)
        await clock.untilWaiting()
        await clock.advance()
        #expect(gate.showsPlaceholder)
        gate.cancel()
        await clock.untilIdle()
        #expect(!gate.showsPlaceholder)
        #expect(clock.waiting.isEmpty, "the minimum-time wait is cancelled")

        // Back on the screen, still loading: the gate starts over from the grace period.
        gate.update(isLoading: true)
        await clock.untilWaiting()
        #expect(clock.waiting == [grace])
        #expect(!gate.showsPlaceholder)
    }
}

/// A sleep that only ends when the test says so, and throws when its task is cancelled.
@MainActor
final class ManualSleep {
    private var pending: [(id: Int, duration: Duration, continuation: CheckedContinuation<Void, any Error>)] = []
    private var nextID = 0
    /// Every wait asked for, in order.
    private(set) var requested: [Duration] = []
    /// The waits not yet ended.
    var waiting: [Duration] { pending.map(\.duration) }

    func sleep(_ duration: Duration) async throws {
        let id = nextID
        nextID += 1
        requested.append(duration)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                self.enqueue(id, duration, continuation)
            }
        } onCancel: {
            Task { @MainActor in self.drop(id) }
        }
    }

    private func enqueue(_ id: Int, _ duration: Duration, _ continuation: CheckedContinuation<Void, any Error>) {
        if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
        } else {
            pending.append((id, duration, continuation))
        }
    }

    /// Ends the oldest wait, then lets whoever was waiting run on to its next one.
    func advance() async {
        guard !pending.isEmpty else { return }
        pending.removeFirst().continuation.resume()
        await settle()
    }

    func untilWaiting() async {
        for _ in 0..<100 where pending.isEmpty { await Task.yield() }
    }

    func untilIdle() async {
        for _ in 0..<100 where !pending.isEmpty { await Task.yield() }
        await settle()
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private func drop(_ id: Int) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
