import AppKit
import Combine
import StickyCore
import StickyDesign

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings.shared
    private(set) var store: ItemStore!
    private var capture: CaptureService!
    private var links: LinkPreviewService!
    private(set) var panel: PanelController!
    private var corners: CornerManager!
    private let statusItem = StatusItemController()
    private var settingsWindow: SettingsWindowController?
    private var onboarding: OnboardingWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Snapshot.runIfRequested() { return }
        MainMenu.install()
        if SelfTest.runIfRequested(app: self) { return } // isolated: own library, no corners/menu/hotkey
        if LayoutAudit.runIfRequested() { return }        // isolated too: sample library
        openLibrary()

        panel = PanelController(store: store, capture: capture, settings: settings)
        panel.onOpenSettings = { [weak self] in self?.showSettings() }

        corners = CornerManager(settings: settings)
        corners.isPanelOpen = { [weak self] in self?.panel.isShown ?? false }
        corners.onActivate = { [weak self] screen in
            self?.onboarding?.model.cornerActivated()
            self?.togglePanel(on: screen)
        }
        corners.onDragOpen = { [weak self] screen in
            guard let self, !self.panel.isShown else { return }
            self.panel.showForDrop(.corner(screen, self.settings.corner))
        }
        corners.onDrop = { [weak self] pasteboard in
            self?.panel.model.drop(pasteboard, source: DropTypes.currentSourceApp()) ?? false
        }
        panel.onVisibilityChange = { [weak self] open in self?.corners.panelVisibilityChanged(open) }
        corners.start()

        statusItem.onToggle = { [weak self] rect, screen in self?.panel.toggle(.below(rect, screen)) }
        statusItem.onSettings = { [weak self] in self?.showSettings() }
        statusItem.onSetup = { [weak self] in self?.showOnboarding() }
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
        NotificationCenter.default.publisher(for: .showOnboarding).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.showOnboarding() }
            .store(in: &cancellables)

        links.backfill()
        if settings.needsOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                MainActor.assumeIsolated { self?.showOnboarding() }
            }
        }
    }

    private func openLibrary() {
        do {
            store = try ItemStore()
        } catch {
            // Never leave you without a stash: run on a temporary library and say so.
            Log.store.fault("Could not open library: \(error.localizedDescription)")
            store = try? ItemStore(paths: .temporary(), inMemory: true)
            let alert = NSAlert()
            alert.messageText = "Sticky Things couldn’t open its library"
            alert.informativeText = "\(error.localizedDescription)\n\nThings you save now are kept until you quit."
            alert.runModal()
        }
        LegacyImporter.importIfNeeded(into: store)
        store.applyRetention(days: settings.retentionDays)
        store.collectGarbage()
        capture = CaptureService(store: store)
        links = LinkPreviewService(store: store)
        links.isEnabled = { [settings] in settings.fetchLinkPreviews }
        store.onLinkNeedsPreview = { [weak self] item in self?.links.fetch(item) }
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    /// stickythings://open · stickythings://settings · stickythings://setup · stickythings://add?text=…
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "stickythings" {
            switch url.host() {
            case "open", "toggle": togglePanelAtPointer()
            case "settings": showSettings()
            case "setup": showOnboarding()
            case "add", "new":
                let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "text" })?.value
                if let text { capture.saveNote(text) }
            default: break
            }
        }
    }

    // MARK: Actions

    private func togglePanel(on screen: NSScreen) {
        panel.toggle(.corner(screen, settings.corner))
    }

    func togglePanelAtPointer() {
        let screen = CornerManager.screen(containing: NSEvent.mouseLocation) ?? NSScreen.main
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

    func showOnboarding() {
        if panel.isShown { panel.hide(reason: "onboarding", restoringFocus: false) }
        if onboarding == nil || onboarding?.window?.isVisible == false {
            onboarding = OnboardingWindowController(settings: settings)
        }
        onboarding?.present()
    }
}
