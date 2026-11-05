import Foundation
import Testing
@testable import Lilt

/// AirPods' automatic ear detection: taking them out pauses Lilt and putting them back resumes
/// it. macOS sends the page's media session a Pause per AirPod taken out, and on putting them
/// back a Play to the apps it paused. With both out the second Pause finds Lilt already paused,
/// so macOS no longer counts Lilt among the players it paused (log of 2026-11-05: Pause, Pause
/// 130ms later, then Play broadcast only to two other apps, never to Lilt's WebKit session),
/// and nothing resumes. With one out there is a single Pause and the Play reaches Lilt.
///
/// So Lilt remembers a pause that came from the system, and listens for the system's Play
/// itself, in its own process, until it has resumed or you have played or paused by hand.
@MainActor
struct EarDetectionResumeTests {
    private let songs = [Track(id: "schism", title: "Schism", artist: "Tool"), Track(id: "parabola", title: "Parabola", artist: "Tool")]

    /// One AirPod out and back: the page forwards the system's Pause, Lilt pauses, and the
    /// system's Play resumes it.
    @Test func oneOutAndBackResumes() async throws {
        try await withFakePlayer(songs, gapless: false) { player, fakes in
            fakes.startPlaying(player)
            fakes.first.onEvent?(.remote(.pause))
            #expect(!player.isPlaying)
            #expect(fakes.first.calls.last == "pause")
            #expect(player.isPausedRemotely)

            #expect(player.resumeAfterRemotePause())
            #expect(player.isPlaying)
            #expect(fakes.first.calls.last == "play")
            #expect(!player.isPausedRemotely)
        }
    }

    /// Both out: a second Pause arrives while already paused. It must not forget that the first
    /// paused a playing song, so putting them back still resumes.
    @Test func bothOutAndBackResumes() async throws {
        try await withFakePlayer(songs, gapless: false) { player, fakes in
            fakes.startPlaying(player)
            fakes.first.onEvent?(.remote(.pause))
            fakes.first.report(player.current!.id, playing: false)
            fakes.first.onEvent?(.remote(.pause))
            #expect(player.isPausedRemotely)

            #expect(player.resumeAfterRemotePause())
            #expect(player.isPlaying)
        }
    }

    /// The system's Play reaches Lilt's own process even with a web session up, but only while
    /// a system pause is waiting to be undone, so it never claims a second Now Playing entry
    /// or answers Play when nothing of Lilt's was paused.
    @Test func liltListensForThePlayOnlyWhileRemotelyPaused() async throws {
        try await withFakePlayer(songs, gapless: false) { player, fakes in
            let bridge = RemoteCommandBridge(player: player)
            fakes.startPlaying(player)
            await Task.yield()
            #expect(!bridge.isListeningForResume)

            fakes.first.onEvent?(.remote(.pause))
            await Task.yield()
            #expect(bridge.isListeningForResume)

            #expect(player.resumeAfterRemotePause())
            await Task.yield()
            #expect(!bridge.isListeningForResume)
        }
    }

    /// A pause by hand is yours: putting AirPods in afterwards doesn't start the music.
    @Test func aPauseByHandIsNotResumed() async throws {
        try await withFakePlayer(songs, gapless: false) { player, fakes in
            fakes.startPlaying(player)
            player.pause()
            #expect(!player.isPausedRemotely)
            #expect(!player.resumeAfterRemotePause())
            #expect(!player.isPlaying)
        }
    }

    /// Taking AirPods out with nothing playing isn't a pause to undo later.
    @Test func aPauseWhileAlreadyPausedIsNotResumed() async throws {
        try await withFakePlayer(songs, gapless: false) { player, fakes in
            fakes.startPlaying(player)
            player.pause()
            fakes.first.onEvent?(.remote(.pause))
            #expect(!player.isPausedRemotely)
            #expect(!player.resumeAfterRemotePause())
        }
    }

    /// Anything you do by hand after the system paused (play, pause, another song) settles it:
    /// a later Play from the system doesn't act on a pause you've moved on from.
    @Test func actingByHandForgetsTheSystemPause() async throws {
        try await withFakePlayer(songs, gapless: false) { player, fakes in
            fakes.startPlaying(player)
            fakes.first.onEvent?(.remote(.pause))
            player.resume()
            player.pause()
            #expect(!player.isPausedRemotely)
            #expect(!player.resumeAfterRemotePause())
            #expect(!player.isPlaying)

            fakes.first.report(player.current!.id)
            fakes.first.onEvent?(.remote(.pause))
            player.next()
            #expect(!player.isPausedRemotely)
        }
    }

    /// The page's own Play (a media key, Control Center) still plays as before.
    @Test func theSessionsPlayPlays() async throws {
        try await withFakePlayer(songs, gapless: false) { player, fakes in
            fakes.startPlaying(player)
            player.pause()
            fakes.first.onEvent?(.remote(.play))
            #expect(player.isPlaying)
            #expect(fakes.first.calls.last == "play")
        }
    }
}
