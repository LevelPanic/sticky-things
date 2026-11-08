import AppKit
import ApplicationServices
import Quartz
import StickyCore
import StickyDesign
import SwiftUI

/// `StickyThings --selftest` drives the *real* panel window through the app's own accessibility
/// tree (no permissions needed for your own process), the same way VoiceOver does: it presses
/// buttons, performs each card's named actions and types into the real text views.
/// It uses a throwaway library and a private pasteboard, so your items and clipboard are untouched.
@MainActor
enum SelfTest {
    private static var failures = 0

    static func runIfRequested(app: AppDelegate) -> Bool {
        guard CommandLine.arguments.contains("--selftest") else { return false }
        Task { @MainActor in
            await run()
            print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
            exit(failures == 0 ? 0 : 1)
        }
        return true
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() { print("✓ \(name)") } else { failures += 1; print("✗ \(name)") }
    }

    private static func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    static func run() async {
        let paths = StorePaths.temporary()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        guard let store = try? ItemStore(paths: paths, inMemory: true) else { return check(false, "open a library") }
        let settings = Settings(defaults: UserDefaults(suiteName: "StickyThingsSelfTest-\(UUID().uuidString)")!)
        settings.hideConflictBanner = true
        let controller = PanelController(store: store, capture: CaptureService(store: store), settings: settings)
        let model = controller.model
        let clipboard = NSPasteboard(name: .init("StickyThingsSelfTest-\(UUID().uuidString)"))
        defer { clipboard.releaseGlobally() }
        model.pasteboard = clipboard
        let window = controller.panel
        guard let screen = NSScreen.screens.first else { return check(false, "find a screen") }

        // Opening: keyboard focus lands in the composer.
        controller.show(.corner(screen, .bottomRight))
        await wait(0.7)
        check(window.isVisible, "panel opens")
        check(window.isKeyWindow, "panel has keyboard focus")
        check(focusedIdentifier(window) == "composer", "the composer (not search) has focus")

        // The window takes the panel's rounded shape: nothing is drawn in its square corners
        // (otherwise macOS outlines a rectangle around the glass).
        if let shot = WindowCapture.image(of: window) {
            WindowCapture.saveIfRequested(shot, name: "panel")
            check(WindowCapture.cornersAreClear(shot, window: window), "panel corners are transparent")
        } else {
            check(false, "capture the panel window")
        }

        // Typing a note and pressing Return saves it.
        guard let composer = PanelController.findTextView("composer", in: window.contentView) else {
            return check(false, "composer exists")
        }
        window.makeFirstResponder(composer)
        composer.insertText("Call Sam at 4:30", replacementRange: composer.selectedRange())
        composer.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        await wait(0.3)
        check(store.items.first?.text == "Call Sam at 4:30", "typed note is saved with Return")
        check(settings.draft.isEmpty, "composer clears after saving")

        // ⌘V with an empty composer saves anything instantly (here an image).
        let source = NSPasteboard(name: .init("StickyThingsSelfTest-src-\(UUID().uuidString)"))
        defer { source.releaseGlobally() }
        source.clearContents()
        source.setData(samplePNG(), forType: .png)
        check(model.paste(from: source), "⌘V is handled")
        check(store.items.first?.kind == .image, "pasted image becomes an image item")
        await wait(0.5)

        guard let note = store.items.first(where: { $0.kind == .text }) else { return check(false, "note exists") }
        let id = note.id.uuidString

        // One click on a card copies it (its default action, as the pointer and VoiceOver use).
        if let card = AX.find("card-\(id)") {
            check(AX.press(card), "card responds to a click")
            await wait(0.3)
            check(clipboard.string(forType: .string) == "Call Sam at 4:30", "one click copies the note")
            check(model.copiedID == note.id, "card shows Copied")
            check(model.selection == note.id, "clicked card stays selected (its buttons stay visible)")
        } else {
            check(false, "card is in the accessibility tree")
        }

        // The card's buttons work (visible because it's selected; no hover needed).
        await wait(0.3)
        if let copy = AX.find("copy-\(id)") {
            clipboard.clearContents()
            AX.press(copy)
            await wait(0.3)
            check(clipboard.string(forType: .string) == "Call Sam at 4:30", "Copy button works")
        } else {
            check(false, "Copy button is reachable")
        }
        if let edit = AX.find("edit-\(id)") {
            AX.press(edit)
            await wait(0.5)
            check(model.editingID == note.id, "Edit button starts editing in place")
            if let editor = window.firstResponder as? EditorTextView {
                editor.insertText(" (moved to 5)", replacementRange: NSRange(location: (editor.string as NSString).length, length: 0))
                editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
                await wait(0.4)
                check(store.item(note.id)?.text == "Call Sam at 4:30 (moved to 5)", "inline edit is saved")
                check(model.editingID == nil, "Esc finishes editing")
            } else {
                check(false, "inline editor takes the keyboard")
            }
        } else {
            check(false, "Edit button is reachable")
        }

        // Named actions (right-click menu / VoiceOver): Delete, Undo, Pin.
        await wait(0.3)
        if let card = AX.find("card-\(id)") {
            AX.perform("Delete", on: card)
            await wait(0.3)
            check(store.item(note.id) == nil, "Delete action works")
            model.undo()
            await wait(0.3)
            check(store.item(note.id) != nil, "Undo brings it back")
        }
        await wait(0.3)
        if let card = AX.find("card-\(id)") {
            AX.perform("Pin", on: card)
            await wait(0.4)
            check(store.item(note.id)?.pinned == true, "Pin action works")
            if let chip = AX.find("pin-\(id)") {
                clipboard.clearContents()
                let pressed = AX.press(chip)
                await wait(0.3)
                if clipboard.string(forType: .string) == nil {
                    print("  · chip press=\(pressed) actions=\(AX.actions(chip)) clipboard=\(clipboard.types ?? [])")
                }
                check(clipboard.string(forType: .string) == "Call Sam at 4:30 (moved to 5)", "pinned chip copies with one click")
            } else {
                check(false, "pinned chip appears")
            }
        }

        // Keyboard: ↑ selects the newest card, Return copies it and closes.
        model.selection = nil
        window.makeFirstResponder(composer)
        composer.doCommand(by: #selector(NSResponder.moveUp(_:)))
        check(model.selection == model.listItems.first?.id, "↑ selects the newest item")
        composer.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        await wait(0.5)
        check(!controller.isShown, "Return copies and closes")

        // Quick Look previews a stored image; the panel stays open behind it.
        controller.show(.corner(screen, .bottomRight))
        await wait(0.6)
        if let image = store.items.first(where: { $0.kind == .image }) {
            model.quickLook(image)
            await wait(1.2)
            check(model.quickLook.isVisible, "Quick Look previews images")
            model.quickLook.close()
            await wait(0.4)
            check(controller.isShown, "panel stays open behind Quick Look")
        }

        // Esc steps back (selection first), then closes.
        model.selection = store.items.first?.id
        window.makeFirstResponder(composer)
        composer.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        check(model.selection == nil && controller.isShown, "first Esc clears the selection")
        composer.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        await wait(0.4)
        check(!controller.isShown, "second Esc closes the panel")
    }

    private static func focusedIdentifier(_ window: NSWindow) -> String? {
        (window.firstResponder as? NSView)?.identifier?.rawValue
    }

    private static func samplePNG() -> Data {
        let image = NSImage(size: NSSize(width: 80, height: 50), flipped: false) { rect in
            NSColor.systemTeal.setFill(); rect.fill(); return true
        }
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }
}

/// Captures our own windows. Apps can always capture their own windows, so this needs no
/// Screen Recording permission. The call is looked up at runtime because the SDK marks it
/// unavailable in favor of ScreenCaptureKit, which needs permission even for your own windows.
@MainActor
enum WindowCapture {
    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    static func image(of window: NSWindow) -> NSBitmapImageRep? {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        let includingWindow: UInt32 = 1 << 3, boundsIgnoreFraming: UInt32 = 1 << 0
        guard let image = create(.null, includingWindow, UInt32(window.windowNumber), boundsIgnoreFraming)?
            .takeRetainedValue() else { return nil }
        return NSBitmapImageRep(cgImage: image)
    }

    /// The pixel just inside each corner of the window's frame is fully transparent.
    static func cornersAreClear(_ shot: NSBitmapImageRep, window: NSWindow) -> Bool {
        let scale = CGFloat(shot.pixelsWide) / window.frame.width
        let inset = Int(2 * scale)
        let (w, h) = (shot.pixelsWide, shot.pixelsHigh)
        let corners = [(inset, inset), (w - 1 - inset, inset), (inset, h - 1 - inset), (w - 1 - inset, h - 1 - inset)]
        return corners.allSatisfy { (shot.colorAt(x: $0.0, y: $0.1)?.alphaComponent ?? 1) < 0.01 }
    }

    /// `STICKY_SELFTEST_CAPTURES=<folder>` keeps the captures for a look.
    static func saveIfRequested(_ shot: NSBitmapImageRep, name: String) {
        guard let folder = ProcessInfo.processInfo.environment["STICKY_SELFTEST_CAPTURES"],
              let png = shot.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
    }
}

/// Own-process accessibility: query our own UI like VoiceOver would (main thread only).
@MainActor
enum AX {
    static let app = AXUIElementCreateApplication(getpid())

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func find(_ identifier: String, in root: AXUIElement? = nil, depth: Int = 0) -> AXUIElement? {
        let element = root ?? app
        guard depth < 60 else { return nil }
        if attribute(element, "AXIdentifier") as? String == identifier { return element }
        for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            if let hit = find(identifier, in: child, depth: depth + 1) { return hit }
        }
        return nil
    }

    @discardableResult
    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        return AXUIElementCopyActionNames(element, &names) == .success ? (names as? [String] ?? []) : []
    }

    /// Performs a named action such as "Delete" (exposed by `.accessibilityAction(named:)`).
    @discardableResult
    static func perform(_ name: String, on element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success, let actions = names as? [String],
              let action = actions.first(where: { $0 == name || $0.hasPrefix("Name:\(name)") }) else { return false }
        return AXUIElementPerformAction(element, action as CFString) == .success
    }
}
