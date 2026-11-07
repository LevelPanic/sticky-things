import AppKit
import SwiftUI

/// One saved thing in the stack: text, link, image or file.
struct NoteCard: View {
    let note: Note
    let model: PanelModel
    let isSelected: Bool
    let isFlashing: Bool
    @State private var hovering = false

    private var store: NoteStore { model.store }
    private var paper: Color? { note.kind == .text ? note.color.paper : nil }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(note.kind == .image ? 6 : 12)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(hovering ? 0.14 : 0.07),
                                  lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if hovering {
                    actions.padding(6).transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
                }
            }
            .overlay {
                if isFlashing {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
            .onTapGesture { model.copy(note, closeAfter: false) }
            .simultaneousGesture(TapGesture(count: 2).onEnded { model.open(note) })
            .onDrag { NoteActions.itemProvider(for: note, store: store) }
            .contextMenu { menu }
            .help(helpText)
            .animation(.easeOut(duration: 0.18), value: isFlashing)
    }

    // MARK: Content per kind

    @ViewBuilder private var content: some View {
        switch note.kind {
        case .text: textContent
        case .link: linkContent
        case .image: imageContent
        case .file: fileContent
        }
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.text)
                .font(.system(size: 13))
                .lineSpacing(2)
                .lineLimit(7)
                .foregroundStyle(paper == nil ? Color.primary : Color.black.opacity(0.82))
                .frame(maxWidth: .infinity, alignment: .leading)
            footer(nil)
        }
    }

    private var linkContent: some View {
        HStack(alignment: .center, spacing: 10) {
            Group {
                if let icon = store.mediaFile(note.iconFile), FileManager.default.fileExists(atPath: icon.path) {
                    ThumbnailView(url: icon, maxPixel: 64, contentMode: .fill)
                } else {
                    Image(systemName: note.url?.scheme == "mailto" ? "envelope.fill" : "link")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(LinearGradient(colors: [.blue, .indigo], startPoint: .top, endPoint: .bottom))
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title ?? note.url?.host() ?? note.text)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                footer(displayURL)
            }
        }
    }

    private var imageContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(url: store.mediaFile(note.imageFile), maxPixel: 760, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: imageHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            footer(imageCaption).padding(.horizontal, 6).padding(.bottom, 2)
        }
    }

    private var fileContent: some View {
        let url = URL(fileURLWithPath: note.text)
        let exists = FileManager.default.fileExists(atPath: url.path)
        return HStack(spacing: 10) {
            Group {
                if exists && FileInfo.isImage(url) {
                    ThumbnailView(url: url, maxPixel: 96, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                }
            }
            .frame(width: 34, height: 34)
            .opacity(exists ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                footer(exists ? FileInfo.subtitle(for: url) : "Missing — moved or deleted")
            }
        }
    }

    private func footer(_ detail: String?) -> some View {
        HStack(spacing: 6) {
            if let detail {
                Text(detail).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if note.pinned { Image(systemName: "pin.fill").font(.system(size: 9)) }
            Text(RelativeTime.short(note.createdAt)).monospacedDigit()
        }
        .font(.system(size: 11))
        .foregroundStyle(paper == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.black.opacity(0.5)))
    }

    private var displayURL: String {
        guard let url = note.url else { return note.text }
        if url.scheme == "mailto" { return url.absoluteString.replacingOccurrences(of: "mailto:", with: "") }
        var s = (url.host() ?? "") + url.path()
        if s.hasPrefix("www.") { s.removeFirst(4) }
        if s.hasSuffix("/") { s.removeLast() }
        return s.isEmpty ? note.text : s
    }

    /// Card width is fixed, so size the preview from the image's aspect ratio (cropped when very tall).
    private var imageHeight: CGFloat {
        let width = PanelView.width - 24 - 12
        guard let w = note.pixelWidth, let h = note.pixelHeight, w > 0 else { return 150 }
        return min(190, max(70, width * CGFloat(h) / CGFloat(w)))
    }

    private var imageCaption: String {
        if let w = note.pixelWidth, let h = note.pixelHeight { return "Image · \(w) × \(h)" }
        return "Image"
    }

    @ViewBuilder private var background: some View {
        if let paper {
            LinearGradient(colors: [paper, paper.opacity(0.88)], startPoint: .top, endPoint: .bottom)
        } else {
            Rectangle().fill(.background.opacity(hovering || isSelected ? 0.72 : 0.55))
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 4) {
            switch note.kind {
            case .text:
                CircleIconButton(symbol: "pencil", help: "Edit (⌘E)") { model.beginEditing(note) }
            case .link:
                CircleIconButton(symbol: "arrow.up.right", help: "Open link (⌘O)") { model.open(note) }
            case .image, .file:
                CircleIconButton(symbol: "arrow.up.forward.app", help: "Open (⌘O)") { model.open(note) }
            }
            CircleIconButton(symbol: note.pinned ? "pin.slash" : "pin", help: note.pinned ? "Unpin (⌘P)" : "Pin to top (⌘P)") {
                model.togglePin(note)
            }
            CircleIconButton(symbol: "trash", help: "Delete (⌘⌫)", tint: .red) { model.delete(note) }
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Copy") { model.copy(note, closeAfter: false) }
        switch note.kind {
        case .text:
            Button("Edit") { model.beginEditing(note) }
        case .link:
            Button("Open Link") { model.open(note) }
            Button("Edit Link") { model.beginEditing(note) }
        case .image, .file:
            Button("Open") { model.open(note) }
            Button("Show in Finder") { model.reveal(note) }
        }
        Button(note.pinned ? "Unpin" : "Pin to Top") { model.togglePin(note) }
        if note.kind == .text {
            Menu("Color") {
                ForEach(NoteColor.allCases) { color in
                    Button {
                        model.setColor(color, for: note)
                    } label: {
                        if note.color == color { Label(color.name, systemImage: "checkmark") } else { Text(color.name) }
                    }
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete(note) }
    }

    private var helpText: String {
        switch note.kind {
        case .text: return "Click to copy · Double-click to edit · Drag out to use anywhere"
        case .link: return "Click to copy · Double-click to open · Drag out to use anywhere"
        case .image, .file: return "Click to copy · Double-click to open · Drag out to use anywhere"
        }
    }
}
