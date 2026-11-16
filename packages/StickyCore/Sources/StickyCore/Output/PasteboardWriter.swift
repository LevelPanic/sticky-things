#if os(macOS)
import AppKit
import UniformTypeIdentifiers

/// Gives items back exactly as they came in: every pasteboard item, every type, byte for byte —
/// with file URLs pointing at our stored copies so pasting into Finder copies the real file.
@MainActor
public enum PasteboardWriter {
    public static let ourBundleID = "app.stickythings.StickyThings"

    /// Copies an item to the clipboard. Returns false when nothing could be written
    /// (e.g. every file it pointed to is gone).
    @discardableResult
    public static func copy(_ item: Item, store: ItemStore, to pasteboard: NSPasteboard = .general) -> Bool {
        let items = pasteboardItems(for: item, store: store, forClipboard: true)
        guard !items.isEmpty else { return false }
        // Secrets stay on this Mac: no Universal Clipboard hand-off.
        pasteboard.prepareForNewContents(with: item.concealed ? .currentHostOnly : [])
        return pasteboard.writeObjects(items)
    }

    /// - Parameter forClipboard: hand out outbox clones for files (see `FileLibrary.outboxClone`).
    public static func pasteboardItems(for item: Item, store: ItemStore, forClipboard: Bool = false) -> [NSPasteboardItem] {
        var result: [NSPasteboardItem] = []
        for snap in item.snapshot {
            let pbItem = NSPasteboardItem()
            var wrote = false
            if let index = snap.fileIndex, index < item.files.count,
               let url = forClipboard ? store.files.outboxClone(of: item.files[index]) : store.files.url(for: item.files[index]) {
                pbItem.setString(url.absoluteString, forType: .fileURL)
                if !snap.representations.contains(where: { $0.type == UTI.utf8Text }) {
                    pbItem.setString(url.lastPathComponent, forType: .string)
                }
                wrote = true
            }
            for rep in snap.representations {
                guard let data = store.blobs.data(rep.blob) else { continue }
                pbItem.setData(data, forType: NSPasteboard.PasteboardType(rep.type))
                wrote = true
            }
            if wrote { result.append(pbItem) }
        }

        // Notes typed or edited in the app (and links) are described by `text`/`link`.
        if item.kind == .link, let url = item.link?.url {
            let pbItem = result.first ?? NSPasteboardItem()
            if pbItem.data(forType: .URL) == nil { pbItem.setString(url, forType: .URL) }
            if pbItem.data(forType: .string) == nil { pbItem.setString(url, forType: .string) }
            if let title = item.link?.title, pbItem.data(forType: .init(UTI.urlName)) == nil {
                pbItem.setString(title, forType: .init(UTI.urlName))
            }
            if result.isEmpty { result.append(pbItem) }
        } else if item.kind.isTextual {
            let pbItem = result.first ?? NSPasteboardItem()
            if pbItem.data(forType: .string) == nil { pbItem.setString(item.text, forType: .string) }
            if result.isEmpty { result.append(pbItem) }
        }

        // Good-citizen markers (nspasteboard.org): who wrote this, and keep secrets out of
        // other clipboard managers' history.
        if let first = result.first {
            first.setString(item.source?.bundleID ?? ourBundleID, forType: .init(UTI.source))
            if item.concealed { first.setData(Data(), forType: .init(UTI.concealed)) }
        }
        return result
    }

    /// An item provider for dragging an item out of the panel. The richest representation comes
    /// first: a real file (clone) so Finder, Mail and Messages get a document with the right name,
    /// then every stored data type, then plain text / URL.
    public static func itemProvider(for item: Item, store: ItemStore) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = item.files.first.map { ($0.name as NSString).deletingPathExtension } ?? item.title

        var fileURL: URL?
        if let file = item.files.first {
            fileURL = store.files.outboxClone(of: file)
        } else if item.kind == .image || item.kind == .pdf {
            fileURL = Materializer.file(for: item, store: store, purpose: .drag)
        }
        if let fileURL {
            let type = UTType(filenameExtension: fileURL.pathExtension)?.identifier ?? UTType.data.identifier
            provider.registerFileRepresentation(forTypeIdentifier: type, fileOptions: [], visibility: .all) { completion in
                completion(fileURL, false, nil)
                return nil
            }
            provider.registerObject(fileURL as NSURL, visibility: .all)
        }

        var registered = Set<String>()
        for rep in item.snapshot.first?.representations ?? [] where !rep.type.hasPrefix("dyn.") && registered.insert(rep.type).inserted {
            let blobURL = store.blobs.url(for: rep.blob)
            provider.registerDataRepresentation(forTypeIdentifier: rep.type, visibility: .all) { completion in
                completion(try? Data(contentsOf: blobURL), nil)
                return nil
            }
        }
        if item.kind == .link, let url = item.link.flatMap({ URL(string: $0.url) }) {
            provider.registerObject(url as NSURL, visibility: .all)
        }
        if item.kind.isTextual || item.kind == .link || item.kind == .color {
            provider.registerObject(item.text as NSString, visibility: .all)
        }
        return provider
    }
}

/// Turns stored data into real files when something needs a file (dragging to Finder, Quick Look).
@MainActor
public enum Materializer {
    public enum Purpose: String { case drag, preview }

    public static func file(for item: Item, store: ItemStore, purpose: Purpose) -> URL? {
        if let stored = item.files.first, let url = store.files.url(for: stored) { return url }
        let folder = StorePaths.caches.appendingPathComponent(purpose.rawValue, isDirectory: true)
            .appendingPathComponent(item.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let base = safeFileName(item.title ?? defaultName(for: item))
        func write(_ data: Data, ext: String) -> URL? {
            let url = folder.appendingPathComponent(base).appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: url.path) { return url }
            return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
        }
        func blob(_ types: [String]) -> (type: String, data: Data)? {
            for snap in item.snapshot {
                for type in types {
                    if let rep = snap.representation(type), let data = store.blobs.data(rep.blob) { return (type, data) }
                }
            }
            return nil
        }

        switch item.kind {
        case .image:
            guard let image = blob(UTI.images) else { return nil }
            let ext = UTType(image.type)?.preferredFilenameExtension ?? "png"
            return write(image.data, ext: ext == "tiff" ? "tiff" : ext)
        case .pdf:
            guard let pdf = blob([UTI.pdf]) else { return nil }
            return write(pdf.data, ext: "pdf")
        case .richText:
            if let rtf = blob([UTI.rtf]) { return write(rtf.data, ext: "rtf") }
            return write(Data(item.text.utf8), ext: "txt")
        case .text, .color, .other:
            return write(Data(item.text.utf8), ext: "txt")
        case .link:
            guard let url = item.link?.url else { return nil }
            let plist: [String: String] = ["URL": url]
            guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return nil }
            return write(data, ext: "webloc")
        case .file, .folder, .files:
            return nil
        }
    }

    static func defaultName(for item: Item) -> String {
        switch item.kind {
        case .image: return "Sticky Image"
        case .pdf: return "Sticky PDF"
        case .link: return item.link.flatMap { URL(string: $0.url)?.host() } ?? "Link"
        default:
            let words = item.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).prefix(6).joined(separator: " ")
            return words.isEmpty ? "Sticky Note" : words
        }
    }

    static func safeFileName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? "Sticky Thing" : cleaned).prefix(80))
    }
}
#endif
