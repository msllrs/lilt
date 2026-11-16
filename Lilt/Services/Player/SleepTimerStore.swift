import Foundation

/// The running sleep timer, kept in the defaults so a relaunch before it runs out still pauses
/// on time. Only the app's own player is saved and restored (see AppDelegate); a timer that ran
/// out while Lilt was closed is forgotten.
@MainActor
enum SleepTimerStore {
    static let endsKey = "sleepTimerEnds"
    static let lengthKey = "sleepTimerLength"

    static func save(_ player: PlayerService, to defaults: UserDefaults = .standard) {
        guard let length = player.sleepTimer, let ends = player.sleepEnds else {
            defaults.removeObject(forKey: endsKey)
            defaults.removeObject(forKey: lengthKey)
            return
        }
        defaults.set(ends.timeIntervalSinceReferenceDate, forKey: endsKey)
        defaults.set(Double(length.components.seconds), forKey: lengthKey)
    }

    static func restore(into player: PlayerService, from defaults: UserDefaults = .standard, now: Date = .now) {
        guard defaults.object(forKey: endsKey) != nil else { return }
        let ends = Date(timeIntervalSinceReferenceDate: defaults.double(forKey: endsKey))
        let length = defaults.double(forKey: lengthKey)
        let left = ends.timeIntervalSince(now)
        guard left > 0, length > 0 else {
            defaults.removeObject(forKey: endsKey)
            defaults.removeObject(forKey: lengthKey)
            return
        }
        player.setSleepTimer(.seconds(length), remaining: .milliseconds(Int(left * 1000)))
    }
}
