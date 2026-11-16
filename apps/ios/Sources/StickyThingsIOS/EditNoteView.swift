import StickyCore
import SwiftUI

struct EditNoteView: View {
    let item: Item
    @ObservedObject var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @FocusState private var focused: Bool

    init(item: Item, library: Library) {
        self.item = item
        self.library = library
        _text = State(initialValue: item.text)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($focused)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(IOSTheme.field))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
                .padding(16)
                .background(IOSTheme.page)
                .navigationTitle("Edit Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            library.updateText(item, to: text)
                            dismiss()
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
                }
        }
    }
}
