#if os(iOS)
import Foundation
import UniformTypeIdentifiers

/// Turns the item providers from a share sheet, a drop, or the system Paste button into the
/// same `CapturedClip` the Mac pasteboard capture produces.
public enum ItemProviderCapture {
    public static func clip(from providers: [NSItemProvider]) async -> CapturedClip {
        var elements: [CapturedClip.Element] = []
        var stagedFiles: [URL] = []

        for provider in providers {
            if let file = await fileURL(from: provider) {
                elements.append(.init(entries: [], fileURL: file))
                continue
            }
            if let image = await imageData(from: provider) {
                elements.append(.init(entries: [.init(type: image.type, data: image.data)]))
                continue
            }
            if let url = await url(from: provider) {
                elements.append(.init(entries: [
                    .init(type: UTI.url, data: Data(url.absoluteString.utf8)),
                    .init(type: UTI.utf8Text, data: Data(url.absoluteString.utf8)),
                ]))
                continue
            }
            if let text = await text(from: provider) {
                elements.append(.init(entries: [.init(type: UTI.utf8Text, data: Data(text.utf8))]))
                continue
            }
            if let file = await fileRepresentation(from: provider) {
                stagedFiles.append(file)
            }
        }
        return CapturedClip(elements: elements, stagedFiles: stagedFiles)
    }

    // MARK: Providers

    private static func text(from provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { return nil }
        return await load(provider, UTType.plainText.identifier) as? String
    }

    private static func url(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return nil }
        let value = await load(provider, UTType.url.identifier)
        if let url = value as? URL { return url }
        if let url = value as? NSURL { return url as URL }
        if let data = value as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        return nil
    }

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        let value = await load(provider, UTType.fileURL.identifier)
        if let url = value as? URL, url.isFileURL { return url }
        if let url = value as? NSURL, url.isFileURL { return url as URL }
        if let data = value as? Data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
            return url
        }
        return nil
    }

    private static func imageData(from provider: NSItemProvider) async -> (type: String, data: Data)? {
        let type = provider.registeredTypeIdentifiers.first { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        } ?? (provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ? UTType.image.identifier : nil)
        guard let type else { return nil }
        let data = await loadData(provider, type)
        return data.map { (type, $0) }
    }

    /// For files that arrive as data rather than a file URL, copy the provider's temporary file
    /// into our staging area before the provider removes it.
    private static func fileRepresentation(from provider: NSItemProvider) async -> URL? {
        let type = provider.registeredTypeIdentifiers.first { identifier in
            guard let uti = UTType(identifier) else { return false }
            return uti.conforms(to: .data) || uti.conforms(to: .item)
        }
        guard let type else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                guard let url else { continuation.resume(returning: nil); return }
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("StickyShare-\(UUID().uuidString)", isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = folder.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: destination)
                continuation.resume(returning: destination)
            }
        }
    }

    // MARK: Loading

    private static func load(_ provider: NSItemProvider, _ type: String) async -> NSSecureCoding? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    private static func loadData(_ provider: NSItemProvider, _ type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
#endif
