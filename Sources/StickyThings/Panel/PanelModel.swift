import AppKit
import SwiftUI

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var symbol: String
    var hasUndo = false
    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

struct ScrollRequest: Equatable {
    let id: UUID
    let token = UUID()
}

/// Everything the panel shows and every action it can take.
@MainActor
final class PanelModel: ObservableObject {
    let store: NoteStore
    let settings: Settings

    // Presentation
    @Published var isPresented = false
    @Published var anchorAtBottom = true
    @Published var scaleAnchor: UnitPoint = .bottomTrailing
    @Published var panelHeight: CGFloat = 560
    @Published var keepOpen = false
    @Published var conflictAction: String?

    // Input
    @Published var search = "" {
        didSet { if search != oldValue { selection = nil } }
    }
    @Published var editText = ""
    @Published var editingID: UUID?
    @Published var selection: UUID?
    @Published var composerFocus = 0
    @Published var searchFocus = 0
    @Published var composerHeight: CGFloat = 20
    @Published var searchHeight: CGFloat = 18
    @Published var composerFocused = false

    // Feedback
    @Published var toast: Toast?
    @Published var flashID: UUID?
    @Published var isDropTargeted = false
    @Published var scrollRequest: ScrollRequest?
    /// Bumped every time the panel opens so the list jumps back to the newest note.
    @Published var openToken = 0

    var close: () -> Void = {}
    /// Close without handing focus back (we just opened a link/file in another app).
    var closeForHandoff: () -> Void = {}
    var openSettings: () -> Void = {}
    private var undoAction: (() -> Void)?
    private var toastWork: DispatchWorkItem?

    init(store: NoteStore, settings: Settings) {
        self.store = store
        self.settings = settings
    }

    // MARK: Derived

    var isSearching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Newest first. Pinned notes live in their own strip unless you're searching.
    var listNotes: [Note] {
        isSearching ? store.search(search) : store.notes.filter { !$0.pinned }
    }

    var pinnedNotes: [Note] { store.notes.filter(\.pinned) }

    /// The stack grows away from the corner: newest right next to the composer.
    var listFlowsUp: Bool { anchorAtBottom && !isSearching }

    var composerText: Binding<String> {
        Binding(
            get: { [unowned self] in self.editingID == nil ? self.settings.draft : self.editText },
            set: { [unowned self] value in
                if self.editingID == nil { self.settings.draft = value } else { self.editText = value }
                if self.selection != nil { self.selection = nil }
            }
        )
    }

    // MARK: Opening

    func prepareForOpen() {
        selection = nil
        flashID = nil
        isDropTargeted = false
        toast = nil
        if !isSearching { search = "" }
        conflictAction = settings.hideConflictBanner ? nil : MacHotCorners.conflictingAction(for: settings.corner)
        composerFocus += 1
        openToken += 1
    }

    // MARK: Composer

    func submitComposer() {
        if let id = editingID {
            store.updateText(id, to: editText)
            editingID = nil
            editText = ""
            flashID = id
            showToast("Updated", symbol: "checkmark")
            return
        }
        guard let note = store.addText(settings.draft) else { return }
        settings.draft = ""
        didSave([note])
    }

    /// ⌘V: with an empty composer anything on the clipboard is saved instantly.
    func handlePaste(_ pasteboard: NSPasteboard) -> Bool {
        let contents = Clip.read(from: pasteboard)
        guard !contents.isEmpty else { return false }
        let composerEmpty = composerText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let nonText = contents.filter { !$0.isText }
        if editingID != nil || !composerEmpty {
            // Typing already: text pastes inline, images/files still become their own notes.
            guard !nonText.isEmpty else { return false }
            didSave(store.add(nonText))
            return true
        }
        didSave(store.add(contents))
        return true
    }

    /// ⌥⌘V: paste the clipboard's text into the composer to edit it before saving.
    func pasteIntoComposer() {
        guard let string = NSPasteboard.general.string(forType: .string) else { return }
        composerText.wrappedValue += string
        composerFocus += 1
    }

    func dropped(_ pasteboard: NSPasteboard) -> Bool {
        isDropTargeted = false
        let contents = Clip.read(from: pasteboard)
        guard !contents.isEmpty else { return false }
        didSave(store.add(contents))
        return true
    }

    private func didSave(_ notes: [Note]) {
        guard let first = notes.first else { return }
        selection = nil
        if !search.isEmpty { search = "" }
        flashID = first.id
        scrollRequest = ScrollRequest(id: first.id)
        showToast(notes.count > 1 ? "Saved \(notes.count) items" : "Saved", symbol: "checkmark")
    }

    // MARK: Keyboard

    func handleComposerCommand(_ command: KeyCommand) -> Bool {
        switch command {
        case .enter:
            if let note = selectedNote { copy(note, closeAfter: true) } else { submitComposer() }
            return true
        case .up:
            return moveSelection(visualDown: false)
        case .down:
            return moveSelection(visualDown: true)
        case .escape:
            escape()
            return true
        case .tab:
            searchFocus += 1
            return true
        case .deleteSelection:
            if let note = selectedNote { delete(note); return true }
            return false
        case .newline:
            return false
        }
    }

    func handleSearchCommand(_ command: KeyCommand) -> Bool {
        switch command {
        case .enter:
            if let note = selectedNote ?? listNotes.first { copy(note, closeAfter: true) }
            return true
        case .up:
            return moveSelection(visualDown: false)
        case .down:
            return moveSelection(visualDown: true)
        case .escape:
            if selection != nil { selection = nil } else if !search.isEmpty { search = "" } else { composerFocus += 1 }
            return true
        case .tab:
            composerFocus += 1
            return true
        case .deleteSelection:
            if let note = selectedNote { delete(note); return true }
            return false
        case .newline:
            return true
        }
    }

    private func escape() {
        if selection != nil {
            selection = nil
        } else if editingID != nil {
            cancelEditing()
        } else if !search.isEmpty {
            search = ""
        } else {
            close()
        }
    }

    /// Moves the keyboard selection visually up or down through the cards.
    /// Returns false when the key should be left to the text field.
    @discardableResult
    func moveSelection(visualDown: Bool) -> Bool {
        let list = listNotes
        guard !list.isEmpty else { return selection != nil }
        // index 0 = newest = closest to the input field
        let older = listFlowsUp ? !visualDown : visualDown
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

    var selectedNote: Note? { selection.flatMap { store.note($0) } }

    /// Command-key shortcuts while the panel is focused. Returns true if handled.
    func handleKeyEquivalent(_ event: NSEvent, textHasSelection: Bool) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if flags == [.command, .option], key == "v" { pasteIntoComposer(); return true }
        guard flags == .command else { return false }
        switch key {
        case "f": searchFocus += 1; return true
        case "n": selection = nil; composerFocus += 1; return true
        case "w": close(); return true
        case ",": openSettings(); return true
        case "c":
            if !textHasSelection, let note = selectedNote { copy(note, closeAfter: false); return true }
            return false
        case "p":
            if let note = selectedNote { togglePin(note); return true }
            return false
        case "e":
            if let note = selectedNote, note.kind == .text || note.kind == .link { beginEditing(note); return true }
            return false
        case "o":
            if let note = selectedNote { open(note); return true }
            return false
        case "z":
            if let undoAction { undoAction(); self.undoAction = nil; toast = nil; return true }
            return false
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            let index = Int(key)! - 1
            let pinned = pinnedNotes
            if index < pinned.count { copy(pinned[index], closeAfter: true); return true }
            return false
        default:
            return false
        }
    }

    // MARK: Note actions

    func copy(_ note: Note, closeAfter: Bool) {
        guard NoteActions.copy(note, store: store) else {
            showToast("That file has moved or been deleted", symbol: "exclamationmark.triangle")
            return
        }
        flash(note.id)
        if closeAfter && !keepOpen {
            close()
        } else {
            showToast("Copied", symbol: "doc.on.doc")
        }
    }

    func open(_ note: Note) {
        switch note.kind {
        case .text: beginEditing(note)
        default:
            NoteActions.open(note, store: store)
            if !keepOpen { closeForHandoff() }
        }
    }

    func reveal(_ note: Note) {
        NoteActions.revealInFinder(note, store: store)
        if !keepOpen { closeForHandoff() }
    }

    func togglePin(_ note: Note) {
        withAnimation(.snappy) { store.togglePin(note.id) }
        if selection == note.id, !isSearching { selection = nil }
        showToast(note.pinned ? "Unpinned" : "Pinned", symbol: note.pinned ? "pin.slash" : "pin")
    }

    func setColor(_ color: NoteColor, for note: Note) {
        store.setColor(color, for: note.id)
    }

    func delete(_ note: Note) {
        let list = listNotes
        let index = list.firstIndex(where: { $0.id == note.id })
        guard let removed = withAnimation(.snappy, { store.delete(note.id) }) else { return }
        if selection == note.id, let index {
            let remaining = listNotes
            selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
        if editingID == note.id { cancelEditing() }
        undoAction = { [weak self] in
            withAnimation(.snappy) { self?.store.restore(removed.note, at: removed.index) }
        }
        showToast("Deleted", symbol: "trash", undo: true)
    }

    func undo() {
        undoAction?()
        undoAction = nil
        toast = nil
    }

    func beginEditing(_ note: Note) {
        editingID = note.id
        editText = note.text
        selection = nil
        composerFocus += 1
    }

    func cancelEditing() {
        editingID = nil
        editText = ""
        composerFocus += 1
    }

    // MARK: Feedback

    func flash(_ id: UUID) {
        flashID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            MainActor.assumeIsolated { if self?.flashID == id { self?.flashID = nil } }
        }
    }

    func showToast(_ text: String, symbol: String, undo: Bool = false) {
        if !undo { undoAction = nil }
        let toast = Toast(text: text, symbol: symbol, hasUndo: undo)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { self.toast = toast }
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.toast?.id == toast.id else { return }
                withAnimation(.easeOut(duration: 0.2)) { self.toast = nil }
                if undo { self.undoAction = nil }
            }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (undo ? 4.0 : 1.6), execute: work)
    }

    func disableMacHotCorner() {
        MacHotCorners.disable(settings.corner)
        conflictAction = nil
        showToast("Quick Note corner turned off", symbol: "checkmark")
    }

    func hideConflictBanner() {
        settings.hideConflictBanner = true
        withAnimation { conflictAction = nil }
    }
}
