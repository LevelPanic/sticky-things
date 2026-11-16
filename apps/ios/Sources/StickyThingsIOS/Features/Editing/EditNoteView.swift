import StickyCore
import StickyIOSDesign
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
                .font(StickyType.body)
                .scrollContentBackground(.hidden)
                .padding(StickySpace.s)
                .stickyField(radius: StickyRadius.action, fill: StickyPalette.surfaceSunken)
                .padding(StickyMetrics.contentInset)
                .background(StickyPalette.page)
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
