import Foundation

/// Settings ▸ Playback ▸ Double-click the player: what a double-click on the platter's empty
/// glass does, in the panel and the mini player alike.
enum PlatterDoubleClick: String, CaseIterable, Identifiable {
    case miniPlayer, upNext

    static let key = "platterDoubleClick"

    var id: Self { self }

    var label: String {
        switch self {
        case .miniPlayer: "Mini Player"
        case .upNext: "Up Next"
        }
    }

    @MainActor func perform(on delegate: AppDelegate?) {
        guard let delegate else { return }
        let navigation = delegate.navigation
        switch self {
        case .miniPlayer: delegate.setMiniPlayer(!navigation.isMiniPlayer)
        case .upNext: delegate.setQueueVisible(!navigation.isQueueVisible)
        }
    }
}
