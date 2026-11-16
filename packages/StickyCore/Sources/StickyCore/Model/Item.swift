import Foundation

/// How an item is shown. Derived from what was captured; the captured data itself is kept
/// losslessly in `snapshot` so anything can be given back exactly as it came in.
public enum ItemKind: String, Codable, Sendable, CaseIterable {
    case text, richText, link, image, pdf, file, folder, files, color, other

    public var label: String {
        switch self {
        case .text: return "Note"
        case .richText: return "Formatted text"
        case .link: return "Link"
        case .image: return "Image"
        case .pdf: return "PDF"
        case .file: return "File"
        case .folder: return "Folder"
        case .files: return "Files"
        case .color: return "Color"
        case .other: return "Data"
        }
    }

    public var isTextual: Bool { self == .text || self == .richText }
}

/// Filters shown in the panel.
public enum ItemFilter: String, CaseIterable, Sendable {
    case all, notes, links, images, files

    public func matches(_ kind: ItemKind) -> Bool {
        switch self {
        case .all: return true
        case .notes: return kind == .text || kind == .richText || kind == .color || kind == .other
        case .links: return kind == .link
        case .images: return kind == .image
        case .files: return kind == .pdf || kind == .file || kind == .folder || kind == .files
        }
    }
}

/// One pasteboard type's data, stored by content hash in the blob store.
public struct Representation: Codable, Hashable, Sendable {
    public var type: String
    public var blob: String
    public var size: Int

    public init(type: String, blob: String, size: Int) {
        self.type = type
        self.blob = blob
        self.size = size
    }
}

/// One NSPasteboardItem (a copy of three files is three of these).
public struct SnapshotItem: Codable, Hashable, Sendable {
    public var representations: [Representation]
    /// Index into `Item.files` when this pasteboard item stood for a file (its URL is rewritten
    /// to our stored copy when the item is given back).
    public var fileIndex: Int?
    public init(representations: [Representation], fileIndex: Int? = nil) {
        self.representations = representations
        self.fileIndex = fileIndex
    }

    public func representation(_ type: String) -> Representation? {
        representations.first { $0.type == type }
    }
}

/// A file or folder that was pasted/dropped. We keep our own copy (an instant APFS clone when
/// possible) so the stash still works after the original is moved or deleted.
public struct StoredFile: Codable, Hashable, Sendable {
    public var name: String
    public var originalPath: String
    /// Path relative to the file library, when we kept a copy.
    public var libraryPath: String?
    public var bookmark: Data?
    public var byteSize: Int64
    public var contentType: String?
    public var isDirectory: Bool

    public init(name: String, originalPath: String, libraryPath: String? = nil, bookmark: Data? = nil,
                byteSize: Int64 = 0, contentType: String? = nil, isDirectory: Bool = false) {
        self.name = name
        self.originalPath = originalPath
        self.libraryPath = libraryPath
        self.bookmark = bookmark
        self.byteSize = byteSize
        self.contentType = contentType
        self.isDirectory = isDirectory
    }
}

public struct LinkInfo: Codable, Hashable, Sendable {
    public var url: String
    public var title: String?
    public var iconBlob: String?

    public init(url: String, title: String? = nil, iconBlob: String? = nil) {
        self.url = url
        self.title = title
        self.iconBlob = iconBlob
    }
}

public struct SourceApp: Codable, Hashable, Sendable {
    public var bundleID: String?
    public var name: String?
    public init(bundleID: String?, name: String?) {
        self.bundleID = bundleID
        self.name = name
    }
}

public struct PixelSize: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Optional sticky-note tint for an item.
public enum Tint: String, Codable, Sendable, CaseIterable {
    case none, yellow, orange, pink, purple, blue, green
}

public struct Item: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: ItemKind
    /// Plain text: the body of a note, otherwise a readable description (URL, file names…).
    public var text: String
    /// Optional title: page title, file name, or one the user gave it.
    public var title: String?
    /// Text the user added to a non-text item (an image, PDF, file…). Separate from the captured
    /// data, so it never changes what the item gives back when copied.
    public var caption: String?
    /// Everything that was on the pasteboard, losslessly. Empty for notes typed in the app.
    public var snapshot: [SnapshotItem]
    public var files: [StoredFile]
    public var link: LinkInfo?
    public var pixelSize: PixelSize?
    public var pageCount: Int?
    public var source: SourceApp?
    public var tint: Tint
    public var pinned: Bool
    /// Came from a password manager (nspasteboard.org ConcealedType): shown blurred.
    public var concealed: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var byteSize: Int64
    /// Hash of everything captured; used to avoid saving the same thing twice in a row.
    public var fingerprint: String?

    public init(id: UUID = UUID(), kind: ItemKind, text: String, title: String? = nil,
                caption: String? = nil, snapshot: [SnapshotItem] = [], files: [StoredFile] = [],
                link: LinkInfo? = nil, pixelSize: PixelSize? = nil, pageCount: Int? = nil,
                source: SourceApp? = nil, tint: Tint = .none, pinned: Bool = false,
                concealed: Bool = false, createdAt: Date = Date(), updatedAt: Date? = nil,
                byteSize: Int64 = 0, fingerprint: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.title = title
        self.caption = caption
        self.snapshot = snapshot
        self.files = files
        self.link = link
        self.pixelSize = pixelSize
        self.pageCount = pageCount
        self.source = source
        self.tint = tint
        self.pinned = pinned
        self.concealed = concealed
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.byteSize = byteSize
        self.fingerprint = fingerprint
    }

    /// One line for chips, menus and accessibility.
    public var headline: String {
        if let title, !title.isEmpty { return title }
        switch kind {
        case .text, .richText, .other, .color:
            let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? kind.label : trimmed
        case .link:
            return link.flatMap { URL(string: $0.url)?.host() } ?? text
        case .image, .pdf, .file, .folder:
            return files.first?.name ?? kind.label
        case .files:
            return "\(files.count) items"
        }
    }

    /// Text that search matches against (lowercased by the store).
    public var searchText: String {
        var parts = [text, title ?? "", caption ?? "", kind.label, source?.name ?? ""]
        parts += files.map(\.name)
        if let link { parts.append(link.url) }
        return parts.joined(separator: " ")
    }

    /// Whether a user caption makes sense for this kind (media and documents, not notes).
    public var supportsCaption: Bool {
        switch kind {
        case .image, .pdf, .file, .folder, .files, .color, .other: return !concealed
        case .text, .richText, .link: return false
        }
    }

    /// Every blob this item references (for garbage collection).
    public var blobReferences: Set<String> {
        var set = Set(snapshot.flatMap { $0.representations.map(\.blob) })
        if let icon = link?.iconBlob { set.insert(icon) }
        return set
    }
}
