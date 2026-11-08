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
