import Foundation

/// Content-addressed storage: data is saved once under its SHA-256, so pasting the same
/// screenshot twice costs nothing and items can share data safely.
public final class BlobStore: @unchecked Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func url(for hash: String) -> URL {
        root.appendingPathComponent(String(hash.prefix(2)), isDirectory: true).appendingPathComponent(hash)
    }

    /// Stores `data` and returns its hash. Writing is atomic; existing blobs are not rewritten.
    @discardableResult
    public func put(_ data: Data) throws -> String {
        let hash = Hashing.sha256(data)
        let url = url(for: hash)
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        return hash
    }

    public func data(_ hash: String) -> Data? {
        try? Data(contentsOf: url(for: hash), options: .mappedIfSafe)
    }

    public func exists(_ hash: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: hash).path)
    }

    /// Deletes blobs nobody references. `olderThan` keeps very recent blobs (an undo may still need them).
    public func collectGarbage(keeping referenced: Set<String>, olderThan age: TimeInterval = 3600) -> Int {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-age)
        var removed = 0
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { return 0 }
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true, !referenced.contains(url.lastPathComponent),
                  (values?.contentModificationDate ?? .distantPast) < cutoff else { continue }
            if (try? fm.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
    }

    public var totalSize: Int64 { FileLibrary.directorySize(root) }
}
