import Foundation
import XCTest

/// Impeccable's audit checklist, automated: scans the UI source for "slop tells" and
/// design-system drift. A failure names the file, line and rule.
final class DesignLintTests: XCTestCase {
    private struct Rule {
        let name: String
        let pattern: String
        var allowedFiles: Set<String> = []
        var check: ((NSTextCheckingResult, String) -> Bool)? = nil // return true = violation
    }

    private static let rules: [Rule] = [
        Rule(name: "No bouncy or springy motion (use Motion tokens)", pattern: #"\.bouncy|\.snappy|\.spring\(|interpolatingSpring"#),
        Rule(name: "No uppercase or tracked labels (sentence case)", pattern: #"\.uppercased\(\)|\.tracking\("#,
             allowedFiles: ["KeyCombo.swift"]), // key caps show letters as printed on the keyboard
        Rule(name: "No decorative gradients (the sticky graphic is the only illustration)",
             pattern: #"LinearGradient|RadialGradient|AngularGradient|\.gradient\b"#, allowedFiles: ["StickyNoteGraphic.swift"]),
        Rule(name: "No SwiftUI materials or glass below the panel (system glass is drawn by AppKit)",
             pattern: #"\.ultraThinMaterial|\.thinMaterial|\.regularMaterial|\.thickMaterial|\.glassEffect\("#),
        Rule(name: "No raw colors outside the palette", pattern: #"Color\(red:|NSColor\(red:|NSColor\(calibratedRed"#,
             allowedFiles: ["Palette.swift", "StickyNoteGraphic.swift"]),
        Rule(name: "No functional text below 11 pt", pattern: #"\.system\(size: ([0-9.]+)"#) { match, line in
            let range = Range(match.range(at: 1), in: line)!
            return (Double(line[range]) ?? 99) < 11
        },
        Rule(name: "No em dashes in UI copy", pattern: #""[^"]*—[^"]*""#),
        Rule(name: "No vague button labels (verb + object)", pattern: #"Button\("(OK|Submit|Yes|No|Okay)""#),
        Rule(name: "No exclamation marks in UI copy", pattern: #""[A-Z][^"\\]*!""#),
        Rule(name: "Decoration never needs a permission: don't read the desktop picture (it can live in a protected folder)",
             pattern: #"desktopImageURL"#),
        Rule(name: "No one-off nudges of tokens (Space.s - 2): use or add a token",
             pattern: #"\b(Space|Radius|Metrics)\.[a-zA-Z]+ *[-+] *[0-9]"#),
    ]

    func testUISourceFollowsTheDesignSystem() throws {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path),
              root.path != "/" {
            root.deleteLastPathComponent()
        }
        let folders = ["apps/macos/Sources/StickyThings", "packages/StickyDesign/Sources/StickyDesign"]
            .map { root.appendingPathComponent($0) }
        var violations: [String] = []
        var scanned = 0

        for folder in folders {
            let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
            for file in files {
                scanned += 1
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
                for (index, rawLine) in lines.enumerated() {
                    let line = rawLine.trimmingCharacters(in: .whitespaces)
                    if line.hasPrefix("//") || line.hasPrefix("///") || line.hasPrefix("*") { continue }
                    let code = rawLine.components(separatedBy: " // ").first ?? rawLine // drop trailing comments
                    for rule in Self.rules where !rule.allowedFiles.contains(file.lastPathComponent) {
                        let regex = try NSRegularExpression(pattern: rule.pattern)
                        for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                            if let check = rule.check, !check(match, code) { continue }
                            violations.append("\(file.lastPathComponent):\(index + 1)  \(rule.name)\n    \(line)")
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(scanned, 10, "should scan the UI sources")
        XCTAssert(violations.isEmpty, "\n" + violations.joined(separator: "\n"))
    }
}
