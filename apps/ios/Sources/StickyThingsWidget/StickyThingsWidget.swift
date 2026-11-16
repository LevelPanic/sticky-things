import ImageIO
import StickyCore
import StickyIOSDesign
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Model

struct StickyWidgetItem: Identifiable {
    let id: UUID
    let kind: ItemKind
    let title: String
    let detail: String?
    let tint: Tint
    let createdAt: Date
    let image: UIImage?
}

struct StickyWidgetEntry: TimelineEntry {
    let date: Date
    let items: [StickyWidgetItem]
    let pinnedCount: Int
    let totalCount: Int

    static let empty = StickyWidgetEntry(date: Date(), items: [], pinnedCount: 0, totalCount: 0)

    static let placeholder: StickyWidgetEntry = {
        let items = [
            StickyWidgetItem(id: UUID(), kind: .text, title: "Wi-Fi: Garden-5G", detail: "password is on the fridge",
                             tint: .yellow, createdAt: Date(), image: nil),
            StickyWidgetItem(id: UUID(), kind: .text, title: "Flight QF12 · seat 34A", detail: "gate 26",
                             tint: .blue, createdAt: Date().addingTimeInterval(-3600), image: nil),
            StickyWidgetItem(id: UUID(), kind: .link, title: "Sticky Things on GitHub", detail: "github.com/LevelPanic",
                             tint: .none, createdAt: Date().addingTimeInterval(-7200), image: nil),
        ]
        return StickyWidgetEntry(date: Date(), items: items, pinnedCount: 2, totalCount: 5)
    }()
}

// MARK: - Provider

struct StickyWidgetProvider: TimelineProvider {
    typealias Entry = StickyWidgetEntry

    func placeholder(in context: Context) -> StickyWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (StickyWidgetEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { @MainActor in
            completion(WidgetLibrary.load())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StickyWidgetEntry>) -> Void) {
        Task { @MainActor in
            let entry = WidgetLibrary.load()
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
        }
    }
}

@MainActor
enum WidgetLibrary {
    static func load() -> StickyWidgetEntry {
        guard let store = try? ItemStore(paths: StickyAppGroup.paths) else { return .empty }
        let visible = store.items.filter { !$0.concealed }
        let pinned = visible.filter(\.pinned)
        let rest = visible.filter { !$0.pinned }
        let shown = (pinned + rest).prefix(StickyMetrics.widgetItemLimit).map { widgetItem($0, store: store) }
        return StickyWidgetEntry(date: Date(), items: shown, pinnedCount: pinned.count, totalCount: visible.count)
    }

    private static func widgetItem(_ item: Item, store: ItemStore) -> StickyWidgetItem {
        StickyWidgetItem(
            id: item.id,
            kind: item.kind,
            title: title(item),
            detail: detail(item),
            tint: item.kind.isTextual ? item.tint : .none,
            createdAt: item.createdAt,
            image: item.kind == .image ? image(item, store: store) : nil
        )
    }

    private static func title(_ item: Item) -> String {
        switch item.kind {
        case .link:
            if let title = item.link?.title, !title.isEmpty { return title }
            if let host = item.link.flatMap({ URL(string: $0.url)?.host() }) { return host }
            return item.headline
        case .image:
            if let caption = item.caption, !caption.isEmpty { return caption }
            return item.files.first?.name ?? "Image"
        default:
            return item.headline
        }
    }

    private static func detail(_ item: Item) -> String? {
        switch item.kind {
        case .text, .richText:
            let firstLine = item.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? item.text
            return firstLine == item.headline ? nil : firstLine
        case .link:
            guard let string = item.link?.url, let url = URL(string: string) else { return nil }
            return url.host() ?? string
        case .image:
            guard let size = item.pixelSize else { return nil }
            return "\(size.width) × \(size.height)"
        case .pdf:
            guard let pages = item.pageCount else { return item.files.first?.name }
            return pages == 1 ? "1 page" : "\(pages) pages"
        case .file, .folder:
            return item.kind == .folder ? "Folder" : ByteCountFormatter.string(fromByteCount: item.files.first?.byteSize ?? 0, countStyle: .file)
        case .files:
            return "\(item.files.count) files"
        case .color:
            return "Color"
        case .other:
            return item.text
        }
    }

    private static func image(_ item: Item, store: ItemStore) -> UIImage? {
        for snapshot in item.snapshot {
            for type in UTI.images {
                guard let rep = snapshot.representation(type), let data = store.blobs.data(rep.blob) else { continue }
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { continue }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 420,
                ]
                guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { continue }
                return UIImage(cgImage: thumbnail)
            }
        }
        return nil
    }
}

// MARK: - Widget

struct StickyThingsWidget: Widget {
    static let kind = "app.stickythings.widget.library"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: StickyWidgetProvider()) { entry in
            StickyWidgetView(entry: entry)
        }
        .configurationDisplayName("Sticky Things")
        .description("Pinned and recent items, ready to copy or open.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryInline, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

@main
struct StickyThingsWidgetBundle: WidgetBundle {
    var body: some Widget {
        StickyThingsWidget()
    }
}

// MARK: - View

struct StickyWidgetView: View {
    let entry: StickyWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemLarge: large
            case .accessoryRectangular: accessoryRectangular
            case .accessoryInline: accessoryInline
            case .accessoryCircular: accessoryCircular
            default: medium
            }
        }
        .containerBackground(for: .widget) { background }
        .widgetURL(URL(string: "stickythings://open")!)
    }

    @ViewBuilder private var background: some View {
        switch family {
        case .accessoryRectangular, .accessoryInline, .accessoryCircular:
            AccessoryWidgetBackground()
        default:
            StickyPalette.paper
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: StickySpace.s) {
            header
            if let item = entry.items.first {
                itemBlock(item, showsImage: true)
                Spacer(minLength: 0)
                Text(entry.totalCount == 1 ? "1 item" : "\(entry.totalCount) items")
                    .font(StickyType.widgetMeta)
                    .foregroundStyle(StickyPalette.paperInkSecondary)
            } else {
                Spacer()
                Text("Nothing saved yet").font(StickyType.widgetMeta).foregroundStyle(StickyPalette.paperInkSecondary)
                Spacer()
            }
        }
        .padding(StickySpace.l)
        .widgetURL(itemURL(entry.items.first?.id) ?? URL(string: "stickythings://open")!)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: StickySpace.s) {
            header
            ForEach(entry.items.prefix(3)) { item in
                Link(destination: itemURL(item.id)!) {
                    itemBlock(item, showsImage: false)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(StickySpace.l)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: StickySpace.s) {
            header
            ForEach(entry.items) { item in
                Link(destination: itemURL(item.id)!) {
                    itemBlock(item, showsImage: false)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Divider().overlay(StickyPalette.paperInkSecondary.opacity(0.18))
            Button(intent: OpenStickyThingIntent()) {
                Label("New Sticky Thing", systemImage: "plus")
                    .font(StickyType.widgetHeader)
                    .foregroundStyle(StickyPalette.paperInk)
            }
            .buttonStyle(.plain)
        }
        .padding(StickySpace.l)
    }

    // MARK: Lock Screen

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: StickySpace.xxs) {
            Label("Sticky Things", systemImage: "note.text")
                .font(StickyType.widgetHeader)
                .widgetAccentable()
            if let item = entry.items.first {
                Text(item.title)
                    .font(StickyType.widgetRow)
                    .lineLimit(2)
                Text(entry.totalCount == 1 ? "1 item" : "\(entry.totalCount) items")
                    .font(StickyType.widgetMeta)
            } else {
                Text("Nothing saved yet").font(StickyType.widgetMeta)
            }
        }
        .widgetURL(itemURL(entry.items.first?.id) ?? URL(string: "stickythings://open")!)
    }

    private var accessoryInline: some View {
        Label(entry.items.first?.title ?? "Sticky Things", systemImage: "note.text")
            .widgetURL(itemURL(entry.items.first?.id) ?? URL(string: "stickythings://open")!)
    }

    private var accessoryCircular: some View {
        VStack(spacing: StickySpace.xxs) {
            Image(systemName: "note.text")
                .font(StickyType.widgetMeta)
                .widgetAccentable()
            Text("\(entry.totalCount)")
                .font(.title3.weight(.semibold))
            Text("items")
                .font(StickyType.widgetMeta)
        }
        .widgetURL(URL(string: "stickythings://open")!)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: StickySpace.xs) {
            Image(systemName: "note.text")
                .font(StickyType.widgetHeader)
                .widgetAccentable()
            Text("Sticky Things")
                .font(StickyType.widgetHeader)
            Spacer(minLength: StickySpace.xs)
            if entry.pinnedCount > 0 {
                Image(systemName: "pin.fill")
                    .font(StickyType.widgetMeta)
            }
        }
        .foregroundStyle(StickyPalette.paperInkSecondary)
    }

    private func itemBlock(_ item: StickyWidgetItem, showsImage: Bool) -> some View {
        HStack(spacing: StickySpace.s) {
            if showsImage, let image = item.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: StickyMetrics.widgetImage, height: StickyMetrics.widgetImage)
                    .clipShape(RoundedRectangle(cornerRadius: StickyRadius.s, style: .continuous))
            } else {
                itemIcon(item)
            }
            VStack(alignment: .leading, spacing: StickySpace.xxs) {
                Text(item.title)
                    .font(StickyType.widgetRow)
                    .foregroundStyle(StickyPalette.paperInk)
                    .lineLimit(showsImage ? 2 : 1)
                if let detail = item.detail {
                    Text(detail)
                        .font(StickyType.widgetMeta)
                        .foregroundStyle(StickyPalette.paperInkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: StickySpace.xs)
            Text(StickyRelativeTime.compact(item.createdAt))
                .font(StickyType.widgetMeta)
                .foregroundStyle(StickyPalette.paperInkSecondary)
                .lineLimit(1)
        }
    }

    private func itemIcon(_ item: StickyWidgetItem) -> some View {
        StickyKindTile(kind: item.kind, tint: item.tint,
                       fill: item.tint == .none ? StickyPalette.subduedFill : nil,
                       size: StickyMetrics.widgetIcon)
    }

    private func itemURL(_ id: UUID?) -> URL? {
        guard let id else { return nil }
        return URL(string: "stickythings://item/\(id.uuidString)")
    }
}
