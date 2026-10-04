import AppKit
import SwiftUI

/// How the header controls (library/back, recents, account) and optionally the search field are
/// drawn. Picked in the tweak panel so variants can be compared in place.
enum HeaderControlMode: String, CaseIterable, Identifiable {
    /// Bare glyphs, flat quaternary fill on the field (the original look).
    case flat
    /// SwiftUI `glassEffect(.regular)`, interactive.
    case glass
    /// SwiftUI `glassEffect(.clear)`, interactive: less frost, more of what's behind.
    case clear
    /// An `NSGlassEffectView` with its private variant/lensing/scrim dials exposed.
    case appKit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .flat: "Flat"
        case .glass: "Glass"
        case .clear: "Clear"
        case .appKit: "AppKit (private dials)"
        }
    }
}

/// A raw `NSGlassEffectView`, with AppKit's private knobs reachable through key-value coding.
/// Every private key is set defensively; a missing key on a future OS is ignored.
struct GlassSurface<S: InsettableShape>: NSViewRepresentable {
    let shape: S
    var cornerRadius: CGFloat
    var style: HeaderControlStyle

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
        view.style = style.clearBase ? .clear : .regular
        view.tintColor = style.tint.map { NSColor($0) }
        func set(_ value: Any?, _ key: String) {
            guard view.responds(to: NSSelectorFromString(key.hasPrefix("_") ? "set\(key):" : "set\(key.prefix(1).uppercased())\(key.dropFirst()):")) else { return }
            view.setValue(value, forKey: key)
        }
        set(style.variant, "_variant")
        set(style.subvariant < 0 ? nil : style.subvariant, "_subvariant")
        set(style.contentLensing, "_contentLensing")
        set(style.scrim, "_scrimState")
        set(style.subdued, "_subduedState")
        set(style.interaction, "_interactionState")
        set(style.adaptiveAppearance, "_adaptiveAppearance")
        set(style.reducedShadow, "_useReducedShadowRadius")
    }
}

/// The header-control surface in the chosen mode.
struct HeaderControlSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let cornerRadius: CGFloat
    /// Tint to pass to the glass (the cover's colour when enabled).
    var tint: Color?

    private var style: HeaderControlStyle { ArtworkStyle.shared.headerControls }

    func body(content: Content) -> some View {
        let style = style
        Group {
            switch style.mode {
            case .flat:
                content
            case .glass, .clear:
                let glass: Glass = style.mode == .clear ? .clear : .regular
                content
                    .glassEffect(glass.tint(tint?.opacity(style.tintOpacity)).interactive(style.interactive), in: shape)
            case .appKit:
                var s = style
                let _ = { s.tint = tint?.opacity(style.tintOpacity) }()
                content
                    .background { GlassSurface(shape: shape, cornerRadius: cornerRadius, style: s) }
                    .clipShape(shape)
            }
        }
        .glassEdge(shape, opacity: style.mode == .flat ? 0 : (style.rim ? style.rimOpacity : 0))
        // Glass pixels are transparent to the window server; keep the control clickable.
        .background { if style.mode != .flat { shape.fill(Color.black.opacity(0.012)) } }
        .contentShape(shape)
    }
}

extension View {
    /// A round header control of `Theme.Size.headerRow` size, drawn in the tweakable mode.
    func headerControl(tint: Color? = nil) -> some View {
        frame(width: Theme.Size.headerRow, height: Theme.Size.headerRow)
            .modifier(HeaderControlSurface(shape: Circle(), cornerRadius: Theme.Size.headerRow / 2, tint: tint))
    }

    /// A capsule surface (the search field) in the tweakable mode.
    func headerSurface(tint: Color? = nil) -> some View {
        modifier(HeaderControlSurface(shape: Capsule(), cornerRadius: Theme.Size.headerRow / 2, tint: tint))
    }
}
