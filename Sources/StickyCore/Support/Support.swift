import CryptoKit
import Foundation
import os

/// Structured logging (view with Console.app, filter "app.stickythings").
public enum Log {
    public static let capture = Logger(subsystem: "app.stickythings", category: "capture")
    public static let store = Logger(subsystem: "app.stickythings", category: "store")
    public static let output = Logger(subsystem: "app.stickythings", category: "output")
    public static let ui = Logger(subsystem: "app.stickythings", category: "ui")
}

public enum Hashing {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Where everything lives on disk. Tests point this at a temporary folder.
public struct StorePaths: Sendable {
    public let root: URL
    public var database: URL { root.appendingPathComponent("library.sqlite") }
    public var blobs: URL { root.appendingPathComponent("blobs", isDirectory: true) }
    public var files: URL { root.appendingPathComponent("files", isDirectory: true) }
    public var staging: URL { root.appendingPathComponent("staging", isDirectory: true) }
    public var legacyNotes: URL { root.appendingPathComponent("notes.json") }
    public var legacyMedia: URL { root.appendingPathComponent("media", isDirectory: true) }

    public init(root: URL) { self.root = root }

    public static var `default`: StorePaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return StorePaths(root: base.appendingPathComponent("Sticky Things", isDirectory: true))
    }

    public static func temporary() -> StorePaths {
        StorePaths(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("StickyThings-\(UUID().uuidString)", isDirectory: true))
    }

    /// Caches (thumbnails, Quick Look temp files) can be thrown away any time.
    public static var caches: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.stickythings", isDirectory: true)
    }

    public func createDirectories() throws {
        for dir in [root, blobs, files, staging] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

public enum CoreError: Error, LocalizedError, Equatable {
    case database(String)
    case nothingToSave
    case tooLarge(Int64)
    case missingFile(String)

    public var errorDescription: String? {
        switch self {
        case .database(let message): return "The library couldn’t be saved (\(message))."
        case .nothingToSave: return "There was nothing on the clipboard to save."
        case .tooLarge(let bytes):
            return "That’s too big to stash (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))."
        case .missingFile(let name): return "“\(name)” has been moved or deleted."
        }
    }
}
