import AppKit
import StickyCore
import StickyDesign
import SwiftUI

@MainActor
final class CornerPeekModel: ObservableObject {
    enum Phase: Equatable { case hidden, peek, armed, dropTarget, saved, panelOpen }
    @Published var phase: Phase = .hidden
    @Published var showsNote = true
    /// Bumped to play a short shake, so a held drag visibly gets ready to open the panel.
    @Published var shake = 0
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
    var dragToOpen = true
    var dragOpenDelay: Double = 0.6
    var dragTriggerArea: CGFloat = CornerDragArea.medium.size
    var onActivate: (() -> Void)?
    var onDragOpen: (() -> Void)?
    var onDrop: ((NSPasteboard) -> Bool)?
    var isPanelOpen: () -> Bool = { false }

    private var dwellTimer: Timer?
    private var shrinkWork: DispatchWorkItem?
    private var dragOpenWork: DispatchWorkItem?
    private var dragShowWork: DispatchWorkItem?
    private var pointerInside = false
    private var dragSession = false
    private var dragInside = false

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
        guard !dragSession else { return }
        pointerInside = true
        shrinkWork?.cancel()
        if frame.width < Self.peekSize { setSize(Self.peekSize) }
        guard !isPanelOpen() else { return }
        withAnimation(Motion.emphasized) { model.phase = .peek }
        if trigger == .hover {
            dwellTimer?.invalidate()
            dwellTimer = Timer.scheduledTimer(withTimeInterval: max(0.05, hoverDelay), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.pointerInside, !self.dragSession, !self.isPanelOpen() else { return }
                    self.activate()
                }
            }
        }
    }

    func pointerExited() {
        guard !dragSession else { return }
        pointerInside = false
        dwellTimer?.invalidate()
        guard model.phase != .saved else { return }
        withAnimation(Motion.standard) {
            model.phase = isPanelOpen() ? .panelOpen : .hidden
        }
        scheduleShrink()
    }

    func clicked() {
        dwellTimer?.invalidate()
        activate()
    }

    private func activate() {
        withAnimation(Motion.quick) { model.phase = .panelOpen }
        onActivate?()
    }

    /// Keeps the peek in sync when the panel opens/closes from elsewhere.
    func panelVisibilityChanged(_ open: Bool) {
        if open {
            withAnimation(Motion.quick) { model.phase = .panelOpen }
            cancelDragOpen()
        } else {
            withAnimation(Motion.emphasized) {
                model.phase = pointerInside ? .peek : .hidden
            }
            if !pointerInside { scheduleShrink() }
        }
    }

    /// A drag is moving somewhere in another app. The corner grows into a comfortable catch
    /// area *only* while the mouse button is down, so at rest it still stays out of the way.
    func dragSessionBegan() {
        guard !dragSession, !isPanelOpen() else { return }
        dragSession = true
        pointerInside = false
        shrinkWork?.cancel()
        dwellTimer?.invalidate()
        if model.phase == .peek { model.phase = .hidden }
        if frame.width < dragTriggerArea { setSize(max(Self.idleSize, dragTriggerArea)) }
    }

    func dragSessionEnded() {
        guard dragSession else { return }
        dragSession = false
        dragInside = false
        pointerInside = false
        cancelDragOpen()
        if model.phase == .armed || model.phase == .dropTarget {
            withAnimation(Motion.standard) { model.phase = .hidden }
        }
        if model.phase != .saved { scheduleShrink(after: 0.12) }
    }

    private func scheduleShrink(after delay: Double = 0.3) {
        shrinkWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.pointerInside else { return }
                guard self.model.phase == .hidden || self.model.phase == .panelOpen else { return }
                self.setSize(self.dragSession ? max(Self.idleSize, self.dragTriggerArea) : Self.idleSize)
            }
        }
        shrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Drag & drop

    func dragEntered() {
        shrinkWork?.cancel()
        dwellTimer?.invalidate()
        dragInside = true
        setSize(max(Self.dropSize, dragTriggerArea))
        if dragToOpen && !isPanelOpen() {
            withAnimation(Motion.emphasized) { model.phase = .armed }
            shake()
            scheduleDragOpen()
        } else {
            withAnimation(Motion.emphasized) { model.phase = .dropTarget }
        }
    }

    func dragExited() {
        dragInside = false
        cancelDragOpen()
        guard model.phase != .saved else { return }
        withAnimation(Motion.standard) { model.phase = .hidden }
        scheduleShrink()
    }

    func performDrop(_ pasteboard: NSPasteboard) -> Bool {
        dragInside = false
        cancelDragOpen()
        let ok = onDrop?(pasteboard) ?? false
        withAnimation(Motion.emphasized) { model.phase = ok ? .saved : .hidden }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.phase == .saved else { return }
                withAnimation(Motion.standard) { self.model.phase = .hidden }
                self.pointerInside = false
                self.scheduleShrink(after: 0.3)
            }
        }
        return ok
    }

    /// Wait in the corner with something held: the note shakes, then the panel opens so the
    /// drag can be dropped into it. A quick drop still saves straight away.
    private func scheduleDragOpen() {
        dragOpenWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.beginDragOpen() }
        }
        dragOpenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.2, dragOpenDelay), execute: work)
    }

    private func beginDragOpen() {
        guard dragInside, dragSession, !isPanelOpen() else { return }
        shake()
        let show = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.dragInside, self.dragSession, !self.isPanelOpen() else { return }
                withAnimation(Motion.quick) { self.model.phase = .panelOpen }
                self.onDragOpen?()
            }
        }
        dragShowWork = show
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: show)
    }

    private func cancelDragOpen() {
        dragOpenWork?.cancel()
        dragOpenWork = nil
        dragShowWork?.cancel()
        dragShowWork = nil
    }

    private func shake() {
        guard !Motion.reduceMotion else { return }
        withAnimation(Motion.shake) { model.shake += 1 }
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
        registerForDraggedTypes(DropTypes.all)
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
            if model.showsNote || model.phase == .armed || model.phase == .dropTarget || model.phase == .saved {
                ZStack {
                    MiniStickyNote(size: noteSize, foldCorner: corner.peekFold,
                                   showLines: !isDropFeedback)
                    if isDropFeedback {
                        Image(systemName: model.phase == .saved ? "checkmark" : arrowSymbol(for: corner))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(StickyPalette.ink.opacity(0.8))
                            .offset(x: -sx * 8, y: -sy * 8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .rotationEffect(.degrees((corner.isLeft == corner.isTop) ? 12 : -12))
                .modifier(CornerShakeEffect(animatableData: CGFloat(model.shake), direction: sx))
                .shadow(color: .black.opacity(model.phase == .dropTarget || model.phase == .armed ? 0.32 : 0.22),
                        radius: model.phase == .dropTarget || model.phase == .armed ? 8 : 4, x: -sx * 2, y: -sy * 2)
                .scaleEffect(model.phase == .dropTarget ? 1.12 : 1, anchor: corner.unitPoint)
                .offset(x: sx * hiddenBy, y: sy * hiddenBy)
            }
        }
        .frame(width: CornerWindow.canvasSize, height: CornerWindow.canvasSize)
        .allowsHitTesting(false)
    }

    private var isDropFeedback: Bool {
        model.phase == .armed || model.phase == .dropTarget || model.phase == .saved
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
        case .armed, .dropTarget, .saved: return 62
        }
    }
}

/// A short horizontal wobble that decays to nothing. Triggered by bumping `model.shake`.
private struct CornerShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    var direction: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let travel = sin(animatableData * .pi * 6) * Space.xs * direction
        return ProjectionTransform(CGAffineTransform(translationX: travel, y: 0))
    }
}
