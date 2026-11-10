import AppKit
import XCTest
import StickyCore
import StickyDesign
@testable import StickyThings

@MainActor
final class PanelModelTests: XCTestCase {
    var paths: StorePaths!
    var store: ItemStore!
    var model: PanelModel!
    var clipboard: NSPasteboard!

    override func setUp() async throws {
        paths = StorePaths.temporary()
        store = try ItemStore(paths: paths, inMemory: true)
        let settings = Settings(defaults: UserDefaults(suiteName: "PanelModelTests-\(UUID().uuidString)")!)
        model = PanelModel(store: store, capture: CaptureService(store: store), settings: settings)
        clipboard = NSPasteboard(name: .init("PanelModelTests-\(UUID().uuidString)"))
        model.pasteboard = clipboard
    }

    override func tearDown() async throws {
        clipboard.releaseGlobally()
        try? FileManager.default.removeItem(at: paths.root)
    }

    private func pasteboard(_ fill: (NSPasteboard) -> Void) -> NSPasteboard {
        let pb = NSPasteboard(name: .init("PanelModelTests-src-\(UUID().uuidString)"))
        pb.clearContents()
        fill(pb)
        return pb
    }

    func testPasteSavesInstantlyOnlyWhenNotTyping() {
        let text = pasteboard { $0.setString("from Safari", forType: .string) }
        defer { text.releaseGlobally() }
        XCTAssertTrue(model.paste(from: text), "empty composer: saved instantly")
        XCTAssertEqual(store.items.first?.text, "from Safari")

        model.settings.draft = "I'm typing "
        XCTAssertFalse(model.paste(from: text), "while typing, text pastes inline")

        let image = pasteboard { pb in
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            pb.setData(rep.representation(using: .png, properties: [:])!, forType: .png)
        }
        defer { image.releaseGlobally() }
        XCTAssertTrue(model.paste(from: image), "while typing, an image still becomes its own item")
        XCTAssertEqual(store.items.first?.kind, .image)
        XCTAssertEqual(model.settings.draft, "I'm typing ", "the draft is left alone")
    }

    func testArrowKeysMoveAwayFromTheCorner() {
        model.capture.saveNote("older")
        model.capture.saveNote("newer")
        model.anchorAtBottom = true // composer at the bottom: the stack grows upward
        XCTAssertTrue(model.handleComposerCommand(.up))
        XCTAssertEqual(model.selectedItem?.text, "newer")
        _ = model.handleComposerCommand(.up)
        XCTAssertEqual(model.selectedItem?.text, "older")
        _ = model.handleComposerCommand(.down)
        _ = model.handleComposerCommand(.down)
        XCTAssertNil(model.selection, "↓ past the newest returns to the composer")
        XCTAssertFalse(model.handleComposerCommand(.down), "nothing below the composer: let the text view have it")

        model.anchorAtBottom = false // opened from the menu bar: composer on top
        XCTAssertTrue(model.handleComposerCommand(.down))
        XCTAssertEqual(model.selectedItem?.text, "newer")
    }

    func testOneClickCopySelectsAndConfirms() {
        model.capture.saveNote("copy me")
        let item = store.items[0]
        model.copy(item)
        XCTAssertEqual(clipboard.string(forType: .string), "copy me")
        XCTAssertEqual(model.copiedID, item.id)
        XCTAssertEqual(model.selection, item.id)
    }

    func testHoverMovingBetweenCards() {
        let a = UUID(), b = UUID()
        model.setHovered(a, true)
        XCTAssertEqual(model.hoveredID, a)
        model.setHovered(b, true)   // SwiftUI may report entering B before leaving A
        model.setHovered(a, false)
        XCTAssertEqual(model.hoveredID, b, "leaving A must not clear B")
        model.setHovered(b, false)
        XCTAssertNil(model.hoveredID)
    }

    func testInlineEditAndUndo() {
        model.capture.saveNote("draft")
        let item = store.items[0]
        model.beginEditing(item)
        XCTAssertEqual(model.editingID, item.id)
        model.finishEditing(item.id, text: "final", rtf: nil)
        XCTAssertNil(model.editingID)
        XCTAssertEqual(store.item(item.id)?.text, "final")
        XCTAssertEqual(model.toast?.canUndo, true)
        model.undo()
        XCTAssertEqual(store.item(item.id)?.text, "draft")
    }

    func testEditEndings() {
        model.capture.saveNote("draft")
        let item = store.items[0]

        model.beginEditing(item)
        let focus = model.composerFocus
        model.finishEditing(item.id, text: "typo", rtf: nil, ending: .cancel)
        XCTAssertNil(model.editingID)
        XCTAssertEqual(store.item(item.id)?.text, "draft", "Cancel discards")
        XCTAssertEqual(model.composerFocus, focus + 1, "Esc puts the caret back in the composer")

        model.beginEditing(item)
        let focusBefore = model.composerFocus
        model.finishEditing(item.id, text: "kept", rtf: nil, ending: .focusLost)
        XCTAssertNil(model.editingID)
        XCTAssertEqual(store.item(item.id)?.text, "kept", "clicking elsewhere saves")
        XCTAssertEqual(model.composerFocus, focusBefore, "the field you clicked keeps the caret")

        // The editor of a card you already left (panel closed, another card being edited) still saves.
        model.beginEditing(item)
        model.editingID = nil
        model.finishEditing(item.id, text: "late", rtf: nil, ending: .focusLost)
        XCTAssertEqual(store.item(item.id)?.text, "late")
    }

    func testClickEditsNotesByDefaultAndCopiesEverythingElse() {
        XCTAssertEqual(model.settings.clickAction, .edit, "editing is the default")
        model.capture.saveNote("a note")
        let note = store.items[0]
        model.click(note)
        XCTAssertEqual(model.editingID, note.id, "a click edits a note")
        XCTAssertNil(clipboard.string(forType: .string), "…without copying it")
        model.finishEditing(note.id, text: "a note", rtf: nil, ending: .cancel)

        model.capture.saveNote("https://example.com/page")
        let link = store.items[0]
        model.click(link)
        XCTAssertNil(model.editingID, "links aren't edited by a click")
        XCTAssertEqual(clipboard.string(forType: .string), "https://example.com/page", "…they're copied")

        store.update(note.id) { $0.concealed = true }
        clipboard.clearContents()
        model.click(store.item(note.id)!)
        XCTAssertNil(model.editingID, "a hidden password copy never opens in an editor")
        XCTAssertEqual(clipboard.string(forType: .string), "a note")

        store.update(note.id) { $0.concealed = false }
        model.settings.clickAction = .copy
        clipboard.clearContents()
        model.click(store.item(note.id)!)
        XCTAssertNil(model.editingID)
        XCTAssertEqual(clipboard.string(forType: .string), "a note", "with clicks set to copy, a note is copied")
        XCTAssertEqual(model.selection, note.id, "…and stays selected so its buttons stay visible")
    }

    func testClickSettingIsRemembered() {
        let defaults = UserDefaults(suiteName: "PanelModelTests-click-\(UUID().uuidString)")!
        Settings(defaults: defaults).clickAction = .copy
        XCTAssertEqual(Settings(defaults: defaults).clickAction, .copy)
    }

    func testEditingWhatYoureAlreadyEditingKeepsTheEdit() {
        model.capture.saveNote("draft")
        let item = store.items[0]
        model.beginEditing(item)
        let session = model.editSession
        model.beginEditing(item) // a double-click on a note that a click already opened
        XCTAssertEqual(model.editSession, session, "the editor isn't rebuilt")
        XCTAssertEqual(model.editingID, item.id)
        model.activate(item)
        XCTAssertEqual(model.editSession, session)
    }

    func testSelectionFollowsWhereYouWork() {
        model.capture.saveNote("a")
        let item = store.items[0]

        model.copy(item)
        XCTAssertEqual(model.selection, item.id, "clicking a card selects it")
        model.pointedAtComposer()
        XCTAssertNil(model.selection, "clicking the composer clears it")

        model.copy(item)
        let searchFocus = model.searchFocus
        model.pointedAtSearch(focus: true)
        XCTAssertNil(model.selection, "clicking search clears it")
        XCTAssertEqual(model.searchFocus, searchFocus + 1, "clicking the search field's icon focuses its text")

        model.copy(item)
        model.clickedBackground()
        XCTAssertNil(model.selection, "clicking empty space clears it")

        model.copy(item)
        model.settings.draft = "now I'm writing"
        XCTAssertNil(model.selection, "typing a note clears it")

        // Browsing with ↑ while a draft exists still selects (the draft didn't change).
        XCTAssertTrue(model.moveSelection(visualDown: false) || model.moveSelection(visualDown: true))
        XCTAssertNotNil(model.selection)
    }

    func testFinishingAnEditClearsItsOutline() {
        model.capture.saveNote("draft")
        let item = store.items[0]
        for ending in [InlineTextEditor.Ending.save, .cancel, .focusLost] {
            model.beginEditing(item)
            XCTAssertEqual(model.selection, item.id)
            model.finishEditing(item.id, text: "draft", rtf: nil, ending: ending)
            XCTAssertNil(model.selection, "\(ending) leaves no outline behind")
        }
        // Starting another card's edit doesn't deselect it when the first edit finishes late.
        model.capture.saveNote("other")
        let other = store.items[0]
        model.beginEditing(item)
        model.beginEditing(other)
        model.finishEditing(item.id, text: "draft", rtf: nil, ending: .focusLost)
        XCTAssertEqual(model.selection, other.id)
        XCTAssertEqual(model.editingID, other.id)
    }

    func testEditingALinkKeepsItALink() {
        model.capture.saveNote("https://example.com/a")
        let item = store.items[0]
        XCTAssertEqual(item.kind, .link)
        model.beginEditing(item)
        model.finishEditing(item.id, text: "https://example.com/b", rtf: nil, ending: .save)
        XCTAssertEqual(store.item(item.id)?.kind, .link)
        XCTAssertEqual(store.item(item.id)?.link?.url, "https://example.com/b")
    }

    func testReturnInComposerSavesTextEvenWithASelection() {
        model.capture.saveNote("old")
        model.selection = store.items[0].id
        model.settings.draft = "new note"
        XCTAssertTrue(model.handleComposerCommand(.enter))
        XCTAssertEqual(store.items.first?.text, "new note", "typed text is saved, not the selected card copied")
        XCTAssertNil(model.selection)
        XCTAssertNil(clipboard.string(forType: .string))

        model.selection = store.items[1].id
        var closed = false
        model.close = { closed = true }
        XCTAssertTrue(model.handleComposerCommand(.enter))
        XCTAssertEqual(clipboard.string(forType: .string), "old", "empty composer: Return copies the selection")
        XCTAssertTrue(closed)
    }

    func testDeleteSelectsNeighbourAndUndoRestores() {
        model.capture.saveNote("a")
        model.capture.saveNote("b")
        model.capture.saveNote("c")
        let b = store.items[1]
        model.selection = b.id
        model.delete(b)
        XCTAssertNil(store.item(b.id))
        XCTAssertNotNil(model.selection, "selection moves to a neighbour")
        model.undo()
        XCTAssertEqual(store.items.map(\.text), ["c", "b", "a"])
    }

    func testPinnedShortcutsAndFilters() {
        model.capture.saveNote("wifi password")
        model.capture.saveNote("https://example.com")
        store.togglePin(store.items[1].id)
        XCTAssertEqual(model.pinnedItems.map(\.text), ["wifi password"])
        XCTAssertFalse(model.listItems.contains { $0.pinned }, "pinned items live in the strip")

        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0,
                                     context: nil, characters: "1", charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 18)!
        XCTAssertTrue(model.handleKeyEquivalent(event, textHasSelection: false))
        XCTAssertEqual(clipboard.string(forType: .string), "wifi password")

        model.filter = .links
        XCTAssertEqual(model.listItems.map(\.kind), [.link])
        model.search = "wifi"
        model.filter = .all
        XCTAssertEqual(model.listItems.map(\.text), ["wifi password"], "search includes pinned items")
    }
}

final class GeometryTests: XCTestCase {
    func testCornerRectsAndHardCorners() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(ScreenCorner.bottomRight.rect(size: NSSize(width: 10, height: 10), in: screen),
                       NSRect(x: 1430, y: 0, width: 10, height: 10))
        let left = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let right = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        XCTAssertFalse(ScreenCorner.isHard(.bottomRight, of: left, among: [left, right]), "pointer slides onto the next display")
        XCTAssertTrue(ScreenCorner.isHard(.bottomRight, of: right, among: [left, right]))
    }

    func testDefaultShortcut() {
        XCTAssertEqual(KeyCombo.default.displayString, "⌃⌥N")
        XCTAssertTrue(KeyCombo.default.isValidGlobalShortcut)
    }
}
