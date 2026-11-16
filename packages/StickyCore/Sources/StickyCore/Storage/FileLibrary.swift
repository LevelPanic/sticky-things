import Foundation
import UniformTypeIdentifiers

/// Keeps our own copies of files people stash, so the stash survives the original being moved,
/// renamed or deleted. On the same APFS volume `copyItem` makes a clone: instant and it takes
/// no extra space until one side changes. Folders and huge cross-volume files are kept as links.
public final class FileLibrary: @unchecked Sendable {
    public let root: URL
    /// Largest file we'll physically copy from another volume (external drives, network shares).
    public var maxCrossVolumeCopy: Int64 = 200 * 1024 * 1024

    public init(root: URL) {
        self.root = root
    }

    public func folder(for itemID: UUID) -> URL {
        root.appendingPathComponent(itemID.uuidString, isDirectory: true)
    }

    /// Records a file and, when sensible, keeps a copy of it inside the library.
    public func importFile(at source: URL, into itemID: UUID) -> StoredFile {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentTypeKey,
                                         .volumeIdentifierKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        let values = try? source.resourceValues(forKeys: keys)
        let isDirectory = values?.isDirectory ?? false
        let size = Int64(values?.fileSize ?? 0)
        var stored = StoredFile(
            name: source.lastPathComponent,
            originalPath: source.path,
            bookmark: try? source.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
            byteSize: size,
            contentType: values?.contentType?.identifier,
            isDirectory: isDirectory
        )

        // Cloud placeholders (iCloud, Dropbox, OneDrive…) would block while downloading:
        // link instead and ask iCloud to fetch it.
        let isPlaceholder = Self.isDataless(source)
            || (values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus == .notDownloaded)
        if isPlaceholder { try? fm.startDownloadingUbiquitousItem(at: source) }

        guard !isDirectory, !isPlaceholder else { return stored }
        if !sameVolume(source, values?.volumeIdentifier), size > maxCrossVolumeCopy { return stored }

        do {
            let folder = folder(for: itemID)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = uniqueURL(in: folder, name: source.lastPathComponent)
            try fm.copyItem(at: source, to: destination)
            stored.libraryPath = itemID.uuidString + "/" + destination.lastPathComponent
        } catch {
            Log.store.error("Could not copy \(source.path, privacy: .private): \(error.localizedDescription)")
        }
        return stored
    }

    /// Imports a file that already sits in our staging area (received file promises) by moving it.
    public func adoptStagedFile(at staged: URL, into itemID: UUID) -> StoredFile {
        let fm = FileManager.default
        let values = try? staged.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .isDirectoryKey])
        var stored = StoredFile(name: staged.lastPathComponent, originalPath: staged.path,
                                byteSize: Int64(values?.fileSize ?? 0), contentType: values?.contentType?.identifier,
                                isDirectory: values?.isDirectory ?? false)
        do {
            let folder = folder(for: itemID)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = uniqueURL(in: folder, name: staged.lastPathComponent)
            try fm.moveItem(at: staged, to: destination)
            stored.libraryPath = itemID.uuidString + "/" + destination.lastPathComponent
            stored.originalPath = destination.path
        } catch {
            Log.store.error("Could not adopt staged file: \(error.localizedDescription)")
        }
        return stored
    }

    /// The best URL to use for a stored file right now: our copy, the original, or wherever it moved.
    public func url(for file: StoredFile) -> URL? {
        let fm = FileManager.default
        if let relative = file.libraryPath {
            let copy = root.appendingPathComponent(relative)
            if fm.fileExists(atPath: copy.path) { return copy }
        }
        if fm.fileExists(atPath: file.originalPath) { return URL(fileURLWithPath: file.originalPath) }
        if let bookmark = file.bookmark {
            var stale = false
            if let moved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale),
               fm.fileExists(atPath: moved.path) {
                return moved
            }
        }
        return nil
    }

    /// A fresh clone to hand out (clipboard, drags). Finder's ⌥⌘V *moves* pasted files, so we
    /// never give out the stored copy itself. Clones are instant on APFS.
    public func outboxClone(of file: StoredFile) -> URL? {
        guard let source = url(for: file) else { return nil }
        let folder = StorePaths.caches.appendingPathComponent("outbox", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = folder.appendingPathComponent(file.name.isEmpty ? source.lastPathComponent : file.name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            Log.output.error("Outbox clone failed: \(error.localizedDescription)")
            return source
        }
    }

    /// Clears old outbox clones (anything handed out more than a day ago).
    public static func cleanOutbox(olderThan age: TimeInterval = 86_400) {
        let outbox = StorePaths.caches.appendingPathComponent("outbox", isDirectory: true)
        let cutoff = Date().addingTimeInterval(-age)
        for folder in (try? FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if created < cutoff { try? FileManager.default.removeItem(at: folder) }
        }
    }

    /// True for "dataless" cloud placeholders (TN3150). `lstat` doesn't download anything.
    static func isDataless(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return info.st_flags & UInt32(SF_DATALESS) != 0
    }

    public func removeFiles(for itemID: UUID) {
        try? FileManager.default.removeItem(at: folder(for: itemID))
    }

    /// Removes folders of items that no longer exist.
    public func collectGarbage(keeping itemIDs: Set<UUID>) -> Int {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var removed = 0
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent), !itemIDs.contains(id) else { continue }
            if (try? FileManager.default.removeItem(at: folder)) != nil { removed += 1 }
        }
        return removed
    }

    private func sameVolume(_ source: URL, _ sourceVolume: (any NSCopying & NSSecureCoding & NSObjectProtocol)?) -> Bool {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard let sourceVolume, let ours = try? root.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier else { return false }
        return sourceVolume.isEqual(ours)
    }

    private func uniqueURL(in folder: URL, name: String) -> URL {
        var candidate = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    public static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
