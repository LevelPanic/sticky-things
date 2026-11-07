import AppKit
import ImageIO
import SwiftUI

/// Small, cached thumbnails so scrolling stays smooth.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    func cached(_ url: URL, maxPixel: Int) -> NSImage? {
        cache.object(forKey: "\(url.path)#\(maxPixel)" as NSString)
    }

    func load(_ url: URL, maxPixel: Int) async -> NSImage? {
        if let hit = cached(url, maxPixel: maxPixel) { return hit }
        let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
        if let image { cache.setObject(image, forKey: "\(url.path)#\(maxPixel)" as NSString) }
        return image
    }
}

struct ThumbnailView: View {
    let url: URL?
    var maxPixel = 720
    var contentMode: ContentMode = .fit
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
            }
        }
        .task(id: url) {
            guard let url else { return }
            if let hit = ThumbnailCache.shared.cached(url, maxPixel: maxPixel) { image = hit; return }
            image = await ThumbnailCache.shared.load(url, maxPixel: maxPixel)
        }
    }
}

enum RelativeTime {
    static func short(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "\(Int(seconds / 3600))h" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if seconds < 6 * 86_400 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// Section titles for the list.
    static func section(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.wide).day())
        }
        return date.formatted(.dateTime.month(.wide).day().year())
    }
}

enum FileInfo {
    static func subtitle(for url: URL) -> String {
        var parts: [String] = []
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .localizedTypeDescriptionKey])
        if values?.isDirectory == true {
            parts.append("Folder")
        } else if let size = values?.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        parts.append(url.deletingLastPathComponent().lastPathComponent)
        return parts.joined(separator: " · ")
    }

    static func isImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "heic", "gif", "tiff", "tif", "webp", "bmp"].contains(url.pathExtension.lowercased())
    }
}

/// Little round icon button used across the panel.
struct CircleIconButton: View {
    let symbol: String
    var help: String
    var size: CGFloat = 24
    var tint: Color = .primary
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(tint.opacity(hovering ? 1 : 0.75))
                .frame(width: size, height: size)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().strokeBorder(.primary.opacity(hovering ? 0.18 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
