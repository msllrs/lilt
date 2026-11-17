import AppKit
import Testing
@testable import Lilt

/// The notes rising from the playing disc sway and change hue through animations on the emitter
/// layer. Those run forever, and a running animation has the window server redraw the panel every
/// frame, so once births stop and the last note has faded they come off, and go back on when the
/// music does.
@MainActor
struct NoteEmitterRestTests {
    /// The shipped notes, sway and hue drift both on, with notes that live a tenth of a second so
    /// the test needn't wait out the real two and a half.
    private static var style: NotesStyle {
        var style = NotesStyle.standard
        style.colorMode = .hueDrift
        style.lifetime = 0.1
        style.lifetimeRange = 0.05
        return style
    }

    /// In a window, as on screen: a layer with no window to draw into drops its animations.
    private static func hosted() -> (NoteEmitterHostView, NSWindow) {
        let view = NoteEmitterHostView(frame: NSRect(x: 0, y: 0, width: 120, height: 120))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0.02
        window.contentView = view
        window.orderFrontRegardless()
        return (view, window)
    }

    private static func emitter(_ view: NoteEmitterHostView) throws -> CAEmitterLayer {
        try #require(view.layer?.sublayers?.first as? CAEmitterLayer)
    }

    private static func update(_ view: NoteEmitterHostView, playing: Bool) {
        view.update(isPlaying: playing, center: CGPoint(x: 60, y: 60), artworkURL: nil, style: style)
    }

    @Test func stoppedNotesStopAnimatingOnceTheLastHasFaded() async throws {
        let (view, window) = Self.hosted()
        defer { window.close() }
        Self.update(view, playing: true)
        let emitter = try Self.emitter(view)
        #expect(!(emitter.animationKeys() ?? []).isEmpty)

        Self.update(view, playing: false)
        // The notes already in the air keep their sway until they've gone.
        #expect(!(emitter.animationKeys() ?? []).isEmpty)
        try await Task.sleep(for: .milliseconds(400))
        #expect(emitter.animationKeys() == nil)

        Self.update(view, playing: true)
        let keys = emitter.animationKeys() ?? []
        #expect(keys.contains { $0.hasPrefix("sway-") })
        #expect(keys.contains { $0.hasPrefix("hue-") })
    }

    @Test func playingAgainBeforeTheNotesFadeKeepsTheirMotion() async throws {
        let (view, window) = Self.hosted()
        defer { window.close() }
        Self.update(view, playing: true)
        let emitter = try Self.emitter(view)
        Self.update(view, playing: false)
        Self.update(view, playing: true)
        try await Task.sleep(for: .milliseconds(400))
        #expect(!(emitter.animationKeys() ?? []).isEmpty)
    }
}
