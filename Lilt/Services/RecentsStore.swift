import Foundation
import Observation

/// Recently played tracks and recently opened pages, most recent first, persisted across
/// launches. Feeds the clock menu beside the search field.
@MainActor
@Observable
final class RecentsStore {
    private static let key = "recents"
    private static let limit = 8

    private(set) var played: [Track] = []
    private(set) var viewed: [BrowseItem] = []

    var isEmpty: Bool { played.isEmpty && viewed.isEmpty }

    private struct Saved: Codable {
        var played: [Track]
        var viewed: [BrowseItem]
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            played = saved.played
            viewed = saved.viewed
        }
    }

    func recordPlayed(_ track: Track) {
        played.removeAll { $0.id == track.id }
        played.insert(track, at: 0)
        played = Array(played.prefix(Self.limit))
        save()
    }

    func recordViewed(_ item: BrowseItem) {
        viewed.removeAll { $0.id == item.id }
        viewed.insert(item, at: 0)
        viewed = Array(viewed.prefix(Self.limit))
        save()
    }

    func clear() {
        played = []
        viewed = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(Saved(played: played, viewed: viewed)), forKey: Self.key)
    }
}
