import AppKit
import StickyCore
import StickyDesign
import SwiftUI

enum PanelLayout {
    static let width: CGFloat = 372
    static let listPadding: CGFloat = Space.m
    static let cardPadding: CGFloat = Space.m
    static var cardContentWidth: CGFloat { width - listPadding * 2 - cardPadding * 2 }
}

enum RelativeTime {
    static func short(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if seconds < 6 * 86_400 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

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

/// Thumbnail for any item that has one (image data, PDFs, any file via Quick Look).
struct ItemThumbnail: View {
    let item: Item
    let store: ItemStore
    var maxPixel = 760
    var contentMode: ContentMode = .fill
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Palette.surfaceSunken.color)
            }
        }
        .task(id: "\(item.id)-\(item.updatedAt.timeIntervalSince1970)-\(maxPixel)") {
            guard let source = ThumbnailService.source(for: item, store: store) else { return }
            let key = "\(item.id)-\(item.updatedAt.timeIntervalSince1970)-\(maxPixel)"
            if let hit = ThumbnailService.shared.cached(key: key) { image = hit; return }
            image = await ThumbnailService.shared.thumbnail(for: source, key: key, maxPixel: maxPixel)
        }
    }
}

/// Small square icon for links (favicon), files (icon/thumbnail) and other things.
struct ItemIcon: View {
    let item: Item
    let store: ItemStore
    var size: CGFloat = 32

    var body: some View {
        Group {
            switch item.kind {
            case .link:
                if let hash = item.link?.iconBlob, let image = NSImage(contentsOf: store.blobs.url(for: hash)) {
                    Image(nsImage: image).resizable().interpolation(.high)
                } else {
                    glyph(item.link?.url.hasPrefix("mailto:") == true ? "envelope" : "link")
                }
            case .file, .folder, .pdf:
                if let file = item.files.first, let url = store.files.url(for: file) {
                    if item.kind == .pdf || FileInfo.isImage(url) {
                        ItemThumbnail(item: item, store: store, maxPixel: Int(size * 3))
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                    }
                } else if item.kind == .pdf {
                    ItemThumbnail(item: item, store: store, maxPixel: Int(size * 3))
                } else {
                    glyph("questionmark.folder")
                }
            case .color:
                RoundedRectangle(cornerRadius: Radius.s, style: .continuous).fill(Color(hexString: item.text) ?? .gray)
            default:
                glyph("shippingbox")
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
    }

    private func glyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Palette.textSecondary.color)
            .frame(width: size, height: size)
            .background(Palette.surfaceSunken.color)
    }
}

/// Up to three overlapping file icons for multi-file items.
struct FileStack: View {
    let item: Item
    let store: ItemStore

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(item.files.prefix(3).enumerated()), id: \.offset) { index, file in
                Group {
                    if let url = store.files.url(for: file) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                    } else {
                        Image(systemName: "doc").resizable().scaledToFit().padding(6).foregroundStyle(Palette.textTertiary.color)
                    }
                }
                .frame(width: 30, height: 30)
                .offset(x: CGFloat(index) * 12)
            }
        }
        .frame(width: 30 + CGFloat(min(item.files.count, 3) - 1) * 12, height: 32, alignment: .leading)
    }
}

enum FileInfo {
    static func isImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "heic", "gif", "tiff", "tif", "webp", "bmp"].contains(url.pathExtension.lowercased())
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

extension Color {
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(nsColor: NSColor(hex: value))
    }
}

extension Tint {
    var swatch: Swatch? { TintPalette.paper(rawValue) }
    var name: String { self == .none ? "No Color" : rawValue.capitalized }
}
