import AppKit

/// Turns pastes and drops into stored items. Every path ends here, so behaviour is identical
/// whether you pressed ⌘V, dropped on the panel or threw something at the corner.
@MainActor
public final class CaptureService {
    public let store: ItemStore
    public var limits = PasteboardSnapshotter.Limits()

    public init(store: ItemStore) {
        self.store = store
    }

    public enum Outcome: Equatable {
        /// New items were saved.
        case saved([Item])
        /// The very same thing was already the newest item.
        case duplicate(Item)
        /// File promises are being received; items arrive via the completion handler.
        case pending
    }

    /// Saves whatever is on `pasteboard` (⌘V or a drop). Throws `nothingToSave` when empty.
    public func save(from pasteboard: NSPasteboard, source: SourceApp?,
                     promisesDone: ((Result<[Item], Error>) -> Void)? = nil) throws -> Outcome {
        if PasteboardSnapshotter.needsFilePromises(pasteboard), let promisesDone {
            receiveFilePromises(from: pasteboard, source: source, completion: promisesDone)
            return .pending
        }
        let clip = PasteboardSnapshotter.capture(pasteboard, limits: limits)
        return try save(clip, source: source)
    }

    public func save(_ clip: CapturedClip, source: SourceApp?) throws -> Outcome {
        guard !clip.isEmpty else {
            if !clip.skipped.isEmpty { throw CoreError.tooLarge(Int64(limits.perType)) }
            throw CoreError.nothingToSave
        }
        let fingerprint = Self.fingerprint(of: clip)
        if let newest = store.items.first, newest.fingerprint == fingerprint {
            return .duplicate(newest)
        }
        let item = try makeItem(from: clip, source: source, fingerprint: fingerprint)
        store.insert(item)
        return .saved([item])
    }

    /// A note typed into the composer.
    @discardableResult
    public func saveNote(_ text: String) -> Outcome? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fingerprint = Hashing.sha256(Data(("note:" + trimmed).utf8))
        if let newest = store.items.first, newest.fingerprint == fingerprint { return .duplicate(newest) }
        var item: Item
        if let url = Classifier.singleLink(in: trimmed) {
            item = Item(kind: .link, text: url.absoluteString, link: LinkInfo(url: url.absoluteString))
        } else {
            item = Item(kind: .text, text: trimmed)
        }
        item.byteSize = Int64(trimmed.utf8.count)
        item.fingerprint = fingerprint
        store.insert(item)
        return .saved([item])
    }

    // MARK: Building items

    func makeItem(from clip: CapturedClip, source: SourceApp?, fingerprint: String) throws -> Item {
        let id = UUID()
        let result = Classifier.classify(clip)
        var files: [StoredFile] = []
        var snapshot: [SnapshotItem] = []
        var bytes: Int64 = 0

        for element in clip.elements {
            var reps: [Representation] = []
            for entry in element.entries {
                let hash = try store.blobs.put(entry.data)
                reps.append(Representation(type: entry.type, blob: hash, size: entry.data.count))
                bytes += Int64(entry.data.count)
            }
            var fileIndex: Int?
            if let url = element.fileURL {
                let stored = store.files.importFile(at: url, into: id)
                fileIndex = files.count
                files.append(stored)
                bytes += stored.byteSize
            }
            snapshot.append(SnapshotItem(representations: reps, fileIndex: fileIndex))
        }
        for staged in clip.stagedFiles {
            let stored = store.files.adoptStagedFile(at: staged, into: id)
            snapshot.append(SnapshotItem(representations: [], fileIndex: files.count))
            files.append(stored)
            bytes += stored.byteSize
        }

        // Point the title at our copy's name (files may have been renamed to stay unique).
        let sourceApp = source ?? clip.sourceBundleID.map { SourceApp(bundleID: $0, name: Self.appName(for: $0)) }
        return Item(id: id, kind: result.kind, text: result.text, title: result.title, snapshot: snapshot,
                    files: files, link: result.link, pixelSize: result.pixelSize, pageCount: result.pageCount,
                    source: sourceApp, concealed: clip.concealed, byteSize: bytes, fingerprint: fingerprint)
    }

    static func fingerprint(of clip: CapturedClip) -> String {
        var parts: [String] = []
        for element in clip.elements {
            parts.append(element.fileURL?.path ?? "-")
            for entry in element.entries { parts.append(entry.type + "=" + Hashing.sha256(entry.data)) }
        }
        parts += clip.stagedFiles.map(\.lastPathComponent)
        return Hashing.sha256(Data(parts.joined(separator: "|").utf8))
    }

    static func appName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: File promises (Photos, Mail, Safari images…)

    private lazy var promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.name = "app.stickythings.promises"
        return queue
    }()

    private func receiveFilePromises(from pasteboard: NSPasteboard, source: SourceApp?,
                                     completion: @escaping (Result<[Item], Error>) -> Void) {
        let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
        let destination = store.paths.staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let expected = receivers.reduce(0) { $0 + max(1, $1.fileNames.count) }

        let collector = PromiseCollector(expected: expected) { [weak self] urls, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard !urls.isEmpty else {
                    completion(.failure(error ?? CoreError.nothingToSave))
                    return
                }
                let clip = CapturedClip(elements: [], stagedFiles: urls.sorted { $0.path < $1.path })
                do {
                    let item = try self.makeItem(from: clip, source: source, fingerprint: UUID().uuidString)
                    self.store.insert(item)
                    try? FileManager.default.removeItem(at: destination)
                    completion(.success([item]))
                } catch {
                    completion(.failure(error))
                }
            }
        }
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: promiseQueue) { url, error in
                collector.add(url: error == nil ? url : nil, error: error)
            }
        }
        // Some apps never deliver (or deliver fewer files than promised): don't wait forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { collector.finish() }
    }
}

/// Gathers promised files as they arrive (on a background queue) and reports once.
final class PromiseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private var error: Error?
    private var remaining: Int
    private var done = false
    private let onDone: ([URL], Error?) -> Void

    init(expected: Int, onDone: @escaping ([URL], Error?) -> Void) {
        remaining = max(1, expected)
        self.onDone = onDone
    }

    func add(url: URL?, error: Error?) {
        lock.lock()
        if let url { urls.append(url) }
        if let error, self.error == nil { self.error = error }
        remaining -= 1
        let complete = remaining <= 0
        lock.unlock()
        if complete { DispatchQueue.main.async { self.finish() } }
    }

    func finish() {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        let result = (urls, error)
        lock.unlock()
        onDone(result.0, result.1)
    }
}
