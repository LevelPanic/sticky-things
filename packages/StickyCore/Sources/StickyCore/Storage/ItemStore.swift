import Foundation

/// The single source of truth the UI observes. Keeps every item in memory (newest first)
/// and writes each change straight to SQLite.
@MainActor
public final class ItemStore: ObservableObject {
    @Published public private(set) var items: [Item] = []
    /// Last storage error, surfaced by the UI as a banner.
    @Published public private(set) var lastError: String?

    public let paths: StorePaths
    public let blobs: BlobStore
    public let files: FileLibrary
    private let database: ItemDatabase

    /// Called whenever a link item is added or its URL changes (to fetch title + icon).
    public var onLinkNeedsPreview: ((Item) -> Void)?

    public struct Removed: Sendable {
        public let item: Item
        public let index: Int
    }

    /// - Parameter inMemory: keep the database in memory (tests and previews). Blobs and files
    ///   still go to `paths`, which tests point at a temporary folder.
    public init(paths: StorePaths = .default, inMemory: Bool = false) throws {
        self.paths = paths
        try paths.createDirectories()
        blobs = BlobStore(root: paths.blobs)
        files = FileLibrary(root: paths.files)
        database = try ItemDatabase(url: inMemory ? nil : paths.database)
        items = try database.loadAll()
    }

    // MARK: Reading

    public func item(_ id: UUID) -> Item? { items.first { $0.id == id } }

    public var pinned: [Item] { items.filter(\.pinned) }

    /// Every word must match (case and diacritic insensitive).
    public func search(_ query: String, filter: ItemFilter = .all) -> [Item] {
        let terms = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).map(String.init)
        return items.filter { item in
            guard filter.matches(item.kind) else { return false }
            guard !terms.isEmpty else { return true }
            let haystack = item.searchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    // MARK: Writing

    public func insert(_ item: Item) {
        insert([item])
    }

    public func insert(_ newItems: [Item]) {
        guard !newItems.isEmpty else { return }
        persist { try database.upsert(newItems) }
        items.insert(contentsOf: newItems, at: 0)
        items.sort { $0.createdAt > $1.createdAt }
        for item in newItems where item.kind == .link && item.link?.title == nil { onLinkNeedsPreview?(item) }
    }

    public func update(_ id: UUID, _ mutate: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        let before = item
        mutate(&item)
        guard item != before else { return }
        item.updatedAt = Date()
        items[index] = item
        persist { try database.upsert(item) }
        if item.kind == .link, item.link?.url != before.link?.url { onLinkNeedsPreview?(item) }
    }

    /// Replaces a note's text (inline editing). Keeps rich text when `rtf` is given.
    public func setText(_ id: UUID, to text: String, rtf: Data? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let rtfHash = rtf.flatMap { try? blobs.put($0) }
        update(id) { item in
            if let url = Classifier.singleLink(in: trimmed), rtf == nil {
                item.kind = .link
                item.text = url.absoluteString
                item.link = LinkInfo(url: url.absoluteString)
                item.snapshot = []
                return
            }
            item.text = text
            item.kind = rtfHash == nil ? .text : .richText
            item.link = nil
            var reps: [Representation] = []
            if let rtfHash, let rtf { reps.append(Representation(type: "public.rtf", blob: rtfHash, size: rtf.count)) }
            item.snapshot = reps.isEmpty ? [] : [SnapshotItem(representations: reps)]
        }
    }

    public func togglePin(_ id: UUID) { update(id) { $0.pinned.toggle() } }

    public func setTint(_ tint: Tint, for id: UUID) { update(id) { $0.tint = tint } }

    /// Sets or removes the text the user added to an image, PDF or file.
    public func setCaption(_ id: UUID, to caption: String?) {
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        update(id) { $0.caption = (trimmed?.isEmpty ?? true) ? nil : trimmed }
    }

    @discardableResult
    public func delete(_ id: UUID) -> Removed? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let item = items.remove(at: index)
        persist { try database.delete([id]) }
        return Removed(item: item, index: index)
    }

    public func restore(_ removed: Removed) {
        guard item(removed.item.id) == nil else { return }
        persist { try database.upsert(removed.item) }
        items.insert(removed.item, at: min(removed.index, items.count))
        items.sort { $0.createdAt > $1.createdAt }
    }

    public func deleteAll(keepPinned: Bool) {
        let doomed = items.filter { !keepPinned || !$0.pinned }
        persist { try database.delete(doomed.map(\.id)) }
        items.removeAll { !keepPinned || !$0.pinned }
        for item in doomed { files.removeFiles(for: item.id) }
    }

    /// Removes unpinned items older than `days` (0 keeps everything).
    public func applyRetention(days: Int, now: Date = Date()) {
        guard days > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let doomed = items.filter { !$0.pinned && $0.createdAt < cutoff }
        guard !doomed.isEmpty else { return }
        persist { try database.delete(doomed.map(\.id)) }
        let ids = Set(doomed.map(\.id))
        items.removeAll { ids.contains($0.id) }
    }

    /// Frees blobs and file copies nothing references any more. Run at launch (undo is per-session).
    @discardableResult
    public func collectGarbage(blobGracePeriod: TimeInterval = 3600) -> Int {
        let referenced = items.reduce(into: Set<String>()) { $0.formUnion($1.blobReferences) }
        let blobsRemoved = blobs.collectGarbage(keeping: referenced, olderThan: blobGracePeriod)
        let foldersRemoved = files.collectGarbage(keeping: Set(items.map(\.id)))
        return blobsRemoved + foldersRemoved
    }

    public var diskUsage: Int64 {
        blobs.totalSize + FileLibrary.directorySize(paths.files)
    }

    public func meta(_ key: String) -> String? { database.meta(key) }
    public func setMeta(_ key: String, _ value: String) { persist { try database.setMeta(key, value) } }

    private func persist(_ work: () throws -> Void) {
        do {
            try work()
            if lastError != nil { lastError = nil }
        } catch {
            lastError = error.localizedDescription
            Log.store.error("Store write failed: \(error.localizedDescription)")
        }
    }
}
