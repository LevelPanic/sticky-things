import StickyCore
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: item.kind.iosSymbol)
                        .foregroundStyle(.secondary)
                    Text(item.headline)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                TextEditor(text: $text)
                    .focused($focused)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 140)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(IOSTheme.field))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
                Text("Saved with the item, never inside the original file. Captions are searchable.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(IOSTheme.page)
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
