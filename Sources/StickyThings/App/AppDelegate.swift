import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings.shared
    let store = NoteStore()
    private lazy var linkFetcher = LinkPreviewFetcher(store: store)
    private var panel: PanelController!
    private var corners: CornerManager!
    private let statusItem = StatusItemController()
    private var settingsWindow: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Snapshot.runIfRequested() { return }

        MainMenu.install()
        store.load()
        store.applyRetention(days: settings.retentionDays)
        store.garbageCollectMedia()
        linkFetcher.isEnabled = { [settings] in settings.fetchLinkPreviews }
        store.onLinkAdded = { [weak self] note in self?.linkFetcher.fetch(note) }

        panel = PanelController(store: store, settings: settings)
        panel.onOpenSettings = { [weak self] in self?.showSettings() }

        corners = CornerManager(settings: settings)
        corners.isPanelOpen = { [weak self] in self?.panel.isShown ?? false }
        corners.onActivate = { [weak self] screen in self?.togglePanel(on: screen) }
        corners.onDrop = { [weak self] pasteboard in
            guard let self else { return false }
            let contents = Clip.read(from: pasteboard)
            return !contents.isEmpty && !self.store.add(contents).isEmpty
        }
        panel.onVisibilityChange = { [weak self] open in self?.corners.panelVisibilityChanged(open) }
        corners.start()

        statusItem.onToggle = { [weak self] rect, screen in self?.panel.toggle(.below(rect, screen)) }
        statusItem.onSettings = { [weak self] in self?.showSettings() }
        statusItem.hotKeyDescription = { [weak self] in self?.settings.hotKey?.displayString }
        statusItem.setVisible(settings.showMenuBarIcon)

        GlobalHotKey.shared.onPress = { [weak self] in self?.togglePanelAtPointer() }
        GlobalHotKey.shared.register(settings.hotKey)

        settings.$showMenuBarIcon.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] visible in self?.statusItem.setVisible(visible) }
            .store(in: &cancellables)
        settings.$hotKey.dropFirst().receive(on: RunLoop.main)
            .sink { combo in GlobalHotKey.shared.register(combo) }
            .store(in: &cancellables)

        linkFetcher.backfill()

        if !settings.hasLaunchedBefore {
            settings.hasLaunchedBefore = true
            // Say hello from the corner itself, so you see where it lives.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                MainActor.assumeIsolated { self?.togglePanelAtPointer(primary: true) }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    /// stickythings://open · stickythings://settings · stickythings://add?text=…
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "stickythings" {
            switch url.host() {
            case "open", "toggle": togglePanelAtPointer()
            case "settings": showSettings()
            case "add", "new":
                let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "text" })?.value
                if let text { store.addText(text) }
            default: break
            }
        }
    }

    // MARK: Actions

    private func togglePanel(on screen: NSScreen) {
        panel.toggle(.corner(screen, settings.corner))
    }

    private func togglePanelAtPointer(primary: Bool = false) {
        let screen = primary ? NSScreen.screens.first : (CornerManager.screen(containing: NSEvent.mouseLocation) ?? NSScreen.main)
        guard let screen else { return }
        panel.toggle(.corner(screen, settings.corner))
    }

    @objc func showSettingsAction(_ sender: Any?) { showSettings() }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings, store: store)
        }
        settingsWindow?.show()
    }
}
