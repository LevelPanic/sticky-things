import PhotosUI
import StickyCore
import SwiftUI
import UniformTypeIdentifiers

/// The iOS equivalent of the Mac composer: one screen, keyboard up, get it out of your head.
struct QuickCaptureView: View {
    @ObservedObject var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showFiles = false
    @State private var savingPhoto = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                editor
                actionBar
            }
            .background(IOSTheme.page)
            .navigationTitle("New Sticky Thing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
            }
            .onChange(of: photoItem) { _, selected in
                guard let selected else { return }
                loadPhoto(selected)
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                importFiles(result)
            }
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .focused($focused)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 190)
            if text.isEmpty {
                Text("Write a note, paste a link, or save a photo or file.")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(IOSTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.quaternary))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            PasteButton(supportedContentTypes: [.plainText, .url, .image, .pdf]) { providers in
                paste(providers)
            }
            Menu {
                Button { showPhotoPicker = true } label: {
                    Label("Photo", systemImage: "photo")
                }
                Button { showFiles = true } label: {
                    Label("File", systemImage: "folder")
                }
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Add a photo or file")
            Spacer(minLength: 4)
            Button {
                if library.addNote(text) { dismiss() }
            } label: {
                Label("Save", systemImage: "arrow.up.circle.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .fixedSize()
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || savingPhoto)
        }
        .font(.subheadline.weight(.medium))
        .buttonStyle(.bordered)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: Actions

    private func paste(_ providers: [NSItemProvider]) {
        Task {
            let clip = await ItemProviderCapture.clip(from: providers)
            let isText = clip.fileURLs.isEmpty && clip.stagedFiles.isEmpty
                && clip.firstData(UTI.images) == nil && clip.plainText != nil
            if isText, let string = clip.plainText {
                text += string
                focused = true
            } else {
                library.save(clip)
                dismiss()
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        savingPhoto = true
        Task {
            defer { savingPhoto = false }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                library.flash("Could not read that photo")
                return
            }
            let type = item.supportedContentTypes.first?.identifier ?? UTType.image.identifier
            library.saveImage(data, type: type)
            dismiss()
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }
            library.saveFiles(urls)
            dismiss()
        case .failure(let error):
            library.flash(error.localizedDescription)
        }
    }
}
