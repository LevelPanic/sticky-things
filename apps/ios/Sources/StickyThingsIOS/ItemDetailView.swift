import QuickLook
import StickyCore
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

    private var current: Item { library.store.item(item.id) ?? item }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        content
                        if let caption = current.caption, !caption.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Caption").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(caption).font(.body).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(IOSTheme.card))
                        }
                        details
                        actions
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .frame(width: proxy.size.width)
                }
            }
            .background(IOSTheme.page)
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
        HStack(spacing: 12) {
            Image(systemName: current.kind.iosSymbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(current.kind.label).font(.headline)
                Text(current.source?.name.map { "\($0) · \(IOSDate.short(current.createdAt))" } ?? IOSDate.short(current.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if current.pinned {
                Image(systemName: "pin.fill").foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch current.kind {
        case .text, .richText:
            Text(current.text)
                .font(.body)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(current.tint.iosPaper))
                .foregroundStyle(current.tint.iosInk)
        case .image, .pdf:
            ItemThumbnailView(item: current, library: library)
                .containerRelativeFrame(.horizontal) { length, _ in max(0, length - 32) }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture { previewURL = library.previewURL(for: current) }
        case .link:
            if let url = current.link.flatMap({ URL(string: $0.url) }) {
                Link(destination: url) {
                    Label(current.link?.title ?? url.host() ?? "Open Link", systemImage: "arrow.up.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(IOSTheme.card))
            }
        default:
            HStack(spacing: 14) {
                Image(systemName: current.kind.iosSymbol)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(IOSTheme.field))
                VStack(alignment: .leading, spacing: 4) {
                    Text(current.headline).font(.body.weight(.semibold)).lineLimit(2)
                    Text(current.files.map(\.name).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(IOSTheme.card))
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                action("Copy", symbol: "doc.on.doc") { library.copy(current) }
                action("Share", symbol: "square.and.arrow.up") { showingShare = true }
                if current.supportsCaption {
                    action(current.caption == nil ? "Caption" : "Edit", symbol: "text.bubble") { showingCaption = true }
                }
                if current.kind.isTextual || current.kind == .link {
                    action("Edit", symbol: "pencil") { showingEdit = true }
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

    private func action(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                Text(title).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
    }
}
