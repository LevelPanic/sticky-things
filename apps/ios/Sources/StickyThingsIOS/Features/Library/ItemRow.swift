import StickyCore
import StickyIOSDesign
import SwiftUI
import UIKit

/// One saved item on iOS. Tap copies it, the context menu has the rest.
struct ItemRow: View {
    let item: Item
    @ObservedObject var library: Library
    var onOpen: () -> Void
    var onEditCaption: () -> Void
    var onShare: () -> Void
    var onPreview: () -> Void

    private var tint: Tint { item.kind.isTextual ? item.tint : .none }

    var body: some View {
        visualRow
            .onTapGesture { library.copy(item) }
            .onDrag { library.itemProvider(for: item) }
            .contextMenu {
                ItemRowMenu(item: item, library: library, onOpen: onOpen,
                            onEditCaption: onEditCaption, onShare: onShare, onPreview: onPreview)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { library.delete(item) } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button { library.togglePin(item) } label: {
                    Label(item.pinned ? "Unpin" : "Pin", systemImage: item.pinned ? "pin.slash" : "pin")
                }
                .tint(.orange)
            }
            .modifier(ItemRowAccessibility(item: item, library: library, onOpen: onOpen))
    }

    private var visualRow: some View {
        Group {
            switch item.kind {
            case .text, .richText:
                noteBody
            case .image:
                imageBody
            case .color:
                rowBody(title: item.text, detail: "Color", swatch: Color(hexString: item.text))
            default:
                rowBody(title: title, detail: detail)
            }
        }
        .padding(StickyMetrics.cardPadding)
        .stickyCard(tint: tint == .none ? nil : StickyTintPalette.paper(tint))
    }

    // MARK: Bodies

    private var noteBody: some View {
        VStack(alignment: .leading, spacing: StickySpace.s) {
            Text(item.text)
                .font(StickyType.body)
                .lineSpacing(StickyMetrics.bodyLineSpacing)
                .lineLimit(10)
                .foregroundStyle(StickyTintPalette.ink(tint))
                .frame(maxWidth: .infinity, alignment: .leading)
            meta(detail: item.kind == .richText ? "Formatted" : nil)
        }
    }

    private var imageBody: some View {
        VStack(alignment: .leading, spacing: StickySpace.s) {
            ItemThumbnailView(item: item, library: library)
                .frame(maxWidth: .infinity)
                .frame(height: StickyMetrics.thumbnail)
                .clipShape(RoundedRectangle(cornerRadius: StickyRadius.m, style: .continuous))
            if let caption = item.caption, !caption.isEmpty {
                Text(caption)
                    .font(StickyType.body)
                    .foregroundStyle(StickyPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            meta(detail: imageDetail)
        }
    }

    private func rowBody(title: String, detail: String, swatch: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: StickySpace.s) {
            HStack(spacing: StickySpace.m) {
                StickyKindTile(kind: item.kind, tint: item.tint, swatch: swatch, size: StickyMetrics.rowIcon)
                Text(title)
                    .font(StickyType.cardTitle)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let caption = item.caption, !caption.isEmpty {
                Text(caption)
                    .font(StickyType.body)
                    .foregroundStyle(StickyPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            meta(detail: detail)
        }
    }

    private func meta(detail: String?) -> some View {
        HStack(spacing: StickySpace.xxs) {
            if let detail, !detail.isEmpty {
                Text(detail).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: StickySpace.xs)
            if item.pinned {
                Image(systemName: "pin.fill").font(StickyType.meta)
            }
            Text(item.source?.name.map { "\($0) · \(StickyRelativeTime.short(item.createdAt))" } ?? StickyRelativeTime.short(item.createdAt))
                .monospacedDigit()
        }
        .font(StickyType.meta)
        .foregroundStyle(StickyTintPalette.secondaryInk(tint))
    }

    // MARK: Details

    private var title: String {
        switch item.kind {
        case .link: return item.link?.title ?? item.headline
        case .pdf, .file, .folder: return item.headline
        case .files: return "\(item.files.count) items"
        default: return item.headline
        }
    }

    private var detail: String {
        switch item.kind {
        case .link:
            guard let string = item.link?.url, let url = URL(string: string) else { return item.text }
            return url.host() ?? string
        case .pdf:
            var parts: [String] = []
            if let pages = item.pageCount { parts.append(pages == 1 ? "1 page" : "\(pages) pages") }
            if item.byteSize > 0 { parts.append(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file)) }
            return parts.joined(separator: " · ")
        case .file, .folder:
            if item.files.first?.isDirectory == true { return "Folder" }
            return ByteCountFormatter.string(fromByteCount: item.files.first?.byteSize ?? 0, countStyle: .file)
        case .files:
            return item.files.map(\.name).joined(separator: ", ")
        case .other:
            return item.text
        default:
            return item.kind.label
        }
    }

    private var imageDetail: String {
        var parts: [String] = []
        if let size = item.pixelSize { parts.append("\(size.width) × \(size.height)") }
        if let name = item.files.first?.name { parts.append(name) }
        return parts.joined(separator: " · ")
    }
}

/// The right-click / long-press menu, kept as its own view so the row body stays small.
struct ItemRowMenu: View {
    let item: Item
    @ObservedObject var library: Library
    var onOpen: () -> Void
    var onEditCaption: () -> Void
    var onShare: () -> Void
    var onPreview: () -> Void

    var body: some View {
        Button { library.copy(item) } label: { Label("Copy", systemImage: "doc.on.doc") }
        Button { onOpen() } label: { Label("Show Details", systemImage: "info.circle") }
        if item.kind == .link, let url = item.link.flatMap({ URL(string: $0.url) }) {
            Button { UIApplication.shared.open(url) } label: { Label("Open Link", systemImage: "arrow.up.right") }
        }
        if !library.shareItems(for: item).isEmpty {
            Button { onShare() } label: { Label("Share", systemImage: "square.and.arrow.up") }
        }
        if item.kind == .image || item.kind == .pdf || !item.files.isEmpty {
            Button { onPreview() } label: { Label("Quick Look", systemImage: "eye") }
        }
        Button { library.togglePin(item) } label: {
            Label(item.pinned ? "Unpin" : "Pin", systemImage: item.pinned ? "pin.slash" : "pin")
        }
        if item.supportsCaption {
            Button { onEditCaption() } label: {
                Label(item.caption == nil ? "Add Caption" : "Edit Caption", systemImage: "text.bubble")
            }
        }
        Divider()
        Button(role: .destructive) { library.delete(item) } label: { Label("Delete", systemImage: "trash") }
    }
}

struct ItemRowAccessibility: ViewModifier {
    let item: Item
    @ObservedObject var library: Library
    var onOpen: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.kind.label), \(item.headline), \(StickyRelativeTime.short(item.createdAt))")
            .accessibilityHint("Copies to the clipboard")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { library.copy(item) }
            .accessibilityAction(named: "Copy") { library.copy(item) }
            .accessibilityAction(named: "Show Details") { onOpen() }
            .accessibilityAction(named: item.pinned ? "Unpin" : "Pin") { library.togglePin(item) }
            .accessibilityAction(named: "Delete") { library.delete(item) }
    }
}
