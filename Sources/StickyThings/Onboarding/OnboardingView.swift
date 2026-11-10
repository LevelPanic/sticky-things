import AppKit
import StickyDesign
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var settings: Settings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress
                .padding(.top, Space.xl + Space.s)
                .padding(.horizontal, Space.xxl)
            Group {
                switch model.step {
                case .welcome: welcome
                case .corner: chooseCorner
                case .freeCorner: freeCorner
                case .tryIt, .done: tryIt
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.l)
            .transition(.opacity.combined(with: .offset(x: 12)))
            .id(model.step)
            footer
        }
        .frame(width: 580, height: 560)
        .background(Palette.surface.color)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            illustration(highlight: settings.corner, showPointer: false)
            Text("Quick notes that are actually quick").font(TypeScale.display).foregroundStyle(Palette.textPrimary.color)
            Text("Sticky Things lives in a corner of your screen. Click the corner and throw anything in: a thought, a link, a screenshot, a PDF, a file. Click a note to edit it, and copy anything back with one click.")
                .font(.system(size: 14)).foregroundStyle(Palette.textSecondary.color).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chooseCorner: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Pick your corner").font(TypeScale.display).foregroundStyle(Palette.textPrimary.color)
            Text("Corners are the easiest spots on a screen to hit: fling the pointer and you’re there. Bottom right is where Apple’s Quick Note lives, so it’s the natural place to replace it.")
                .font(.system(size: 14)).foregroundStyle(Palette.textSecondary.color).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: Space.xl) {
                CornerPicker(corner: Binding(get: { settings.corner }, set: { model.choose($0) }),
                             badges: model.cornerActions.mapValues { $0 })
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(settings.corner.name).font(TypeScale.bodyStrong).foregroundStyle(Palette.textPrimary.color)
                    if let action = model.conflict {
                        Label("macOS uses it for \(action). We’ll fix that next.", systemImage: "exclamationmark.triangle.fill")
                            .font(TypeScale.footnote).foregroundStyle(Palette.warning.color)
                    } else {
                        Label("Free to use", systemImage: "checkmark.circle.fill")
                            .font(TypeScale.footnote).foregroundStyle(Palette.success.color)
                    }
                    Picker("Open by", selection: $settings.trigger) {
                        Text("Clicking the corner").tag(CornerTrigger.click)
                        Text("Resting the pointer there").tag(CornerTrigger.hover)
                    }
                    .pickerStyle(.radioGroup)
                    .font(TypeScale.footnote)
                    .padding(.top, Space.s)
                }
            }
        }
    }

    private var freeCorner: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Free up the corner").font(TypeScale.display).foregroundStyle(Palette.textPrimary.color)
            Text("macOS doesn’t let apps add themselves to its Hot Corners menu, so Sticky Things watches the corner itself. Set the macOS hot corner to “–” so only one thing opens.")
                .font(.system(size: 14)).foregroundStyle(Palette.textSecondary.color).fixedSize(horizontal: false, vertical: true)
            statusRow
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.m) {
                    Button { model.freeCornerForMe() } label: { Text("Turn It Off for Me").frame(minWidth: 150) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(model.conflict == nil || model.waitingForDock)
                    Text("Sets \(settings.corner.name) to “–” and restarts the Dock (your windows stay put).")
                        .font(TypeScale.footnote).foregroundStyle(Palette.textSecondary.color).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Space.m) {
                    Button { model.openHotCornersSettings() } label: { Text("Open Hot Corners…").frame(minWidth: 150) }
                        .controlSize(.large)
                    Text("Prefer to do it yourself? In the sheet, choose “–” for \(settings.corner.name). This screen updates as soon as you do.")
                        .font(TypeScale.footnote).foregroundStyle(Palette.textSecondary.color).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.l)
            .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Palette.surfaceRaised.color))
            .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).strokeBorder(Palette.border.color))
        }
    }

    private var statusRow: some View {
        HStack(spacing: Space.s) {
            if let action = model.conflict {
                Image(systemName: model.waitingForDock ? "hourglass" : "exclamationmark.triangle.fill").foregroundStyle(Palette.warning.color)
                Text(model.waitingForDock ? "Restarting the Dock…" : "\(action) is still on \(settings.corner.name)")
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.success.color)
                Text("\(settings.corner.name) is free. Sticky Things has it.")
            }
        }
        .font(TypeScale.bodyStrong)
        .foregroundStyle(Palette.textPrimary.color)
        .animation(Motion.standard, value: model.conflict)
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            illustration(highlight: settings.corner, showPointer: !model.cornerTried)
            Text(model.cornerTried ? "That’s it" : "Now try it").font(TypeScale.display).foregroundStyle(Palette.textPrimary.color)
            Text(model.cornerTried
                 ? "Whenever you need it, fling the pointer into the corner. Paste with ⌘V, type, or drop things on the corner itself."
                 : "Move your pointer all the way into the \(settings.corner.name.lowercased()) corner\(clickSuffix).")
                .font(.system(size: 14)).foregroundStyle(Palette.textSecondary.color).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Space.s) {
                Toggle("Open Sticky Things when I log in", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        try? LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                if let combo = settings.hotKey {
                    Text("Shortcut from any app: \(combo.displayString). You can change it in Settings.")
                        .font(TypeScale.footnote).foregroundStyle(Palette.textSecondary.color)
                }
            }
        }
    }

    private var clickSuffix: String { settings.trigger == .click ? " and click" : "" }

    // MARK: Chrome

    private var progress: some View {
        HStack(spacing: Space.s) {
            ForEach(model.stepsShown, id: \.self) { step in
                Capsule()
                    .fill(step <= model.step ? Palette.accent : Palette.border.color)
                    .frame(width: step == model.step ? 28 : 14, height: 5)
                    .animation(Motion.standard, value: model.step)
            }
            Spacer()
        }
        .accessibilityLabel("Step \(model.stepsShown.firstIndex(of: model.step).map { $0 + 1 } ?? 4) of \(model.stepsShown.count)")
    }

    private var footer: some View {
        HStack {
            if model.step != .welcome && model.step != .done {
                Button("Back") { model.back() }.controlSize(.large)
            }
            Spacer()
            switch model.step {
            case .welcome:
                Button("Set It Up") { model.next() }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            case .corner:
                Button("Continue") { model.next() }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            case .freeCorner:
                Button(model.conflict == nil ? "Continue" : "Skip for Now") { model.next() }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            case .tryIt, .done:
                Button(model.cornerTried ? "Done" : "Finish") { model.go(to: .done) }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, Space.xxl)
        .padding(.vertical, Space.l)
        .background(Palette.surfaceSunken.color)
    }

    /// A tiny screen with the chosen corner highlighted (and a pointer heading there).
    private func illustration(highlight corner: ScreenCorner, showPointer: Bool) -> some View {
        ScreenIllustration(corner: corner, showPointer: showPointer, success: model.cornerTried)
            .frame(width: 240, height: 150)
    }
}

/// Mini screen: neutral desktop, menu bar, dock, the chosen corner with its peeking note.
struct ScreenIllustration: View {
    let corner: ScreenCorner
    var showPointer: Bool
    var success: Bool
    @State private var pointerAtCorner = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
        ZStack(alignment: corner.alignment) {
            ScreenPreview()
            MiniStickyNote(size: 46, foldCorner: corner.peekFold)
                .rotationEffect(.degrees(corner.isLeft == corner.isTop ? 12 : -12))
                .offset(x: (corner.isLeft ? -1 : 1) * (success ? 12 : 20), y: (corner.isTop ? -1 : 1) * (success ? 12 : 20))
                .elevation(.sticky)
            if showPointer {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Palette.textPrimary.color)
                    .offset(x: pointerAtCorner ? (corner.isLeft ? 4 : -4) : (corner.isLeft ? 90 : -90),
                            y: pointerAtCorner ? (corner.isTop ? 6 : -6) : (corner.isTop ? 60 : -60))
                    .onAppear {
                        guard !Motion.reduceMotion else { pointerAtCorner = true; return }
                        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.4).repeatForever(autoreverses: false)) {
                            pointerAtCorner = true
                        }
                    }
            }
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    let model: OnboardingModel

    init(settings: Settings) {
        model = OnboardingModel(settings: settings)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 560),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(model: model, settings: settings))
        super.init(window: window)
        window.delegate = self
        model.onFinish = { [weak self] in self?.close() }
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        model.start()
    }

    func windowWillClose(_ notification: Notification) {
        model.stop()
        if model.step != .done { model.settings.onboardingVersion = Settings.currentOnboardingVersion }
    }
}
