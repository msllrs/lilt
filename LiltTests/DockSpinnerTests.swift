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

    @Test func drawingAFrameIsCheap() {
        let start = Date.now
        for i in 0..<24 { _ = tile(CGFloat(i) * 15) }
        let perFrame = Date.now.timeIntervalSince(start) / 24
        print("dock frame: \(String(format: "%.1f", perFrame * 1000)) ms")
        #expect(perFrame < 0.05)
    }
}
