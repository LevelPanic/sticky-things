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

/// Which pane Settings shows. The window controller switches it (e.g. "Set Up Corner…").
@MainActor
final class SettingsNavigation: ObservableObject {
    /// Never nil for long: a click on the sidebar's empty space keeps the current pane.
    @Published var pane: SettingsPane? = .corner {
        didSet { if pane == nil { pane = oldValue ?? .corner } }
    }
    init(pane: SettingsPane = .corner) { self.pane = pane }
}

/// Settings on the system's own layout, like System Settings: a sidebar, the pane's title in
/// the toolbar, and grouped forms. Nothing here is positioned by hand, so the sidebar, title and
/// form line up the way every Mac app's do.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var store: ItemStore
    @ObservedObject var navigation: SettingsNavigation

    static let size = CGSize(width: 720, height: 560)
    static let sidebarWidth: CGFloat = 200

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.pane) {
                ForEach(SettingsPane.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                        .accessibilityIdentifier("pane-\(item.rawValue)")
                }
            }
            .navigationSplitViewColumnWidth(Self.sidebarWidth)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .layoutProbe("settings-detail")
                .navigationTitle(currentPane.title)
        }
        .coordinateSpace(name: LayoutRegistry.space)
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var currentPane: SettingsPane { navigation.pane ?? .corner }

    @ViewBuilder private var detail: some View {
        switch currentPane {
        case .corner: CornerSettings(settings: settings)
        case .general: GeneralSettings(settings: settings)
        case .notes: NotesSettings(settings: settings, store: store)
        case .about: AboutSettings(settings: settings)
        }
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
                VStack(spacing: Space.s) {
                    CornerPicker(corner: $settings.corner, badges: cornerBadges)
                    Text("Sticky Things lives in the **\(settings.corner.name.lowercased())** corner")
                        .font(TypeScale.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.xs)
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
                Toggle("Open the panel when I hold a drag at the corner", isOn: $settings.dragToOpen)
                if settings.dragToOpen {
                    LabeledContent("Drag delay") {
                        HStack {
                            Slider(value: $settings.dragOpenDelay, in: 0.2...1.5, step: 0.05)
                            Text(String(format: "%.2fs", settings.dragOpenDelay))
                                .monospacedDigit().frame(width: 52, alignment: .trailing)
                        }
                    }
                    Picker("Drag trigger area", selection: $settings.dragTriggerArea) {
                        ForEach(CornerDragArea.allCases) { area in Text(area.name).tag(area) }
                    }
                    .pickerStyle(.segmented)
                }
                Toggle("Use the corner on every display", isOn: $settings.allDisplays)
            } footer: {
                Text(settings.dragToOpen
                     ? "Drop right on the corner to save instantly, or hold a drag there until the panel opens and drop it into the panel."
                     : "Tip: drag a file, image or text onto the corner to save it without opening anything.")
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
                        .font(TypeScale.caption).foregroundStyle(.secondary)
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
                    Text(loginError).font(TypeScale.caption).foregroundStyle(Palette.danger.color)
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
                Picker("Clicking a note", selection: $settings.clickAction) {
                    Text("Edits it in place").tag(ClickAction.edit)
                    Text("Copies it").tag(ClickAction.copy)
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text(settings.clickAction == .edit
                     ? "Links, images and files are copied with a click. To copy a note, use its Copy button or ⌘C."
                     : "To edit a note, double-click it, use its Edit button, or press ⌘E.")
            }

            Section {
                LabeledContent("Saved") {
                    let pinned = store.pinned.count
                    Text("\(store.items.count) \(store.items.count == 1 ? "item" : "items")" + (pinned > 0 ? " · \(pinned) pinned" : ""))
                }
                LabeledContent("Space used") {
                    Text(ByteCountFormatter.string(fromByteCount: store.diskUsage, countStyle: .file))
                }
                Picker("Keep unpinned items", selection: $settings.retentionDays) {
                    Text("Forever").tag(0)
                    Text("For 1 year").tag(365)
                    Text("For 90 days").tag(90)
                    Text("For 30 days").tag(30)
                    Text("For 7 days").tag(7)
                }
                .onChange(of: settings.retentionDays) { _, days in store.applyRetention(days: days) }
            } footer: {
                Text("Pinned items are always kept. Everything stays on this Mac, in ~/Library/Application Support/Sticky Things. Files you add are kept as copies (instant APFS clones), so they survive the original being moved or deleted.")
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
        .confirmationDialog("Delete all \(store.items.count) items?", isPresented: $confirmDelete) {
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
                HStack(spacing: Space.l) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text("Sticky Things").font(TypeScale.title)
                        Text("Version \(version)").font(TypeScale.callout).foregroundStyle(.secondary)
                        Text("Quick notes that are actually quick. Click a corner, paste anything.")
                            .font(TypeScale.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, Space.xs)
            }
            Section("In the panel") {
                shortcut("↩", "Save what you typed · copy the selected note and close")
                shortcut("⌘V", "Save whatever is on the clipboard instantly")
                shortcut("⌥⌘V", "Paste into the text box to edit before saving")
                shortcut("⇧↩", "New line")
                shortcut("↑ ↓", "Browse your notes")
                shortcut("⌘C", "Copy the selected note")
                shortcut("⌘E · ⌘O", "Edit · open the selected note")
                shortcut("⌘⇧E", "Add or edit text on an image, PDF or file")
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
            Text(keys).font(TypeScale.bodyStrong)
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let navigation = SettingsNavigation()

    init(settings: Settings, store: ItemStore) {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, store: store, navigation: navigation))
        // Let SwiftUI own the toolbar and title, so the pane's title sits in the toolbar and the
        // sidebar runs full height under the window buttons, like System Settings.
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("StickyThingsSettings")
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(pane: SettingsPane = .corner, activate: Bool = true) {
        navigation.pane = pane
        guard activate else { return }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
