import AppKit
import StickyCore
import StickyDesign
import SwiftUI

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var symbol: String
    var canUndo = false
    var isError = false
    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

struct ScrollRequest: Equatable {
    let id: UUID
    let token = UUID()
}

/// Everything the panel shows and every action it can take. Views only call these methods,
/// so behaviour is testable without clicking anything.
@MainActor
final class PanelModel: ObservableObject {
    let store: ItemStore
    let capture: CaptureService
    let settings: Settings
    let quickLook = QuickLookController()

    // Presentation
    @Published var isPresented = false
    @Published var anchorAtBottom = true
    @Published var scaleAnchor: UnitPoint = .bottomTrailing
    @Published var panelHeight: CGFloat = 560
    @Published var keepOpen = false
    @Published var conflictAction: String?

    // Browsing
    @Published var search = "" { didSet { if search != oldValue { selection = nil } } }
    @Published var filter: ItemFilter = .all { didSet { if filter != oldValue { selection = nil } } }
    @Published var selection: UUID? { didSet { syncQuickLook() } }
    @Published var hoveredID: UUID?

    // Editing & composing
    @Published var editingID: UUID?
    @Published var composerFocus = 0
    @Published var searchFocus = 0
    @Published var composerHeight: CGFloat = 20
    @Published var searchHeight: CGFloat = 18
    @Published var composerFocused = false

    // Feedback
    @Published var toast: Toast?
    @Published var copiedID: UUID?
    @Published var isDropTargeted = false
    @Published var scrollRequest: ScrollRequest?
    @Published var openToken = 0
    @Published var savingCount = 0

    /// The app you were in when the panel opened (credited on things you paste).
    var sourceApp: SourceApp?
    /// Where "copy" writes. Tests swap in a private pasteboard so your clipboard is untouched.
    var pasteboard: NSPasteboard = .general
    var close: () -> Void = {}
    var closeForHandoff: () -> Void = {}
    /// Asks the controller to activate the app (Quick Look needs it).
    var needsActivation: () -> Void = {}
    var openSettings: () -> Void = {}

    private var undoAction: (() -> Void)?
    private var toastWork: DispatchWorkItem?

    init(store: ItemStore, capture: CaptureService, settings: Settings) {
        self.store = store
        self.capture = capture
        self.settings = settings
    }

    // MARK: Derived

    var isSearching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }
    var isFiltering: Bool { isSearching || filter != .all }

    /// Newest first. Pinned items live in their own strip unless you search or filter.
    var listItems: [Item] {
        let matches = store.search(search, filter: filter)
        return isFiltering ? matches : matches.filter { !$0.pinned }
    }

    var pinnedItems: [Item] { store.pinned }

    /// The stack grows away from the corner: the newest thing sits right next to the composer.
    var listFlowsUp: Bool { anchorAtBottom && !isFiltering }

    var selectedItem: Item? { selection.flatMap { store.item($0) } }

    // MARK: Opening

    func prepareForOpen() {
        selection = nil
        copiedID = nil
        isDropTargeted = false
        toast = nil
        conflictAction = settings.hideConflictBanner ? nil : MacHotCorners.conflictingAction(for: settings.corner)
        composerFocus += 1
        openToken += 1
    }

    func didClose() {
        quickLook.close()
        if editingID != nil { editingID = nil }
        hoveredID = nil
    }

    /// Pointer entered or left a card. Leaving one card never clears the card it moved onto
    /// (SwiftUI can report "entered B" before "left A").
    func setHovered(_ id: UUID, _ inside: Bool) {
        withAnimation(Motion.quick) {
            if inside { hoveredID = id } else if hoveredID == id { hoveredID = nil }
        }
    }

    // MARK: Saving things

    func submitComposer() {
        guard let outcome = capture.saveNote(settings.draft) else { return }
        settings.draft = ""
        handle(outcome, verb: "Saved")
    }

    /// ⌘V in the composer. With an empty composer *anything* is saved instantly; while typing,
    /// text pastes inline and only non-text things (images, files…) become their own items.
    func paste(from pasteboard: NSPasteboard) -> Bool {
        let clip = PasteboardSnapshotter.capture(pasteboard, limits: capture.limits)
        guard !clip.isEmpty else { return false }
        let composerEmpty = settings.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !composerEmpty {
            let kind = Classifier.classify(clip).kind
            if kind.isTextual || kind == .link { return false }
        }
        do {
            handle(try capture.save(clip, source: sourceApp), verb: "Saved")
        } catch {
            showError(error)
        }
        return true
    }

    /// ⌥⌘V: put the clipboard's text in the composer to edit before saving.
    func pasteIntoComposer() {
        guard let string = NSPasteboard.general.string(forType: .string) else { return }
        settings.draft += string
        composerFocus += 1
    }

    /// Something was dropped on the panel or thrown at the corner.
    @discardableResult
    func drop(_ pasteboard: NSPasteboard, source: SourceApp?) -> Bool {
        isDropTargeted = false
        do {
            let outcome = try capture.save(from: pasteboard, source: source) { [weak self] result in
                guard let self else { return }
                self.savingCount = max(0, self.savingCount - 1)
                switch result {
                case .success(let items): self.handle(.saved(items), verb: "Saved")
                case .failure(let error): self.showError(error)
                }
            }
            if outcome == .pending {
                savingCount += 1
                showToast("Saving…", symbol: "arrow.down.circle")
            } else {
                handle(outcome, verb: "Saved")
            }
            return true
        } catch {
            showError(error)
            return false
        }
    }

    private func handle(_ outcome: CaptureService.Outcome, verb: String) {
        switch outcome {
        case .saved(let items):
            guard let first = items.first else { return }
            selection = nil
            if isFiltering { search = ""; filter = .all }
            flashCopied(nil)
            scrollRequest = ScrollRequest(id: first.id)
            showToast(items.count > 1 ? "\(verb) \(items.count) items" : verb, symbol: "checkmark")
        case .duplicate(let item):
            scrollRequest = ScrollRequest(id: item.id)
            selection = item.id
            showToast("Already saved", symbol: "checkmark")
        case .pending:
            break
        }
    }

    // MARK: Item actions

    /// One click: copy, losslessly. Optionally close so you can paste right away.
    func copy(_ item: Item, closeAfter: Bool = false) {
        guard PasteboardWriter.copy(item, store: store, to: pasteboard) else {
            showError(CoreError.missingFile(item.files.first?.name ?? item.headline))
            return
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        selection = item.id // keeps its buttons visible, even without hover
        flashCopied(item.id)
        if closeAfter && !keepOpen {
            close()
        } else {
            showToast("Copied", symbol: "doc.on.doc")
        }
    }

    /// Double click: edit notes in place, preview files and images, open links.
    func activate(_ item: Item) {
        switch item.kind {
        case .text, .richText: beginEditing(item)
        case .link: open(item)
        default: quickLook(item)
        }
    }

    func open(_ item: Item) {
        switch item.kind {
        case .link:
            if let url = item.link.flatMap({ URL(string: $0.url) }) { NSWorkspace.shared.open(url) }
        default:
            guard let url = Materializer.file(for: item, store: store, purpose: .preview) else { return }
            NSWorkspace.shared.open(url)
        }
        if !keepOpen { closeForHandoff() }
    }

    func reveal(_ item: Item) {
        let urls = item.files.compactMap { store.files.url(for: $0) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        if !keepOpen { closeForHandoff() }
    }

    func beginEditing(_ item: Item) {
        guard item.kind.isTextual || item.kind == .link else { return }
        selection = item.id
        editingID = item.id
    }

    func finishEditing(_ id: UUID, text: String, rtf: Data?) {
        guard editingID == id else { return }
        editingID = nil
        composerFocus += 1
        guard let before = store.item(id) else { return }
        let changed = text != before.text || rtf != nil && before.kind != .richText
        guard changed, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.setText(id, to: text, rtf: rtf)
        undoAction = { [weak self] in
            self?.store.update(id) { $0 = before }
        }
        showToast("Note edited", symbol: "pencil", canUndo: true)
    }

    func togglePin(_ item: Item) {
        withAnimation(Motion.standard) { store.togglePin(item.id) }
        showToast(item.pinned ? "Unpinned" : "Pinned to top", symbol: item.pinned ? "pin.slash" : "pin")
    }

    func setTint(_ tint: Tint, for item: Item) {
        store.setTint(tint, for: item.id)
    }

    func delete(_ item: Item) {
        let visible = listItems
        let index = visible.firstIndex { $0.id == item.id }
        guard let removed = withAnimation(Motion.standard, { store.delete(item.id) }) else { return }
        if selection == item.id {
            let remaining = listItems
            selection = remaining.isEmpty ? nil : remaining[min(index ?? 0, remaining.count - 1)].id
        }
        if editingID == item.id { editingID = nil }
        undoAction = { [weak self] in withAnimation(Motion.standard) { self?.store.restore(removed) } }
        showToast(item.kind.isTextual ? "Note deleted" : "\(item.kind.label) deleted", symbol: "trash", canUndo: true)
    }

    func undo() {
        undoAction?()
        undoAction = nil
        withAnimation(Motion.quick) { toast = nil }
    }

    func quickLook(_ item: Item) {
        selection = item.id
        let urls = previewURLs(for: item)
        if urls.isEmpty { open(item); return }
        if !quickLook.isVisible { needsActivation() }
        quickLook.toggle(urls: urls)
    }

    private func previewURLs(for item: Item) -> [URL] {
        let files = item.files.compactMap { store.files.url(for: $0) }
        if !files.isEmpty { return files }
        return Materializer.file(for: item, store: store, purpose: .preview).map { [$0] } ?? []
    }

    private func syncQuickLook() {
        guard quickLook.isVisible, let item = selectedItem else { return }
        quickLook.show(urls: previewURLs(for: item))
    }

    // MARK: Keyboard

    func handleComposerCommand(_ command: KeyCommand) -> Bool {
        switch command {
        case .enter:
            if let item = selectedItem { copy(item, closeAfter: true) } else { submitComposer() }
            return true
        case .up: return moveSelection(visualDown: false)
        case .down: return moveSelection(visualDown: true)
        case .escape:
            escape()
            return true
        case .tab:
            searchFocus += 1
            return true
        case .deleteSelection:
            if let item = selectedItem { delete(item); return true }
            return false
        case .newline:
            return false
        }
    }

    func handleSearchCommand(_ command: KeyCommand) -> Bool {
        switch command {
        case .enter:
            if let item = selectedItem ?? listItems.first { copy(item, closeAfter: true) }
            return true
        case .up: return moveSelection(visualDown: false)
        case .down: return moveSelection(visualDown: true)
        case .escape:
            if selection != nil { selection = nil } else if !search.isEmpty { search = "" } else { composerFocus += 1 }
            return true
        case .tab:
            composerFocus += 1
            return true
        case .deleteSelection:
            if let item = selectedItem { delete(item); return true }
            return false
        case .newline:
            return true
        }
    }

    private func escape() {
        if quickLook.isVisible {
            quickLook.close()
        } else if selection != nil {
            selection = nil
        } else if isFiltering {
            search = ""
            filter = .all
        } else {
            close()
        }
    }

    /// Moves the keyboard selection visually up or down. Returns false to let the text field
    /// handle the key (e.g. moving the caret).
    @discardableResult
    func moveSelection(visualDown: Bool) -> Bool {
        let list = listItems
        guard !list.isEmpty else { return selection != nil }
        let older = listFlowsUp ? !visualDown : visualDown // index 0 = newest = next to the input
        if let id = selection, let index = list.firstIndex(where: { $0.id == id }) {
            let next = older ? index + 1 : index - 1
            selection = next < 0 ? nil : list[min(next, list.count - 1)].id
        } else if older {
            selection = list[0].id
        } else {
            return false
        }
        if let selection { scrollRequest = ScrollRequest(id: selection) }
        return true
    }

    /// ⌘-shortcuts while the panel is focused. Returns true when handled.
    func handleKeyEquivalent(_ event: NSEvent, textHasSelection: Bool) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if flags == [.command, .option], key == "v" { pasteIntoComposer(); return true }
        if flags.isEmpty, key == " ", editingID == nil, let item = selectedItem, !composerFocused || settings.draft.isEmpty {
            quickLook(item)
            return true
        }
        guard flags == .command else { return false }
        switch key {
        case "f": searchFocus += 1; return true
        case "n": selection = nil; composerFocus += 1; return true
        case "w": close(); return true
        case ",": openSettings(); return true
        case "c":
            if !textHasSelection, let item = selectedItem { copy(item); return true }
            return false
        case "p":
            if let item = selectedItem { togglePin(item); return true }
            return false
        case "e":
            if let item = selectedItem { beginEditing(item); return true }
            return false
        case "o":
            if let item = selectedItem { open(item); return true }
            return false
        case "y":
            if let item = selectedItem { quickLook(item); return true }
            return false
        case "z":
            if undoAction != nil { undo(); return true }
            return false
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            let index = Int(key)! - 1
            if index < pinnedItems.count { copy(pinnedItems[index], closeAfter: true); return true }
            return false
        default:
            return false
        }
    }

    // MARK: Feedback

    private func flashCopied(_ id: UUID?) {
        copiedID = id
        guard let id else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            MainActor.assumeIsolated { if self?.copiedID == id { self?.copiedID = nil } }
        }
    }

    func showToast(_ text: String, symbol: String, canUndo: Bool = false, isError: Bool = false) {
        if !canUndo { undoAction = nil }
        let toast = Toast(text: text, symbol: symbol, canUndo: canUndo, isError: isError)
        withAnimation(Motion.standard) { self.toast = toast }
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.toast?.id == toast.id else { return }
                withAnimation(Motion.quick) { self.toast = nil }
                if canUndo { self.undoAction = nil }
            }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (canUndo || isError ? 6 : 2.5), execute: work)
    }

    func showError(_ error: Error) {
        showToast(error.localizedDescription, symbol: "exclamationmark.triangle", isError: true)
    }

    func disableMacHotCorner() {
        MacHotCorners.disable(settings.corner)
        conflictAction = nil
        showToast("Quick Note corner turned off", symbol: "checkmark")
    }

    func hideConflictBanner() {
        settings.hideConflictBanner = true
        withAnimation(Motion.standard) { conflictAction = nil }
    }
}
