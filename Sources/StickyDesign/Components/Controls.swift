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

/// Pressed feedback for larger buttons: darken one step, never scale.
public struct PressStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Capsule label for pinned items: 24 pt tall, 12 pt medium, ≤ 160 pt wide.
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
        .padding(.horizontal, Space.s + 2)
        .frame(height: 24)
        .frame(maxWidth: 160)
        .background(Capsule().fill(tint?.color ?? Palette.surfaceRaised.color))
        .overlay(Capsule().strokeBorder(isHighlighted ? Palette.accent : .clear, lineWidth: 2))
        .padding(.vertical, Space.xxs) // 28 pt hit area
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
                    .padding(.horizontal, Space.s + 2)
                    .frame(minWidth: Metrics.minHitTarget + 4, minHeight: Metrics.minHitTarget + 4)
                    .background(Capsule().fill(selected ? Palette.accent.opacity(0.18) : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(option.title)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Sentence-case section label ("Today", "Yesterday").
public struct SectionHeader: View {
    let title: String
    public init(_ title: String) { self.title = title }
    public var body: some View {
        Text(title)
            .font(TypeScale.section)
            .foregroundStyle(Palette.textSecondary.color)
            .padding(.leading, Space.xs)
            .padding(.top, Space.l)     // more space above a header…
            .padding(.bottom, Space.xxs) // …than below it
            .accessibilityAddTraits(.isHeader)
    }
}

/// One keyboard hint ("⌘V saves what you copied").
public struct KeyHint: View {
    let key: String
    let label: String
    public init(_ key: String, _ label: String) {
        self.key = key
        self.label = label
    }
    public var body: some View {
        (Text(key).fontWeight(.semibold) + Text(" " + label))
            .font(TypeScale.caption)
            .foregroundStyle(Palette.textSecondary.color)
    }
}
