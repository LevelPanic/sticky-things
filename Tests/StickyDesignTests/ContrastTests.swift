import XCTest
@testable import StickyDesign

/// The design system's promises, checked automatically (WCAG 2.x AA: 4.5:1 for text,
/// 3:1 for large text and UI boundaries), in light and dark appearance.
final class ContrastTests: XCTestCase {
    private func assertContrast(_ text: Swatch, on background: Swatch, atLeast minimum: Double,
                                _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let light = Contrast.ratio(text.light, background.light)
        let dark = Contrast.ratio(text.dark, background.dark)
        XCTAssertGreaterThanOrEqual(light, minimum, "\(label) (light) is \(String(format: "%.2f", light)):1", file: file, line: line)
        XCTAssertGreaterThanOrEqual(dark, minimum, "\(label) (dark) is \(String(format: "%.2f", dark)):1", file: file, line: line)
    }

    func testTextOnEverySurface() {
        for (name, surface) in [("surface", Palette.surface), ("raised", Palette.surfaceRaised),
                                ("raised hover", Palette.surfaceRaisedHover), ("sunken", Palette.surfaceSunken)] {
            assertContrast(Palette.textPrimary, on: surface, atLeast: 7, "primary on \(name)")
            assertContrast(Palette.textSecondary, on: surface, atLeast: 4.5, "secondary on \(name)")
        }
        assertContrast(Palette.textOnInverse, on: Palette.surfaceInverse, atLeast: 7, "toast text")
        assertContrast(Palette.accentOnInverse, on: Palette.surfaceInverse, atLeast: 4.5, "toast action")
    }

    /// Hints use the system placeholder tone: quieter than secondary text, never below 3:1.
    func testHintsStayReadableButQuiet() {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            // Hints sit on the composer and on untinted cards (tinted notes use their own ink).
            for (surfaceName, surface) in [("raised", Palette.surfaceRaised), ("raised hover", Palette.surfaceRaisedHover)] {
                let background = name == "light" ? surface.light : surface.dark
                let hint = Self.resolve(Palette.hintNSColor, in: appearance, over: background)
                let ratio = Contrast.ratio(hint, background)
                XCTAssertGreaterThanOrEqual(ratio, 3, "hint on \(surfaceName) (\(name)) is \(String(format: "%.2f", ratio)):1")
                let secondary = Contrast.ratio(name == "light" ? Palette.textSecondary.light : Palette.textSecondary.dark, background)
                XCTAssertLessThan(ratio, secondary, "hint should be quieter than secondary text on \(surfaceName) (\(name))")
            }
        }
    }

    /// A dynamic system color as an opaque hex over a background, in one appearance.
    private static func resolve(_ color: NSColor, in appearance: NSAppearance.Name, over background: UInt32) -> UInt32 {
        var result: UInt32 = 0
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            let c = color.usingColorSpace(.sRGB)!
            let a = c.alphaComponent
            func mix(_ fg: CGFloat, _ shift: UInt32) -> UInt32 {
                let bg = CGFloat((background >> shift) & 0xFF) / 255
                return UInt32(((fg * a + bg * (1 - a)) * 255).rounded()) << shift
            }
            result = mix(c.redComponent, 16) | mix(c.greenComponent, 8) | mix(c.blueComponent, 0)
        }
        return result
    }

    func testInkOnStickyPaper() {
        assertContrast(Palette.paperInk, on: Palette.paper, atLeast: 7, "ink on paper")
        assertContrast(Palette.paperInkSecondary, on: Palette.paper, atLeast: 4.5, "secondary ink on paper")
        for name in ["yellow", "orange", "pink", "purple", "blue", "green"] {
            let paper = TintPalette.paper(name)!
            assertContrast(TintPalette.ink, on: paper, atLeast: 7, "ink on \(name)")
            assertContrast(TintPalette.inkSecondary, on: paper, atLeast: 4.5, "secondary ink on \(name)")
        }
    }

    func testStatusColorsAndBorders() {
        assertContrast(Palette.danger, on: Palette.surfaceRaised, atLeast: 4.5, "danger text")
        assertContrast(Palette.warningInk, on: Palette.warningSurface, atLeast: 7, "banner text")
        assertContrast(Palette.warning, on: Palette.warningSurface, atLeast: 3, "banner icon")
        assertContrast(Palette.success, on: Palette.surfaceRaised, atLeast: 4.5, "success text")
        // UI boundaries (Increase Contrast edges, focus) need 3:1.
        assertContrast(Palette.borderStrong, on: Palette.surfaceRaised, atLeast: 3, "strong border")
    }

    func testContrastMath() {
        XCTAssertEqual(Contrast.ratio(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
        XCTAssertEqual(Contrast.ratio(0x777777, 0x777777), 1, accuracy: 0.01)
    }
}
