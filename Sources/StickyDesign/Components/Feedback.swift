import SwiftUI

/// Short-lived confirmation ("Copied", "Note deleted · Undo"). An inverse capsule with at most
/// one action. Errors stay longer and say what to do next.
public struct ToastView: View {
    let text: String
    let symbol: String
    let isError: Bool
    let actionTitle: String?
    let action: (() -> Void)?

    public init(text: String, symbol: String, isError: Bool = false, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.symbol = symbol
        self.isError = isError
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text(text).font(TypeScale.callout.weight(.medium)).lineLimit(2)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(TypeScale.callout.weight(.semibold))
                    .foregroundStyle(Palette.accentOnInverse.color)
                    .padding(.leading, Space.xxs)
            }
        }
        .foregroundStyle(Palette.textOnInverse.color)
        .padding(.horizontal, Space.m)
        .frame(minHeight: Space.xxl)
        .background(Capsule().fill(Palette.surfaceInverse.color))
        .elevation(.lifted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// For problems that persist (a busy corner, storage trouble): the problem, the fix, one action.
public struct Banner<Actions: View>: View {
    let symbol: String
    let message: String
    let onDismiss: (() -> Void)?
    let actions: Actions

    public init(symbol: String = "exclamationmark.triangle.fill", message: String, onDismiss: (() -> Void)? = nil,
                @ViewBuilder actions: () -> Actions) {
        self.symbol = symbol
        self.message = message
        self.onDismiss = onDismiss
        self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.s) {
                Image(systemName: symbol).foregroundStyle(Palette.warning.color).padding(.top, 1)
                Text(message)
                    .font(TypeScale.callout)
                    .foregroundStyle(Palette.warningInk.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let onDismiss {
                    IconButton("Hide This Tip", symbol: "xmark", action: onDismiss)
                        .padding(.top, -Space.xs)
                }
            }
            HStack(spacing: Space.s) { actions }
        }
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Palette.warningSurface.color))
    }
}

/// Card chrome: opaque (legible over any wallpaper), concentric radius, clear hover, selection
/// and "copied" states. Light mode lifts with a soft shadow; dark mode with a lighter fill + border.
public struct CardSurface: ViewModifier {
    var tint: Swatch?
    var isHovered: Bool
    var isSelected: Bool
    var isHighlighted: Bool
    @Environment(\.colorScheme) private var scheme

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
        let fill = tint?.color ?? (isHovered ? Palette.surfaceRaisedHover.color : Palette.surfaceRaised.color)
        content
            .background(shape.fill(fill))
            .overlay(shape.fill(Palette.accent.opacity(isHighlighted ? 0.18 : 0)).allowsHitTesting(false))
            .overlay(shape.strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1).allowsHitTesting(false))
            .clipShape(shape)
            .elevation(.card)
    }

    private var borderColor: Color {
        if isSelected { return Palette.accent }
        return scheme == .dark ? Palette.border.color : .clear
    }
}

public extension View {
    func cardSurface(tint: Swatch? = nil, hovered: Bool = false, selected: Bool = false, highlighted: Bool = false) -> some View {
        modifier(CardSurface(tint: tint, isHovered: hovered, isSelected: selected, isHighlighted: highlighted))
    }
}

/// The panel's background is system glass drawn by AppKit (see the app's PanelController).
/// Offscreen renders can't sample the desktop, so snapshots ask for a flat surface instead.
public enum PanelMaterial {
    nonisolated(unsafe) public static var flat = false
}

public extension View {
    /// Flat surface behind the panel content in snapshots; nothing at runtime (glass is behind us).
    @ViewBuilder func panelBackdrop(cornerRadius: CGFloat = Radius.panel) -> some View {
        if PanelMaterial.flat {
            background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Palette.surface.color))
        } else {
            self
        }
    }
}
