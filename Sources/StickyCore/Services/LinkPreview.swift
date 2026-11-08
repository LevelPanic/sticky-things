import AppKit
import LinkPresentation

/// Fetches a page title and site icon once per link (like Messages does).
@MainActor
public final class LinkPreviewService {
    private weak var store: ItemStore?
    private var inFlight = Set<UUID>()
    public var isEnabled: () -> Bool = { true }

    public init(store: ItemStore) { self.store = store }

    public func fetch(_ item: Item) {
        guard isEnabled(), item.kind == .link, let string = item.link?.url, let url = URL(string: string),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), !inFlight.contains(item.id) else { return }
        inFlight.insert(item.id)
        let id = item.id
        let provider = LPMetadataProvider()
        provider.timeout = 10
        provider.startFetchingMetadata(for: url) { metadata, _ in
            let title = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let iconProvider = metadata?.iconProvider
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let title, !title.isEmpty { self.store?.update(id) { $0.link?.title = title } }
                    guard let iconProvider, iconProvider.canLoadObject(ofClass: NSImage.self) else {
                        self.inFlight.remove(id); return
                    }
                    iconProvider.loadObject(ofClass: NSImage.self) { object, _ in
                        let png = (object as? NSImage).flatMap { Self.iconPNG($0) }
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated {
                                self.inFlight.remove(id)
                                guard let png, let store = self.store, let hash = try? store.blobs.put(png) else { return }
                                store.update(id) { $0.link?.iconBlob = hash }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Fetch anything missing (links saved while offline).
    public func backfill() {
        guard let store else { return }
        for item in store.items.prefix(80) where item.kind == .link && item.link?.title == nil { fetch(item) }
    }

    nonisolated static func iconPNG(_ image: NSImage) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: 64, height: 64)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
