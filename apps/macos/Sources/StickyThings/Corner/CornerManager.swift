import AppKit
import Combine

/// Keeps one hot-corner window per display and rebuilds them when displays or settings change.
@MainActor
final class CornerManager {
    private(set) var windows: [CornerWindow] = []
    private let settings: Settings
    private let dragWatcher = DragSessionWatcher()
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var rebuildScheduled = false

    /// Called with the screen whose corner was clicked/hovered.
    var onActivate: ((NSScreen) -> Void)?
    /// Called when a drag has rested in the corner long enough to open the panel.
    var onDragOpen: ((NSScreen) -> Void)?
    var onDrop: ((NSPasteboard) -> Bool)?
    var isPanelOpen: () -> Bool = { false }

    init(settings: Settings) {
        self.settings = settings
    }

    func start() {
        rebuild()
        dragWatcher.onDragChange = { [weak self] dragging in
            guard let self else { return }
            if dragging { self.windows.forEach { $0.dragSessionBegan() } }
            else { self.windows.forEach { $0.dragSessionEnded() } }
        }
        dragWatcher.start()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windows.forEach { $0.orderFrontRegardless() } }
        })

        // Settings publish *before* they change, so hop to the next run loop turn.
        Publishers.MergeMany(
            settings.$corner.map { _ in () }.eraseToAnyPublisher(),
            settings.$allDisplays.map { _ in () }.eraseToAnyPublisher(),
            settings.$trigger.map { _ in () }.eraseToAnyPublisher(),
            settings.$hoverDelay.map { _ in () }.eraseToAnyPublisher(),
            settings.$showPeek.map { _ in () }.eraseToAnyPublisher(),
            settings.$dragToOpen.map { _ in () }.eraseToAnyPublisher(),
            settings.$dragOpenDelay.map { _ in () }.eraseToAnyPublisher(),
            settings.$dragTriggerArea.map { _ in () }.eraseToAnyPublisher()
        )
        .dropFirst(8)
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.scheduleRebuild() }
        .store(in: &cancellables)
    }

    func panelVisibilityChanged(_ open: Bool) {
        windows.forEach { $0.panelVisibilityChanged(open) }
    }

    private func scheduleRebuild() {
        guard !rebuildScheduled else { return }
        rebuildScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.rebuildScheduled = false
                self?.rebuild()
            }
        }
    }

    func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()

        let all = NSScreen.screens
        guard let primary = all.first else { return }
        let frames = all.map(\.frame)
        let corner = settings.corner
        var screens = settings.allDisplays ? all : [primary]
        screens = screens.filter { ScreenCorner.isHard(corner, of: $0.frame, among: frames) }
        if screens.isEmpty { screens = [primary] }

        for screen in screens {
            let window = CornerWindow(screen: screen, corner: corner, showPeek: settings.showPeek)
            window.trigger = settings.trigger
            window.hoverDelay = settings.hoverDelay
            window.dragToOpen = settings.dragToOpen
            window.dragOpenDelay = settings.dragOpenDelay
            window.dragTriggerArea = settings.dragTriggerArea.size
            window.isPanelOpen = { [weak self] in self?.isPanelOpen() ?? false }
            window.onActivate = { [weak self, weak screen] in
                guard let self, let screen else { return }
                self.onActivate?(screen)
            }
            window.onDragOpen = { [weak self, weak screen] in
                guard let self, let screen else { return }
                self.onDragOpen?(screen)
            }
            window.onDrop = { [weak self] pasteboard in self?.onDrop?(pasteboard) ?? false }
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    /// The display a point (in screen coordinates) is on.
    static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}
