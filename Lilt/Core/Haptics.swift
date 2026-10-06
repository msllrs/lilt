import AppKit

/// The trackpad's taps for things locking into place. The system decides whether there is
/// hardware to play them on; without a Force Touch trackpad nothing happens.
enum Haptics {
    /// A layout landing at one of its stops: the compact header locking in, or the hero back
    /// at the top. Timed to the frame that shows it.
    static func alignment() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
    }

    /// A surface changing level under the pointer: the platter opening or closing the queue.
    static func levelChange() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
