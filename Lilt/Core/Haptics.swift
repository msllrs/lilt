import AppKit
import OSLog

/// The trackpad's taps for things locking into place. The system decides whether there is
/// hardware to play them on; without a Force Touch trackpad nothing happens.
enum Haptics {
    private static let log = Logger(subsystem: "com.msllrs.Lilt", category: "haptics")

    /// A layout landing at one of its stops: the compact header locking in, or the hero back
    /// at the top.
    static func alignment() {
        log.debug("alignment")
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// A surface changing level under the pointer: the platter opening or closing the queue.
    static func levelChange() {
        log.debug("levelChange")
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
