import AppKit
import SwiftUI

public enum KeyCommand: Sendable {
    case up, down, enter, newline, escape, tab, deleteSelection
}

/// NSTextView with a placeholder and paste interception (⌘V saves anything instantly).
public final class StickyTextView: NSTextView {
    public var placeholder: String = "" { didSet { needsDisplay = true } }
    public var placeholderFont: NSFont?
    /// Return true to swallow the paste (it was saved as a note instead).
    public var onPaste: ((NSPasteboard) -> Bool)?
    public var onFocusChange: ((Bool) -> Void)?
    /// The pointer clicked in this field (even if it already had the keyboard).
    public var onClick: (() -> Void)?

    public override func mouseDown(with event: NSEvent) {
        onClick?()
        super.mouseDown(with: event)
    }

    public override func paste(_ sender: Any?) {
        if let onPaste, onPaste(NSPasteboard.general) { return }
        pasteAsPlainText(sender)
    }

    public override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange?(true) }
        return ok
    }

    public override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFocusChange?(false) }
        return ok
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: placeholderFont ?? font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        let x = textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0)
        let rect = NSRect(x: x, y: textContainerInset.height,
                          width: bounds.width - x * 2, height: bounds.height - textContainerInset.height)
        (placeholder as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }

    public override var acceptsFirstResponder: Bool { true }
}

/// SwiftUI wrapper around `StickyTextView` that grows with its content.
public struct KeyTextView: NSViewRepresentable {
    /// Space above and below the text inside the view.
    static let textInset: CGFloat = 2

    /// Height of the view holding one line of text at this size, so fields can center it.
    public static func singleLineHeight(fontSize: CGFloat) -> CGFloat {
        ceil(NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: fontSize)) + textInset * 2)
    }

    @Binding public var text: String
    @Binding public var height: CGFloat
    public var placeholder: String
    public var fontSize: CGFloat = 14
    public var maxLines: Int = 6
    public var singleLine = false
    /// Increment to move keyboard focus here.
    public var focusToken: Int
    public var onCommand: (KeyCommand) -> Bool
    public var onPaste: ((NSPasteboard) -> Bool)? = nil
    public var onFocusChange: ((Bool) -> Void)? = nil
    /// The pointer clicked in the field (a click says where you're working, focused or not).
    public var onClick: (() -> Void)? = nil
    /// Lets the window find this field (e.g. to focus the composer when the panel opens).
    public var identifier: String? = nil

    public init(text: Binding<String>, height: Binding<CGFloat>, placeholder: String, fontSize: CGFloat = 14,
                maxLines: Int = 6, singleLine: Bool = false, focusToken: Int,
                onCommand: @escaping (KeyCommand) -> Bool, onPaste: ((NSPasteboard) -> Bool)? = nil,
                onFocusChange: ((Bool) -> Void)? = nil, onClick: (() -> Void)? = nil, identifier: String? = nil) {
        self._text = text
        self._height = height
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.maxLines = maxLines
        self.singleLine = singleLine
        self.focusToken = focusToken
        self.onCommand = onCommand
        self.onPaste = onPaste
        self.onFocusChange = onFocusChange
        self.onClick = onClick
        self.identifier = identifier
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

        let textView = StickyTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .systemFont(ofSize: fontSize)
        textView.placeholderFont = .systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 0, height: Self.textInset)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.placeholder = placeholder
        textView.identifier = identifier.map { NSUserInterfaceItemIdentifier(rawValue: $0) }
        textView.onPaste = onPaste
        textView.onFocusChange = onFocusChange
        textView.onClick = onClick
        textView.string = text
        if singleLine { container.maximumNumberOfLines = 1; container.lineBreakMode = .byTruncatingTail }

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false // only once the text outgrows maxLines (see recalculateHeight)
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.documentView = textView
        context.coordinator.textView = textView
        DispatchQueue.main.async { context.coordinator.recalculateHeight() }
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }
        textView.onPaste = onPaste
        textView.onFocusChange = onFocusChange
        textView.onClick = onClick
        if textView.placeholder != placeholder { textView.placeholder = placeholder }
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            DispatchQueue.main.async { coordinator.recalculateHeight() }
        }
        if coordinator.lastFocusToken != focusToken {
            coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                guard let window = textView.window else { return }
                window.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
            }
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: KeyTextView
        weak var textView: StickyTextView?
        var lastFocusToken: Int

        init(_ parent: KeyTextView) {
            self.parent = parent
            self.lastFocusToken = parent.focusToken // focus only when explicitly requested
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            if parent.text != textView.string { parent.text = textView.string }
            recalculateHeight()
        }

        func recalculateHeight() {
            guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
            layout.ensureLayout(for: container)
            let lineHeight = layout.defaultLineHeight(for: textView.font ?? .systemFont(ofSize: parent.fontSize))
            let used = layout.usedRect(for: container).height
            let lines = parent.singleLine ? 1 : parent.maxLines
            let target = min(max(used, lineHeight), lineHeight * CGFloat(lines)) + textView.textContainerInset.height * 2
            let overflows = !parent.singleLine && used > lineHeight * CGFloat(lines) + 0.5
            if let scroll = textView.enclosingScrollView, scroll.hasVerticalScroller != overflows {
                scroll.hasVerticalScroller = overflows
            }
            let rounded = ceil(target)
            if abs(parent.height - rounded) > 0.5 { parent.height = rounded }
        }

        public func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if flags.contains(.shift) || flags.contains(.option) {
                    if parent.singleLine { return true }
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                return parent.onCommand(.enter)
            case #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                if parent.singleLine { return true }
                return false
            case #selector(NSResponder.moveUp(_:)):
                // Only leave the text when the caret is on the first line.
                if parent.singleLine || isCaretOnFirstLine(textView) { return parent.onCommand(.up) }
                return false
            case #selector(NSResponder.moveDown(_:)):
                if parent.singleLine || isCaretOnLastLine(textView) { return parent.onCommand(.down) }
                return false
            case #selector(NSResponder.cancelOperation(_:)):
                return parent.onCommand(.escape)
            case #selector(NSResponder.insertTab(_:)):
                return parent.onCommand(.tab)
            case #selector(NSResponder.deleteToBeginningOfLine(_:)):
                // ⌘⌫ deletes the selected card when the field is empty.
                if textView.string.isEmpty { return parent.onCommand(.deleteSelection) }
                return false
            default:
                return false
            }
        }

        private func isCaretOnFirstLine(_ textView: NSTextView) -> Bool {
            let location = textView.selectedRange().location
            let string = textView.string as NSString
            guard location > 0 else { return true }
            guard let layout = textView.layoutManager else { return true }
            let glyph = layout.glyphIndexForCharacter(at: min(location, max(0, string.length - 1)))
            var range = NSRange()
            layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
            return range.location == 0
        }

        private func isCaretOnLastLine(_ textView: NSTextView) -> Bool {
            let string = textView.string as NSString
            let location = textView.selectedRange().location
            guard string.length > 0, location < string.length else { return true }
            guard let layout = textView.layoutManager else { return true }
            let glyph = layout.glyphIndexForCharacter(at: location)
            var range = NSRange()
            layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
            return NSMaxRange(range) >= layout.numberOfGlyphs
        }
    }
}
