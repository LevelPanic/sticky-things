import StickyIOSDesign
import SwiftUI

/// The library's persistent ChatGPT-style composer. It is intentionally not a sheet.
struct ComposerBar: View {
    @Binding var text: String
    @FocusState.Binding var focused: Bool
    var isBusy: Bool
    let onSend: () -> Void
    let onPhoto: () -> Void
    let onFile: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: StickySpace.s) {
            Menu {
                Button(action: onPhoto) {
                    Label("Photo", systemImage: "photo")
                }
                Button(action: onFile) {
                    Label("File", systemImage: "folder")
                }
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: StickyMetrics.glyph, weight: .medium))
                    .foregroundStyle(StickyPalette.textSecondary)
                    .frame(width: StickyMetrics.touch, height: StickyMetrics.touch)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .accessibilityLabel("Add a photo or file")

            TextField("Write a note…", text: $text, axis: .vertical)
                .focused($focused)
                .lineLimit(1...5)
                .font(StickyType.body)
                .padding(.horizontal, StickySpace.m)
                .padding(.vertical, StickySpace.s)
                .frame(minHeight: StickyMetrics.composerField)
                .stickyField()

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: StickyMetrics.glyph, weight: .semibold))
                    .foregroundStyle(canSend ? StickyPalette.toastText : StickyPalette.textTertiary)
                    .frame(width: StickyMetrics.composerSend, height: StickyMetrics.composerSend)
                    .background(
                        Circle().fill(canSend ? StickyPalette.accent : StickyPalette.surfaceSunken)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Save Note")
        }
        .padding(.horizontal, StickySpace.m)
        .padding(.vertical, StickySpace.s)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
