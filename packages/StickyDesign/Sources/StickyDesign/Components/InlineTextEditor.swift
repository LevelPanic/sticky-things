import AppKit
import SwiftUI

/// Edit text right where it is. Grows with its content and keeps formatting when `rich` is set.
///
/// Return or ⌘Return saves, ⇧Return or ⌥Return starts a new line, Esc cancels. Leaving the
/// editor any other way (clicking another field, the view going away) saves, like renaming in
/// Finder. `handle` lets buttons outside the text view save or cancel.
public struct InlineTextEditor: NSViewRepresentable {
    /// How an edit ended.
    public enum Ending: Equatable, Sendable {
        /// Return, ⌘Return or a Save button.
        case save
        /// Esc or a Cancel button: discard the changes.
        case cancel
        /// Focus moved elsewhere or the editor went away: keep the changes, leave focus alone.
        case focusLost
    }

    public var initialText: String
    public var initialRTF: Data?
    public var font: NSFont
    public var textColor: NSColor
    public var maxHeight: CGFloat
    @Binding public var height: CGFloat
    public var handle: InlineEditHandle?
    /// Stable for one edit. If SwiftUI temporarily builds two platform views for the same edit
    /// (a growing card in a lazy list can do this), the older view must not end the newer edit.
    public var editToken: UUID
    /// Called once when editing ends: plain text, RTF when the content is rich, and how it ended.
    public var onFinish: (String, Data?, Ending) -> Void

    public init(initialText: String, initialRTF: Data? = nil, font: NSFont, textColor: NSColor = .labelColor,
                maxHeight: CGFloat = 320, height: Binding<CGFloat>, handle: InlineEditHandle? = nil,
                editToken: UUID,
                onFinish: @escaping (String, Data?, Ending) -> Void) {
        self.initialText = initialText
        self.initialRTF = initialRTF
        self.font = font
        self.textColor = textColor
        self.maxHeight = maxHeight
        self._height = height
        self.handle = handle
        self.editToken = editToken
        self.onFinish = onFinish
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        let textView = EditorTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.isRichText = initialRTF != nil
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = .controlAccentColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = .zero
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        if let rtf = initialRTF, let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            storage.setAttributedString(attributed)
        } else {
            textView.string = initialText
        }
        let coordinator = context.coordinator
        textView.onResign = { [weak coordinator] in coordinator?.finish(.focusLost) }
        textView.onReady = { [weak coordinator] in coordinator?.attached() }

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = textView
        coordinator.textView = textView

        DispatchQueue.main.async { coordinator.recalculateHeight() }
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
    }

    public static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.finish(.focusLost) // e.g. the panel closed mid-edit: keep what was typed
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineTextEditor
        weak var textView: EditorTextView?
        private var finished = false
        private var didAttach = false

        init(_ parent: InlineTextEditor) { self.parent = parent }

        /// The platform view is really on screen with a width. A measurement duplicate SwiftUI
        /// creates for a growing card never gets here, so it can't steal focus or the edit.
        func attached() {
            guard !didAttach, let textView else { return }
            didAttach = true
            parent.handle?.attach(owner: ObjectIdentifier(self), token: parent.editToken,
                                  save: { [weak self] in self?.finish(.save) },
                                  cancel: { [weak self] in self?.finish(.cancel) },
                                  focus: { [weak textView] in textView?.window?.makeFirstResponder(textView) })
            recalculateHeight()
        }

        public func textDidChange(_ notification: Notification) { recalculateHeight() }

        public func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if flags.contains(.shift) || flags.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    finish(.save)
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                finish(.cancel)
                return true
            default:
                return false
            }
        }

        func finish(_ ending: Ending) {
            guard !finished, let textView else { return }
            finished = true
            let owner = ObjectIdentifier(self)
            let otherEditor = parent.handle?.hasOtherEditor(owner: owner, token: parent.editToken) ?? false
            parent.handle?.detach(owner: owner)
            // A platform view that never made it on screen (a measurement duplicate) must not
            // end the live edit, and neither must a duplicate from the same edit resigning.
            guard !(ending == .focusLost && (otherEditor || (parent.handle != nil && !didAttach))) else { return }
            var rtf: Data?
            if textView.isRichText, let storage = textView.textStorage {
                rtf = storage.rtf(from: NSRange(location: 0, length: storage.length), documentAttributes: [:])
            }
            parent.onFinish(textView.string, rtf, ending)
        }

        func recalculateHeight() {
            guard let textView, let layout = textView.layoutManager, let container = textView.textContainer,
                  let width = textView.enclosingScrollView?.contentSize.width, width > 0 else { return }
            layout.ensureLayout(for: container)
            let lineHeight = layout.defaultLineHeight(for: parent.font)
            let used = max(layout.usedRect(for: container).height, lineHeight)
            let target = ceil(min(used, parent.maxHeight))
            if abs(parent.height - target) > 0.5 { parent.height = target }
        }
    }
}

/// Lets things outside the text view drive the active edit: the Save and Cancel buttons, a click
/// on empty space (which saves, like clicking away), a click in the editor's padding (focus).
/// One handle can serve a whole list: the newest live editor responds, and an editor that
/// finishes never detaches the one that replaced it.
@MainActor
public final class InlineEditHandle {
    private struct Entry {
        let owner: ObjectIdentifier
        let token: UUID
        let save: () -> Void
        let cancel: () -> Void
        let focus: () -> Void
    }

    /// There can briefly be two platform views for one edit (a growing card in a lazy list).
    /// Keep each one so the older can go away without ending the newer, and so Save still works
    /// after the newest of them resigns.
    private var entries: [Entry] = []
    private var current: Entry? { entries.last }

    public init() {}

    /// Whether an editor is attached right now.
    public var isActive: Bool { !entries.isEmpty }
    public func save() { current?.save() }
    public func cancel() { current?.cancel() }
    public func focus() { current?.focus() }

    func attach(owner: ObjectIdentifier, token: UUID, save: @escaping () -> Void,
                cancel: @escaping () -> Void, focus: @escaping () -> Void) {
        entries.removeAll { $0.owner == owner }
        entries.append(Entry(owner: owner, token: token, save: save, cancel: cancel, focus: focus))
    }

    /// True when another live platform view belongs to the *same* edit. The one going away must
    /// not end the edit; a view from a different edit should finish and save as usual.
    func hasOtherEditor(owner: ObjectIdentifier, token: UUID) -> Bool {
        entries.contains { $0.owner != owner && $0.token == token }
    }

    func detach(owner: ObjectIdentifier) {
        entries.removeAll { $0.owner == owner }
    }
}

public final class EditorTextView: NSTextView {
    var onResign: () -> Void = {}
    /// Called once the view is really in a window with a width and is safe to use.
    var onReady: (() -> Void)?
    private var takesFocusWhenShown = true
    private var ready = false
    private var readyAttempts = 0

    /// Leaving the window (the panel closed, the card scrolled away) ends the edit and keeps the
    /// text. SwiftUI doesn't reliably dismantle the view, and AppKit doesn't resign a first
    /// responder that is removed from its window.
    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, window != nil { onResign() }
        super.viewWillMove(toWindow: newWindow)
    }

    /// Take the keyboard once SwiftUI has actually put us in the window. (Asking right after
    /// creation only worked when timing was lucky; often the window was still nil.) A zero-width
    /// platform view is a measurement copy SwiftUI made for a growing card; never focus it.
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard takesFocusWhenShown, let window else { return }
        waitUntilReady(in: window)
    }

    private func waitUntilReady(in window: NSWindow) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === window, self.superview != nil else { return }
            guard self.bounds.width > 0 else {
                guard self.readyAttempts < 5 else { return }
                self.readyAttempts += 1
                self.waitUntilReady(in: window)
                return
            }
            guard !self.ready else { return }
            self.ready = true
            self.takesFocusWhenShown = false
            self.onReady?()
            if window.firstResponder !== self { window.makeFirstResponder(self) }
            self.setSelectedRange(NSRange(location: (self.string as NSString).length, length: 0))
        }
    }

    public override func keyDown(with event: NSEvent) {
        // ⌘↩ saves too (Return alone is handled as insertNewline).
        if event.keyCode == 36, event.modifierFlags.contains(.command) {
            doCommand(by: #selector(NSResponder.insertNewline(_:)))
            return
        }
        super.keyDown(with: event)
    }

    /// Clicking another field ends the edit, even when nothing was typed (AppKit only sends
    /// `textDidEndEditing` after a change, which left the card stuck in edit mode).
    public override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onResign() }
        return resigned
    }
}
