import Foundation

/// A defaults suite no other test, or the app, shares: for services that remember what they're
/// told, so a test never writes the listener's saved feed, levels or volumes.
func isolatedDefaults(_ suite: String) -> UserDefaults {
    let name = "LiltTests.\(suite).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}
