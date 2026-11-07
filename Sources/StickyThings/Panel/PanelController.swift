import AppKit
import SwiftUI

enum PanelAnchor {
    /// Bloom out of a screen corner.
    case corner(NSScreen, ScreenCorner)
    /// Drop down from a rect (the menu bar icon), in screen coordinates.
    case below(NSRect, NSScreen)
}

/// A borderless panel that can take keyboard focus without activating the app,
/// so the app you were in stays frontmost (like Spotlight).
final class QuickPanel: NSPanel {
    var keyEquivalentHandler: ((NSEvent, Bool) -> Bool)?
    var fallbackKeyHandler: ((KeyCommand) -> Bool)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let textView = firstResponder as? NSTextView
        let hasSelection = (textView?.selectedRange().length ?? 0) > 0
        if keyEquivalentHandler?(event, hasSelection) == true { return true }

        // We are usually not the active app, so the (hidden) main menu never sees these.
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        var selector: Selector?
        if flags == .command {
            switch key {
            case "x": selector = #selector(NSText.cut(_:))
            case "c": selector = #selector(NSText.copy(_:))
            case "v": selector = #selector(NSText.paste(_:))
            case "a": selector = #selector(NSText.selectAll(_:))
            case "z": selector = Selector(("undo:"))
            default: break
            }
        } else if flags == [.command, .shift], key == "z" {
            selector = Selector(("redo:"))
        }
        if let selector, NSApp.sendAction(selector, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// Keys that reach the window when no text field is focused.
    override func keyDown(with event: NSEvent) {
        let command: KeyCommand?
        switch Int(event.keyCode) {
        case 126: command = .up
        case 125: command = .down
        case 36, 76: command = .enter
        case 53: command = .escape
        case 48: command = .tab
        default: command = nil
        }
        if let command, fallbackKeyHandler?(command) == true { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        _ = fallbackKeyHandler?(.escape)
    }
}

/// Hosts the SwiftUI panel and accepts drops from other apps.
final class DropContainerView: NSView {
    var onDragChange: ((Bool) -> Void)?
    var onDrop: ((NSPasteboard) -> Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(Clip.dropTypes)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource == nil else { return [] } // our own cards being dragged out
        onDragChange?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingSource == nil ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { onDragChange?(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragChange?(false)
        return onDrop?(sender.draggingPasteboard) ?? false
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel = QuickPanel()
    let model: PanelModel
    private(set) var isShown = false
    private var previousApp: NSRunningApplication?
    private var activatedForFocus = false
    private var outsideClickMonitor: Any?
    private var hideWork: DispatchWorkItem?

    var onVisibilityChange: ((Bool) -> Void)?
    var onOpenSettings: (() -> Void)?

    static let maxHeight: CGFloat = 580
    static let screenInset: CGFloat = 10

    init(store: NoteStore, settings: Settings) {
        model = PanelModel(store: store, settings: settings)
        super.init()
        panel.delegate = self

        let container = DropContainerView(frame: .zero)
        let host = NSHostingView(rootView: PanelView(model: model, store: store, settings: settings))
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.onDragChange = { [weak self] targeted in
            withAnimation(.easeOut(duration: 0.15)) { self?.model.isDropTargeted = targeted }
        }
        container.onDrop = { [weak self] pasteboard in self?.model.dropped(pasteboard) ?? false }
        panel.contentView = container

        panel.keyEquivalentHandler = { [weak self] event, hasSelection in
            self?.model.handleKeyEquivalent(event, textHasSelection: hasSelection) ?? false
        }
        panel.fallbackKeyHandler = { [weak self] command in
            self?.model.handleComposerCommand(command) ?? false
        }
        model.close = { [weak self] in self?.hide(reason: "model") }
        // Opening a link/file hands focus to that app, so don't pull it back.
        model.closeForHandoff = { [weak self] in self?.hide(reason: "handoff", restoringFocus: false) }
        model.openSettings = { [weak self] in
            self?.hide(reason: "settings", restoringFocus: false)
            self?.onOpenSettings?()
        }
    }

    func toggle(_ anchor: PanelAnchor) {
        isShown ? hide(reason: "toggle") : show(anchor)
    }

    func show(_ anchor: PanelAnchor) {
        hideWork?.cancel()
        let (frame, atBottom, scaleAnchor) = layout(for: anchor)
        model.anchorAtBottom = atBottom
        model.scaleAnchor = scaleAnchor
        model.panelHeight = frame.height - PanelView.margin * 2
        model.prepareForOpen()

        let wasShown = isShown
        isShown = true
        if !wasShown {
            model.isPresented = false
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        }
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isShown else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { self.model.isPresented = true }
                // macOS only lets a background app take keyboard focus right after you interact
                // with it. If it said no (e.g. opened from a URL), activate and hand focus back on close.
                if !self.panel.isKeyWindow {
                    self.activatedForFocus = true
                    NSApp.activate(ignoringOtherApps: true)
                    self.panel.makeKeyAndOrderFront(nil)
                }
            }
        }
        installOutsideClickMonitor()
        if !wasShown { onVisibilityChange?(true) }
        if UserDefaults.standard.bool(forKey: "debugLogging") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    DebugLog.write("shown key=\(self.panel.isKeyWindow) appActive=\(NSApp.isActive) firstResponder=\(self.panel.firstResponder.map { String(describing: type(of: $0)) } ?? "nil") frame=\(self.panel.frame)")
                }
            }
        }
    }

    /// `restoringFocus`: give the keyboard back to the previous app (only when *we* closed the
    /// panel — never after you clicked into another app, or we'd steal focus from it).
    func hide(reason: String = "other", restoringFocus: Bool = true) {
        DebugLog.write("hide reason=\(reason) key=\(panel.isKeyWindow) active=\(NSApp.isActive)")
        guard isShown else { return }
        isShown = false
        removeOutsideClickMonitor()
        withAnimation(.easeIn(duration: 0.12)) { model.isPresented = false }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return }
                self.panel.orderOut(nil)
                if self.model.editingID != nil { self.model.cancelEditing() }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
        model.store.saveNow()
        onVisibilityChange?(false)
        restoreFocus(restoringFocus)
    }

    /// If we had to activate to get the keyboard, give it back to the app you were in.
    private func restoreFocus(_ wanted: Bool) {
        defer { activatedForFocus = false; previousApp = nil }
        guard wanted, activatedForFocus, NSApp.isActive else { return }
        let settingsOpen = NSApp.windows.contains { $0.isVisible && $0 !== panel && $0.styleMask.contains(.titled) }
        guard !settingsOpen, let previousApp, !previousApp.isTerminated else { return }
        previousApp.activate()
    }

    // MARK: Geometry

    private func layout(for anchor: PanelAnchor) -> (NSRect, Bool, UnitPoint) {
        let width = PanelView.width
        let margin = PanelView.margin
        switch anchor {
        case let .corner(screen, corner):
            let visible = screen.visibleFrame
            let height = min(Self.maxHeight, visible.height - Self.screenInset * 2)
            let content = corner.rect(size: NSSize(width: width, height: height), in: visible, inset: Self.screenInset)
            return (content.insetBy(dx: -margin, dy: -margin), !corner.isTop, corner.unitPoint)
        case let .below(rect, screen):
            let visible = screen.visibleFrame
            let height = min(Self.maxHeight, rect.minY - visible.minY - Self.screenInset - 6)
            var x = rect.midX - width / 2
            x = min(max(x, visible.minX + Self.screenInset), visible.maxX - width - Self.screenInset)
            let content = NSRect(x: x, y: rect.minY - 6 - height, width: width, height: height)
            let anchorX = max(0, min(1, (rect.midX - x) / width))
            return (content.insetBy(dx: -margin, dy: -margin), false, UnitPoint(x: anchorX, y: 0))
        }
    }

    // MARK: Dismissal

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        // Global monitors only see clicks that go to *other* apps — exactly "clicked outside".
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.keepOpen else { return }
                self.hide(reason: "outsideClick", restoringFocus: false)
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isShown, !model.keepOpen else { return }
        // Give a click on our own corner/menu icon a moment to toggle instead of re-open.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isShown, !self.panel.isKeyWindow else { return }
                self.hide(reason: "resignKey", restoringFocus: false)
            }
        }
    }
}
