import AppKit
import Quartz
import StickyCore
import StickyDesign
import SwiftUI

enum PanelAnchor {
    /// Bloom out of a screen corner.
    case corner(NSScreen, ScreenCorner)
    /// Drop down from a rect (the menu bar icon), in screen coordinates.
    case below(NSRect, NSScreen)
}

/// The borderless panel. The app activates while it's open so hover, tooltips, menus and
/// Quick Look all behave normally; focus goes back to your previous app when it closes.
final class QuickPanel: NSPanel {
    var keyEquivalentHandler: ((NSEvent, Bool) -> Bool)?
    var fallbackKeyHandler: ((KeyCommand) -> Bool)?
    weak var quickLook: QuickLookController?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true                       // the window server draws a real shadow around the glass
        ignoresMouseEvents = false             // every pixel is ours: no clicks or hovers fall through
        allowsToolTipsWhenApplicationIsInactive = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let textView = firstResponder as? NSTextView
        let hasSelection = (textView?.selectedRange().length ?? 0) > 0
        if keyEquivalentHandler?(event, hasSelection) == true { return true }

        // ⌘V/⌘C/⌘X/⌘A/⌘Z: let the main menu's Edit items handle them (user-initiated paste).
        if let menu = NSApp.mainMenu, menu.performKeyEquivalent(with: event) { return true }
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

    /// Keys that reach the window when no text field has focus.
    override func keyDown(with event: NSEvent) {
        let command: KeyCommand?
        switch Int(event.keyCode) {
        case 126: command = .up
        case 125: command = .down
        case 36, 76: command = .enter
        case 53: command = .escape
        case 48: command = .tab
        case 51 where event.modifierFlags.contains(.command): command = .deleteSelection
        default: command = nil
        }
        if let command, fallbackKeyHandler?(command) == true { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) { _ = fallbackKeyHandler?(.escape) }

    // Quick Look asks the responder chain who controls it.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { quickLook != nil }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { quickLook?.attach(panel) }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { quickLook?.detach(panel) }
}

/// System glass behind the panel: Liquid Glass on macOS 26, a vibrant material before that.
@MainActor
enum PanelChrome {
    static func background(cornerRadius: CGFloat, content: NSView) -> NSView {
        content.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = roundedMask(radius: cornerRadius)
        content.frame = effect.bounds
        effect.addSubview(content)
        return effect
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let size = NSSize(width: radius * 2 + 1, height: radius * 2 + 1)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Clicks count on the first try, even if the panel wasn't key yet.
final class PanelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Hosts the SwiftUI panel and accepts drops of anything from other apps.
final class DropContainerView: NSView {
    var onDragChange: ((Bool) -> Void)?
    var onDrop: ((NSPasteboard) -> Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(DropTypes.all)
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
    private var activatedForFocus = false
    private var previousApp: NSRunningApplication?
    private var outsideClickMonitor: Any?
    private var hideWork: DispatchWorkItem?

    var onVisibilityChange: ((Bool) -> Void)?
    var onOpenSettings: (() -> Void)?

    static let maxHeight: CGFloat = 600
    static let screenInset: CGFloat = 10

    init(store: ItemStore, capture: CaptureService, settings: Settings) {
        model = PanelModel(store: store, capture: capture, settings: settings)
        super.init()
        panel.delegate = self
        panel.quickLook = model.quickLook

        let container = DropContainerView(frame: .zero)
        let host = PanelHostingView(rootView: PanelView(model: model, store: store, settings: settings))
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.onDragChange = { [weak self] targeted in
            withAnimation(Motion.quick) { self?.model.isDropTargeted = targeted }
        }
        container.onDrop = { [weak self] pasteboard in
            self?.model.drop(pasteboard, source: DropTypes.currentSourceApp()) ?? false
        }
        panel.contentView = PanelChrome.background(cornerRadius: Radius.panel, content: container)

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
        // Quick Look's panel only takes the keyboard when our app is active.
        model.needsActivation = { [weak self] in self?.activateForFocus() }
    }

    func toggle(_ anchor: PanelAnchor) {
        isShown ? hide(reason: "toggle") : show(anchor)
    }

    func show(_ anchor: PanelAnchor) {
        hideWork?.cancel()
        let (frame, atBottom, scaleAnchor, travel) = layout(for: anchor)
        model.anchorAtBottom = atBottom
        model.scaleAnchor = scaleAnchor
        model.panelHeight = frame.height

        let wasShown = isShown
        isShown = true
        if !wasShown {
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
            model.sourceApp = previousApp.map { SourceApp(bundleID: $0.bundleIdentifier, name: $0.localizedName) }
        }
        model.isPresented = true
        model.prepareForOpen()

        // Slide a few points out of the corner while fading in (a crossfade with Reduce Motion).
        if !wasShown {
            panel.alphaValue = 0
            panel.setFrame(frame.offsetBy(dx: travel.width, dy: travel.height), display: false)
        }
        // Like Spotlight: take the keyboard without making your current app inactive.
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.reduceMotion ? 0.15 : Motion.panelInDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isShown else { return }
                // macOS only lets a background app take the keyboard right after you interact with
                // it (a click or the hotkey). Opened any other way (e.g. a URL): activate instead.
                if !self.panel.isKeyWindow { self.activateForFocus() }
                self.focusComposer()
                self.panel.invalidateShadow()
                DebugLog.write("shown key=\(self.panel.isKeyWindow) active=\(NSApp.isActive)")
            }
        }
        installOutsideClickMonitor()
        if !wasShown { onVisibilityChange?(true) }
    }

    /// Activates the app (focus goes back to the previous app when the panel closes).
    func activateForFocus() {
        activatedForFocus = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// `restoringFocus`: if we had to activate, hand the keyboard back to the previous app,
    /// but only when *we* closed the panel (never after you clicked into another app).
    func hide(reason: String = "other", restoringFocus: Bool = true) {
        guard isShown else { return }
        DebugLog.write("hide reason=\(reason)")
        isShown = false
        removeOutsideClickMonitor()
        model.didClose()
        model.isPresented = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.reduceMotion ? 0.12 : Motion.panelOutDuration * 0.8
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        })
        onVisibilityChange?(false)
        if restoringFocus, activatedForFocus, NSApp.isActive, let previousApp, !previousApp.isTerminated, !settingsWindowVisible {
            previousApp.activate()
        }
        activatedForFocus = false
        previousApp = nil
    }

    /// Puts the caret in the composer (where typing and ⌘V go).
    func focusComposer() {
        guard let composer = Self.findTextView("composer", in: panel.contentView) else { return }
        panel.initialFirstResponder = composer
        if panel.firstResponder !== composer { panel.makeFirstResponder(composer) }
    }

    static func findTextView(_ identifier: String, in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView, textView.identifier?.rawValue == identifier { return textView }
        for subview in view.subviews {
            if let hit = findTextView(identifier, in: subview) { return hit }
        }
        return nil
    }

    private var settingsWindowVisible: Bool {
        NSApp.windows.contains { $0.isVisible && $0 !== panel && $0.styleMask.contains(.titled) }
    }

    // MARK: Geometry

    private func layout(for anchor: PanelAnchor) -> (NSRect, Bool, UnitPoint, NSSize) {
        let width = PanelLayout.width
        let t = Motion.panelTravel
        switch anchor {
        case let .corner(screen, corner):
            let visible = screen.visibleFrame
            let height = min(Self.maxHeight, visible.height - Self.screenInset * 2)
            let content = corner.rect(size: NSSize(width: width, height: height), in: visible, inset: Self.screenInset)
            let travel = NSSize(width: corner.isLeft ? -t : t, height: corner.isTop ? t : -t)
            return (content, !corner.isTop, corner.unitPoint, travel)
        case let .below(rect, screen):
            let visible = screen.visibleFrame
            let height = min(Self.maxHeight, rect.minY - visible.minY - Self.screenInset - 6)
            var x = rect.midX - width / 2
            x = min(max(x, visible.minX + Self.screenInset), visible.maxX - width - Self.screenInset)
            let content = NSRect(x: x, y: rect.minY - 6 - height, width: width, height: height)
            let anchorX = max(0, min(1, (rect.midX - x) / width))
            return (content, false, UnitPoint(x: anchorX, y: 0), NSSize(width: 0, height: t))
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
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isShown, !self.panel.isKeyWindow else { return }
                // Quick Look, our menus and alerts are part of us; only leave when focus left the app.
                if NSApp.keyWindow is QLPreviewPanel || self.model.quickLook.isVisible { return }
                if NSApp.isActive, NSApp.keyWindow != nil, !(NSApp.keyWindow?.styleMask.contains(.titled) ?? false) { return }
                self.hide(reason: "resignKey", restoringFocus: false)
            }
        }
    }
}
