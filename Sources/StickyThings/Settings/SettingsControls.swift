import AppKit
import SwiftUI

/// A tiny Mac screen; click a corner to choose where Sticky Things lives.
struct CornerPicker: View {
    @Binding var corner: ScreenCorner
    @State private var hovered: ScreenCorner?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.50, blue: 0.95), Color(red: 0.55, green: 0.32, blue: 0.85)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(spacing: 0) {
                Rectangle().fill(.white.opacity(0.35)).frame(height: 9)
                Spacer()
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white.opacity(0.35))
                    .frame(width: 110, height: 14)
                    .padding(.bottom, 6)
            }
            ForEach(ScreenCorner.allCases) { option in
                cornerButton(option)
            }
        }
        .frame(width: 290, height: 182)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.black.opacity(0.25), lineWidth: 3))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }

    private func cornerButton(_ option: ScreenCorner) -> some View {
        let selected = option == corner
        let sx: CGFloat = option.isLeft ? -1 : 1
        let sy: CGFloat = option.isTop ? -1 : 1
        return ZStack(alignment: option.alignment) {
            Color.clear
            if selected || hovered == option {
                MiniStickyNote(size: 44, foldCorner: option.opposite)
                    .rotationEffect(.degrees(option.isLeft == option.isTop ? 12 : -12))
                    .shadow(color: .black.opacity(0.3), radius: 3)
                    .offset(x: sx * (selected ? 14 : 22), y: sy * (selected ? 14 : 22))
                    .opacity(selected ? 1 : 0.55)
                    .transition(.offset(x: sx * 30, y: sy * 30).combined(with: .opacity))
            } else {
                Circle().fill(.white.opacity(0.25)).frame(width: 14, height: 14)
                    .padding(8)
            }
        }
        .frame(width: 145, height: 91)
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovered = inside ? option : nil } }
        .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { corner = option } }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: option.alignment)
        .help(option.name)
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
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
