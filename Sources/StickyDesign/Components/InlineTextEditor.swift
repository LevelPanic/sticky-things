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
    /// Called once when editing ends: plain text, RTF when the content is rich, and how it ended.
    public var onFinish: (String, Data?, Ending) -> Void

    public init(initialText: String, initialRTF: Data? = nil, font: NSFont, textColor: NSColor = .labelColor,
                maxHeight: CGFloat = 320, height: Binding<CGFloat>, handle: InlineEditHandle? = nil,
                onFinish: @escaping (String, Data?, Ending) -> Void) {
        self.initialText = initialText
        self.initialRTF = initialRTF
        self.font = font
        self.textColor = textColor
        self.maxHeight = maxHeight
        self._height = height
        self.handle = handle
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
        handle?.attach(owner: ObjectIdentifier(coordinator),
                       save: { [weak coordinator] in coordinator?.finish(.save) },
                       cancel: { [weak coordinator] in coordinator?.finish(.cancel) },
                       focus: { [weak textView] in textView?.window?.makeFirstResponder(textView) })

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

        init(_ parent: InlineTextEditor) { self.parent = parent }

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
            parent.handle?.detach(owner: ObjectIdentifier(self))
            var rtf: Data?
            if textView.isRichText, let storage = textView.textStorage {
                rtf = storage.rtf(from: NSRange(location: 0, length: storage.length), documentAttributes: [:])
            }
            parent.onFinish(textView.string, rtf, ending)
        }

        func recalculateHeight() {
            guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
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
/// One handle can serve a whole list: only the editor currently attached responds, and an editor
/// that finishes never detaches the one that replaced it.
@MainActor
public final class InlineEditHandle {
    private var owner: ObjectIdentifier?
    private var onSave: (() -> Void)?
    private var onCancel: (() -> Void)?
    private var onFocus: (() -> Void)?

    public init() {}

    /// Whether an editor is attached right now.
    public var isActive: Bool { owner != nil }
    public func save() { onSave?() }
    public func cancel() { onCancel?() }
    public func focus() { onFocus?() }

    func attach(owner: ObjectIdentifier, save: @escaping () -> Void, cancel: @escaping () -> Void,
                focus: @escaping () -> Void) {
        self.owner = owner
        onSave = save
        onCancel = cancel
        onFocus = focus
    }

    func detach(owner: ObjectIdentifier) {
        guard self.owner == owner else { return }
        self.owner = nil
        onSave = nil
        onCancel = nil
        onFocus = nil
    }
}

public final class EditorTextView: NSTextView {
    var onResign: () -> Void = {}
    private var takesFocusWhenShown = true

    /// Leaving the window (the panel closed, the card scrolled away) ends the edit and keeps the
    /// text. SwiftUI doesn't reliably dismantle the view, and AppKit doesn't resign a first
    /// responder that is removed from its window.
    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, window != nil { onResign() }
        super.viewWillMove(toWindow: newWindow)
    }

    /// Take the keyboard once SwiftUI has actually put us in the window. (Asking right after
    /// creation only worked when timing was lucky; often the window was still nil.)
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard takesFocusWhenShown, let window else { return }
        takesFocusWhenShown = false
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === window else { return }
            window.makeFirstResponder(self)
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
