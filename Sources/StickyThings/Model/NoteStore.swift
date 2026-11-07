import AppKit
import CryptoKit
import Foundation

/// Owns every note and persists them as JSON (+ image files) in Application Support.
@MainActor
final class NoteStore: ObservableObject {
    /// Newest first.
    @Published private(set) var notes: [Note] = []

    let rootURL: URL
    let mediaURL: URL
    private var fileURL: URL { rootURL.appendingPathComponent("notes.json") }
    private var pendingSave: DispatchWorkItem?
    /// When false nothing touches the disk (used for previews and tests).
    var persists = true

    /// Called after a link note is added so its title/icon can be fetched.
    var onLinkAdded: ((Note) -> Void)?

    init(rootURL: URL? = nil) {
        let base = rootURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sticky Things", isDirectory: true)
        self.rootURL = base
        self.mediaURL = base.appendingPathComponent("media", isDirectory: true)
    }

    // MARK: Loading & saving

    func load() {
        try? FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let file = try decoder.decode(StoreFile.self, from: data)
            notes = file.notes.sorted { $0.createdAt > $1.createdAt }
        } catch {
            // Keep a copy of the unreadable file instead of silently overwriting it.
            let backup = rootURL.appendingPathComponent("notes-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            NSLog("Sticky Things: could not read notes.json (\(error)); backed up to \(backup.path)")
        }
    }

    func scheduleSave() {
        guard persists else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard persists else { return }
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(StoreFile(version: 1, notes: notes))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Sticky Things: failed to save notes: \(error)")
        }
    }

    private struct StoreFile: Codable {
        var version: Int
        var notes: [Note]
    }

    // MARK: Adding

    /// Adds pasted/dropped content. Returns the notes that were created (or the existing
    /// note when the same thing was just saved, so callers can highlight it).
    @discardableResult
    func add(_ contents: [ClipContent]) -> [Note] {
        var result: [Note] = []
        for content in contents {
            switch content {
            case .text(let string):
                if let note = addText(string) { result.append(note) }
            case .link(let url):
                if let existing = duplicateOfNewest(kind: .link, text: url.absoluteString) {
                    result.append(existing); continue
                }
                let note = Note(kind: .link, text: url.absoluteString)
                insert(note)
                onLinkAdded?(note)
                result.append(note)
            case .image(let png):
                let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
                if let newest = notes.first, newest.kind == .image, newest.contentHash == hash {
                    result.append(newest); continue
                }
                var note = Note(kind: .image, text: "")
                let name = "\(note.id.uuidString).png"
                if persists {
                    try? FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
                    try? png.write(to: mediaURL.appendingPathComponent(name), options: .atomic)
                }
                note.imageFile = name
                note.contentHash = hash
                if let rep = NSBitmapImageRep(data: png) {
                    note.pixelWidth = rep.pixelsWide
                    note.pixelHeight = rep.pixelsHigh
                }
                insert(note)
                result.append(note)
            case .files(let urls):
                // Insert oldest-first so the first file ends up on top.
                for url in urls.reversed() {
                    if let existing = duplicateOfNewest(kind: .file, text: url.path) {
                        result.append(existing); continue
                    }
                    var note = Note(kind: .file, text: url.path)
                    note.bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                    insert(note)
                    result.append(note)
                }
            }
        }
        return result
    }

    @discardableResult
    func addText(_ string: String) -> Note? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = Clip.linkURL(from: trimmed) { return add([.link(url)]).first }
        if let existing = duplicateOfNewest(kind: .text, text: trimmed) { return existing }
        let note = Note(kind: .text, text: trimmed)
        insert(note)
        return note
    }

    private func duplicateOfNewest(kind: NoteKind, text: String) -> Note? {
        guard let newest = notes.first, newest.kind == kind, newest.text == text else { return nil }
        return newest
    }

    private func insert(_ note: Note) {
        notes.insert(note, at: 0)
        scheduleSave()
    }

    // MARK: Editing

    func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }

    func update(_ id: UUID, _ mutate: (inout Note) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var note = notes[index]
        mutate(&note)
        note.updatedAt = Date()
        notes[index] = note
        scheduleSave()
    }

    func updateText(_ id: UUID, to text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { note in
            if note.kind == .text, let url = Clip.linkURL(from: trimmed) {
                note.kind = .link
                note.text = url.absoluteString
            } else if note.kind == .link, Clip.linkURL(from: trimmed) == nil {
                note.kind = .text
                note.text = trimmed
                note.title = nil
            } else {
                note.text = trimmed
            }
        }
        if let note = note(id), note.kind == .link, note.title == nil { onLinkAdded?(note) }
    }

    func togglePin(_ id: UUID) { update(id) { $0.pinned.toggle() } }

    func setColor(_ color: NoteColor, for id: UUID) { update(id) { $0.color = color } }

    /// Removes a note and returns what is needed to undo it.
    @discardableResult
    func delete(_ id: UUID) -> (note: Note, index: Int)? {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return nil }
        let note = notes.remove(at: index)
        scheduleSave()
        return (note, index)
    }

    func restore(_ note: Note, at index: Int) {
        guard !notes.contains(where: { $0.id == note.id }) else { return }
        notes.insert(note, at: min(index, notes.count))
        notes.sort { $0.createdAt > $1.createdAt }
        scheduleSave()
    }

    func deleteAll(keepPinned: Bool) {
        notes.removeAll { !keepPinned || !$0.pinned }
        saveNow()
        garbageCollectMedia()
    }

    /// Deletes unpinned notes older than `days` (0 = keep forever).
    func applyRetention(days: Int) {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let before = notes.count
        notes.removeAll { !$0.pinned && $0.createdAt < cutoff }
        if notes.count != before { saveNow() }
    }

    /// Removes media files that no note references any more (keeps undo simple).
    func garbageCollectMedia() {
        guard persists else { return }
        let referenced = Set(notes.flatMap { [$0.imageFile, $0.iconFile].compactMap { $0 } })
        let files = (try? FileManager.default.contentsOfDirectory(atPath: mediaURL.path)) ?? []
        for file in files where !referenced.contains(file) {
            try? FileManager.default.removeItem(at: mediaURL.appendingPathComponent(file))
        }
    }

    // MARK: Media helpers

    func mediaFile(_ name: String?) -> URL? {
        guard let name else { return nil }
        return mediaURL.appendingPathComponent(name)
    }

    func saveIcon(_ png: Data, for id: UUID) -> String? {
        let name = "\(id.uuidString)-icon.png"
        do {
            try FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
            try png.write(to: mediaURL.appendingPathComponent(name), options: .atomic)
            return name
        } catch { return nil }
    }

    /// Resolves a file note to its current location (follows the bookmark if it moved).
    func resolvedFileURL(for note: Note) -> URL? {
        guard note.kind == .file else { return nil }
        let original = URL(fileURLWithPath: note.text)
        if FileManager.default.fileExists(atPath: original.path) { return original }
        if let bookmark = note.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
                if url.path != note.text { update(note.id) { $0.text = url.path } }
                return url
            }
        }
        return nil
    }

    var diskUsage: Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        if let attrs = try? fm.attributesOfItem(atPath: fileURL.path) { total += (attrs[.size] as? Int64) ?? 0 }
        for file in (try? fm.contentsOfDirectory(atPath: mediaURL.path)) ?? [] {
            if let attrs = try? fm.attributesOfItem(atPath: mediaURL.appendingPathComponent(file).path) {
                total += (attrs[.size] as? Int64) ?? 0
            }
        }
        return total
    }

    // MARK: Search

    func search(_ query: String) -> [Note] {
        let terms = query.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return notes }
        return notes.filter { note in
            let haystack = note.searchableText.lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    // MARK: Test / preview helpers

    func replaceAll(with notes: [Note]) {
        self.notes = notes.sorted { $0.createdAt > $1.createdAt }
    }
}
