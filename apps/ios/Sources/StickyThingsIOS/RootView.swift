import CoreSpotlight
import PhotosUI
import QuickLook
import StickyCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RootView: View {
    @StateObject private var library = Library()
    @ObservedObject private var router = QuickCaptureRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("iosComposerDraft") private var draft = ""
    @FocusState private var composerFocused: Bool
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showFiles = false
    @State private var savingAttachment = false

    @State private var captionItem: Item?
    @State private var selectedItem: Item?
    @State private var previewURL: URL?
    @State private var shareItems: [Any] = []
    @State private var showingShare = false

    var body: some View {
        NavigationStack {
            Group {
                if !library.isReady {
                    loadingState
                } else if library.allItems.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .background(IOSTheme.page)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }
            .navigationTitle("Sticky Things")
            .searchable(text: $library.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search items")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
            }
            .sheet(item: $selectedItem) { item in
                ItemDetailView(item: item, library: library)
                    .presentationDetents([.large])
            }
            .sheet(item: $captionItem) { item in
                CaptionEditorView(item: item, library: library)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingShare) {
                ActivityView(items: shareItems)
                    .presentationDetents([.medium, .large])
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                importFiles(result)
            }
            .onChange(of: photoItem) { _, selected in
                guard let selected else { return }
                loadPhoto(selected)
            }
            .quickLookPreview($previewURL)
            .overlay(alignment: .bottom) {
                if let message = library.lastMessage {
                    toast(message)
                }
            }
            .dropDestination(for: String.self) { strings, _ in
                let text = strings.joined(separator: "\n")
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? false : library.addNote(text)
            }
            .dropDestination(for: URL.self) { urls, _ in
                accept(urls)
            }
            .onOpenURL { url in
                handle(url)
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                if let id = SpotlightIndexer.itemID(from: activity) {
                    selectedItem = library.item(id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .quickCapture)) { _ in
                router.request()
            }
            .onChange(of: router.token) { _, _ in
                if router.consume() { focusComposer() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, router.consume() { focusComposer() }
            }
            .onAppear {
                if router.consume() || CommandLine.arguments.contains("--composer") {
                    focusComposer()
                }
            }
            .task {
                await library.load()
                if CommandLine.arguments.contains("--detail"),
                   let item = library.allItems.first(where: { $0.kind == .image }) ?? library.allItems.first {
                    selectedItem = item
                }
                // A control can open the app before the intent's App Group flag is visible.
                for _ in 0..<4 {
                    if router.consume() {
                        focusComposer()
                        break
                    }
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
    }

    private func focusComposer() {
        composerFocused = true
    }

    // MARK: Content

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Opening your library…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        List {
            if !library.pinned.isEmpty {
                Section {
                    ForEach(library.pinned) { item in
                        row(item)
                    }
                } header: {
                    Text("Pinned")
                }
            }
            if !library.listItems.isEmpty {
                Section {
                    ForEach(library.listItems) { item in
                        row(item)
                    }
                } header: {
                    Text(library.isFiltering ? "Results" : "Recent")
                }
            } else if library.isFiltering {
                Section {
                    ContentUnavailableView(
                        "No Items",
                        systemImage: library.isSearching ? "magnifyingglass" : "line.3.horizontal.decrease.circle",
                        description: Text(library.isSearching ? "Nothing matches “\(library.search)”." : "Nothing in this filter yet.")
                    )
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func row(_ item: Item) -> some View {
        ItemRow(
            item: item,
            library: library,
            onOpen: { selectedItem = item },
            onEditCaption: { captionItem = item },
            onShare: { share(item) },
            onPreview: { preview(item) }
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func share(_ item: Item) {
        let items = library.shareItems(for: item)
        guard !items.isEmpty else { return }
        shareItems = items
        showingShare = true
    }

    private func preview(_ item: Item) {
        previewURL = library.previewURL(for: item)
    }

    // MARK: Composer

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !savingAttachment
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
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
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .menuIndicator(.hidden)
            .accessibilityLabel("Add a photo or file")

            TextField("Write a note…", text: $draft, axis: .vertical)
                .focused($composerFocused)
                .lineLimit(1...5)
                .font(.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(IOSTheme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.quaternary)
                )

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canSend ? .white : .secondary)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(canSend ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Save Note")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        composerFocused = true
        _ = library.addNote(text)
    }

    // MARK: Attachments

    private func loadPhoto(_ item: PhotosPickerItem) {
        savingAttachment = true
        Task {
            defer { savingAttachment = false }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                library.flash("Could not read that photo")
                return
            }
            let type = item.supportedContentTypes.first?.identifier ?? UTType.image.identifier
            library.saveImage(data, type: type)
            composerFocused = true
            photoItem = nil
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }
            library.saveFiles(urls)
        case .failure(let error):
            library.flash(error.localizedDescription)
        }
    }

    // MARK: Links

    private func handle(_ url: URL) {
        guard url.scheme == "stickythings" else { return }
        switch url.host() {
        case "new", "open":
            router.request()
        case "item":
            if let id = UUID(uuidString: url.lastPathComponent) {
                selectedItem = library.item(id)
            }
        default:
            break
        }
    }

    private func accept(_ urls: [URL]) -> Bool {
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty {
            let accessed = files.filter { $0.startAccessingSecurityScopedResource() }
            defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }
            library.saveFiles(files)
            return true
        }
        let links = urls.filter { !$0.isFileURL }.map(\.absoluteString)
        guard !links.isEmpty else { return false }
        return library.addNote(links.joined(separator: "\n"))
    }

    private var filterMenu: some View {
        Menu {
            Picker("Filter", selection: $library.filter) {
                Label("All", systemImage: "square.stack").tag(ItemFilter.all)
                Label("Notes", systemImage: "text.alignleft").tag(ItemFilter.notes)
                Label("Links", systemImage: "link").tag(ItemFilter.links)
                Label("Images", systemImage: "photo").tag(ItemFilter.images)
                Label("Files", systemImage: "doc").tag(ItemFilter.files)
            }
        } label: {
            Image(systemName: library.filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filter")
    }

    // MARK: Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 22) {
                MiniStickyNoteView()
                    .rotationEffect(.degrees(-5))
                    .padding(.top, 30)
                VStack(spacing: 10) {
                    Text("Nothing saved yet")
                        .font(.title2.weight(.semibold))
                    Text("Write a note below, or save a link, photo or file. It stays on this iPhone, in the same library format as the Mac app.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    tip("button.programmable", "Assign Sticky Things to the Action Button in Settings ▸ Action Button")
                    tip("switch.2", "Add the New Sticky Thing control to Control Center")
                    tip("square.and.arrow.up", "Or send anything here from another app with Share")
                    tip("hand.draw", "On iPad, drag items straight into the list")
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(IOSTheme.card))
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toast(_ message: String) -> some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.78)))
            .padding(.bottom, 76)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeOut(duration: 0.2), value: library.lastMessage)
    }
}

/// A drawn note for the empty state, matching the Mac app's little sticky.
struct MiniStickyNoteView: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(IOSTheme.paper)
                .frame(width: 92, height: 92)
                .shadow(color: .black.opacity(0.16), radius: 5, y: 3)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(IOSTheme.paperInk.opacity(0.18))
                        .frame(width: index == 3 ? 32 : 48, height: 4)
                }
            }
            .padding(.top, 28)
            .padding(.leading, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Path { path in
                path.move(to: CGPoint(x: 74, y: 0))
                path.addLine(to: CGPoint(x: 92, y: 0))
                path.addLine(to: CGPoint(x: 92, y: 18))
                path.closeSubpath()
            }
            .fill(Color.white.opacity(0.5))
            .frame(width: 92, height: 92)
        }
        .frame(width: 92, height: 92)
        .accessibilityHidden(true)
    }
}
