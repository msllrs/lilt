import Foundation

extension Theme {
    /// When a loading placeholder (a skeleton) is allowed on screen. See `LoadingGate`.
    enum Loading {
        /// How long a load runs before its placeholder appears. A cached or quick InnerTube
        /// response usually lands inside this, and anything under about a fifth of a second
        /// reads as the page simply arriving, so it never flashes a skeleton first.
        static let grace: Duration = .milliseconds(200)
        /// Once shown, how long a placeholder stays before the content replaces it. A skeleton
        /// that blinks off a frame or two after it appeared reads as a flicker; this is about the
        /// length of `Motion.standard`, long enough to register as a state. The most it delays
        /// content is a response landing just after `grace`, shown at `grace + minimumShown`.
        static let minimumShown: Duration = .milliseconds(300)
    }
}
