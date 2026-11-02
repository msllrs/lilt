import AppKit
import SwiftUI

/// The panel in miniature, on the real surface a window style draws: Liquid Glass, or the sidebar
/// material, translucent or flat. The layout is the panel's own (search field, skeleton rows,
/// the platter) laid out with its tokens at full size and scaled down, so the picture keeps the
/// panel's proportions. The surfaces are window-server composited and can't be scaled, so they
/// are mounted at the small size with the panel's corner scaled to match, and they keep that
/// corner: the native frame re-corners only the panel's own (`followsWindowCorner`).
///
/// The platter wears the playing cover's colour the way the real one does (`CoverTint`, the
/// platter's accent wash); with nothing playing it is neutral.
struct WindowStylePreview: View {
    var style: WindowStyle
    /// The cover's dominant colour, or nil for a neutral platter.
    var accent: Color?
    var artwork: NSImage? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private static let scale = Theme.Size.windowStylePreviewScale
    static let size = CGSize(width: Theme.Size.panelWidth * scale, height: Theme.Size.panelMinHeight * scale)
    static let cornerRadius = Theme.Radius.window * scale

    /// Placeholders at a fifth of their size need more ink than a loading screen's to read.
    private static let ink = Color.primary.opacity(0.2)
    private static let rowCount = 6

    /// What actually goes on screen: with Reduce Transparency on, glass gives way to solid.
    private var shown: PanelStyle { style.panelStyle.effective(reduceTransparency: reduceTransparency) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        panel
            .frame(width: Theme.Size.panelWidth, height: Theme.Size.panelMinHeight)
            .scaleEffect(Self.scale)
            .frame(width: Self.size.width, height: Self.size.height)
            .clipShape(shape)
            .background { surface.allowsHitTesting(false) }
            .overlay { shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1 / displayScale) }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var surface: some View {
        switch shown.surface {
        case .glass:
            GlassBackground(cornerRadius: Self.cornerRadius, followsWindowCorner: false)
        case .sidebar:
            SidebarBackground(cornerRadius: Self.cornerRadius, translucent: shown.translucent, isHidden: false, followsWindowCorner: false)
        }
    }

    /// The panel at full size: the search field, a page of rows, the platter over them.
    private var panel: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Self.ink)
                .frame(height: Theme.Size.headerRow)
                .padding(Theme.Space.panelInset)
            VStack(spacing: 0) {
                ForEach(0..<Self.rowCount, id: \.self) { i in
                    Skeleton.Row(seed: i, fill: Self.ink)
                        .opacity(1 - Double(i) / Double(Self.rowCount) * 0.6)
                }
            }
            .padding(.horizontal, Theme.Space.rowInset)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { platter.padding(Theme.Space.panelInset) }
    }

    private var platter: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
        let dials = ArtworkStyle.shared.platter
        let tint = CoverTint(accent: accent, colorScheme: colorScheme, platter: dials)
        return HStack(spacing: Theme.Space.md) {
            cover
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Skeleton.Bar(width: 128, height: 11, fill: tint?.title ?? Self.ink)
                Skeleton.Bar(width: 80, height: 8, fill: tint?.secondary ?? Self.ink)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.fill")
                .font(.system(size: Theme.Size.playIcon))
                .foregroundStyle(tint?.control ?? Self.ink)
        }
        .padding(Theme.Space.barPadding)
        .background {
            shape.fill(Skeleton.fill)
            if let accent, dials.cornerAccentOpacity > 0 {
                shape.fill(
                    EllipticalGradient(
                        colors: [accent.opacity(dials.cornerAccentOpacity), .clear],
                        center: dials.accentPlacement.unitPoint,
                        startRadiusFraction: 0,
                        endRadiusFraction: dials.cornerAccentRadius
                    )
                )
            }
        }
    }

    @ViewBuilder private var cover: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.barArtwork, style: .continuous)
        Group {
            if let artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else {
                shape.fill(accent ?? Self.ink)
            }
        }
        .frame(width: Theme.Size.barArtwork, height: Theme.Size.barArtwork)
        .clipShape(shape)
    }
}

/// One window style to pick: the panel in miniature on a tile, its name underneath. The chosen
/// one wears a ring in the system accent colour and a checkmark; with keyboard focus on the
/// picker, the chosen card also carries the focus ring.
struct WindowStyleCard: View {
    var style: WindowStyle
    var isSelected: Bool
    var isFocused: Bool = false
    var accent: Color?
    var artwork: NSImage? = nil
    var action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Padding round the miniature; the tile's corner is concentric with the miniature's.
    private static let padding = Theme.Space.sm
    private static let tileRadius = WindowStylePreview.cornerRadius + padding
    private static let selection = Color(nsColor: .controlAccentColor)

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous)
        Button(action: action) {
            VStack(spacing: Theme.Space.sm) {
                WindowStylePreview(style: style, accent: accent, artwork: artwork)
                    .padding(Self.padding)
                    .frame(maxWidth: .infinity)
                    .background { tile.fill(.quaternary) }
                    .overlay {
                        tile.strokeBorder(isSelected ? Self.selection : .clear, lineWidth: Theme.Size.selectionRing)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Self.selection)
                                .padding(Theme.Space.xs)
                        }
                    }
                    // The focus ring sits just outside the selection ring, as AppKit's does.
                    .overlay {
                        if isFocused {
                            tile.inset(by: -Theme.Size.selectionRing)
                                .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: Theme.Size.selectionRing)
                        }
                    }
                Text(style.title)
                    .font(.callout)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityValue(style == .glass && reduceTransparency ? "Shown as Solid" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Settings ▸ Appearance ▸ Window style: Glass, Normal and Solid side by side as cards. One tab
/// stop for the row, like a segmented control: the arrow keys move the choice, and a click picks
/// a card outright. Each card is a button VoiceOver reads with its selected state.
struct WindowStylePicker: View {
    @Binding var selection: WindowStyle
    /// The playing cover's colour for the miniature platters (nil: neutral).
    var accent: Color?
    var artwork: NSImage? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            ForEach(WindowStyle.allCases) { style in
                WindowStyleCard(
                    style: style,
                    isSelected: selection == style,
                    isFocused: isFocused && selection == style,
                    accent: accent,
                    artwork: artwork
                ) { selection = style }
                .focusable(false)
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .upArrow]) { _ in step(-1) }
        .onKeyPress(keys: [.rightArrow, .downArrow]) { _ in step(1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Window style")
    }

    /// Moves the choice one card along, stopping at either end as a segmented control does.
    private func step(_ offset: Int) -> KeyPress.Result {
        let all = WindowStyle.allCases
        guard let index = all.firstIndex(of: selection) else { return .ignored }
        let next = min(max(index + offset, 0), all.count - 1)
        selection = all[next]
        return .handled
    }
}
