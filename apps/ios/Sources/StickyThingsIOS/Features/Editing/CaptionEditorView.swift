import StickyCore
import StickyIOSDesign
import SwiftUI

/// Add text to an image, PDF or file. The same `Item.caption` field as the Mac app.
struct CaptionEditorView: View {
    let item: Item
    @ObservedObject var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @FocusState private var focused: Bool

    init(item: Item, library: Library) {
        self.item = item
        self.library = library
        _text = State(initialValue: item.caption ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: StickySpace.m) {
                HStack(spacing: StickySpace.s) {
                    Image(systemName: StickyKind.symbol(for: item.kind))
                        .foregroundStyle(StickyPalette.textSecondary)
                    Text(item.headline)
                        .font(StickyType.button)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                TextEditor(text: $text)
                    .focused($focused)
                    .font(StickyType.body)
                    .scrollContentBackground(.hidden)
                    .padding(StickySpace.s)
                    .frame(minHeight: StickyMetrics.detailThumbnail * 0.5)
                    .stickyField(radius: StickyRadius.action, fill: StickyPalette.surfaceSunken)
                Text("Saved with the item, never inside the original file. Captions are searchable.")
                    .font(StickyType.meta)
                    .foregroundStyle(StickyPalette.textSecondary)
            }
            .padding(StickyMetrics.contentInset)
            .background(StickyPalette.page)
            .navigationTitle(item.caption == nil ? "Add Caption" : "Edit Caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        library.setCaption(item, to: text)
                        dismiss()
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
            }
        }
    }
}
