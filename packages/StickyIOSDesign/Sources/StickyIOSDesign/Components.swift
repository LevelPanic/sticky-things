#if canImport(UIKit)
import StickyCore
import SwiftUI

public extension View {
    /// The card surface used by the library list: a quiet fill, a hairline border, and an
    /// accent ring only while selected or highlighted.
    func stickyCard(tint: Color? = nil, highlighted: Bool = false) -> some View {
        modifier(StickyCardSurface(tint: tint, highlighted: highlighted))
    }

    /// The rounded well used by editors and text fields.
    func stickyField(radius: CGFloat = StickyRadius.field, fill: Color = StickyPalette.surface) -> some View {
        modifier(StickyFieldSurface(radius: radius, fill: fill))
    }
}

public struct StickyCardSurface: ViewModifier {
    public var tint: Color?
    public var highlighted: Bool

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: StickyRadius.l, style: .continuous)
        content
            .background(shape.fill(tint ?? StickyPalette.surface))
            .overlay(shape.strokeBorder(highlighted ? StickyPalette.accent : StickyPalette.border,
                                        lineWidth: highlighted ? 2 : 1))
            .contentShape(shape)
    }
}

public struct StickyFieldSurface: ViewModifier {
    public var radius: CGFloat
    public var fill: Color

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(StickyPalette.border))
    }
}

/// A consistent icon plate for an item kind. The color is only a supporting cue; the symbol
/// and accessibility label carry the meaning.
public struct StickyKindTile: View {
    public let kind: ItemKind
    public var tint: Tint
    public var swatch: Color?
    public var fill: Color?
    public var size: CGFloat

    public init(kind: ItemKind, tint: Tint = .none, swatch: Color? = nil,
                fill: Color? = nil, size: CGFloat = StickyMetrics.rowIcon) {
        self.kind = kind
        self.tint = tint
        self.swatch = swatch
        self.fill = fill
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: StickyRadius.s, style: .continuous)
                .fill(swatch ?? fill ?? (tint == .none ? StickyPalette.surfaceSunken : StickyTintPalette.paper(tint)))
            if swatch == nil {
                Image(systemName: StickyKind.symbol(for: kind))
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(tint == .none ? StickyPalette.textSecondary : StickyTintPalette.ink(tint))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A 44 pt target with a restrained 32 pt visual plate. Used for icon-only actions.
public struct StickyIconButton: View {
    public enum Role { case normal, destructive }

    public let title: String
    public let symbol: String
    public var role: Role
    public let action: () -> Void

    public init(_ title: String, symbol: String, role: Role = .normal, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.role = role
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: StickyMetrics.glyph, weight: .medium))
                .foregroundStyle(role == .destructive ? StickyPalette.danger : StickyPalette.textSecondary)
                .frame(width: StickyMetrics.iconButton, height: StickyMetrics.iconButton)
                .background(
                    RoundedRectangle(cornerRadius: StickyRadius.m, style: .continuous)
                        .fill(StickyPalette.surfaceSunken)
                )
                .frame(width: StickyMetrics.touch, height: StickyMetrics.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

public struct StickyToastView: View {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(StickyType.button)
            .foregroundStyle(StickyPalette.toastText)
            .padding(.horizontal, StickySpace.l)
            .padding(.vertical, StickySpace.s)
            .background(Capsule().fill(StickyPalette.toast))
    }
}

/// A drawn note for empty states and onboarding. It is the only decorative gradient-free
/// illustration in the iOS design system.
public struct StickyMiniNote: View {
    public var size: CGFloat

    public init(size: CGFloat = StickyMetrics.miniNote) {
        self.size = size
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: size * 0.15, style: .continuous)
                .fill(StickyPalette.paper)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.14), radius: size * 0.05, y: size * 0.03)
            VStack(alignment: .leading, spacing: size * 0.075) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(StickyPalette.paperInk.opacity(0.18))
                        .frame(width: index == 3 ? size * 0.35 : size * 0.52, height: size * 0.045)
                }
            }
            .padding(.top, size * 0.3)
            .padding(.leading, size * 0.2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Path { path in
                path.move(to: CGPoint(x: size * 0.8, y: 0))
                path.addLine(to: CGPoint(x: size, y: 0))
                path.addLine(to: CGPoint(x: size, y: size * 0.2))
                path.closeSubpath()
            }
            .fill(StickyPalette.paperInk.opacity(0.14))
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The detail screen's equal-width action tiles (Copy, Share, Edit, Caption).
public struct StickyActionButton: View {
    public let title: String
    public let symbol: String
    public let action: () -> Void

    public init(_ title: String, symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: StickySpace.xxs) {
                Image(systemName: symbol)
                    .font(.system(size: StickyMetrics.glyph, weight: .medium))
                Text(title)
                    .font(StickyType.meta.weight(.medium))
            }
            .padding(.vertical, StickySpace.s)
            .frame(maxWidth: .infinity, minHeight: StickyMetrics.actionTile)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .accessibilityLabel(title)
    }
}
#endif
