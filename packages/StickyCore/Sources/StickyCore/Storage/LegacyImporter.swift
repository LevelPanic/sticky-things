import Foundation

/// Brings notes from version 1 (notes.json + media/) into the library, once.
@MainActor
public enum LegacyImporter {
    private struct V1File: Decodable { var notes: [V1Note] }
    private struct V1Note: Decodable {
        var id: UUID
        var kind: String
        var text: String
        var title: String?
        var imageFile: String?
        var iconFile: String?
        var bookmark: Data?
        var pixelWidth: Int?
        var pixelHeight: Int?
        var color: String?
        var pinned: Bool?
        var createdAt: Date
        var updatedAt: Date?
    }

    /// Returns how many notes were imported (0 when there was nothing to do).
    @discardableResult
    public static func importIfNeeded(into store: ItemStore) -> Int {
        let paths = store.paths
        guard store.meta("legacyImported") == nil else { return 0 }
        defer { store.setMeta("legacyImported", "1") }
        guard let data = try? Data(contentsOf: paths.legacyNotes) else { return 0 }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(V1File.self, from: data) else {
            Log.store.error("Could not read v1 notes.json; leaving it untouched")
            return 0
        }

        var items: [Item] = []
        for note in file.notes where store.item(note.id) == nil {
            var item = Item(id: note.id, kind: .text, text: note.text, title: nil,
                            tint: Tint(rawValue: note.color ?? "") ?? .none, pinned: note.pinned ?? false,
                            createdAt: note.createdAt, updatedAt: note.updatedAt)
            switch note.kind {
            case "link":
                item.kind = .link
                var link = LinkInfo(url: note.text, title: note.title)
                if let icon = note.iconFile, let png = try? Data(contentsOf: paths.legacyMedia.appendingPathComponent(icon)) {
                    link.iconBlob = try? store.blobs.put(png)
                }
                item.link = link
            case "image":
                guard let name = note.imageFile,
                      let png = try? Data(contentsOf: paths.legacyMedia.appendingPathComponent(name)),
                      let hash = try? store.blobs.put(png) else { continue }
                item.kind = .image
                item.text = ""
                item.snapshot = [SnapshotItem(representations: [Representation(type: UTI.png, blob: hash, size: png.count)])]
                if let w = note.pixelWidth, let h = note.pixelHeight { item.pixelSize = PixelSize(width: w, height: h) }
                item.byteSize = Int64(png.count)
            case "file":
                let url = URL(fileURLWithPath: note.text)
                var stored = FileManager.default.fileExists(atPath: url.path)
                    ? store.files.importFile(at: url, into: note.id)
                    : StoredFile(name: url.lastPathComponent, originalPath: url.path)
                if stored.bookmark == nil { stored.bookmark = note.bookmark }
                let result = Classifier.classifyFiles([url])
                item.kind = FileManager.default.fileExists(atPath: url.path) ? result.kind : .file
                item.text = url.lastPathComponent
                item.title = url.lastPathComponent
                item.files = [stored]
                item.snapshot = [SnapshotItem(representations: [], fileIndex: 0)]
            default:
                item.byteSize = Int64(note.text.utf8.count)
            }
            items.append(item)
        }
        store.insert(items)
        // Keep the old file around (renamed) rather than deleting anything.
        let backup = paths.root.appendingPathComponent("notes-v1-imported.json")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: paths.legacyNotes, to: backup)
        Log.store.info("Imported \(items.count) notes from v1")
        return items.count
    }
}
