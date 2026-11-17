import AppKit
import SwiftUI
import Testing
@testable import Lilt

/// Each ambience sound has a level of its own, set by dragging the ring round its button, under
/// the drawer's level for all of them; a click on the button still switches the sound.
@MainActor
@Suite(.serialized)
struct AmbienceLevelRingTests {
    /// An ambience service on fake pages, with defaults of its own.
    private func withAmbience(_ body: @MainActor (AmbienceService, @MainActor () -> [FakeBridge]) async throws -> Void) async rethrows {
        var made: [FakeBridge] = []
        let ambience = AmbienceService(defaults: isolatedDefaults("AmbienceLevelRingTests"))
        ambience.volume = 0.5
        ambience.makePlayer = { let page = FakeBridge(); made.append(page); return page }
        try await body(ambience, { made })
    }

    @Test func aSoundsLevelSitsUnderTheBeds() async throws {
        try await withAmbience { ambience, made in
            ambience.toggle(.rain)
            ambience.toggle(.fire)
            made()[0].onEvent?(.playing(videoId: nil))
            made()[1].onEvent?(.playing(videoId: nil))
            #expect(made()[0].volume == 0.5, "full until set")
            ambience.setLevel(0.5, for: .rain)
            #expect(made()[0].volume == 0.25)
            #expect(made()[1].volume == 0.5, "the other sound keeps its own")
            ambience.volume = 1
            #expect(made()[0].volume == 0.5)
            #expect(made()[1].volume == 1)
            ambience.setLevel(3, for: .fire)
            #expect(ambience.level(of: .fire) == 1, "kept within silent and full")
        }
    }

    @Test func levelsAreRemembered() {
        let defaults = isolatedDefaults("AmbienceLevelRingTests")
        let ambience = AmbienceService(defaults: defaults)
        ambience.setLevel(0.25, for: .ocean)
        #expect(AmbienceService(defaults: defaults).level(of: .ocean) == 0.25)
    }

    /// The drawer with its sounds, in an off-screen window, and the hit area over each button.
    private func handles(_ ambience: AmbienceService) async -> (NSWindow, [GrabHandleView]) {
        let size = CGSize(width: 300, height: AmbiencePanel.height)
        let view = AmbiencePanel(accent: nil).frame(width: size.width, height: size.height).environment(ambience)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.contentView?.layoutSubtreeIfNeeded()
        for _ in 0..<5 { try? await Task.sleep(for: .milliseconds(20)) }
        func all(_ v: NSView) -> [GrabHandleView] { ((v as? GrabHandleView).map { [$0] } ?? []) + v.subviews.flatMap(all) }
        let found = all(window.contentView!).sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
        return (window, found)
    }

    /// The press on a button lands on its hit area, which won't let it move the window.
    @Test func aPressOnASoundIsTheButtonsNotTheWindows() async throws {
        try await withAmbience { ambience, _ in
            let (window, handles) = await handles(ambience)
            defer { window.close() }
            try #require(handles.count == AmbienceService.Sound.allCases.count)
            for handle in handles {
                let frame = handle.convert(handle.bounds, to: nil)
                let hit = window.contentView?.hitTest(CGPoint(x: frame.midX, y: frame.midY))
                #expect(hit === handle, "the press should reach the sound's hit area, not the window background")
                #expect(!handle.mouseDownCanMoveWindow)
            }
        }
    }

    @Test func aClickSwitchesAndADragSetsTheLevel() async throws {
        try await withAmbience { ambience, _ in
            let (window, handles) = await handles(ambience)
            defer { window.close() }
            let rain = try #require(handles.first)
            rain.onToggle()
            #expect(ambience.active == [.rain])
            // A wobble is a click, not a drag.
            rain.onDrag(2)
            #expect(ambience.level(of: .rain) == 1)
            // Down half the travel takes it from full to half.
            rain.onDrag(-AmbienceSoundButton.travel / 2)
            #expect(abs(ambience.level(of: .rain) - 0.5) < 0.01)
            rain.onRelease(-AmbienceSoundButton.travel / 2, 0)
            #expect(ambience.active == [.rain], "a drag doesn't switch the sound")
        }
    }
}
