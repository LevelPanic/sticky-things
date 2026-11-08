import AppKit
import SwiftUI

/// Semantic colors. Neutrals are tinted warm (paper), never flat gray; the brand signature is
/// sticky-note yellow; selection and focus use the system accent color like every Mac app.
/// Every text/background pair here is checked for contrast in `StickyDesignTests`.
public enum Palette {
    // Surfaces (OKLCH-derived, hue 95 = paper, chroma ≤ 0.008: neutral, not cream)
    public static let surface = Swatch(light: 0xF1F0ED, dark: 0x1A1917)         // opaque panel fallback
    public static let surfaceRaised = Swatch(light: 0xFDFCFA, dark: 0x2F2E2A)   // cards, composer
    public static let surfaceRaisedHover = Swatch(light: 0xF6F6F3, dark: 0x373733)
    public static let surfaceSunken = Swatch(light: 0xEEEDE9, dark: 0x1F1E1B)   // wells, search
    public static let surfaceInverse = Swatch(light: 0x242320, dark: 0xE9E8E3)  // toasts
    public static let border = Swatch(light: 0xD8D7D4, dark: 0x454440)
    public static let borderStrong = Swatch(light: 0x76746F, dark: 0x908F8A)   // Increase Contrast

    // Text
    public static let textPrimary = Swatch(light: 0x1D1C18, dark: 0xF1F0EC)
    public static let textSecondary = Swatch(light: 0x5F5E57, dark: 0xB6B4AF)
    /// Kept as an alias: the scale has two text levels plus disabled.
    public static let textTertiary = textSecondary
    public static let textDisabled = Swatch(light: 0x8D8C88, dark: 0x7E7D79)
    public static let textOnInverse = Swatch(light: 0xF4F3F0, dark: 0x1D1C18)
    public static let accentOnInverse = Swatch(light: 0xFBDD67, dark: 0x84550F)

    // Brand: the sticky itself (a surface, never text on light backgrounds)
    public static let paper = Swatch(light: 0xFFE88B, dark: 0xE1CE80)
    public static let paperInk = Swatch(light: 0x47300C, dark: 0x372508)
    public static let paperInkSecondary = Swatch(light: 0x6C4F25, dark: 0x5B4320)

    // Status
    public static let danger = Swatch(light: 0xB6322B, dark: 0xF7857D)
    public static let success = Swatch(light: 0x287C42, dark: 0x76CF8A)
    public static let warning = Swatch(light: 0xB35713, dark: 0xF7AB5D)
    public static let warningSurface = Swatch(light: 0xFDF0DC, dark: 0x42321D)
    public static let warningInk = Swatch(light: 0x673C14, dark: 0xF0D8A6)

    /// Interactive tint: the user's system accent color, like every Mac app.
    public static var accent: Color { Color(nsColor: .controlAccentColor) }
}

/// Sticky-note papers for notes. Light .92 / dark .84 lightness, chroma ≤ .075, dark ink.
public enum TintPalette {
    public static func paper(_ name: String) -> Swatch? {
        switch name {
        case "yellow": return Palette.paper
        case "orange": return Swatch(light: 0xFFDEC2, dark: 0xEAC2A0)
        case "pink": return Swatch(light: 0xFFD9E6, dark: 0xEEBACD)
        case "purple": return Swatch(light: 0xE9DEFF, dark: 0xD1C2EF)
        case "blue": return Swatch(light: 0xCCE9FF, dark: 0xA5D1F1)
        case "green": return Swatch(light: 0xC6F3C6, dark: 0xB1D6B1)
        default: return nil
        }
    }
    public static let ink = Swatch(light: 0x2B2418, dark: 0x231C10)
    public static let inkSecondary = Swatch(light: 0x584B33, dark: 0x45392A)
}

/// A light/dark color pair that SwiftUI and AppKit can both use.
public struct Swatch: Sendable, Hashable {
    public let light: UInt32
    public let dark: UInt32

    public init(light: UInt32, dark: UInt32) {
        self.light = light
        self.dark = dark
    }

    public var nsColor: NSColor {
        let light = self.light, dark = self.dark
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }

    public var color: Color { Color(nsColor: nsColor) }

    public func resolved(dark isDark: Bool) -> NSColor { NSColor(hex: isDark ? dark : light) }
}

extension Swatch: ShapeStyle {
    public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        color.resolve(in: environment)
    }
}

public extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// WCAG 2.x contrast math, used by the design tests (and handy in previews).
public enum Contrast {
    public static func luminance(_ hex: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF) + 0.7152 * channel((hex >> 8) & 0xFF) + 0.0722 * channel(hex & 0xFF)
    }

    public static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
