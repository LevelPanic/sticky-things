import StickyCore
import SwiftUI

enum IOSTheme {
    static let paper = Color(red: 1.0, green: 0.91, blue: 0.55)
    static let paperInk = Color(red: 0.28, green: 0.19, blue: 0.05)
    static let accent = Color.accentColor
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let field = Color(uiColor: .tertiarySystemGroupedBackground)
    static let page = Color(uiColor: .systemGroupedBackground)
}

extension Tint {
    /// The note paper colors on iOS. The Mac palette is in StickyDesign, which is macOS-only.
    var iosPaper: Color {
        switch self {
        case .none: return IOSTheme.card
        case .yellow: return Color(red: 1.0, green: 0.91, blue: 0.55)
        case .orange: return Color(red: 1.0, green: 0.87, blue: 0.76)
        case .pink: return Color(red: 1.0, green: 0.85, blue: 0.90)
        case .purple: return Color(red: 0.91, green: 0.87, blue: 1.0)
        case .blue: return Color(red: 0.80, green: 0.91, blue: 1.0)
        case .green: return Color(red: 0.78, green: 0.95, blue: 0.78)
        }
    }

    var iosInk: Color { self == .none ? Color.primary : IOSTheme.paperInk }
    var iosSecondaryInk: Color {
        self == .none ? Color.secondary : IOSTheme.paperInk.opacity(0.72)
    }
}

extension Color {
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255,
                  opacity: 1)
    }
}

enum IOSDate {
    static func short(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if seconds < 6 * 86_400 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

extension ItemKind {
    var iosSymbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "textformat"
        case .link: return "link"
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .file: return "doc"
        case .folder: return "folder"
        case .files: return "doc.on.doc"
        case .color: return "paintpalette"
        case .other: return "shippingbox"
        }
    }
}
