import AppKit
import StickyDesign
import SwiftUI

/// A tiny version of *your* screen (your own wallpaper); click a corner to choose it.
/// `badges` marks corners macOS already uses (e.g. "Quick Note").
struct CornerPicker: View {
    @Binding var corner: ScreenCorner
    var badges: [ScreenCorner: String] = [:]
    @State private var hovered: ScreenCorner?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
        ZStack {
            Wallpaper()
            ForEach(ScreenCorner.allCases) { option in
                CornerSpot(option: option, isSelected: option == corner, isHovered: hovered == option, badge: badges[option])
                    .onHover { inside in withAnimation(Motion.quick) { hovered = inside ? option : nil } }
                    .onTapGesture { withAnimation(Motion.emphasized) { corner = option } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: option.alignment)
            }
        }
        .frame(width: 290, height: 182)
        .clipShape(shape)
    }
}

/// The current desktop picture (falls back to a neutral fill).
struct Wallpaper: View {
    var body: some View {
        // Color.clear takes exactly the size it's offered; the photo fills it and is clipped.
        Color.clear
            .overlay {
                if let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen),
                   let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Palette.surfaceSunken.color
                }
            }
            .clipped()
    }
}

private struct CornerSpot: View {
    let option: ScreenCorner
    let isSelected: Bool
    let isHovered: Bool
    let badge: String?

    var body: some View {
        ZStack(alignment: option.alignment) {
            Color.clear
            if isSelected || isHovered { note } else { ring }
            if let badge, !isSelected { badgeView(badge) }
        }
        .frame(width: 145, height: 91)
        .contentShape(Rectangle())
        .help(badge.map { "\(option.name). macOS uses it for \($0)." } ?? option.name)
        .accessibilityElement()
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var note: some View {
        let sx: CGFloat = option.isLeft ? -1 : 1
        let sy: CGFloat = option.isTop ? -1 : 1
        let inset: CGFloat = isSelected ? 14 : 22
        return MiniStickyNote(size: 44, foldCorner: option.peekFold)
            .rotationEffect(.degrees(option.isLeft == option.isTop ? 12 : -12))
            .elevation(.sticky)
            .offset(x: sx * inset, y: sy * inset)
            .opacity(isSelected ? 1 : 0.6)
    }

    private var ring: some View {
        Circle()
            .strokeBorder(.white.opacity(0.85), lineWidth: 1.5)
            .background(Circle().fill(.black.opacity(0.18)))
            .frame(width: 14, height: 14)
            .padding(Space.s + 2)
    }

    private func badgeView(_ text: String) -> some View {
        Text(text)
            .font(TypeScale.caption.weight(.semibold))
            .foregroundStyle(Palette.warningInk.color)
            .padding(.horizontal, Space.xs + 1)
            .padding(.vertical, Space.xxs)
            .background(Capsule().fill(Palette.warningSurface.color))
            .padding(option.isTop ? .top : .bottom, Space.s + 16)
            .padding(option.isLeft ? .leading : .trailing, Space.s)
    }
}

/// Click, then press the shortcut you want.
struct HotKeyRecorder: View {
    @Binding var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Press a shortcut…" : (combo?.displayString ?? "Record Shortcut"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .frame(minWidth: 130)
            }
            .buttonStyle(.bordered)
            .tint(recording ? .accentColor : nil)
            if combo != nil && !recording {
                Button { combo = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove shortcut")
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        message = nil
        recording = true
        GlobalHotKey.shared.isSuspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // esc cancels
            let candidate = KeyCombo(event: event)
            if candidate.isValidGlobalShortcut {
                combo = candidate
                stop()
            } else {
                message = "Add ⌘, ⌥ or ⌃"
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        GlobalHotKey.shared.isSuspended = false
    }
}
