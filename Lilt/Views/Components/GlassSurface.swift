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
        Self.apply(style, to: view)
    }

    /// Writes `style` onto `view`: the public style and tint, then the private dials through KVC.
    static func apply(_ style: HeaderControlStyle, to view: NSGlassEffectView) {
        view.style = style.clearBase ? .clear : .regular
        view.tintColor = style.tint.map { NSColor($0) }
        func set(_ value: Any?, _ key: String) {
            guard Self.setter(for: key, on: view).map({ Self.accepts($0, value) }) == true else { return }
            view.setValue(value, forKey: key)
        }
        // The public `style` setter picks a variant of its own (regular 1, clear 2); the dial only
        // overrides it when moved off 0, otherwise "clear base" would be undone here.
        if style.variant != 0 { set(style.variant, "_variant") }
        set(style.subvariant.isEmpty ? nil : style.subvariant, "_subvariant")
        set(style.contentLensing, "_contentLensing")
        set(style.scrim, "_scrimState")
        set(style.subdued, "_subduedState")
        set(style.interaction.clamped(to: HeaderControlStyle.interactionRange), "_interactionState")
        set(style.adaptiveAppearance.clamped(to: HeaderControlStyle.adaptiveAppearanceRange), "_adaptiveAppearance")
        set(style.reducedShadow, "_useReducedShadowRadius")
    }

    /// The private dials `apply` writes, with the ObjC type code each setter must take.
    static var privateKeys: [String: Character] { [
        "_variant": "q", "_subvariant": "@", "_contentLensing": "q", "_scrimState": "q",
        "_subduedState": "q", "_interactionState": "q", "_adaptiveAppearance": "q",
        "_useReducedShadowRadius": "B",
    ] }

    /// The type code of the setter's single argument for `key` on `view`'s class, or nil when
    /// there is no such setter.
    static func setter(for key: String, on view: NSView) -> Character? {
        let name = key.hasPrefix("_") ? "set\(key):" : "set\(key.prefix(1).uppercased())\(key.dropFirst()):"
        guard let method = class_getInstanceMethod(type(of: view), NSSelectorFromString(name)),
              let encoding = method_getTypeEncoding(method)
        else { return nil }
        // "v24@0:8q16": return type, self, _cmd, then the argument; digits are frame offsets.
        let codes = String(cString: encoding).filter { !$0.isNumber }
        return codes.count == 4 ? codes.last : nil
    }

    /// Whether a value of this Swift type can go through KVC to a setter taking `code` without
    /// raising: objects take strings or nil, integers take Int, booleans take Bool.
    static func accepts(_ code: Character, _ value: Any?) -> Bool {
        switch code {
        case "@": return value == nil || value is String
        case "q", "Q", "i", "I", "l", "L", "s", "S": return value is Int
        case "B", "c", "C": return value is Bool
        default: return false
        }
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

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
