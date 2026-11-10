import AppKit
import StickyCore
import StickyDesign
import SwiftUI

/// `StickyThings --layout <folder>` opens the *real* panel with sample data, walks it through
/// its states in light and dark, and for each state writes a capture of the real window
/// (glass included) and the measured frame of every identified element. The self-test runs
/// the same measurements against the layout rules in `LayoutRules`.
@MainActor
enum LayoutAudit {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--layout"), index + 1 < args.count else { return false }
        let folder = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Task { @MainActor in
            let failures = await run(folder: folder)
            print(failures == 0 ? "\nLayout: no rule violations" : "\nLayout: \(failures) rule violations")
            exit(failures == 0 ? 0 : 1)
        }
        return true
    }

    static func run(folder: URL) async -> Int {
        LayoutRegistry.isRecording = true
        let paths = StorePaths.temporary()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        guard let store = try? ItemStore(paths: paths, inMemory: true) else { return 1 }
        let capture = CaptureService(store: store)
        Snapshot.fillSamples(store: store, capture: capture)
        let settings = Settings(defaults: UserDefaults(suiteName: "StickyThingsLayout-\(UUID().uuidString)")!)
        settings.hideConflictBanner = true
        settings.hotKey = .default
        settings.draft = ""
        let controller = PanelController(store: store, capture: capture, settings: settings)
        let model = controller.model
        let clipboard = NSPasteboard(name: .init("StickyThingsLayout-\(UUID().uuidString)"))
        defer { clipboard.releaseGlobally() }
        model.pasteboard = clipboard
        guard let screen = NSScreen.screens.first else { return 1 }
        var violations = 0

        func record(_ state: String, _ appearance: String) async {
            await wait(0.5)
            let name = "\(state)-\(appearance)"
            if let shot = WindowCapture.image(of: controller.panel),
               let png = shot.representation(using: .png, properties: [:]) {
                try? png.write(to: folder.appendingPathComponent("\(name).png"))
            }
            let frames = LayoutProbe.frames(in: controller.panel)
            let report = frames.sorted { $0.value.minY == $1.value.minY ? $0.value.minX < $1.value.minX : $0.value.minY < $1.value.minY }
                .map { String(format: "%-34@ x %6.1f  y %6.1f  w %6.1f  h %6.1f  right %6.1f", $0.key as NSString,
                              $0.value.minX, $0.value.minY, $0.value.width, $0.value.height,
                              controller.panel.frame.width - $0.value.maxX) }
                .joined(separator: "\n")
            try? report.write(to: folder.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
            let problems = LayoutRules.violations(frames, panelWidth: controller.panel.frame.width, panelHeight: controller.panel.frame.height)
            violations += problems.count
            print(problems.isEmpty ? "✓ \(name)" : "✗ \(name)\n" + problems.map { "    \($0)" }.joined(separator: "\n"))
        }

        for (appearanceName, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            controller.panel.appearance = NSAppearance(named: appearance)
            controller.show(.corner(screen, .bottomRight))
            await wait(0.6)
            await record("items", appearanceName)

            model.selection = store.items.first(where: { $0.kind == .link })?.id
            await record("selected", appearanceName)
            model.selection = nil

            settings.draft = "Pick up the dry cleaning\nand the parcel from the post office"
            await record("typing", appearanceName)
            settings.draft = ""

            model.search = "review"
            await record("search", appearanceName)
            model.search = ""

            if let note = store.items.first(where: { $0.kind == .text && !$0.pinned }) {
                model.beginEditing(note)
                await record("editing", appearanceName)
                if let editor = controller.panel.firstResponder as? EditorTextView {
                    editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
                }
            }
            controller.hide()
            await wait(0.4)
        }

        // From a top corner: the composer sits under the header.
        for (appearanceName, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            controller.panel.appearance = NSAppearance(named: appearance)
            controller.show(.corner(screen, .topRight))
            await wait(0.6)
            await record("top-corner", appearanceName)
            controller.hide()
            await wait(0.4)
        }

        // Settings: the real window, every pane, both appearances (same throwaway library).
        let settingsWindow = SettingsWindowController(settings: settings, store: store)
        for (appearanceName, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            settingsWindow.window?.appearance = NSAppearance(named: appearance)
            for pane in SettingsPane.allCases {
                settingsWindow.show(pane: pane, activate: false)
                settingsWindow.window?.orderFrontRegardless()
                await wait(0.7)
                guard let window = settingsWindow.window else { continue }
                let name = "settings-\(pane.rawValue)-\(appearanceName)"
                if let shot = WindowCapture.image(of: window), let png = shot.representation(using: .png, properties: [:]) {
                    try? png.write(to: folder.appendingPathComponent("\(name).png"))
                }
                var problems = SettingsLayoutRules.violations(LayoutProbe.frames(in: window), pane: pane)
                if window.title != pane.title { problems.append("window title is “\(window.title)”, not “\(pane.title)”") }
                violations += problems.count
                print(problems.isEmpty ? "✓ \(name)" : "✗ \(name)\n" + problems.map { "    \($0)" }.joined(separator: "\n"))
            }
        }
        settingsWindow.close()

        // The empty panel (first run).
        let emptyStore = try! ItemStore(paths: StorePaths.temporary(), inMemory: true)
        let empty = PanelController(store: emptyStore, capture: CaptureService(store: emptyStore), settings: settings)
        for (appearanceName, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            empty.panel.appearance = NSAppearance(named: appearance)
            empty.show(.corner(screen, .bottomRight))
            await wait(0.6)
            await wait(0.5)
            let name = "empty-\(appearanceName)"
            if let shot = WindowCapture.image(of: empty.panel), let png = shot.representation(using: .png, properties: [:]) {
                try? png.write(to: folder.appendingPathComponent("\(name).png"))
            }
            let problems = LayoutRules.violations(LayoutProbe.frames(in: empty.panel), panelWidth: empty.panel.frame.width, panelHeight: empty.panel.frame.height)
            violations += problems.count
            print(problems.isEmpty ? "✓ \(name)" : "✗ \(name)\n" + problems.map { "    \($0)" }.joined(separator: "\n"))
            empty.hide()
            await wait(0.4)
        }
        return violations
    }

    private static func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

/// Measures the panel through its own accessibility tree: every element with an identifier,
/// as a frame in panel coordinates (origin top-left, points).
@MainActor
enum LayoutProbe {
    static func frames(in window: NSWindow) -> [String: NSRect] {
        var result: [String: NSRect] = [:]
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 60 else { return }
            if let id = AX.attribute(element, "AXIdentifier") as? String, !id.isEmpty,
               let positionValue = AX.attribute(element, kAXPositionAttribute),
               let sizeValue = AX.attribute(element, kAXSizeAttribute) {
                var position = CGPoint.zero, size = CGSize.zero
                AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
                // AX: screen points from the top of the main screen. Panel: from its top-left.
                let panelTop = top - window.frame.maxY
                result[id] = NSRect(x: position.x - window.frame.minX, y: position.y - panelTop,
                                    width: size.width, height: size.height)
            }
            if ProcessInfo.processInfo.environment["STICKY_LAYOUT_DUMP"] != nil {
                var position = CGPoint.zero, size = CGSize.zero
                if let p = AX.attribute(element, kAXPositionAttribute) { AXValueGetValue(p as! AXValue, .cgPoint, &position) }
                if let s = AX.attribute(element, kAXSizeAttribute) { AXValueGetValue(s as! AXValue, .cgSize, &size) }
                let role = AX.attribute(element, kAXRoleAttribute) as? String ?? "?"
                let id = AX.attribute(element, "AXIdentifier") as? String ?? ""
                let label = AX.attribute(element, kAXDescriptionAttribute) as? String ?? ""
                if role != "AXMenuItem", role != "AXMenuBarItem", role != "AXMenu" {
                    print(String(repeating: "  ", count: depth) + "\(role) id=\(id) label=\(label.prefix(30)) \(Int(position.x - window.frame.minX)),\(Int(position.y - (top - window.frame.maxY))) \(Int(size.width))x\(Int(size.height))")
                }
            }
            for child in AX.attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                walk(child, depth: depth + 1)
            }
        }
        walk(AX.app, depth: 0)
        // Layout boxes come from SwiftUI itself (see LayoutRegistry).
        result.merge(LayoutRegistry.frames) { _, recorded in recorded }
        return result
    }
}

/// The panel's grid (docs/DESIGN.md), written down so it can't drift. Each rule checks real
/// frames measured from the running panel, to half a point.
enum LayoutRules {
    static let tolerance: CGFloat = 0.5

    static func violations(_ frames: [String: NSRect], panelWidth width: CGFloat, panelHeight height: CGFloat? = nil) -> [String] {
        var problems: [String] = []
        let inset = PanelLayout.inset, gap = PanelLayout.gap
        let column = inset + PanelLayout.cardPadding // where content starts: x = 24
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= tolerance }
        func expect(_ ok: Bool, _ message: @autoclosure () -> String) { if !ok { problems.append(message()) } }
        func f(_ v: CGFloat) -> String { String(format: "%.1f", v) }
        func matching(_ prefix: String) -> [(String, NSRect)] {
            frames.filter { $0.key.hasPrefix(prefix) && $0.value.width > 0 }.map { ($0.key, $0.value) }
        }

        // 1. Outer column: containers run from x = 12 to width − 12.
        for id in ["search-field", "composer-field", "banner", "error-banner", "empty-tips"] {
            guard let r = frames[id] else { continue }
            expect(near(r.minX, inset), "\(id) starts at x \(f(r.minX)), not \(f(inset))")
        }
        for id in ["composer-field", "settings", "banner", "error-banner", "empty-tips"] {
            guard let r = frames[id] else { continue }
            expect(near(r.maxX, width - inset), "\(id) ends \(f(width - r.maxX)) from the right edge, not \(f(inset))")
        }
        let list = frames["items"]
        let visibleCards = matching("card-").filter { _, r in
            guard let list else { return false }
            return r.minY >= list.minY - tolerance && r.maxY <= list.maxY + tolerance
        }
        for (id, r) in visibleCards {
            expect(near(r.minX, inset) && near(r.maxX, width - inset),
                   "\(id.prefix(13)) spans x \(f(r.minX))–\(f(r.maxX)), not \(f(inset))–\(f(width - inset))")
        }
        if let firstPin = matching("pin-").min(by: { $0.1.minX < $1.1.minX })?.1 {
            expect(near(firstPin.minX, inset), "the first pinned chip starts at x \(f(firstPin.minX)), not \(f(inset))")
        }
        if let all = frames["filter-All"] {
            expect(near(all.minX, inset), "the filter bar starts at x \(f(all.minX)), not \(f(inset))")
        }

        // 2. Content column: text and leading icons start 12 pt inside their container (x = 24).
        if let r = frames["composer"] {
            expect(near(r.minX, column), "composer text starts at x \(f(r.minX)), not on the content column (\(f(column)))")
        }
        // SF Symbols carry side bearings: icons align by their layout box, so the ink that
        // accessibility reports may sit up to 2 pt inside the column, never outside it.
        if let r = frames["magnifyingglass"] {
            expect(r.minX >= column - tolerance && r.minX <= column + 2,
                   "the search icon's ink starts at x \(f(r.minX)), outside \(f(column))–\(f(column + 2))")
        }
        for (id, r) in matching("section-") where list.map({ r.minY >= $0.minY && r.maxY <= $0.maxY }) ?? true {
            expect(near(r.minX, column), "\(id) starts at x \(f(r.minX)), not on the content column (\(f(column)))")
        }
        for (id, r) in matching("editor-") {
            expect(near(r.minX, column), "\(id.prefix(15)) starts at x \(f(r.minX)), not \(f(column))")
        }

        // 3. Fields: 36 pt on one line, text centered, trailing buttons 4 pt in on every side.
        let buttonInset = Metrics.fieldButtonInset
        if let field = frames["search-field"] {
            expect(near(field.height, Metrics.fieldHeight), "search field is \(f(field.height)) tall, not \(f(Metrics.fieldHeight))")
            if let text = frames["search"] {
                expect(near(text.midY, field.midY), "search text is \(f(text.midY - field.midY)) off the field's center")
            }
            if let clear = frames["clear-search"] {
                expect(near(field.maxX - clear.maxX, buttonInset) && near(clear.midY, field.midY),
                       "the clear button isn't \(f(buttonInset)) pt in and centered")
            }
        }
        // The composer: text on top across the full width, a toolbar line below it.
        if let field = frames["composer-field"] {
            let singleLine = KeyTextView.singleLineHeight(fontSize: PanelView.composerFontSize)
            if let text = frames["composer"] {
                expect(near(field.maxX - text.maxX, Metrics.fieldInset),
                       "composer text ends \(f(field.maxX - text.maxX)) from the field's edge, not \(f(Metrics.fieldInset))")
                expect(near(text.minY - field.minY, PanelLayout.composerTopInset),
                       "composer text starts \(f(text.minY - field.minY)) below the field's top, not \(f(PanelLayout.composerTopInset))")
                if near(text.height, singleLine) {
                    let expected = PanelLayout.composerMinHeight(singleLine: singleLine)
                    expect(near(field.height, expected), "one-line composer is \(f(field.height)) tall, not \(f(expected))")
                }
                if let send = frames["send"] {
                    expect(near(send.minY - text.maxY, PanelLayout.composerLineGap),
                           "composer text → toolbar is \(f(send.minY - text.maxY)), not \(f(PanelLayout.composerLineGap))")
                }
            }
            if let send = frames["send"] {
                expect(near(field.maxX - send.maxX, buttonInset) && near(field.maxY - send.maxY, buttonInset),
                       "send button is \(f(field.maxX - send.maxX)) / \(f(field.maxY - send.maxY)) pt in, not \(f(buttonInset))")
                if let hint = frames["composer-hint"] {
                    expect(near(hint.minX, column), "the composer's hint starts at x \(f(hint.minX)), not \(f(column))")
                    expect(near(hint.midY, send.midY), "the composer's hint is \(f(hint.midY - send.midY)) off its toolbar line")
                }
            }
        }

        // 4. Header row: buttons centered on the search field, 8 pt after it, 4 pt apart.
        if let field = frames["search-field"], let keep = frames["keep-open"], let settings = frames["settings"] {
            expect(near(keep.midY, field.midY) && near(settings.midY, field.midY), "header buttons aren't centered on the search field")
            expect(near(keep.minX - field.maxX, gap), "search field to its buttons is \(f(keep.minX - field.maxX)), not \(f(gap))")
            expect(near(settings.minX - keep.maxX, Space.xs), "header buttons are \(f(settings.minX - keep.maxX)) apart, not \(f(Space.xs))")
        }

        // 5. Control rows: 28 pt tall; filter segments 4 pt apart and icon-only ones all one size;
        //    pinned chips 8 pt apart.
        let filters = matching("filter-").map(\.1).sorted { $0.minX < $1.minX }
        for r in filters { expect(near(r.height, Metrics.controlRow), "a filter is \(f(r.height)) tall, not \(f(Metrics.controlRow))") }
        for (a, b) in zip(filters, filters.dropFirst()) {
            expect(near(b.minX - a.maxX, Space.xs), "filters are \(f(b.minX - a.maxX)) apart, not \(f(Space.xs))")
        }
        let iconOnly = filters.filter { $0.width < Metrics.controlRow + Space.m }
        if let first = iconOnly.first {
            expect(iconOnly.allSatisfy { near($0.width, first.width) }, "icon-only filters differ in width: \(iconOnly.map { f($0.width) })")
        }
        let pins = matching("pin-").map(\.1).sorted { $0.minX < $1.minX }
        for r in pins { expect(near(r.height, Metrics.controlRow), "a pinned chip is \(f(r.height)) tall, not \(f(Metrics.controlRow))") }
        for (a, b) in zip(pins, pins.dropFirst()) {
            expect(near(b.minX - a.maxX, gap), "pinned chips are \(f(b.minX - a.maxX)) apart, not \(f(gap))")
        }

        // 6. Vertical rhythm: 12 pt from the top, 8 pt between blocks, 12 pt from the bottom.
        let blockIDs = ["search-field", "filters", "pinned", "banner", "error-banner", "items", "composer-field"]
        let blocks = blockIDs.compactMap { id in frames[id].map { (id, $0) } }.sorted { $0.1.minY < $1.1.minY }
        if let first = blocks.first {
            expect(near(first.1.minY, inset), "\(first.0) is \(f(first.1.minY)) from the top, not \(f(inset))")
        }
        for (a, b) in zip(blocks, blocks.dropFirst()) {
            let space = b.1.minY - a.1.maxY
            expect(near(space, gap), "\(a.0) → \(b.0) is \(f(space)), not \(f(gap))")
        }
        if let height, let last = blocks.last {
            expect(near(height - last.1.maxY, inset), "\(last.0) is \(f(height - last.1.maxY)) from the bottom, not \(f(inset))")
        }

        // 7. The list: 8 pt between cards; a section header 8 pt above its first card and 16 pt
        //    below the card before it.
        let rows = (visibleCards.map { ($0.0, $0.1) } + matching("section-").filter { _, r in
            guard let list else { return false }
            return r.minY >= list.minY - tolerance && r.maxY <= list.maxY + tolerance
        }).sorted { $0.1.minY < $1.1.minY }
        for (a, b) in zip(rows, rows.dropFirst()) {
            let space = b.1.minY - a.1.maxY
            let expected = b.0.hasPrefix("section-") ? gap * 2 : gap
            expect(near(space, expected), "\(a.0.prefix(13)) → \(b.0.prefix(13)) is \(f(space)), not \(f(expected))")
        }

        // 8. Editing: Save and Cancel end on the card's content edge.
        for (id, save) in matching("save-") {
            let cardID = "card-" + id.dropFirst("save-".count)
            if let card = frames[cardID] {
                expect(near(card.maxX - save.maxX, PanelLayout.cardPadding), "Save is \(f(card.maxX - save.maxX)) from the card edge, not \(f(PanelLayout.cardPadding))")
            }
        }
        return problems
    }
}

/// What the system can't guarantee in Settings (the sidebar, title and forms are native).
enum SettingsLayoutRules {
    static func violations(_ frames: [String: NSRect], pane: SettingsPane) -> [String] {
        var problems: [String] = []
        let tolerance = LayoutRules.tolerance
        func f(_ v: CGFloat) -> String { String(format: "%.1f", v) }
        if pane == .corner {
            if let preview = frames["corner-preview"], let detail = frames["settings-detail"] {
                if abs(preview.midX - detail.midX) > tolerance {
                    problems.append("the corner preview is \(f(preview.midX - detail.midX)) off the pane's center")
                }
            } else {
                problems.append("corner preview or pane not measured")
            }
        }
        for item in SettingsPane.allCases where frames["pane-\(item.rawValue)"] == nil {
            problems.append("sidebar row for \(item.title) not found")
        }
        return problems
    }
}
