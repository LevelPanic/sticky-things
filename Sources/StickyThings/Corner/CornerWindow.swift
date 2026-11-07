import AppKit
import SwiftUI

@MainActor
final class CornerPeekModel: ObservableObject {
    enum Phase: Equatable { case hidden, peek, dropTarget, saved, panelOpen }
    @Published var phase: Phase = .hidden
    @Published var showsNote = true
    let corner: ScreenCorner
    init(corner: ScreenCorner) { self.corner = corner }
}

/// The invisible hot zone in a screen corner. It grows a little when the pointer
/// arrives so a sticky note can peek out, and becomes a drop target while dragging.
@MainActor
final class CornerWindow: NSPanel {
    static let idleSize: CGFloat = 6
    static let peekSize: CGFloat = 96
    static let dropSize: CGFloat = 156
    static let canvasSize: CGFloat = 156

    let corner: ScreenCorner
    private(set) var screenFrame: NSRect
    let model: CornerPeekModel
    weak var screen_: NSScreen?

    var trigger: CornerTrigger = .click
    var hoverDelay: Double = 0.25
    var onActivate: (() -> Void)?
    var onDrop: ((NSPasteboard) -> Bool)?
    var isPanelOpen: () -> Bool = { false }

    private var dwellTimer: Timer?
    private var shrinkWork: DispatchWorkItem?
    private var pointerInside = false

    init(screen: NSScreen, corner: ScreenCorner, showPeek: Bool) {
        self.corner = corner
        self.screenFrame = screen.frame
        self.screen_ = screen
        self.model = CornerPeekModel(corner: corner)
        model.showsNote = showPeek
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.idleSize, height: Self.idleSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = false // catch the pointer even though we're transparent
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none

        let hit = CornerHitView(window: self)
        let host = NSHostingView(rootView: CornerPeekView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: Self.canvasSize, height: Self.canvasSize)
        hit.host = host
        hit.addSubview(host)
        contentView = hit
        setSize(Self.idleSize)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setSize(_ size: CGFloat) {
        let rect = corner.rect(size: NSSize(width: size, height: size), in: screenFrame)
        setFrame(rect, display: true)
        contentView?.needsLayout = true
    }

    // MARK: Pointer

    func pointerEntered() {
        pointerInside = true
        shrinkWork?.cancel()
        if frame.width < Self.peekSize { setSize(Self.peekSize) }
        guard !isPanelOpen() else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) { model.phase = .peek }
        if trigger == .hover {
            dwellTimer?.invalidate()
            dwellTimer = Timer.scheduledTimer(withTimeInterval: max(0.05, hoverDelay), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.pointerInside, !self.isPanelOpen() else { return }
                    self.activate()
                }
            }
        }
    }

    func pointerExited() {
        pointerInside = false
        dwellTimer?.invalidate()
        guard model.phase != .saved else { return }
        withAnimation(.easeIn(duration: 0.18)) {
            model.phase = isPanelOpen() ? .panelOpen : .hidden
        }
        scheduleShrink()
    }

    func clicked() {
        dwellTimer?.invalidate()
        activate()
    }

    private func activate() {
        withAnimation(.easeOut(duration: 0.15)) { model.phase = .panelOpen }
        onActivate?()
    }

    /// Keeps the peek in sync when the panel opens/closes from elsewhere.
    func panelVisibilityChanged(_ open: Bool) {
        if open {
            withAnimation(.easeOut(duration: 0.15)) { model.phase = .panelOpen }
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                model.phase = pointerInside ? .peek : .hidden
            }
            if !pointerInside { scheduleShrink() }
        }
    }

    private func scheduleShrink(after delay: Double = 0.3) {
        shrinkWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.pointerInside else { return }
                if self.model.phase == .panelOpen && self.isPanelOpen() { /* stay small but keep state */ }
                self.setSize(Self.idleSize)
            }
        }
        shrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Drag & drop

    func dragEntered() {
        shrinkWork?.cancel()
        dwellTimer?.invalidate()
        setSize(Self.dropSize)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { model.phase = .dropTarget }
    }

    func dragExited() {
        withAnimation(.easeIn(duration: 0.18)) { model.phase = .hidden }
        pointerInside = false
        scheduleShrink()
    }

    func performDrop(_ pasteboard: NSPasteboard) -> Bool {
        let ok = onDrop?(pasteboard) ?? false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { model.phase = ok ? .saved : .hidden }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.phase == .saved else { return }
                withAnimation(.easeIn(duration: 0.25)) { self.model.phase = .hidden }
                self.pointerInside = false
                self.scheduleShrink(after: 0.3)
            }
        }
        return ok
    }
}

/// Receives the pointer, clicks and drops for the corner; the SwiftUI drawing sits inside it.
@MainActor
private final class CornerHitView: NSView {
    weak var cornerWindow: CornerWindow?
    var host: NSView?
    private var trackingArea: NSTrackingArea?

    init(window: CornerWindow) {
        cornerWindow = window
        super.init(frame: .zero)
        registerForDraggedTypes(Clip.dropTypes)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        guard let host, let corner = cornerWindow?.corner else { return }
        let size = CornerWindow.canvasSize
        host.frame = NSRect(x: corner.isLeft ? 0 : bounds.width - size,
                            y: corner.isTop ? bounds.height - size : 0,
                            width: size, height: size)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { cornerWindow?.pointerEntered() }
    override func mouseExited(with event: NSEvent) { cornerWindow?.pointerExited() }
    override func mouseDown(with event: NSEvent) { cornerWindow?.clicked() }
    override func rightMouseDown(with event: NSEvent) { cornerWindow?.clicked() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource == nil else { return [] } // ignore drags of our own cards
        cornerWindow?.dragEntered()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingSource == nil ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { cornerWindow?.dragExited() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        cornerWindow?.performDrop(sender.draggingPasteboard) ?? false
    }
}

/// The note that peeks out of the corner.
struct CornerPeekView: View {
    @ObservedObject var model: CornerPeekModel
    private let noteSize: CGFloat = 70

    var body: some View {
        let corner = model.corner
        let sx: CGFloat = corner.isLeft ? -1 : 1
        let sy: CGFloat = corner.isTop ? -1 : 1
        let visible = visibleAmount
        let hiddenBy = noteSize - visible

        ZStack(alignment: corner.alignment) {
            Color.clear
            if model.phase == .dropTarget || model.phase == .saved {
                RadialGradient(colors: [Color.accentColor.opacity(0.45), Color.accentColor.opacity(0.0)],
                               center: corner.unitPoint, startRadius: 4, endRadius: CornerWindow.dropSize)
                    .transition(.opacity)
            }
            if model.showsNote || model.phase == .dropTarget || model.phase == .saved {
                ZStack {
                    MiniStickyNote(size: noteSize, foldCorner: corner.opposite, showLines: model.phase != .dropTarget && model.phase != .saved)
                    if model.phase == .dropTarget || model.phase == .saved {
                        Image(systemName: model.phase == .saved ? "checkmark" : arrowSymbol(for: corner))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(StickyPalette.ink.opacity(0.8))
                            .offset(x: -sx * 8, y: -sy * 8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .rotationEffect(.degrees((corner.isLeft == corner.isTop) ? 12 : -12))
                .shadow(color: .black.opacity(0.28), radius: 6, x: -sx * 2, y: -sy * 2)
                .scaleEffect(model.phase == .dropTarget ? 1.12 : 1, anchor: corner.unitPoint)
                .offset(x: sx * hiddenBy, y: sy * hiddenBy)
            }
        }
        .frame(width: CornerWindow.canvasSize, height: CornerWindow.canvasSize)
        .allowsHitTesting(false)
    }

    private func arrowSymbol(for corner: ScreenCorner) -> String {
        switch corner {
        case .topLeft: return "arrow.up.left"
        case .topRight: return "arrow.up.right"
        case .bottomLeft: return "arrow.down.left"
        case .bottomRight: return "arrow.down.right"
        }
    }

    private var visibleAmount: CGFloat {
        switch model.phase {
        case .hidden, .panelOpen: return -noteSize * 0.35 // fully tucked away (incl. rotation & shadow)
        case .peek: return 34
        case .dropTarget, .saved: return 62
        }
    }
}
