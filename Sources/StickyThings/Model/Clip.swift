import AppKit
import UniformTypeIdentifiers

/// Something that was pasted or dropped, before it becomes a Note.
enum ClipContent: Equatable {
    case text(String)
    case link(URL)
    case image(Data) // PNG data
    case files([URL])

    var isText: Bool {
        switch self {
        case .text, .link: return true
        default: return false
        }
    }
}

enum Clip {
    /// Read whatever is on a pasteboard (clipboard or drag) in priority order:
    /// files → images → links → text.
    static func read(from pasteboard: NSPasteboard) -> [ClipContent] {
        // 1. Files copied in Finder (or dragged).
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return [.files(Array(urls.prefix(25)))]
        }

        let string = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stringIsLink = string.flatMap(linkURL(from:)) != nil

        // 2. Image data (screenshots, "Copy Image" in browsers). Spreadsheets also put a
        //    picture on the pasteboard, so real text wins unless it is just the image's URL.
        if string == nil || string!.isEmpty || stringIsLink, let png = imagePNG(from: pasteboard) {
            return [.image(png)]
        }

        // 3. Text / links.
        if let string, !string.isEmpty {
            if let url = linkURL(from: string) { return [.link(url)] }
            return [.text(string)]
        }

        // 4. A bare URL without a string representation.
        if let url = NSURL(from: pasteboard) as URL?, !url.isFileURL {
            return [.link(url)]
        }
        return []
    }

    /// Returns a URL when the whole string is a single web/mail link.
    static func linkURL(from string: String) -> URL? {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count < 4000, !s.contains(where: { $0.isWhitespace }) else { return nil }
        var candidate = s
        if s.lowercased().hasPrefix("www.") { candidate = "https://" + s }
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "http", "https":
            guard let host = url.host(), host.contains(".") || host == "localhost" else { return nil }
            return url
        case "mailto", "tel", "facetime", "ftp", "sftp", "ssh", "vscode", "slack", "zoommtg", "notion", "obsidian", "x-apple.systempreferences":
            return url
        default:
            return nil
        }
    }

    static func imagePNG(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier),
            NSPasteboard.PasteboardType(UTType.heic.identifier), NSPasteboard.PasteboardType(UTType.gif.identifier),
            NSPasteboard.PasteboardType(UTType.webP.identifier),
        ]
        for type in imageTypes {
            if let data = pasteboard.data(forType: type), let png = pngData(from: data) { return png }
        }
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
           let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation {
            return pngData(from: tiff)
        }
        return nil
    }

    static func pngData(from data: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Pasteboard types we accept for drops.
    static let dropTypes: [NSPasteboard.PasteboardType] = [
        .fileURL, .URL, .string, .png, .tiff, .rtf, .html,
        NSPasteboard.PasteboardType(UTType.jpeg.identifier),
        NSPasteboard.PasteboardType(UTType.heic.identifier),
    ]
}
