import AppKit
import SwiftUI

/// Edit text right where it is. Grows with its content, keeps formatting when `rich` is set,
/// and finishes on Esc, ⌘↩ or clicking elsewhere (changes are kept; the app offers Undo).
public struct InlineTextEditor: NSViewRepresentable {
    public var initialText: String
    public var initialRTF: Data?
    public var font: NSFont
    public var textColor: NSColor
    public var maxHeight: CGFloat
    @Binding public var height: CGFloat
    /// Called once when editing ends: plain text plus RTF when the content is rich.
    public var onFinish: (String, Data?) -> Void

    public init(initialText: String, initialRTF: Data? = nil, font: NSFont, textColor: NSColor = .labelColor,
                maxHeight: CGFloat = 320, height: Binding<CGFloat>, onFinish: @escaping (String, Data?) -> Void) {
        self.initialText = initialText
        self.initialRTF = initialRTF
        self.font = font
        self.textColor = textColor
        self.maxHeight = maxHeight
        self._height = height
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
        textView.onFinish = { [weak coordinator = context.coordinator] in coordinator?.finish() }

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = textView
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            context.coordinator.recalculateHeight()
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        }
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
    }

    public static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.finish() // e.g. the panel closed mid-edit: keep what was typed
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineTextEditor
        weak var textView: EditorTextView?
        private var finished = false

        init(_ parent: InlineTextEditor) { self.parent = parent }

        public func textDidChange(_ notification: Notification) { recalculateHeight() }

        public func textDidEndEditing(_ notification: Notification) { finish() }

        public func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                finish()
                return true
            }
            return false
        }

        func finish() {
            guard !finished, let textView else { return }
            finished = true
            var rtf: Data?
            if textView.isRichText, let storage = textView.textStorage {
                rtf = storage.rtf(from: NSRange(location: 0, length: storage.length), documentAttributes: [:])
            }
            parent.onFinish(textView.string, rtf)
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

public final class EditorTextView: NSTextView {
    var onFinish: () -> Void = {}

    public override func keyDown(with event: NSEvent) {
        // ⌘↩ finishes editing.
        if event.keyCode == 36, event.modifierFlags.contains(.command) {
            onFinish()
            return
        }
        super.keyDown(with: event)
    }
}
