import AppKit
import XCTest
@testable import StickyThings

final class ClipTests: XCTestCase {
    func testLinkDetection() {
        XCTAssertNotNil(Clip.linkURL(from: "https://example.com/a?b=1"))
        XCTAssertEqual(Clip.linkURL(from: "www.apple.com")?.absoluteString, "https://www.apple.com")
        XCTAssertNotNil(Clip.linkURL(from: "  mailto:hi@example.com \n"))
        XCTAssertNil(Clip.linkURL(from: "check https://example.com later"))
        XCTAssertNil(Clip.linkURL(from: "just some words"))
        XCTAssertNil(Clip.linkURL(from: "https://nodot"))
    }

    func testReadsTextLinkAndImageFromPasteboard() {
        let pb = NSPasteboard(name: NSPasteboard.Name("StickyThingsTests-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }

        pb.clearContents()
        pb.setString("hello\nworld", forType: .string)
        XCTAssertEqual(Clip.read(from: pb), [.text("hello\nworld")])

        pb.clearContents()
        pb.setString("https://example.com", forType: .string)
        XCTAssertEqual(Clip.read(from: pb), [.link(URL(string: "https://example.com")!)])

        pb.clearContents()
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        pb.writeObjects([image])
        guard case .image(let png)? = Clip.read(from: pb).first else { return XCTFail("expected an image") }
        XCTAssertEqual(NSBitmapImageRep(data: png)?.pixelsWide, 4)
    }

    func testSpreadsheetTextBeatsItsPicture() {
        let pb = NSPasteboard(name: NSPasteboard.Name("StickyThingsTests-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        let image = NSImage(size: NSSize(width: 2, height: 2), flipped: false) { rect in rect.fill(); return true }
        pb.writeObjects([image])
        pb.setString("a\tb\n1\t2", forType: .string)
        XCTAssertEqual(Clip.read(from: pb), [.text("a\tb\n1\t2")])
    }
}

@MainActor
final class NoteStoreTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("StickyThingsTests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testAddSaveAndReload() throws {
        let store = NoteStore(rootURL: folder)
        store.load()
        store.addText("first")
        store.add([.link(URL(string: "https://example.com")!)])
        store.addText("second")
        store.togglePin(store.notes[0].id)
        store.saveNow()

        let reloaded = NoteStore(rootURL: folder)
        reloaded.load()
        XCTAssertEqual(reloaded.notes.map(\.text), ["second", "https://example.com", "first"])
        XCTAssertEqual(reloaded.notes.first?.pinned, true)
        XCTAssertEqual(reloaded.notes[1].kind, .link)
    }

    func testDuplicatePasteIsIgnored() {
        let store = NoteStore(rootURL: folder)
        store.persists = false
        store.addText("same")
        store.addText("same")
        XCTAssertEqual(store.notes.count, 1)
    }

    func testDeleteAndUndo() {
        let store = NoteStore(rootURL: folder)
        store.persists = false
        store.addText("a"); store.addText("b"); store.addText("c")
        let removed = store.delete(store.notes[1].id)!
        XCTAssertEqual(store.notes.map(\.text), ["c", "a"])
        store.restore(removed.note, at: removed.index)
        XCTAssertEqual(store.notes.map(\.text), ["c", "b", "a"])
    }

    func testSearchMatchesAllTerms() {
        let store = NoteStore(rootURL: folder)
        store.persists = false
        store.addText("Call Sam about the lease")
        store.addText("Groceries: milk, eggs")
        XCTAssertEqual(store.search("sam lease").count, 1)
        XCTAssertEqual(store.search("EGGS").first?.text, "Groceries: milk, eggs")
        XCTAssertEqual(store.search("").count, 2)
    }

    func testEditingTurnsTextIntoLink() {
        let store = NoteStore(rootURL: folder)
        store.persists = false
        let note = store.addText("draft")!
        store.updateText(note.id, to: "https://example.com")
        XCTAssertEqual(store.note(note.id)?.kind, .link)
    }

    func testImagesAreStoredAndDeduplicated() throws {
        let store = NoteStore(rootURL: folder)
        store.load()
        let image = NSImage(size: NSSize(width: 3, height: 2), flipped: false) { rect in rect.fill(); return true }
        let png = Clip.pngData(from: image.tiffRepresentation!)!
        store.add([.image(png)])
        store.add([.image(png)])
        XCTAssertEqual(store.notes.count, 1)
        let note = store.notes[0]
        XCTAssertEqual(note.pixelWidth, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.mediaFile(note.imageFile)!.path))
    }

    func testRetentionKeepsPinned() {
        let store = NoteStore(rootURL: folder)
        store.persists = false
        let old = Date().addingTimeInterval(-40 * 86_400)
        store.replaceAll(with: [
            Note(kind: .text, text: "old", createdAt: old),
            Note(kind: .text, text: "old pinned", pinned: true, createdAt: old),
            Note(kind: .text, text: "new"),
        ])
        store.applyRetention(days: 30)
        XCTAssertEqual(Set(store.notes.map(\.text)), ["old pinned", "new"])
    }
}

final class GeometryTests: XCTestCase {
    func testCornerRects() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(ScreenCorner.bottomRight.rect(size: NSSize(width: 10, height: 10), in: screen),
                       NSRect(x: 1430, y: 0, width: 10, height: 10))
        XCTAssertEqual(ScreenCorner.topLeft.rect(size: NSSize(width: 10, height: 10), in: screen, inset: 5),
                       NSRect(x: 5, y: 885, width: 10, height: 10))
    }

    func testHardCornersWithTwoDisplays() {
        let left = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let right = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        let frames = [left, right]
        // The left display's bottom-right corner touches the right display: the pointer slides past it.
        XCTAssertFalse(ScreenCorner.isHard(.bottomRight, of: left, among: frames))
        XCTAssertTrue(ScreenCorner.isHard(.bottomRight, of: right, among: frames))
        XCTAssertTrue(ScreenCorner.isHard(.bottomLeft, of: left, among: frames))
        XCTAssertTrue(ScreenCorner.isHard(.bottomRight, of: left, among: [left]))
    }

    func testKeyComboDisplay() {
        XCTAssertEqual(KeyCombo.default.displayString, "⌃⌥N")
        XCTAssertTrue(KeyCombo.default.isValidGlobalShortcut)
    }
}
