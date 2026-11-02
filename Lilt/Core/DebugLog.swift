import os

#if DEBUG
/// Debug builds' diagnostic lines, readable in Console or with
/// `log stream --predicate 'subsystem == "com.msllrs.Lilt"'`.
///
/// Not `NSLog`: the unified log keeps NSLog's text as `<private>` for an app that wasn't started
/// by Xcode, so the lines only ever read in full in unit tests (whose host Xcode launches).
/// Here the text is marked public; these lines carry song ids and titles, nothing personal.
enum DebugLog {
    private static let playerLog = Logger(subsystem: "com.msllrs.Lilt", category: "player")

    static func player(_ message: String) {
        playerLog.notice("\(message, privacy: .public)")
    }
}
#endif
