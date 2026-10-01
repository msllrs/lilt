import AppKit
import MediaPlayer

/// Publishes to the system Now Playing widget and routes media keys to the player.
@MainActor
final class NowPlayingManager {
    weak var player: PlayerService?

    private var artworkURL: URL?
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?

    init() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.perform { $0.resume() } ?? .noActionableNowPlayingItem }
        center.pauseCommand.addTarget { [weak self] _ in self?.perform { $0.pause() } ?? .noActionableNowPlayingItem }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.perform { $0.togglePlayPause() } ?? .noActionableNowPlayingItem }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.perform { $0.next() } ?? .noActionableNowPlayingItem }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.perform { $0.previous() } ?? .noActionableNowPlayingItem }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return self?.perform { $0.seek(to: event.positionTime) } ?? .noActionableNowPlayingItem
        }
    }

    private nonisolated func perform(_ action: @MainActor (PlayerService) -> Void) -> MPRemoteCommandHandlerStatus {
        MainActor.assumeIsolated {
            guard let player else { return .noActionableNowPlayingItem }
            action(player)
            return .success
        }
    }

    func update(track: Track?, title: String, artist: String, artworkURL: URL?, isPlaying: Bool, currentTime: Double, duration: Double) {
        let center = MPNowPlayingInfoCenter.default()
        guard track != nil else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
        loadArtworkIfNeeded(artworkURL)
    }

    private func loadArtworkIfNeeded(_ url: URL?) {
        guard url != artworkURL else { return }
        artworkURL = url
        artwork = nil
        artworkTask?.cancel()
        guard let url else { return }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data), !Task.isCancelled else { return }
            // MediaPlayer calls this handler on its own queue, so it must not inherit main-actor isolation.
            nonisolated(unsafe) let artworkImage = image
            self?.artwork = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in artworkImage }
            if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                info[MPMediaItemPropertyArtwork] = self?.artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }
}
