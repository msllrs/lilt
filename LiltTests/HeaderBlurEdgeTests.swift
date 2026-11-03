import AppKit
import Metal
import QuartzCore
import SwiftUI
import Testing
@testable import Lilt

/// The header blur samples what is composited beneath it, which on the glass surface includes
/// whatever lies behind the window. Along the window's own edges it must blur only the window:
/// sampling past them pulls the desktop beside the panel in, and a dark desktop shows as dark
/// bands down the panel's sides and across its top as the blur comes in.
///
/// The window server can't be captured off screen, so this stands in for it: a dark "desktop"
/// layer with a maroon "window" on it, the real header backdrop mounted in the window flush with
/// its edges, all rendered by Core Animation into a texture. A backdrop samples every layer below
/// it in the tree it is rendered in, which is what the window server does with the screen.
@MainActor
struct HeaderBlurEdgeTests {
    private static let window = CGSize(width: 240, height: 120)
    /// Desktop showing around the window, wider than any blur, so nothing past the window is
    /// out of the backdrop's reach.
    private static let margin: CGFloat = 48
    /// The desktop behind the panel in the user's report: a near-black editor.
    private static let desktop = CGColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1)
    /// The page ambient's maroon, with lighter stripes so there is something to blur.
    private static let page = CGColor(red: 0.4, green: 0.2, blue: 0.25, alpha: 1)
    private static let stripe = CGColor(red: 0.6, green: 0.3, blue: 0.35, alpha: 1)
    private static let stripePitch: CGFloat = 4
    /// The edges may differ from the middle by this share of its brightness at most; the blur of
    /// an even pattern is even right up to the edge when nothing outside the window is sampled.
    private static let tolerance = 0.05

    /// Renders the desktop, the window and the backdrop; returns the pixels (BGRA, rows of
    /// `width`) and the window's rect in them.
    private func render() throws -> (pixels: [UInt8], width: Int, window: (x: Int, y: Int, w: Int, h: Int)) {
        let width = Int(Self.window.width + Self.margin * 2), height = Int(Self.window.height + Self.margin * 2)
        let screen = CALayer()
        screen.frame = CGRect(x: 0, y: 0, width: width, height: height)
        screen.backgroundColor = Self.desktop
        let window = CALayer()
        window.frame = CGRect(origin: CGPoint(x: Self.margin, y: Self.margin), size: Self.window)
        window.backgroundColor = Self.page
        for x in stride(from: 0, to: Self.window.width, by: Self.stripePitch) {
            let stripe = CALayer()
            stripe.frame = CGRect(x: x, y: 0, width: Self.stripePitch / 2, height: Self.window.height)
            stripe.backgroundColor = Self.stripe
            window.addSublayer(stripe)
        }
        screen.addSublayer(window)

        // The glass surface's own header blur, at full strength over the whole height.
        let blur = ArtworkStyle.shared.surface(.dark, reduceTransparency: false).headerBlur
        let view = BackdropHostView(frame: NSRect(origin: .zero, size: Self.window))
        view.ownContentOnly = false
        view.configure(radius: blur.radius, saturation: 1, brightness: 0, fadeStart: 1)
        view.layout()
        let host = try #require(view.layer)
        host.frame = window.bounds
        window.addSublayer(host)

        let device = try #require(MTLCreateSystemDefaultDevice())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let queue = try #require(device.makeCommandQueue())
        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
        renderer.layer = screen
        renderer.bounds = screen.frame
        CATransaction.flush()
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        let done = try #require(queue.makeCommandBuffer())
        done.commit()
        done.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return (pixels, width, (Int(Self.margin), Int(Self.margin), Int(Self.window.width), Int(Self.window.height)))
    }

    private func luminance(_ pixels: [UInt8], _ width: Int, _ x: Int, _ y: Int) -> Double {
        let i = (y * width + x) * 4
        return (0.0722 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.2126 * Double(pixels[i + 2])) / 255
    }

    @Test func windowEdgesAreAsBrightAsTheMiddleUnderTheBlur() throws {
        guard ProgressiveBlurBackdrop.isAvailable else { return }
        let (pixels, width, w) = try render()
        let midX = w.x + w.w / 2, midY = w.y + w.h / 2
        let middle = luminance(pixels, width, midX, midY)
        // Make sure the render happened: the middle is the blurred page, not the desktop.
        #expect(middle > luminance(pixels, width, 0, 0) * 2, "the window rendered")
        // The first and last pixel inside the window on each side, halfway along it (clear of
        // the rounded top corners). Top and bottom are both checked, whichever way up the
        // texture is; only the top runs against the effect's strong edge.
        let edges: [(String, Int, Int)] = [
            ("left", w.x, midY), ("right", w.x + w.w - 1, midY),
            ("first row", midX, w.y), ("last row", midX, w.y + w.h - 1),
        ]
        for (name, x, y) in edges {
            let edge = luminance(pixels, width, x, y)
            #expect(edge >= middle * (1 - Self.tolerance), "the \(name) edge is \(String(format: "%.3f", edge)), the middle \(String(format: "%.3f", middle)): the blur is sampling the desktop beyond the window")
        }
    }
}
