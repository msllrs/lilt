import AppKit
import MediaPlayer
import Observation

/// Media keys and the Now Playing widget between a relaunch and the first play.
///
/// While a track is actually playing, WebKit publishes the page's media session as the system
/// Now Playing entry and routes the media keys to it (next/previous are hijacked in the page to
/// drive Lilt's queue). After a relaunch Lilt shows the restored track but nothing is loaded, so
/// no session exists and the keys have nowhere to go. This publishes Lilt's own entry through
/// MediaPlayer for exactly that window, and withdraws it the moment the web view has a session,
/// so there is never more than one Lilt in Now Playing.
///
/// It also listens for the system's Play after the system paused Lilt (AirPods taken out),
/// web session or not. Taking both AirPods out sends two Pauses, and after the second macOS
/// sends its Play only to apps with command targets in their own process, never to the web
/// session it paused. So while `PlayerService.isPausedRemotely`, Lilt's own process has a play
/// target, and nothing else: no Now Playing info or playback state, so the web session stays
/// the one Lilt entry. The target goes the moment there's no pause to undo.
@MainActor
final class RemoteCommandBridge {
    private let player: PlayerService
    private var active = false
    private var targets: [(MPRemoteCommand, Any)] = []
    /// Lilt's own play target waiting to undo a system pause, while there is one.
    private(set) var isListeningForResume = false
    private var resumeTarget: Any?
    private var artworkURL: URL?

    init(player: PlayerService) {
        self.player = player
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = player.current?.id
            _ = player.hasWebSession
            _ = player.isPlaying
            _ = player.currentTime
            _ = player.duration
            _ = player.isPausedRemotely
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observe()
            }
        }
        update()
    }

    private func update() {
        let wanted = player.current != nil && !player.hasWebSession
        if wanted != active {
            active = wanted
            wanted ? register() : withdraw()
        }
        if active { publish() }
        // Without a web session the full set of targets above already resumes on Play.
        let listening = player.isPausedRemotely && !active
        if listening != isListeningForResume {
            isListeningForResume = listening
            listening ? listenForResume() : stopListeningForResume()
        }
    }

    private func listenForResume() {
        let command = MPRemoteCommandCenter.shared().playCommand
        command.isEnabled = true
        resumeTarget = command.addTarget { [player] _ in
            Task { @MainActor in player.resumeAfterRemotePause() }
            return .success
        }
    }

    private func stopListeningForResume() {
        if let resumeTarget { MPRemoteCommandCenter.shared().playCommand.removeTarget(resumeTarget) }
        resumeTarget = nil
    }

    private func register() {
        let center = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor () -> Void) {
            command.isEnabled = true
            let target = command.addTarget { _ in
                Task { @MainActor in action() }
                return .success
            }
            targets.append((command, target))
        }
        on(center.playCommand) { [player] in player.resume() }
        on(center.pauseCommand) { [player] in player.pause() }
        on(center.togglePlayPauseCommand) { [player] in player.togglePlayPause() }
        on(center.nextTrackCommand) { [player] in player.next() }
        on(center.previousTrackCommand) { [player] in player.previous() }
        // MediaRemote only adopts an app as "now playing" when it reports playing; a paused
        // entry on its own is ignored. Claim the slot, then fall straight back to paused.
        let info = MPNowPlayingInfoCenter.default()
        info.playbackState = .playing
        info.playbackState = .paused
    }

    private func withdraw() {
        for (command, target) in targets { command.removeTarget(target) }
        targets = []
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
        artworkURL = nil
    }

    private func publish() {
        guard let track = player.current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0,
        ]
        if let album = track.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let url = track.artworkURL, let image = ImageCache.shared.cached(url) ?? ImageCache.shared.anyVariant(for: url) {
            // The request handler runs on MediaPlayer's own queue.
            let sendable = image.copy() as! NSImage
            nonisolated(unsafe) let picture = sendable
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in picture }
        } else if let url = track.artworkURL, url != artworkURL {
            artworkURL = url
            Task { [weak self] in
                _ = await ImageCache.shared.load(url)
                self?.update()
            }
        }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = player.isPlaying ? .playing : .paused
    }
}
