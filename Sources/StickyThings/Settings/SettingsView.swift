import AppKit
import StickyCore
import StickyDesign
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case corner, general, notes, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .corner: return "Corner"
        case .general: return "General"
        case .notes: return "Notes"
        case .about: return "About"
        }
    }
    var symbol: String {
        switch self {
        case .corner: return "rectangle.inset.bottomright.filled"
        case .general: return "gearshape"
        case .notes: return "note.text"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var store: ItemStore
    @State var pane: SettingsPane = .corner

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(pane.title)
                    .font(TypeScale.display)
                    .padding(.horizontal, 24)
                    .padding(.top, 34)
                Group {
                    switch pane {
                    case .corner: CornerSettings(settings: settings)
                    case .general: GeneralSettings(settings: settings)
                    case .notes: NotesSettings(settings: settings, store: store)
                    case .about: AboutSettings(settings: settings)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 680, minHeight: 500)
        .background(Palette.surface.color)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPane.allCases) { item in
                Button { pane = item } label: {
                    HStack(spacing: Space.s + 1) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(pane == item ? Palette.accent : Palette.textSecondary.color)
                            .frame(width: 22, height: 22)
                        Text(item.title).font(TypeScale.body)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: Radius.s + 2, style: .continuous)
                        .fill(pane == item ? Palette.accent.opacity(0.18) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 52) // room for the window buttons
        .frame(width: 200)
        .frame(maxHeight: .infinity)
        .background(Palette.surfaceSunken.color)
    }
}

extension Notification.Name {
    static let showOnboarding = Notification.Name("app.stickythings.showOnboarding")
}

extension SettingsPane {
    var tint: Color {
        switch self {
        case .corner: return .orange
        case .general: return .gray
        case .notes: return .yellow
        case .about: return .blue
        }
    }
}

private struct CornerSettings: View {
    @ObservedObject var settings: Settings
    @State private var refresh = 0

    private var cornerBadges: [ScreenCorner: String] {
        let _ = refresh
        var badges: [ScreenCorner: String] = [:]
        for corner in ScreenCorner.allCases { badges[corner] = MacHotCorners.conflictingAction(for: corner) }
        return badges
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        CornerPicker(corner: $settings.corner, badges: cornerBadges)
                        Text("Sticky Things lives in the **\(settings.corner.name.lowercased())** corner")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }

            Section {
                Picker("Open the panel by", selection: $settings.trigger) {
                    Text("Clicking the corner").tag(CornerTrigger.click)
                    Text("Resting the pointer there").tag(CornerTrigger.hover)
                }
                .pickerStyle(.radioGroup)
                if settings.trigger == .hover {
                    LabeledContent("Delay") {
                        HStack {
                            Slider(value: $settings.hoverDelay, in: 0...1, step: 0.05)
                            Text(settings.hoverDelay == 0 ? "Instant" : String(format: "%.2fs", settings.hoverDelay))
                                .monospacedDigit().frame(width: 52, alignment: .trailing)
                        }
                    }
                }
                Toggle("Peek a little note when the pointer reaches the corner", isOn: $settings.showPeek)
                Toggle("Use the corner on every display", isOn: $settings.allDisplays)
            } footer: {
                Text("Tip: drag a file, image or text onto the corner to stash it without opening anything.")
            }

            Section("macOS Hot Corners") {
                let _ = refresh
                if let action = MacHotCorners.conflictingAction(for: settings.corner) {
                    Label {
                        Text("macOS also runs **\(action)** from this corner, so both will open.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning.color)
                    }
                    HStack {
                        Button("Turn Off \(action) Corner") {
                            MacHotCorners.disable(settings.corner)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { refresh += 1 }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Open Hot Corners Settings…") { MacHotCorners.openHotCornersSettings() }
                    }
                    Text("“Turn Off” sets that macOS hot corner to “–” and restarts the Dock. You can change it back any time in System Settings › Desktop & Dock › Hot Corners.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("No macOS hot corner uses this corner.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Palette.success.color)
                }
                Button("Run the Setup Guide Again…") {
                    NotificationCenter.default.post(name: .showOnboarding, object: nil)
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh += 1 }
    }
}

private struct GeneralSettings: View {
    @ObservedObject var settings: Settings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLogin.set(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                if LaunchAtLogin.needsApproval {
                    Button("Approve in Login Items…") { LaunchAtLogin.openLoginItemsSettings() }
                }
                Toggle("Show icon in the menu bar", isOn: $settings.showMenuBarIcon)
            } footer: {
                if !settings.showMenuBarIcon {
                    Text("To get back here without the icon, open Sticky Things again from Applications, or click ⚙︎ in the panel.")
                }
            }

            Section {
                LabeledContent("Open from anywhere") {
                    HotKeyRecorder(combo: $settings.hotKey)
                }
            } footer: {
                Text("Works in every app, even full screen.")
            }

            Section {
                Toggle("Show page titles and icons for saved links", isOn: $settings.fetchLinkPreviews)
            } footer: {
                Text("Fetches the page once when you save a link, like Messages does.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct NotesSettings: View {
    @ObservedObject var settings: Settings
    @ObservedObject var store: ItemStore
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Saved") {
                    let pinned = store.pinned.count
                    Text("\(store.items.count) things" + (pinned > 0 ? " · \(pinned) pinned" : ""))
                }
                LabeledContent("Space used") {
                    Text(ByteCountFormatter.string(fromByteCount: store.diskUsage, countStyle: .file))
                }
                Picker("Keep unpinned things", selection: $settings.retentionDays) {
                    Text("Forever").tag(0)
                    Text("For 1 year").tag(365)
                    Text("For 90 days").tag(90)
                    Text("For 30 days").tag(30)
                    Text("For 7 days").tag(7)
                }
                .onChange(of: settings.retentionDays) { _, days in store.applyRetention(days: days) }
            } footer: {
                Text("Pinned things are always kept. Everything stays on this Mac, in ~/Library/Application Support/Sticky Things. Files you add are kept as copies (instant APFS clones), so they survive the original being moved or deleted.")
            }

            Section {
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.paths.root]) }
                    Spacer()
                    Button("Delete Everything…", role: .destructive) { confirmDelete = true }
                        .disabled(store.items.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all \(store.items.count) things?", isPresented: $confirmDelete) {
            Button("Delete Unpinned", role: .destructive) { store.deleteAll(keepPinned: true) }
            Button("Delete Everything", role: .destructive) { store.deleteAll(keepPinned: false) }
        } message: {
            Text("This can’t be undone.")
        }
    }
}

private struct AboutSettings: View {
    @ObservedObject var settings: Settings

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sticky Things").font(.title2.weight(.semibold))
                        Text("Version \(version)").foregroundStyle(.secondary)
                        Text("Quick notes that are actually quick. Click a corner, paste anything.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("In the panel") {
                shortcut("↩", "Save what you typed · copy the selected note and close")
                shortcut("⌘V", "Save whatever is on the clipboard instantly")
                shortcut("⌥⌘V", "Paste into the text box to edit before saving")
                shortcut("⇧↩", "New line")
                shortcut("↑ ↓", "Browse your notes")
                shortcut("⌘C", "Copy the selected note")
                shortcut("⌘E · ⌘O", "Edit · open the selected note")
                shortcut("⌘P", "Pin / unpin")
                shortcut("⌘⌫", "Delete (⌘Z to undo)")
                shortcut("⌘1 – ⌘9", "Copy a pinned note and close")
                shortcut("⌘F", "Search")
                shortcut("esc", "Close")
                if let combo = settings.hotKey { shortcut(combo.displayString, "Open from anywhere") }
            }
        }
        .formStyle(.grouped)
    }

    private func shortcut(_ keys: String, _ description: String) -> some View {
        LabeledContent {
            Text(description).foregroundStyle(.secondary)
        } label: {
            Text(keys).font(.system(.body, design: .rounded).weight(.semibold)).frame(minWidth: 70, alignment: .leading)
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: Settings
    private let store: ItemStore

    init(settings: Settings, store: ItemStore) {
        self.settings = settings
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Sticky Things"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("StickyThingsSettings")
        super.init(window: window)
        window.delegate = self
        show(pane: .corner, activate: false)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(pane: SettingsPane = .corner, activate: Bool = true) {
        window?.contentView = NSHostingView(rootView: SettingsView(settings: settings, store: store, pane: pane))
        guard activate else { return }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
