import AppKit
import StickyCore
import StickyDesign
import SwiftUI

/// One saved item in the stack.
///
/// Every action is reachable four ways: pointer (click / double-click / hover buttons),
/// right-click menu, keyboard shortcut, and VoiceOver actions. Nothing is hover-only: clicking
/// a card selects it, and a selected card keeps its buttons visible.
struct ItemCard: View {
    let item: Item
    @ObservedObject var model: PanelModel
    @State private var editorHeight: CGFloat = 18

    private var store: ItemStore { model.store }
    private var isHovered: Bool { model.hoveredID == item.id }
    private var isSelected: Bool { model.selection == item.id }
    private var isCopied: Bool { model.copiedID == item.id }
    private var isEditing: Bool { model.editingID == item.id }
    private var showsActions: Bool { (isHovered || isSelected) && !isEditing }
    private var tint: Swatch? { item.kind.isTextual ? item.tint.swatch : nil }

    var body: some View {
        content
            .padding(item.kind == .image ? Space.xs + 2 : PanelLayout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(tint: tint, hovered: isHovered, selected: isSelected || isEditing, highlighted: isCopied)
            .contentShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            .modifier(CardGestures(enabled: !isEditing, item: item, model: model))
            // Accessibility: the card is one element with named actions (VoiceOver, the self-test)…
            .accessibilityElement(children: isEditing ? .contain : .ignore)
            .accessibilityLabel("\(item.kind.label), \(item.headline), \(RelativeTime.short(item.createdAt))")
            .accessibilityHint("Copies to the clipboard")
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction { model.copy(item) }
            .accessibilityAction(named: "Copy") { model.copy(item) }
            .accessibilityAction(named: primaryActionName) { model.activate(item) }
            .accessibilityAction(named: item.pinned ? "Unpin" : "Pin") { model.togglePin(item) }
            .accessibilityAction(named: "Delete") { model.delete(item) }
            .accessibilityIdentifier("card-\(item.id.uuidString)")
            // …and its buttons sit on top as their own elements, so they stay reachable.
            // Bottom-trailing: the slot the meta line's time vacates, so titles stay readable.
            .overlay(alignment: .bottomTrailing) {
                if showsActions { actionBar.padding(Space.xs).transition(.opacity) }
            }
            // Hover tracks the card *and* its buttons. Tracked under the buttons, the pointer
            // reaching them would count as leaving the card and hide them (v2.0 flicker).
            .onHover { inside in model.setHovered(item.id, inside) }
            .animation(Motion.quick, value: isCopied)
            .animation(Motion.quick, value: showsActions)
    }

    private var primaryActionName: String {
        switch item.kind {
        case .text, .richText: return "Edit"
        case .link: return "Open Link"
        default: return "Quick Look"
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .text, .richText: textContent
        case .link: rowContent(title: item.link?.title ?? item.headline, detail: displayURL)
        case .image: imageContent
        case .pdf: rowContent(title: item.files.first?.name ?? item.title ?? "PDF", detail: pdfDetail)
        case .file, .folder: rowContent(title: item.headline, detail: fileDetail)
        case .files: filesContent
        case .color: rowContent(title: item.text, detail: "Color")
        case .other: rowContent(title: item.source.map { "Data from \($0.name ?? "an app")" } ?? "App data", detail: item.text)
        }
    }

    @ViewBuilder private var textContent: some View {
        if isEditing {
            InlineTextEditor(
                initialText: item.text,
                initialRTF: item.kind == .richText ? richTextData : nil,
                font: TypeScale.bodyNSFont,
                textColor: tint == nil ? Palette.textPrimary.nsColor : TintPalette.ink.nsColor,
                height: $editorHeight,
                onFinish: { text, rtf in model.finishEditing(item.id, text: text, rtf: rtf) }
            )
            .frame(height: editorHeight)
            .accessibilityIdentifier("editor-\(item.id.uuidString)")
        } else {
            VStack(alignment: .leading, spacing: Space.s - 2) {
                Text(item.text)
                    .font(TypeScale.body)
                    .lineSpacing(3)
                    .lineLimit(6)
                    .foregroundStyle(tint == nil ? Palette.textPrimary.color : TintPalette.ink.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .blur(radius: item.concealed && !isHovered && !isSelected ? 6 : 0)
                meta(item.kind == .richText ? "Formatted" : (item.concealed ? "Hidden until you point at it" : nil))
            }
        }
    }

    private var imageContent: some View {
        VStack(alignment: .leading, spacing: Space.s - 2) {
            ItemThumbnail(item: item, store: store)
                .frame(maxWidth: .infinity)
                .frame(height: imageHeight)
                .clipShape(RoundedRectangle(cornerRadius: Radius.inner(Radius.l, padding: Space.xs + 2), style: .continuous))
            meta(imageDetail).padding(.horizontal, Space.s).padding(.bottom, Space.xxs)
        }
    }

    private var filesContent: some View {
        HStack(spacing: Space.m) {
            FileStack(item: item, store: store)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("\(item.files.count) items").font(TypeScale.bodyStrong).foregroundStyle(Palette.textPrimary.color)
                Text(item.files.map(\.name).joined(separator: ", "))
                    .font(TypeScale.callout).foregroundStyle(Palette.textSecondary.color).lineLimit(1).truncationMode(.middle)
                meta(nil)
            }
        }
    }

    private func rowContent(title: String, detail: String) -> some View {
        HStack(spacing: Space.m) {
            ItemIcon(item: item, store: store, size: 32)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title)
                    .font(TypeScale.bodyStrong)
                    .foregroundStyle(Palette.textPrimary.color)
                    .lineLimit(2)
                    .truncationMode(.middle)
                meta(detail)
            }
        }
    }

    /// "github.com · Safari · 2 min ago" — the trailing part hides while the action bar shows.
    private func meta(_ detail: String?) -> some View {
        HStack(spacing: Space.xs + 2) {
            if let detail, !detail.isEmpty { Text(detail).lineLimit(1).truncationMode(.middle) }
            Spacer(minLength: Space.xs)
            Group {
                if item.pinned { Image(systemName: "pin.fill").font(.system(size: 11)).accessibilityLabel("Pinned") }
                Text(sourceAndTime).lineLimit(1).monospacedDigit()
            }
            .opacity(showsActions ? 0 : 1)
        }
        .font(TypeScale.caption)
        .foregroundStyle(tint == nil ? Palette.textSecondary.color : TintPalette.inkSecondary.color)
    }

    private var sourceAndTime: String {
        let time = RelativeTime.short(item.createdAt)
        guard let name = item.source?.name, !name.isEmpty else { return time }
        return "\(name) · \(time)"
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack(spacing: Space.xxs) {
            IconButton(isCopied ? "Copied" : "Copy", symbol: isCopied ? "checkmark" : "doc.on.doc", isOn: isCopied) { model.copy(item) }
                .accessibilityIdentifier("copy-\(item.id.uuidString)")
            switch item.kind {
            case .text, .richText:
                IconButton("Edit", symbol: "pencil") { model.beginEditing(item) }
                    .accessibilityIdentifier("edit-\(item.id.uuidString)")
            case .link:
                IconButton("Open Link", symbol: "arrow.up.right") { model.open(item) }
            default:
                IconButton("Quick Look", symbol: "eye") { model.quickLook(item) }
            }
            Menu {
                CardMenuItems(item: item, model: model, compact: true)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium))
                    .frame(width: Metrics.iconButton, height: Metrics.iconButton)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .foregroundStyle(Palette.textSecondary.color)
            .frame(width: Metrics.iconButton, height: Metrics.iconButton)
            .help("More")
            .accessibilityLabel("More Actions")
        }
        .padding(Space.xxs)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Palette.surfaceRaised.color))
        .elevation(.lifted)
    }

    // MARK: Details

    private var richTextData: Data? {
        for snap in item.snapshot {
            if let rep = snap.representation(UTI.rtf) { return store.blobs.data(rep.blob) }
        }
        return nil
    }

    private var displayURL: String {
        guard let string = item.link?.url, let url = URL(string: string) else { return item.text }
        if url.scheme == "mailto" { return string.replacingOccurrences(of: "mailto:", with: "") }
        var s = (url.host() ?? "") + url.path()
        if s.hasPrefix("www.") { s.removeFirst(4) }
        if s.hasSuffix("/") { s.removeLast() }
        return s.isEmpty ? string : s
    }

    private var imageHeight: CGFloat {
        guard let size = item.pixelSize, size.width > 0 else { return 150 }
        let width = PanelLayout.width - PanelLayout.listPadding * 2 - (Space.xs + 2) * 2
        return min(Metrics.thumbnailMaxHeight, max(72, width * CGFloat(size.height) / CGFloat(size.width)))
    }

    private var imageDetail: String {
        var parts: [String] = []
        if let size = item.pixelSize { parts.append("\(size.width) × \(size.height)") }
        if let name = item.files.first?.name { parts.append(name) }
        return parts.isEmpty ? "Image" : parts.joined(separator: " · ")
    }

    private var pdfDetail: String {
        var parts: [String] = []
        if let pages = item.pageCount { parts.append(pages == 1 ? "1 page" : "\(pages) pages") }
        if item.byteSize > 0 { parts.append(FileInfo.size(item.byteSize)) }
        return parts.joined(separator: " · ")
    }

    private var fileDetail: String {
        guard let file = item.files.first else { return item.kind.label }
        if store.files.url(for: file) == nil { return "Moved or deleted" }
        if file.isDirectory { return "Folder" }
        return FileInfo.size(file.byteSize) + (file.libraryPath != nil ? "" : " · linked")
    }
}

/// Click copies (and selects), double-click opens/edits, drag carries every representation,
/// right-click shows everything. Disabled while editing so the text view gets the mouse.
struct CardGestures: ViewModifier {
    let enabled: Bool
    let item: Item
    @ObservedObject var model: PanelModel

    func body(content: Content) -> some View {
        if enabled {
            content
                .onTapGesture { model.copy(item) }
                .simultaneousGesture(TapGesture(count: 2).onEnded { model.activate(item) })
                .onDrag { PasteboardWriter.itemProvider(for: item, store: model.store) }
                .contextMenu { CardMenuItems(item: item, model: model, compact: false) }
        } else {
            content
        }
    }
}

/// The full action list (right-click menu and the card's "More" button).
struct CardMenuItems: View {
    let item: Item
    @ObservedObject var model: PanelModel
    let compact: Bool

    var body: some View {
        if !compact {
            Button("Copy") { model.copy(item) }
        }
        Button("Copy and Close") { model.copy(item, closeAfter: true) }
        Divider()
        switch item.kind {
        case .text, .richText:
            if !compact { Button("Edit") { model.beginEditing(item) } }
        case .link:
            if !compact { Button("Open Link") { model.open(item) } }
            Button("Edit Link") { model.beginEditing(item) }
        default:
            if !compact { Button("Quick Look") { model.quickLook(item) } }
            Button("Open") { model.open(item) }
            if !item.files.isEmpty { Button("Show in Finder") { model.reveal(item) } }
        }
        Button(item.pinned ? "Unpin" : "Pin to Top") { model.togglePin(item) }
        if item.kind.isTextual {
            Menu("Color") {
                ForEach(Tint.allCases, id: \.self) { tint in
                    Button {
                        model.setTint(tint, for: item)
                    } label: {
                        if item.tint == tint { Label(tint.name, systemImage: "checkmark") } else { Text(tint.name) }
                    }
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete(item) }
    }
}
