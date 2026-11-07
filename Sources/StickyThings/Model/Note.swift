import Foundation
import SwiftUI

/// What kind of thing a note holds.
enum NoteKind: String, Codable {
    case text, link, image, file
}

/// Optional sticky-note tint for a card.
enum NoteColor: String, Codable, CaseIterable, Identifiable {
    case none, yellow, orange, pink, purple, blue, green

    var id: String { rawValue }

    var name: String {
        switch self {
        case .none: return "No Color"
        default: return rawValue.capitalized
        }
    }

    /// Paper color used behind the card's content.
    var paper: Color? {
        switch self {
        case .none: return nil
        case .yellow: return Color(red: 1.00, green: 0.88, blue: 0.40)
        case .orange: return Color(red: 1.00, green: 0.74, blue: 0.45)
        case .pink: return Color(red: 1.00, green: 0.70, blue: 0.80)
        case .purple: return Color(red: 0.80, green: 0.72, blue: 1.00)
        case .blue: return Color(red: 0.62, green: 0.82, blue: 1.00)
        case .green: return Color(red: 0.66, green: 0.92, blue: 0.66)
        }
    }

    /// Small dot used in menus.
    var swatch: Color { paper ?? .secondary }
}

struct Note: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: NoteKind
    /// text: the note body · link: absolute URL string · file: absolute path · image: optional caption
    var text: String
    /// link: fetched page title
    var title: String? = nil
    /// image notes: file name of the stored image inside the media folder
    var imageFile: String? = nil
    /// link notes: file name of the fetched site icon inside the media folder
    var iconFile: String? = nil
    /// file notes: bookmark so moved files can still be found
    var bookmark: Data? = nil
    /// image notes: pixel dimensions
    var pixelWidth: Int? = nil
    var pixelHeight: Int? = nil
    /// image notes: content hash used to avoid duplicates
    var contentHash: String? = nil
    var color: NoteColor = .none
    var pinned: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var url: URL? {
        switch kind {
        case .link: return URL(string: text)
        case .file: return URL(fileURLWithPath: text)
        default: return nil
        }
    }

    /// One-line label used for pinned chips, menus and accessibility.
    var shortTitle: String {
        switch kind {
        case .text:
            let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            return line.trimmingCharacters(in: .whitespaces)
        case .link:
            if let title, !title.isEmpty { return title }
            return url?.host() ?? text
        case .image:
            if !text.isEmpty { return text }
            if let w = pixelWidth, let h = pixelHeight { return "Image \(w)×\(h)" }
            return "Image"
        case .file:
            return (text as NSString).lastPathComponent
        }
    }

    /// Text that search matches against.
    var searchableText: String {
        [text, title ?? "", kind == .file ? (text as NSString).lastPathComponent : "", kind.rawValue]
            .joined(separator: " ")
    }
}
