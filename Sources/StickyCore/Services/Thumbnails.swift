import AppKit
import ImageIO
import QuickLookThumbnailing

/// Thumbnails for anything: Quick Look renders files (PDF, video, Office, Keynote…),
/// ImageIO renders stored image data, CoreGraphics renders stored PDF data.
public final class ThumbnailService: @unchecked Sendable {
    public static let shared = ThumbnailService()
    private let cache = NSCache<NSString, NSImage>()

    public enum Source: Sendable {
        case file(URL)
        case imageBlob(URL)
        case pdfBlob(URL)
    }

    public init() {
        cache.countLimit = 400
    }

    /// Works out what to render for an item (needs the store, so call on the main actor).
    @MainActor
    public static func source(for item: Item, store: ItemStore) -> Source? {
        if let file = item.files.first, let url = store.files.url(for: file) { return .file(url) }
        for snap in item.snapshot {
            for type in UTI.images {
                if let rep = snap.representation(type) { return .imageBlob(store.blobs.url(for: rep.blob)) }
            }
            if let rep = snap.representation(UTI.pdf) { return .pdfBlob(store.blobs.url(for: rep.blob)) }
        }
        return nil
    }

    public func cached(key: String) -> NSImage? { cache.object(forKey: key as NSString) }

    public func thumbnail(for source: Source, key: String, maxPixel: Int) async -> NSImage? {
        if let hit = cached(key: key) { return hit }
        let image: NSImage?
        switch source {
        case .file(let url):
            image = await quickLook(url, maxPixel: maxPixel) ?? Self.imageIO(url, maxPixel: maxPixel)
        case .imageBlob(let url):
            image = await Task.detached(priority: .userInitiated) { Self.imageIO(url, maxPixel: maxPixel) }.value
        case .pdfBlob(let url):
            image = await Task.detached(priority: .userInitiated) { Self.pdfFirstPage(url, maxPixel: maxPixel) }.value
        }
        if let image { cache.setObject(image, forKey: key as NSString) }
        return image
    }

    private func quickLook(_ url: URL, maxPixel: Int) async -> NSImage? {
        let side = CGFloat(maxPixel) / 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                                   scale: 2, representationTypes: [.thumbnail, .icon])
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
    }

    static func imageIO(_ url: URL, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func pdfFirstPage(_ url: URL, maxPixel: Int) -> NSImage? {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = CGFloat(maxPixel) / max(box.width, box.height)
        let width = Int(box.width * scale), height = Int(box.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(page)
        guard let cg = context.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }
}
