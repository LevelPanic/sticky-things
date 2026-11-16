#if canImport(UIKit)
import StickyCore
import SwiftUI
import UIKit

// MARK: - Spacing

public enum StickySpace {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

// MARK: - Radii

public enum StickyRadius {
    public static let xs: CGFloat = 6
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 18
    public static let xl: CGFloat = 24
    /// Text fields and the composer.
    public static let field: CGFloat = 22
    public static let action: CGFloat = 14
}

// MARK: - Sizes

public enum StickyMetrics {
    /// The system minimum touch target.
    public static let touch: CGFloat = 44
    public static let iconButton: CGFloat = 32
    public static let glyph: CGFloat = 17
    public static let rowIcon: CGFloat = 40
    public static let detailIcon: CGFloat = 48
    public static let thumbnail: CGFloat = 180
    public static let detailThumbnail: CGFloat = 280
    public static let miniNote: CGFloat = 92
    public static let actionTile: CGFloat = 52
    public static let composerSend: CGFloat = 34
    public static let composerField: CGFloat = 44
    public static let toastBottom: CGFloat = 76
    public static let cardPadding: CGFloat = 16
    public static let cardGap: CGFloat = 12
    public static let contentInset: CGFloat = 16
    public static let bodyLineSpacing: CGFloat = 3
    public static let widgetImage: CGFloat = 42
    public static let widgetIcon: CGFloat = 28
    public static let widgetItemLimit = 6
}

// MARK: - Type
// Semantic sizes only, so Dynamic Type keeps working. Nothing below 11 pt.

public enum StickyType {
    public static let title = Font.title2.weight(.semibold)
    public static let cardTitle = Font.headline
    public static let body = Font.body
    public static let meta = Font.caption
    public static let section = Font.caption.weight(.semibold)
    public static let button = Font.subheadline.weight(.medium)
    public static let widgetHeader = Font.caption.weight(.semibold)
    public static let widgetRow = Font.subheadline.weight(.medium)
    public static let widgetMeta = Font.caption2
}

// MARK: - Motion

public enum StickyMotion {
    public static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    public static var quick: Animation {
        reduceMotion ? .easeInOut(duration: 0.1) : .easeOut(duration: 0.12)
    }

    public static var standard: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .easeOut(duration: 0.22)
    }

    public static var emphasized: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.28)
    }
}

// MARK: - Palette

public enum StickyPalette {
    public static let page = Color(uiColor: .systemGroupedBackground)
    public static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    public static let surfaceRaised = Color(uiColor: .secondarySystemBackground)
    public static let surfaceSunken = Color(uiColor: .tertiarySystemGroupedBackground)
    /// A translucent fill for icon plates and rows that sit on top of brand paper.
    public static let subduedFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.black.withAlphaComponent(0.06)
    })
    public static let separator = Color(uiColor: .separator)
    public static let border = Color(uiColor: .separator).opacity(0.55)

    public static let textPrimary = Color(uiColor: .label)
    public static let textSecondary = Color(uiColor: .secondaryLabel)
    public static let textTertiary = Color(uiColor: .tertiaryLabel)
    public static let hint = Color(uiColor: .placeholderText)

    public static let accent = Color.accentColor
    public static let danger = Color(uiColor: .systemRed)
    public static let success = Color(uiColor: .systemGreen)
    public static let warning = Color(uiColor: .systemOrange)

    public static let toast = Color(uiColor: .label)
    public static let toastText = Color(uiColor: .systemBackground)

    // The sticky note itself. It stays a surface, never a text color.
    public static let paper = dynamic(light: 0xFFE88B, dark: 0x4A4225)
    public static let paperInk = dynamic(light: 0x47300C, dark: 0xF2EDE2)
    public static let paperInkSecondary = dynamic(light: 0x6C4F25, dark: 0xC9C2B4)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

public enum StickyTintPalette {
    public static func paper(_ tint: Tint) -> Color {
        switch tint {
        case .none: return StickyPalette.surface
        case .yellow: return dynamic(light: 0xFFE88B, dark: 0x4A4225)
        case .orange: return dynamic(light: 0xFFDEC2, dark: 0x4A3828)
        case .pink: return dynamic(light: 0xFFD9E6, dark: 0x4A2B35)
        case .purple: return dynamic(light: 0xE9DEFF, dark: 0x3D3450)
        case .blue: return dynamic(light: 0xCCE9FF, dark: 0x233D4F)
        case .green: return dynamic(light: 0xC6F3C6, dark: 0x24402A)
        }
    }

    public static func ink(_ tint: Tint) -> Color {
        tint == .none ? StickyPalette.textPrimary : StickyPalette.paperInk
    }

    public static func secondaryInk(_ tint: Tint) -> Color {
        tint == .none ? StickyPalette.textSecondary : StickyPalette.paperInkSecondary
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

// MARK: - Item presentation

public enum StickyKind {
    public static func symbol(for kind: ItemKind) -> String {
        switch kind {
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

// MARK: - Dates

public enum StickyRelativeTime {
    public static func short(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if seconds < 6 * 86_400 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    public static func compact(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }
}

// MARK: - Colors from stored hex

public extension Color {
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

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
#endif
