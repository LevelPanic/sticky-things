import Combine
import Foundation
import PDFKit
import QuickLookThumbnailing
import StickyCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

/// The iOS library: one local SQLite store, the same schema and item model as the Mac app.
@MainActor
final class Library: ObservableObject {
    let store: ItemStore
    let capture: CaptureService

    @Published var search = ""
    @Published var filter: ItemFilter = .all
    @Published private(set) var lastMessage: String?

    private var cancellables = Set<AnyCancellable>()
    private var toastWork: DispatchWorkItem?

    init() {
        do {
            store = try ItemStore(paths: StickyAppGroup.paths)
        } catch {
            store = try! ItemStore(paths: .temporary(), inMemory: true)
        }
        capture = CaptureService(store: store)
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        LegacyImporter.importIfNeeded(into: store)
        store.collectGarbage()
        SpotlightIndexer.shared.reindex(store.items, store: store)
        #if DEBUG
        DemoContent.seedIfRequested(in: self)
        #endif
    }

    var isFiltering: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filter != .all
    }

    var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var items: [Item] {
        store.search(search, filter: filter)
    }

    var pinned: [Item] {
        items.filter(\.pinned)
    }

    /// Newest first, with pinned items in their own section unless you are searching.
    var listItems: [Item] {
        isFiltering ? items : items.filter { !$0.pinned }
    }

    // MARK: Saving

    @discardableResult
    func addNote(_ text: String) -> Bool {
        guard let outcome = capture.saveNote(text) else {
            flash("Write something first")
            return false
        }
        return handle(outcome)
    }

    func saveImage(_ data: Data, type: String) {
        let clip = CapturedClip(elements: [.init(entries: [.init(type: type, data: data)])])
        save(clip)
    }

    /// URLs must have their security scope open while this runs.
    func saveFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let elements = urls.map { CapturedClip.Element(entries: [], fileURL: $0) }
        save(CapturedClip(elements: elements))
    }

    func save(_ clip: CapturedClip) {
        do {
            _ = handle(try capture.save(clip, source: nil))
        } catch {
            flash(error.localizedDescription)
        }
    }

    @discardableResult
    private func handle(_ outcome: CaptureService.Outcome) -> Bool {
        switch outcome {
        case .saved(let items):
            flash(items.count > 1 ? "Saved \(items.count) items" : "Saved")
            SpotlightIndexer.shared.reindex(store.items, store: store)
            WidgetCenter.shared.reloadAllTimelines()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        case .duplicate:
            flash("Already saved")
            return true
        case .pending:
            return false
        }
    }

    // MARK: Actions

    func copy(_ item: Item) {
        let pasteboard = UIPasteboard.general
        switch item.kind {
        case .text, .richText, .other, .color:
            pasteboard.string = item.text
        case .link:
            if let string = item.link?.url, let url = URL(string: string) {
                pasteboard.url = url
            } else {
                pasteboard.string = item.text
            }
        case .image:
            if let (type, data) = firstData(in: item, types: UTI.images) {
                pasteboard.setData(data, forPasteboardType: type)
            } else {
                flash("The image is missing")
                return
            }
        case .pdf:
            if let (_, data) = firstData(in: item, types: [UTI.pdf]) {
                pasteboard.setData(data, forPasteboardType: UTI.pdf)
            } else if let url = item.files.first.flatMap(store.files.url(for:)) {
                pasteboard.url = url
            }
        case .file, .folder, .files:
            if let url = item.files.first.flatMap(store.files.url(for:)) {
                pasteboard.url = url
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        flash("Copied")
    }

    func delete(_ item: Item) {
        store.delete(item.id)
        SpotlightIndexer.shared.remove(item.id)
        WidgetCenter.shared.reloadAllTimelines()
        flash(item.kind.isTextual ? "Note deleted" : "Item deleted")
    }

    func togglePin(_ item: Item) {
        store.togglePin(item.id)
        SpotlightIndexer.shared.reindex(store.items, store: store)
        WidgetCenter.shared.reloadAllTimelines()
        flash(item.pinned ? "Unpinned" : "Pinned")
    }

    func setCaption(_ item: Item, to text: String) {
        store.setCaption(item.id, to: text)
        SpotlightIndexer.shared.reindex(store.items, store: store)
        WidgetCenter.shared.reloadAllTimelines()
        flash(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Caption removed" : "Caption saved")
    }

    func updateText(_ item: Item, to text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.setText(item.id, to: text)
        SpotlightIndexer.shared.reindex(store.items, store: store)
        WidgetCenter.shared.reloadAllTimelines()
        flash("Note saved")
    }

    func fileURL(for item: Item) -> URL? {
        item.files.first.flatMap(store.files.url(for:))
    }

    /// A real file for Quick Look, ShareLink and the system share sheet. Images and PDFs with
    /// only blob data are written to a temporary preview file.
    func previewURL(for item: Item) -> URL? {
        if let url = fileURL(for: item) { return url }
        if let (type, data) = firstData(in: item, types: UTI.images) {
            return materialize(data, type: type, item: item)
        }
        if let (type, data) = firstData(in: item, types: [UTI.pdf]) {
            return materialize(data, type: type, item: item)
        }
        if item.kind.isTextual || item.kind == .link || item.kind == .color || item.kind == .other {
            let text = item.kind == .link ? (item.link?.url ?? item.text) : item.text
            return materialize(Data(text.utf8), type: UTI.utf8Text, item: item)
        }
        return nil
    }

    func shareItems(for item: Item) -> [Any] {
        switch item.kind {
        case .text, .richText, .other, .color:
            return [item.text]
        case .link:
            return item.link.flatMap { URL(string: $0.url) }.map { [$0] } ?? [item.text]
        case .image:
            if let url = previewURL(for: item) { return [url] }
            if let (_, data) = firstData(in: item, types: UTI.images), let image = UIImage(data: data) { return [image] }
            return []
        case .pdf, .file, .folder, .files:
            let urls = item.files.compactMap { store.files.url(for: $0) }
            if !urls.isEmpty { return urls }
            return previewURL(for: item).map { [$0] } ?? []
        }
    }

    func itemProvider(for item: Item) -> NSItemProvider {
        if let url = previewURL(for: item), let provider = NSItemProvider(contentsOf: url) {
            return provider
        }
        return NSItemProvider(object: item.headline as NSString)
    }

    private func materialize(_ data: Data, type: String, item: Item) -> URL? {
        let ext = UTType(type)?.preferredFilenameExtension ?? "dat"
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("StickyThingsPreview", isDirectory: true)
            .appendingPathComponent(item.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("preview").appendingPathExtension(ext)
        if !FileManager.default.fileExists(atPath: url.path) {
            guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        }
        return url
    }

    // MARK: Thumbnails

    func thumbnail(for item: Item) async -> UIImage? {
        if let file = item.files.first, let url = store.files.url(for: file) {
            if item.kind == .pdf || item.kind == .image {
                if let image = UIImage(contentsOfFile: url.path) { return image }
                return await quickLookThumbnail(url)
            }
            return await quickLookThumbnail(url)
        }
        if let (_, data) = firstData(in: item, types: UTI.images) {
            return UIImage(data: data)
        }
        if let (_, data) = firstData(in: item, types: [UTI.pdf]) {
            return PDFDocument(data: data)?.page(at: 0)?.thumbnail(of: CGSize(width: 800, height: 800), for: .cropBox)
        }
        return nil
    }

    private func firstData(in item: Item, types: [String]) -> (String, Data)? {
        for snap in item.snapshot {
            for type in types {
                if let rep = snap.representation(type), let data = store.blobs.data(rep.blob) {
                    return (type, data)
                }
            }
        }
        return nil
    }

    private func quickLookThumbnail(_ url: URL) async -> UIImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 600, height: 600),
                                                   scale: UIScreen.main.scale, representationTypes: [.thumbnail, .icon])
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.uiImage)
            }
        }
    }

    // MARK: Feedback

    func flash(_ message: String) {
        lastMessage = message
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                withAnimation(.easeOut(duration: 0.2)) { self.lastMessage = nil }
            }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }
}
