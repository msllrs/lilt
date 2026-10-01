import Foundation
import Observation

/// Where you are in the column: the search text and the stack of opened pages. Persisted so a
/// relaunch brings you back to the same view.
@MainActor
@Observable
final class NavigationModel {
    private static let key = "navigationState"

    var query: String { didSet { save() } }
    var path: [BrowseItem] { didSet { save() } }

    private struct Saved: Codable {
        var query: String
        var path: [BrowseItem]
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            query = saved.query
            path = saved.path
        } else {
            query = ""
            path = []
        }
    }

    func open(_ item: BrowseItem) {
        path.append(item)
    }

    private func save() {
        let data = try? JSONEncoder().encode(Saved(query: query, path: path))
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
