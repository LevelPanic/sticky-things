import AppKit
import XCTest
import StickyCore
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
