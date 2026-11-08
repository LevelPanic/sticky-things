import AppKit
import XCTest
@testable import StickyCore

@MainActor
final class RoundTripTests: XCTestCase {
    var paths: StorePaths!
    var store: ItemStore!
    var capture: CaptureService!

    override func setUp() async throws {
        paths = StorePaths.temporary()
        store = try ItemStore(paths: paths, inMemory: true)
        capture = CaptureService(store: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: paths.root)
    }

    /// The core promise: whatever goes in comes back out byte-for-byte, private types included.
    func testEverythingComesBackExactly() throws {
        let source = Fixtures.pasteboard(), target = Fixtures.pasteboard()
        defer { source.releaseGlobally(); target.releaseGlobally() }
        let rtf = NSAttributedString(string: "Hi").rtf(from: NSRange(location: 0, length: 2), documentAttributes: [:])!
        source.clearContents()
        let item = NSPasteboardItem()
        item.setString("Hi", forType: .string)
        item.setData(rtf, forType: .rtf)
        item.setData(Data([1, 2, 3, 4]), forType: .init("com.figma.private-layer-data"))
        source.writeObjects([item])

        guard case .saved(let saved) = try capture.save(from: source, source: nil) else { return XCTFail("not saved") }
        XCTAssertEqual(saved.first?.kind, .richText)
        XCTAssertTrue(PasteboardWriter.copy(saved[0], store: store, to: target))

        let back = target.pasteboardItems?.first
        XCTAssertEqual(back?.string(forType: .string), "Hi")
        XCTAssertEqual(back?.data(forType: .rtf), rtf)
        XCTAssertEqual(back?.data(forType: .init("com.figma.private-layer-data")), Data([1, 2, 3, 4]))
        XCTAssertEqual(back?.string(forType: .init(UTI.source)), PasteboardWriter.ourBundleID)
    }

    func testFilesAreKeptEvenAfterTheOriginalIsDeleted() throws {
        let pb = Fixtures.pasteboard(), target = Fixtures.pasteboard()
        defer { pb.releaseGlobally(); target.releaseGlobally() }
        let bytes = Fixtures.pdf(pages: 2)
        let original = Fixtures.tempFile("Invoice.pdf", contents: bytes)
        pb.clearContents()
        pb.writeObjects([original as NSURL])

        guard case .saved(let saved) = try capture.save(from: pb, source: nil) else { return XCTFail("not saved") }
        let item = saved[0]
        XCTAssertEqual(item.kind, .pdf)
        XCTAssertEqual(item.pageCount, 2)
        XCTAssertNotNil(item.files.first?.libraryPath, "a copy should be kept in the library")

        try FileManager.default.removeItem(at: original)
        XCTAssertTrue(PasteboardWriter.copy(item, store: store, to: target))
        let urls = target.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        let copied = try XCTUnwrap(urls?.first)
        XCTAssertEqual(copied.lastPathComponent, "Invoice.pdf", "keeps the original name")
        XCTAssertEqual(try Data(contentsOf: copied), bytes)

        // What's on the clipboard is a clone, never our stored copy: Finder's ⌥⌘V *moves* pasted
        // files, and that must not empty the library.
        XCTAssertFalse(copied.path.hasPrefix(paths.files.path))
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("moved-\(UUID().uuidString).pdf")
        try FileManager.default.moveItem(at: copied, to: elsewhere)
        let stored = try XCTUnwrap(store.files.url(for: item.files[0]))
        XCTAssertTrue(stored.path.hasPrefix(paths.files.path))
        XCTAssertEqual(try Data(contentsOf: stored), bytes)
    }

    func testDuplicatePastesAndTypedNotes() throws {
        let pb = Fixtures.pasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("same thing", forType: .string)
        guard case .saved = try capture.save(from: pb, source: nil) else { return XCTFail() }
        guard case .duplicate = try capture.save(from: pb, source: nil) else { return XCTFail("should dedupe") }
        XCTAssertEqual(store.items.count, 1)

        XCTAssertEqual(capture.saveNote("https://example.com")?.items.first?.kind, .link)
        XCTAssertNil(capture.saveNote("   "))
        pb.clearContents()
        XCTAssertThrowsError(try capture.save(from: pb, source: nil)) { XCTAssertEqual($0 as? CoreError, .nothingToSave) }
    }

    func testDataOnlyImagesBecomeRealFilesForDragging() throws {
        let pb = Fixtures.pasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setData(Fixtures.png(), forType: .png)
        guard case .saved(let saved) = try capture.save(from: pb, source: nil) else { return XCTFail() }
        let file = try XCTUnwrap(Materializer.file(for: saved[0], store: store, purpose: .drag))
        XCTAssertEqual(file.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: file), Fixtures.png())
    }
}

@MainActor
final class ItemStoreTests: XCTestCase {
    var paths: StorePaths!

    override func setUp() async throws { paths = StorePaths.temporary() }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: paths.root) }

    func testPersistsAcrossLaunches() throws {
        do {
            let store = try ItemStore(paths: paths)
            store.insert(Item(kind: .text, text: "first", createdAt: Date(timeIntervalSince1970: 100)))
            store.insert(Item(kind: .text, text: "second", createdAt: Date(timeIntervalSince1970: 200)))
            store.togglePin(store.items[1].id)
        }
        let reopened = try ItemStore(paths: paths)
        XCTAssertEqual(reopened.items.map(\.text), ["second", "first"])
        XCTAssertEqual(reopened.pinned.map(\.text), ["first"])
    }

    func testEditDeleteUndoSearch() throws {
        let store = try ItemStore(paths: paths, inMemory: true)
        let a = Item(kind: .text, text: "Café meeting notes", createdAt: Date(timeIntervalSince1970: 1))
        let b = Item(kind: .text, text: "groceries", createdAt: Date(timeIntervalSince1970: 2))
        store.insert([a, b])
        XCTAssertEqual(store.search("cafe MEETING").map(\.id), [a.id])
        XCTAssertEqual(store.search("", filter: .links).count, 0)

        store.setText(b.id, to: "https://example.com")
        XCTAssertEqual(store.item(b.id)?.kind, .link)
        let removed = try XCTUnwrap(store.delete(a.id))
        XCTAssertNil(store.item(a.id))
        store.restore(removed)
        XCTAssertEqual(store.items.map(\.id), [b.id, a.id])
    }

    func testRetentionAndGarbageCollection() throws {
        let store = try ItemStore(paths: paths, inMemory: true)
        let capture = CaptureService(store: store)
        let old = Date().addingTimeInterval(-40 * 86_400)
        store.insert([Item(kind: .text, text: "old", createdAt: old),
                      Item(kind: .text, text: "old pinned", pinned: true, createdAt: old)])
        store.applyRetention(days: 30)
        XCTAssertEqual(store.items.map(\.text), ["old pinned"])

        let pb = Fixtures.pasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.writeObjects([Fixtures.tempFile("keep.txt") as NSURL])
        guard case .saved(let saved) = try capture.save(from: pb, source: nil) else { return XCTFail() }
        let folder = store.files.folder(for: saved[0].id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        store.delete(saved[0].id)
        store.collectGarbage(blobGracePeriod: 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testImportsVersionOneNotesOnce() throws {
        try paths.createDirectories()
        try FileManager.default.createDirectory(at: paths.legacyMedia, withIntermediateDirectories: true)
        try Fixtures.png().write(to: paths.legacyMedia.appendingPathComponent("shot.png"))
        let json = """
        {"version":1,"notes":[
          {"id":"\(UUID())","kind":"text","text":"from v1","color":"yellow","pinned":true,"createdAt":"2026-11-01T10:00:00Z"},
          {"id":"\(UUID())","kind":"link","text":"https://apple.com","title":"Apple","createdAt":"2026-11-02T10:00:00Z"},
          {"id":"\(UUID())","kind":"image","text":"","imageFile":"shot.png","pixelWidth":4,"pixelHeight":3,"createdAt":"2026-11-03T10:00:00Z"}
        ]}
        """
        try Data(json.utf8).write(to: paths.legacyNotes)
        let store = try ItemStore(paths: paths)
        XCTAssertEqual(LegacyImporter.importIfNeeded(into: store), 3)
        XCTAssertEqual(store.items.map(\.kind), [.image, .link, .text])
        XCTAssertEqual(store.items.last?.tint, .yellow)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.legacyNotes.path))
        XCTAssertEqual(LegacyImporter.importIfNeeded(into: store), 0)
    }
}

private extension CaptureService.Outcome {
    var items: [Item] {
        switch self {
        case .saved(let items): return items
        case .duplicate(let item): return [item]
        case .pending: return []
        }
    }
}
