import AppKit
import LinkPresentation
import UniformTypeIdentifiers

/// Copying, opening and dragging notes back out into the world.
@MainActor
enum NoteActions {
    /// Puts the note on the clipboard. Returns false when the note's file is gone.
    @discardableResult
    static func copy(_ note: Note, store: NoteStore, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        switch note.kind {
        case .text:
            pasteboard.setString(note.text, forType: .string)
        case .link:
            if let url = note.url {
                pasteboard.writeObjects([url as NSURL])
            }
            pasteboard.setString(note.text, forType: .string)
        case .image:
            guard let url = store.mediaFile(note.imageFile), let image = NSImage(contentsOf: url) else { return false }
            pasteboard.writeObjects([image])
            if let png = try? Data(contentsOf: url) { pasteboard.setData(png, forType: .png) }
        case .file:
            guard let url = store.resolvedFileURL(for: note) else { return false }
            pasteboard.writeObjects([url as NSURL])
        }
        return true
    }

    /// Opens a link in the browser, a file in its app, or an image in Preview.
    static func open(_ note: Note, store: NoteStore) {
        switch note.kind {
        case .link:
            if let url = note.url { NSWorkspace.shared.open(url) }
        case .file:
            if let url = store.resolvedFileURL(for: note) { NSWorkspace.shared.open(url) }
        case .image:
            if let url = store.mediaFile(note.imageFile) { NSWorkspace.shared.open(url) }
        case .text:
            break
        }
    }

    static func revealInFinder(_ note: Note, store: NoteStore) {
        let url: URL?
        switch note.kind {
        case .file: url = store.resolvedFileURL(for: note)
        case .image: url = store.mediaFile(note.imageFile)
        default: url = nil
        }
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    /// Item provider used when a card is dragged out of the panel.
    static func itemProvider(for note: Note, store: NoteStore) -> NSItemProvider {
        switch note.kind {
        case .text:
            return NSItemProvider(object: note.text as NSString)
        case .link:
            if let url = note.url { return NSItemProvider(object: url as NSURL) }
            return NSItemProvider(object: note.text as NSString)
        case .image:
            if let url = store.mediaFile(note.imageFile), let provider = NSItemProvider(contentsOf: url) {
                provider.suggestedName = note.text.isEmpty ? "Sticky Image" : note.text
                return provider
            }
            return NSItemProvider()
        case .file:
            if let url = store.resolvedFileURL(for: note), let provider = NSItemProvider(contentsOf: url) {
                return provider
            }
            return NSItemProvider()
        }
    }
}

/// Fetches page titles and site icons for link notes (like Messages does).
@MainActor
final class LinkPreviewFetcher {
    private weak var store: NoteStore?
    private var inFlight = Set<UUID>()
    var isEnabled: () -> Bool = { true }

    init(store: NoteStore) { self.store = store }

    func fetch(_ note: Note) {
        guard isEnabled(), note.kind == .link, let url = note.url,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              !inFlight.contains(note.id) else { return }
        inFlight.insert(note.id)
        let id = note.id
        let provider = LPMetadataProvider()
        provider.timeout = 10
        provider.startFetchingMetadata(for: url) { metadata, _ in
            let title = metadata?.title
            let iconProvider = metadata?.iconProvider
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.apply(title: title, to: id)
                    guard let iconProvider, iconProvider.canLoadObject(ofClass: NSImage.self) else {
                        self.inFlight.remove(id); return
                    }
                    iconProvider.loadObject(ofClass: NSImage.self) { object, _ in
                        let png = (object as? NSImage).flatMap { Self.iconPNG(from: $0) }
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated {
                                self.inFlight.remove(id)
                                guard let png, let store = self.store, let name = store.saveIcon(png, for: id) else { return }
                                store.update(id) { $0.iconFile = name }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Fetch anything that is missing (e.g. links saved while offline).
    func backfill() {
        guard let store else { return }
        for note in store.notes.prefix(60) where note.kind == .link && note.title == nil {
            fetch(note)
        }
    }

    private func apply(title: String?, to id: UUID) {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return }
        store?.update(id) { $0.title = title }
    }

    nonisolated static func iconPNG(from image: NSImage) -> Data? {
        let size = NSSize(width: 64, height: 64)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
