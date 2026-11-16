import AppKit
import XCTest
@testable import StickyCore

/// Helpers shared by the core tests.
enum Fixtures {
    static func pasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("StickyCoreTests-\(UUID().uuidString)"))
    }

    static func png(width: Int = 4, height: Int = 3) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    static func pdf(pages: Int = 2) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 200, height: 100)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        for _ in 0..<pages { context.beginPDFPage(nil); context.endPDFPage() }
        context.closePDF()
        return data as Data
    }

    static func tempFile(_ name: String, contents: Data = Data("hello".utf8)) -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fixtures-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try! contents.write(to: url)
        return url
    }

    static func clip(_ entries: [(String, Data)], fileURL: URL? = nil) -> CapturedClip {
        CapturedClip(elements: [.init(entries: entries.map { .init(type: $0.0, data: $0.1) }, fileURL: fileURL)])
    }
}

final class ClassifierTests: XCTestCase {
    func testPlainTextNoteAndLinks() {
        XCTAssertEqual(Classifier.classify(Fixtures.clip([(UTI.utf8Text, Data("buy milk".utf8))])).kind, .text)
        let link = Classifier.classify(Fixtures.clip([(UTI.utf8Text, Data("https://apple.com/mac".utf8))]))
        XCTAssertEqual(link.kind, .link)
        XCTAssertEqual(link.link?.url, "https://apple.com/mac")
        XCTAssertEqual(Classifier.singleLink(in: "www.apple.com")?.absoluteString, "https://www.apple.com")
        XCTAssertNotNil(Classifier.singleLink(in: "mailto:hi@example.com"))
        XCTAssertNil(Classifier.singleLink(in: "see https://apple.com later"))
        XCTAssertNil(Classifier.singleLink(in: "file:///Users/me/notes.txt"))
    }

    func testRichTextKeepsPlainTextForSearch() {
        let rtf = NSAttributedString(string: "Bold move", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
            .rtf(from: NSRange(location: 0, length: 9), documentAttributes: [:])!
        let result = Classifier.classify(Fixtures.clip([(UTI.rtf, rtf), (UTI.utf8Text, Data("Bold move".utf8))]))
        XCTAssertEqual(result.kind, .richText)
        XCTAssertEqual(result.text, "Bold move")
        // RTF only (no plain text on the pasteboard) still produces searchable text.
        XCTAssertEqual(Classifier.classify(Fixtures.clip([(UTI.rtf, rtf)])).text, "Bold move")
    }

    func testImagesPDFsAndTheirTextCompanions() {
        let png = Fixtures.png(width: 8, height: 5)
        let screenshot = Classifier.classify(Fixtures.clip([(UTI.png, png)]))
        XCTAssertEqual(screenshot.kind, .image)
        XCTAssertEqual(screenshot.pixelSize, PixelSize(width: 8, height: 5))
        // "Copy Image" in a browser adds the image URL as text: still an image.
        XCTAssertEqual(Classifier.classify(Fixtures.clip([(UTI.png, png), (UTI.utf8Text, Data("https://x.com/a.png".utf8))])).kind, .image)
        // Spreadsheets add a picture of the cells: the text wins.
        XCTAssertEqual(Classifier.classify(Fixtures.clip([(UTI.png, png), (UTI.utf8Text, Data("a\tb".utf8))])).kind, .text)
        let pdf = Classifier.classify(Fixtures.clip([(UTI.pdf, Fixtures.pdf(pages: 3))]))
        XCTAssertEqual(pdf.kind, .pdf)
        XCTAssertEqual(pdf.pageCount, 3)
    }

    func testFilesFoldersAndUnknownData() throws {
        let pdfURL = Fixtures.tempFile("Report.pdf", contents: Fixtures.pdf(pages: 1))
        XCTAssertEqual(Classifier.classifyFiles([pdfURL]).kind, .pdf)
        XCTAssertEqual(Classifier.classifyFiles([Fixtures.tempFile("a.png", contents: Fixtures.png())]).kind, .image)
        XCTAssertEqual(Classifier.classifyFiles([Fixtures.tempFile("notes.zip")]).kind, .file)
        XCTAssertEqual(Classifier.classifyFiles([pdfURL.deletingLastPathComponent()]).kind, .folder)
        XCTAssertEqual(Classifier.classifyFiles([pdfURL, Fixtures.tempFile("b.txt")]).kind, .files)
        let other = Classifier.classify(Fixtures.clip([("com.figma.layers", Data([1, 2, 3]))]))
        XCTAssertEqual(other.kind, .other)
        XCTAssertTrue(other.text.contains("com.figma.layers"))
    }
}

final class SnapshotterTests: XCTestCase {
    func testCapturesEveryItemAndTypeAndSkipsNoise() {
        let pb = Fixtures.pasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        let first = NSPasteboardItem()
        first.setString("hello", forType: .string)
        first.setData(Data([9, 9, 9]), forType: .init("com.example.private"))
        first.setData(Data(), forType: .init(UTI.concealed))
        first.setString("com.example.app", forType: .init(UTI.source))
        first.setData(Data(), forType: .init(UTI.transient))
        let second = NSPasteboardItem()
        second.setString("world", forType: .string)
        pb.writeObjects([first, second])

        let clip = PasteboardSnapshotter.capture(pb)
        XCTAssertEqual(clip.elements.count, 2)
        XCTAssertEqual(clip.elements[0].data("com.example.private"), Data([9, 9, 9]))
        XCTAssertNil(clip.elements[0].data(UTI.transient))
        XCTAssertTrue(clip.concealed)
        XCTAssertEqual(clip.sourceBundleID, "com.example.app")
        XCTAssertEqual(clip.plainText, "hello")
    }

    func testOversizedTypesAreSkippedNotFatal() {
        let pb = Fixtures.pasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString("small", forType: .string)
        item.setData(Data(count: 2_000), forType: .init("com.example.big"))
        pb.writeObjects([item])
        let clip = PasteboardSnapshotter.capture(pb, limits: .init(perType: 1_000, total: 10_000))
        XCTAssertEqual(clip.skipped, ["com.example.big"])
        XCTAssertEqual(clip.plainText, "small")
    }

    func testFinderStyleFileItemsBecomeFiles() {
        let pb = Fixtures.pasteboard()
        defer { pb.releaseGlobally() }
        let a = Fixtures.tempFile("one.txt"), b = Fixtures.tempFile("two.txt")
        pb.clearContents()
        pb.writeObjects([a as NSURL, b as NSURL])
        let clip = PasteboardSnapshotter.capture(pb)
        XCTAssertEqual(clip.fileURLs.map(\.lastPathComponent), ["one.txt", "two.txt"])
        XCTAssertEqual(Classifier.classify(clip).kind, .files)
    }
}
