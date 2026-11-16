import AppKit
import StickyCore

/// Everything the corner and the panel accept as a drop.
///
/// AppKit matches registered types exactly (no UTI conformance), so the list spells out the
/// common concrete types, the legacy aliases apps still use, and file promises (Photos, Mail,
/// Safari images…). Once a drop is accepted we capture *every* type on it, not just these.
enum DropTypes {
    static let all: [NSPasteboard.PasteboardType] = {
        var types: [NSPasteboard.PasteboardType] = [
            .fileURL, .URL, .string, .rtf, .rtfd, .html, .png, .tiff, .pdf, .color, .tabularText,
            .init(UTI.jpeg), .init(UTI.heic), .init(UTI.gif), .init(UTI.webp), .init("public.image"),
            .init("com.apple.webarchive"), .init("public.url-name"), .init(UTI.utf16Text),
            .init("public.plain-text"), .init("public.text"), .init("public.data"), .init("public.content"),
            .init("public.item"), .init("public.movie"), .init("public.audio"), .init("public.vcard"),
            .init("com.apple.pasteboard.promised-file-url"), .init("com.apple.NSFilePromiseItemMetaData"),
            .init("NSFilenamesPboardType"), .init("NSStringPboardType"), .init("Apple URL pasteboard type"),
            .init("Apple PDF pasteboard type"), .init("NeXT TIFF v4.0 pasteboard type"),
            .init("Apple PNG pasteboard type"), .init("NeXT Rich Text Format v1.0 pasteboard type"),
        ]
        types += NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        var seen = Set<String>()
        return types.filter { seen.insert($0.rawValue).inserted }
    }()

    /// The app a drag most likely came from (it's frontmost while you drag out of it).
    @MainActor
    static func currentSourceApp() -> SourceApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return SourceApp(bundleID: app.bundleIdentifier, name: app.localizedName)
    }
}
