import AppKit
import SwiftUI

// MARK: - Spacing (4 pt grid)

public enum Space {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

// MARK: - Corner radii
// Nested shapes stay concentric: inner radius = outer radius − the padding between them.

public enum Radius {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 6
    public static let m: CGFloat = 10
    public static let l: CGFloat = 14
    public static let panel: CGFloat = 24
    public static func inner(_ outer: CGFloat, padding: CGFloat) -> CGFloat { max(Radius.xs, outer - padding) }
}

// MARK: - Type scale (SF Pro / SF Mono; sizes follow macOS's own text styles)

public enum TypeScale {
    /// 11 pt — timestamps, metadata, key hints.
    public static let caption = Font.system(size: 11)
    public static let captionStrong = Font.system(size: 11, weight: .semibold)
    /// 12 pt — secondary lines, banners.
    public static let footnote = Font.system(size: 12)
    /// 13 pt — body text of cards (the macOS default body size).
    public static let body = Font.system(size: 13)
    public static let bodyStrong = Font.system(size: 13, weight: .semibold)
    /// 14 pt — the composer: what you type should feel a touch larger than what you read.
    public static let input = Font.system(size: 14)
    /// 15 pt — empty-state and section titles.
    public static let title = Font.system(size: 15, weight: .semibold)
    /// 11 pt semibold, sentence case — section headers ("Today").
    public static let section = Font.system(size: 11, weight: .semibold)
    /// 12 pt — banners, chips.
    public static let callout = Font.system(size: 12)
    /// 22 pt semibold — onboarding headlines only (no bold inside the panel).
    public static let display = Font.system(size: 22, weight: .semibold)
    public static let mono = Font.system(size: 12, design: .monospaced)

    public static let inputNSFont = NSFont.systemFont(ofSize: 14)
    public static let bodyNSFont = NSFont.systemFont(ofSize: 13)
}

// MARK: - Motion
// Zero-bounce springs (they keep velocity if hover reverses mid-way), exits ~75% of entrances,
// and with Reduce Motion everything becomes a short crossfade.

public enum Motion {
    public static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private static func fade(_ duration: Double = 0.15) -> Animation { .easeInOut(duration: duration) }

    /// Hover, reveal, small state flips.
    public static var quick: Animation { reduceMotion ? fade(0.1) : .timingCurve(0.25, 1, 0.5, 1, duration: 0.12) }
    /// Pin, chips, editor, toasts appearing.
    public static var standard: Animation { reduceMotion ? fade() : .smooth(duration: 0.22) }
    /// List inserts/reorders, onboarding steps, the corner note peeking out.
    public static var emphasized: Animation { reduceMotion ? fade() : .smooth(duration: 0.28) }
    /// Leaving is quicker than arriving.
    public static var exit: Animation { reduceMotion ? fade(0.12) : .timingCurve(0.5, 0, 0.75, 0, duration: 0.18) }
    public static var panelIn: Animation { reduceMotion ? fade() : .smooth(duration: 0.3) }
    public static var panelOut: Animation { reduceMotion ? fade(0.12) : .smooth(duration: panelOutDuration) }
    public static let panelInDuration: Double = 0.3
    public static let panelOutDuration: Double = 0.22
    /// The panel slides this far out of its corner (0 with Reduce Motion).
    public static var panelTravel: CGFloat { reduceMotion ? 0 : 10 }
    public static var panelStartScale: CGFloat { 1 }
}

// MARK: - Elevation
// One method per appearance: light mode uses a soft tinted shadow, dark mode uses lighter
// fills and a border (shadows read as smudges on dark surfaces).

public enum Elevation: Sendable {
    case card, lifted, sticky

    func shadow(dark: Bool) -> (opacity: Double, radius: CGFloat, y: CGFloat) {
        switch self {
        case .card: return dark ? (0, 0, 0) : (0.09, 1.5, 1)
        case .lifted: return dark ? (0.45, 8, 6) : (0.18, 8, 6)
        case .sticky: return (0.22, 2, 2)
        }
    }
}

private struct ElevationModifier: ViewModifier {
    let elevation: Elevation
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        let s = elevation.shadow(dark: dark)
        // Light mode: shadow tinted with the ink color, never pure black.
        let tint = dark ? Color.black : Color(nsColor: NSColor(hex: Palette.textPrimary.light))
        content.shadow(color: tint.opacity(s.opacity), radius: s.radius, y: s.y)
    }
}

public extension View {
    func elevation(_ e: Elevation) -> some View { modifier(ElevationModifier(elevation: e)) }
}

// MARK: - Sizes

public enum Metrics {
    /// Smallest comfortable pointer target on macOS.
    public static let minHitTarget: CGFloat = 24
    /// HIG default control size; never below `minHitTarget` (WCAG 2.5.8).
    public static let iconButton: CGFloat = 28
    public static let thumbnailMaxHeight: CGFloat = 180
}
