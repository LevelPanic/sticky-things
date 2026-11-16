import AppKit
import SwiftUI

/// State layers: the only place translucency is allowed (hover 6–8%, pressed 10–12%).
enum StateLayer {
    static func hover(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.08 : 0.06 }
    static func pressed(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.12 : 0.10 }
}

/// A compact icon button: 28 pt target, 13 pt symbol, a 6 pt plate drawn with state layers.
/// Always labelled (tooltip + VoiceOver).
public struct IconButton: View {
    public enum Role { case normal, destructive }
    let symbol: String
    let label: String
    var size: CGFloat
    var role: Role
    var isOn: Bool
    let action: () -> Void

    public init(_ label: String, symbol: String, size: CGFloat = Metrics.iconButton, role: Role = .normal,
                isOn: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.symbol = symbol
        self.size = max(size, Metrics.minHitTarget)
        self.role = role
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(IconButtonStyle(role: role, isOn: isOn))
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct IconButtonStyle: ButtonStyle {
    let role: IconButton.Role
    let isOn: Bool
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground(pressed: configuration.isPressed))
            .background(
                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .fill(isOn ? Palette.accent.opacity(0.18)
                          : Palette.textPrimary.color.opacity(configuration.isPressed ? StateLayer.pressed(scheme)
                                                              : hovering ? StateLayer.hover(scheme) : 0))
            )
            .onHover { inside in withAnimation(Motion.quick) { hovering = inside } }
    }

    private func foreground(pressed: Bool) -> Color {
        if isOn { return Palette.accent }
        if role == .destructive && (hovering || pressed) { return Palette.danger.color }
        return hovering || pressed ? Palette.textPrimary.color : Palette.textSecondary.color
    }
}

/// The panel's text fields (search, the composer): 36 pt on one line, radius 18 (a capsule on
/// one line, the same corners as it grows), a 1 pt border that turns accent with focus. The fill
/// says the role: raised where things are made (the composer), sunken where they're found (search).
public struct FieldChrome: ViewModifier {
    public enum Fill: Sendable { case raised, sunken }
    let fill: Fill
    let focused: Bool

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.field, style: .circular)
        content
            .frame(minHeight: Metrics.fieldHeight)
            .background(shape.fill(fill == .raised ? Palette.surfaceRaised.color : Palette.surfaceSunken.color))
            .overlay(shape.strokeBorder(focused ? Palette.accent.opacity(0.6) : Palette.border.color,
                                        lineWidth: focused ? 1.5 : 1))
    }
}

public extension View {
    func fieldChrome(_ fill: FieldChrome.Fill, focused: Bool) -> some View {
        modifier(FieldChrome(fill: fill, focused: focused))
    }
}

/// Pressed feedback for larger buttons: darken one step, never scale.
public struct PressStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Capsule label for pinned items: one control row tall (28 pt), content 12 pt in, ≤ 160 pt wide.
public struct Chip: View {
    let title: String
    let symbol: String?
    var tint: Swatch?
    var isHighlighted: Bool

    public init(_ title: String, symbol: String? = nil, tint: Swatch? = nil, isHighlighted: Bool = false) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.isHighlighted = isHighlighted
    }

    public var body: some View {
        HStack(spacing: Space.xs) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .medium)) }
            Text(title).font(TypeScale.callout.weight(.medium)).lineLimit(1)
        }
        .foregroundStyle(tint != nil ? TintPalette.ink.color : Palette.textPrimary.color)
        .padding(.horizontal, Space.m)
        .frame(height: Metrics.controlRow)
        .frame(maxWidth: 160)
        .background(Capsule().fill(tint?.color ?? Palette.surfaceRaised.color))
        .overlay(Capsule().strokeBorder(isHighlighted ? Palette.accent : .clear, lineWidth: 2))
        .contentShape(Capsule())
    }
}

/// A row of filters ("All · Notes · Links · Images · Files").
public struct FilterBar<ID: Hashable>: View {
    public struct Option: Identifiable {
        public let id: ID
        public let title: String
        public let symbol: String
        public init(id: ID, title: String, symbol: String) {
            self.id = id
            self.title = title
            self.symbol = symbol
        }
    }

    let options: [Option]
    @Binding var selection: ID
    @Environment(\.colorScheme) private var scheme

    public init(options: [Option], selection: Binding<ID>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(options) { option in
                let selected = option.id == selection
                Button {
                    withAnimation(Motion.quick) { selection = option.id }
                } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: option.symbol).font(.system(size: 11, weight: .medium))
                        if selected { Text(option.title).font(TypeScale.callout.weight(.medium)) }
                    }
                    .foregroundStyle(selected ? Palette.accent : Palette.textSecondary.color)
                    // Icon-only pills are all one square size; the selected one adds its title,
                    // with its content starting 12 pt in like every other container.
                    .padding(.horizontal, selected ? Space.m : 0)
                    .frame(minWidth: Metrics.controlRow, minHeight: Metrics.controlRow)
                    .background(Capsule().fill(selected ? Palette.accent.opacity(0.18) : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(option.title)
                .accessibilityLabel(option.title)
                .accessibilityIdentifier("filter-\(option.title)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Sentence-case section label ("Today", "Yesterday"), on the content column (12 pt inside
/// the cards' edge). A header after other items gets an extra 8 pt above it.
public struct SectionHeader: View {
    let title: String
    let isFirst: Bool
    public init(_ title: String, isFirst: Bool = false) {
        self.title = title
        self.isFirst = isFirst
    }
    public var body: some View {
        Text(title)
            .font(TypeScale.section)
            .foregroundStyle(Palette.textSecondary.color)
            .padding(.leading, Space.m)
            .padding(.top, isFirst ? 0 : Space.s) // more space above a header than below it
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("section-\(title)")
    }
}

/// One keyboard hint ("⇧↩ new line"): quiet on purpose, in the placeholder tone and one weight,
/// so it never reads as a button.
public struct KeyHint: View {
    let key: String
    let label: String
    let tone: Color?
    /// `tone`: pass the paper's secondary ink when the hint sits on a tinted note.
    public init(_ key: String, _ label: String, tone: Color? = nil) {
        self.key = key
        self.label = label
        self.tone = tone
    }
    public var body: some View {
        Text(key + " " + label)
            .font(TypeScale.caption)
            .foregroundStyle(tone ?? Palette.hint)
    }
}
