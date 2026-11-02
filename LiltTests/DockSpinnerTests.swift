import AppKit
import Testing
@testable import Lilt

/// The spinning Dock tile: 256 pixels marked as 2x, with only the cover turning.
@MainActor
struct DockSpinnerTests {
    /// A cover that isn't rotationally symmetric: left half red, right half blue.
    private let cover: NSImage = {
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 32, height: 64).fill()
        NSColor.blue.setFill(); NSRect(x: 32, y: 0, width: 32, height: 64).fill()
        image.unlockFocus()
        return image
    }()

    private func tile(_ angle: CGFloat) -> NSBitmapImageRep {
        DiscIcon.tile(artwork: cover, edgeLuminance: 0.5, accent: .red, side: 128, scale: 2, angle: angle)
            .representations.first as! NSBitmapImageRep
    }

    @Test func framesAre256PixelsAt2x() {
        let rep = tile(0)
        #expect(rep.pixelsWide == 256 && rep.pixelsHigh == 256)
        #expect(rep.size == NSSize(width: 128, height: 128))
    }

    @Test func halfATurnSwapsTheCoversSides() throws {
        // A point on the disc left of the hub, in pixels (y down).
        let left = try #require(tile(0).colorAt(x: 90, y: 128)?.usingColorSpace(.sRGB))
        let turned = try #require(tile(180).colorAt(x: 90, y: 128)?.usingColorSpace(.sRGB))
        #expect(left.redComponent > left.blueComponent)
        #expect(turned.blueComponent > turned.redComponent)
    }

    /// Settings ▸ Dock takes effect on the song already playing: the lap is rebuilt at the new
    /// rate, or the tile goes still, without waiting for the next cover.
    @Test func changingTheSpinRateTakesEffectAtOnce() {
        let saved = UserDefaults.standard.object(forKey: DockSpin.key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: DockSpin.key) } else { UserDefaults.standard.removeObject(forKey: DockSpin.key) }
        }
        UserDefaults.standard.set(DockSpin.standard.rawValue, forKey: DockSpin.key)
        let still = NSImage(size: NSSize(width: 512, height: 512))
        var shown: [NSImage?] = []
        let spinner = DockSpinner(present: { shown.append($0) }, reducesMotion: { false })
        spinner.show(still: { still }) { [cover] angle in
            DiscIcon.tile(artwork: cover, edgeLuminance: 0.5, accent: .red, side: 16, scale: 1, angle: angle)
        }
        #expect(spinner.frameCount == 120, "eight seconds a lap at 15 fps")

        UserDefaults.standard.set(DockSpin.smooth.rawValue, forKey: DockSpin.key)
        #expect(spinner.frameCount == 240, "still turning at the old rate")

        UserDefaults.standard.set(DockSpin.off.rawValue, forKey: DockSpin.key)
        #expect(spinner.frameCount == 0)
        #expect(shown.last! === still, "the still tile didn't come back")

        UserDefaults.standard.set(DockSpin.standard.rawValue, forKey: DockSpin.key)
        #expect(spinner.frameCount == 120)
        #expect(shown.last! !== still, "turning again but showing the still tile")
    }

    /// Reduce Motion stills the Dock tile whatever Settings ▸ Dock says.
    @Test func reduceMotionShowsTheStillTile() {
        let still = NSImage(size: NSSize(width: 512, height: 512))
        var shown: [NSImage?] = []
        let spinner = DockSpinner(present: { shown.append($0) }, reducesMotion: { true })
        spinner.show(still: { still }) { [cover] angle in
            DiscIcon.tile(artwork: cover, edgeLuminance: 0.5, accent: .red, side: 16, scale: 1, angle: angle)
        }
        #expect(spinner.frameCount == 0)
        #expect(shown.last! === still)
    }

    @Test func drawingAFrameIsCheap() {
        let start = Date.now
        for i in 0..<24 { _ = tile(CGFloat(i) * 15) }
        let perFrame = Date.now.timeIntervalSince(start) / 24
        print("dock frame: \(String(format: "%.1f", perFrame * 1000)) ms")
        #expect(perFrame < 0.05)
    }
}
