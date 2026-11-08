import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Decides how a capture is *shown*. Pure: never touches disk, so it is easy to test.
public enum Classifier {
    public struct Result: Equatable {
        public var kind: ItemKind
        public var text: String
        public var title: String?
        public var link: LinkInfo?
        public var pixelSize: PixelSize?
        public var pageCount: Int?
    }

    public static func classify(_ clip: CapturedClip) -> Result {
        let files = clip.fileURLs + clip.stagedFiles
        if !files.isEmpty { return classifyFiles(files) }

        let string = clip.plainText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = !(string ?? "").isEmpty
        let link = string.flatMap(singleLink(in:))

        // Images: screenshots, "Copy Image" (which often adds the image's URL as text) and
        // selections copied in Preview. Spreadsheets also add a picture, so real text wins.
        if let image = clip.firstData(UTI.images), !hasText || link != nil {
            return Result(kind: .image, text: link?.absoluteString ?? "", title: nil, link: nil,
                          pixelSize: pixelSize(of: image.data))
        }
        if let pdf = clip.firstData([UTI.pdf]), !hasText {
            return Result(kind: .pdf, text: "", title: nil, pageCount: pageCount(of: pdf.data))
        }
        if let link, let string {
            return Result(kind: .link, text: string, title: nil, link: LinkInfo(url: link.absoluteString))
        }
        if hasText, let string {
            let isRich = clip.firstData(UTI.richText) != nil
            return Result(kind: isRich ? .richText : .text, text: string, title: nil)
        }
        if let urlData = clip.firstData([UTI.url])?.data, let url = URL(dataRepresentation: urlData, relativeTo: nil) {
            return Result(kind: .link, text: url.absoluteString, title: nil, link: LinkInfo(url: url.absoluteString))
        }
        if let rich = clip.firstData(UTI.richText), let text = plainText(fromRich: rich.data, type: rich.type), !text.isEmpty {
            return Result(kind: .richText, text: text, title: nil)
        }
        if let colorData = clip.firstData([UTI.color])?.data, let description = colorDescription(colorData) {
            return Result(kind: .color, text: description, title: nil)
        }
        let types = clip.elements.flatMap(\.types).filter { !$0.hasPrefix("dyn.") }
        return Result(kind: .other, text: types.prefix(6).joined(separator: ", "), title: nil)
    }

    static func classifyFiles(_ urls: [URL]) -> Result {
        guard urls.count == 1, let url = urls.first else {
            return Result(kind: .files, text: urls.map(\.lastPathComponent).joined(separator: "\n"), title: nil)
        }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        let name = url.lastPathComponent
        if values?.isDirectory == true, type?.conforms(to: .package) != true {
            return Result(kind: .folder, text: name, title: name)
        }
        if type?.conforms(to: .pdf) == true {
            let pages = CGPDFDocument(url as CFURL)?.numberOfPages
            return Result(kind: .pdf, text: name, title: name, pageCount: pages)
        }
        if type?.conforms(to: .image) == true {
            return Result(kind: .image, text: name, title: name, pixelSize: pixelSize(at: url))
        }
        return Result(kind: .file, text: name, title: name)
    }

    /// A URL when the whole string is one web/mail/app link.
    public static func singleLink(in string: String) -> URL? {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count < 4000, !s.contains(where: \.isWhitespace) else { return nil }
        let candidate = s.lowercased().hasPrefix("www.") ? "https://" + s : s
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "http", "https":
            guard let host = url.host(), host.contains(".") || host == "localhost" else { return nil }
            return url
        case "file":
            return nil // file paths as text stay text
        default:
            // mailto:, tel:, slack://, notion://, obsidian://, x-apple.systempreferences: …
            return scheme.count > 1 && scheme.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) }) && s.contains(":") ? url : nil
        }
    }

    public static func pixelSize(of data: Data) -> PixelSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return pixelSize(source)
    }

    public static func pixelSize(at url: URL) -> PixelSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return pixelSize(source)
    }

    private static func pixelSize(_ source: CGImageSource) -> PixelSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return PixelSize(width: w, height: h)
    }

    public static func pageCount(of pdf: Data) -> Int? {
        guard let provider = CGDataProvider(data: pdf as CFData) else { return nil }
        return CGPDFDocument(provider)?.numberOfPages
    }

    /// Plain text from RTF/RTFD/HTML. HTML parsing is skipped for very large documents.
    public static func plainText(fromRich data: Data, type: String) -> String? {
        switch type {
        case UTI.rtf, "NeXT Rich Text Format v1.0 pasteboard type":
            return NSAttributedString(rtf: data, documentAttributes: nil)?.string
        case UTI.rtfd:
            return NSAttributedString(rtfd: data, documentAttributes: nil)?.string
        case UTI.html:
            // Never run WebKit's HTML importer here: it can hang and fetch remote images.
            return stripTags(data)
        default:
            return nil
        }
    }

    private static func stripTags(_ data: Data) -> String? {
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        let withoutHead = html.replacingOccurrences(of: "(?s)<(script|style|head)[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
        return withoutHead.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func colorDescription(_ data: Data) -> String? {
        guard let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data),
              let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }
}
