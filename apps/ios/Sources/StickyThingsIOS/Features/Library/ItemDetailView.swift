import QuickLook
import StickyCore
import StickyIOSDesign
import SwiftUI
import UIKit

/// The native detail screen for an item, used by the list and by Spotlight results.
struct ItemDetailView: View {
    let item: Item
    @ObservedObject var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var showingShare = false
    @State private var showingCaption = false
    @State private var showingEdit = false
    @State private var showingDelete = false
    @State private var previewURL: URL?

    private var current: Item { library.item(item.id) ?? item }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: StickySpace.l) {
                        header
                        content
                        if let caption = current.caption, !caption.isEmpty {
                            VStack(alignment: .leading, spacing: StickySpace.xs) {
                                Text("Caption").font(StickyType.section).foregroundStyle(StickyPalette.textSecondary)
                                Text(caption).font(StickyType.body).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(StickySpace.l)
                            .stickyCard()
                        }
                        details
                        actions
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(StickyMetrics.contentInset)
                    .frame(width: proxy.size.width)
                }
            }
            .background(StickyPalette.page)
            .navigationTitle(current.kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
            }
            .sheet(isPresented: $showingShare) {
                ActivityView(items: library.shareItems(for: current))
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingCaption) {
                CaptionEditorView(item: current, library: library)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingEdit) {
                EditNoteView(item: current, library: library)
                    .presentationDetents([.medium, .large])
            }
            .quickLookPreview($previewURL)
            .confirmationDialog("Delete this item?", isPresented: $showingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    library.delete(current)
                    dismiss()
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: StickySpace.m) {
            Image(systemName: StickyKind.symbol(for: current.kind))
                .font(.title2.weight(.semibold))
                .foregroundStyle(StickyPalette.textSecondary)
            VStack(alignment: .leading, spacing: StickySpace.xxs) {
                Text(current.kind.label).font(StickyType.cardTitle)
                Text(current.source?.name.map { "\($0) · \(StickyRelativeTime.short(current.createdAt))" } ?? StickyRelativeTime.short(current.createdAt))
                    .font(StickyType.meta)
                    .foregroundStyle(StickyPalette.textSecondary)
            }
            Spacer()
            if current.pinned {
                Image(systemName: "pin.fill").foregroundStyle(StickyPalette.warning)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch current.kind {
        case .text, .richText:
            Text(current.text)
                .font(StickyType.body)
                .lineSpacing(StickyMetrics.bodyLineSpacing)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(StickySpace.l)
                .background(RoundedRectangle(cornerRadius: StickyRadius.l, style: .continuous)
                    .fill(StickyTintPalette.paper(current.tint)))
                .foregroundStyle(StickyTintPalette.ink(current.tint))
        case .image, .pdf:
            ItemThumbnailView(item: current, library: library)
                .containerRelativeFrame(.horizontal) { length, _ in max(0, length - StickyMetrics.contentInset * 2) }
                .frame(height: StickyMetrics.detailThumbnail)
                .clipShape(RoundedRectangle(cornerRadius: StickyRadius.l, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: StickyRadius.l, style: .continuous))
                .onTapGesture { previewURL = library.previewURL(for: current) }
        case .link:
            if let url = current.link.flatMap({ URL(string: $0.url) }) {
                Link(destination: url) {
                    Label(current.link?.title ?? url.host() ?? "Open Link", systemImage: "arrow.up.right")
                        .font(StickyType.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(StickySpace.l)
                }
                .stickyCard()
            }
        default:
            HStack(spacing: StickySpace.l) {
                StickyKindTile(kind: current.kind, size: StickyMetrics.detailIcon)
                VStack(alignment: .leading, spacing: StickySpace.xs) {
                    Text(current.headline).font(StickyType.cardTitle).lineLimit(2)
                    Text(current.files.map(\.name).joined(separator: ", "))
                        .font(StickyType.meta)
                        .foregroundStyle(StickyPalette.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(StickySpace.l)
            .stickyCard()
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: StickySpace.s) {
            if let size = current.pixelSize {
                detail("Size", "\(size.width) × \(size.height)")
            }
            if let pages = current.pageCount {
                detail("Pages", "\(pages)")
            }
            if current.byteSize > 0 {
                detail("Stored", ByteCountFormatter.string(fromByteCount: current.byteSize, countStyle: .file))
            }
            if current.files.count > 1 {
                detail("Files", "\(current.files.count)")
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(StickyPalette.textSecondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(StickyType.body)
    }

    private var actions: some View {
        VStack(spacing: StickySpace.s) {
            HStack(spacing: StickySpace.s) {
                StickyActionButton("Copy", symbol: "doc.on.doc") { library.copy(current) }
                StickyActionButton("Share", symbol: "square.and.arrow.up") { showingShare = true }
                if current.supportsCaption {
                    StickyActionButton(current.caption == nil ? "Caption" : "Edit", symbol: "text.bubble") { showingCaption = true }
                }
                if current.kind.isTextual || current.kind == .link {
                    StickyActionButton("Edit", symbol: "pencil") { showingEdit = true }
                }
            }
            if current.kind == .image || current.kind == .pdf || !current.files.isEmpty {
                Button {
                    previewURL = library.previewURL(for: current)
                } label: {
                    Label("Quick Look", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Button(role: .destructive) { showingDelete = true } label: {
                Label("Delete", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}
