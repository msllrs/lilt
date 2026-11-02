import Foundation
import Observation

/// How fast motion runs. Every `Theme.Motion` token is built from the current pace, so a slower
/// pace slows each animation by the same factor: SwiftUI's, the native frame's display link and
/// the disc's Core Animation settle alike. Content and the frame derive their curves from the
/// same scaled numbers, so the two stay locked in phase at any speed.
struct MotionPace: Equatable, Sendable {
    /// 1 as designed; 0.25 runs every animation four times as long. Always 1 in release builds.
    var speed: Double = 1

    /// The pace tokens are resolved at: a test's own, else the live one.
    static var current: MotionPace { override ?? MotionSettings.shared.pace }

    /// Lets a test resolve tokens at a pace of its own without touching the live settings, which
    /// other suites running alongside read.
    @TaskLocal static var override: MotionPace?

    /// Seconds as designed, stretched to this pace.
    func scaled(_ seconds: TimeInterval) -> TimeInterval { seconds / speed }
}

/// The live pace. Observable, so views whose animations come from tokens re-read them when the
/// tweak panel moves the speed.
@Observable
final class MotionSettings: @unchecked Sendable {
    static let shared = MotionSettings()

    /// The slowest the tweak panel goes: a tenth of designed speed.
    static let speedRange: ClosedRange<Double> = 0.1...1

    #if DEBUG
    /// The tweak panel's Animation speed. Not remembered: a slowed app at the next launch would
    /// read as a bug.
    var speed: Double = 1 {
        didSet { if !Self.speedRange.contains(speed) { speed = min(max(speed, Self.speedRange.lowerBound), Self.speedRange.upperBound) } }
    }
    #else
    /// Fixed in release builds.
    var speed: Double { 1 }
    #endif

    var pace: MotionPace { MotionPace(speed: speed) }
}
