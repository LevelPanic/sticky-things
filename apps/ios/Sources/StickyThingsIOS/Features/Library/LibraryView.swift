import CoreSpotlight
import PhotosUI
import QuickLook
import StickyCore
import StickyIOSDesign
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
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
                    EmptyLibraryView()
                } else {
                    content
                }
            }
            .background(StickyPalette.page)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ComposerBar(text: $draft, focused: $composerFocused, isBusy: savingAttachment,
                            onSend: send, onPhoto: { showPhotoPicker = true }, onFile: { showFiles = true })
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
                    StickyToastView(text: message)
                        .padding(.bottom, StickyMetrics.toastBottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(StickyMotion.standard, value: library.lastMessage)
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
            .onChange(of: router.token) { _, _ in
                if router.consume() { focusComposer() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, router.consume() { focusComposer() }
            }
            .onAppear {
                #if DEBUG
                if CommandLine.arguments.contains("--draft") {
                    draft = "Book the table for Friday at 7"
                }
                #endif
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
        VStack(spacing: StickySpace.s) {
            ProgressView()
            Text("Opening your library…")
                .font(StickyType.meta)
                .foregroundStyle(StickyPalette.textSecondary)
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
        .listRowInsets(EdgeInsets(top: StickySpace.xs, leading: StickyMetrics.contentInset,
                                  bottom: StickySpace.xs, trailing: StickyMetrics.contentInset))
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
}
