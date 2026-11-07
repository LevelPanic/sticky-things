import AppKit
import SwiftUI

/// `StickyThings --snapshot <folder>` renders the UI with sample notes to PNGs and quits.
/// Used to review the design without screen-recording permission.
@MainActor
enum Snapshot {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return false }
        let folder = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        PanelView.flatBackground = true

        let store = sampleStore(in: folder.appendingPathComponent("store"))
        let settings = Settings(defaults: UserDefaults(suiteName: "StickyThingsSnapshot")!)
        settings.corner = .bottomRight
        settings.hotKey = .default
        settings.draft = ""

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let model = PanelModel(store: store, settings: settings)
            model.isPresented = true
            model.panelHeight = 600
            model.selection = store.notes.first(where: { !$0.pinned && $0.kind == .link })?.id
            model.conflictAction = name == "light" ? "Quick Note" : nil
            render(PanelView(model: model, store: store, settings: settings),
                   size: NSSize(width: PanelView.width + PanelView.margin * 2, height: 600 + PanelView.margin * 2),
                   appearance: appearance, to: folder.appendingPathComponent("panel-\(name).png"))

            let emptyStore = NoteStore(rootURL: folder.appendingPathComponent("empty"))
            emptyStore.persists = false
            let emptyModel = PanelModel(store: emptyStore, settings: settings)
            emptyModel.isPresented = true
            emptyModel.panelHeight = 520
            render(PanelView(model: emptyModel, store: emptyStore, settings: settings),
                   size: NSSize(width: PanelView.width + PanelView.margin * 2, height: 520 + PanelView.margin * 2),
                   appearance: appearance, to: folder.appendingPathComponent("empty-\(name).png"))
        }

        for phase in [CornerPeekModel.Phase.peek, .dropTarget] {
            let peek = CornerPeekModel(corner: .bottomRight)
            peek.phase = phase
            let view = ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: [.indigo, .purple], startPoint: .top, endPoint: .bottom)
                CornerPeekView(model: peek)
            }
            .frame(width: 220, height: 220)
            render(view, size: NSSize(width: 220, height: 220), appearance: .darkAqua,
                   to: folder.appendingPathComponent("corner-\(phase == .peek ? "peek" : "drop").png"))
        }

        for pane in [SettingsPane.corner, .general] {
            render(SettingsView(settings: settings, store: store, pane: pane),
                   size: NSSize(width: 720, height: 600), appearance: .darkAqua,
                   to: folder.appendingPathComponent("settings-\(pane.rawValue).png"))
        }

        let pickerSettings = settings
        render(CornerPicker(corner: .constant(pickerSettings.corner)).padding(20),
               size: NSSize(width: 330, height: 222), appearance: .aqua,
               to: folder.appendingPathComponent("corner-picker.png"))

        print("Snapshots written to \(folder.path)")
        exit(0)
    }

    private static func render<V: View>(_ view: V, size: NSSize, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = appearance == .darkAqua ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6)) // let async thumbnails load
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        // Composite on the window color so transparent areas aren't black.
        let output = NSImage(size: size)
        output.lockFocus()
        window.backgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        rep.draw(in: NSRect(origin: .zero, size: size))
        output.unlockFocus()
        if let tiff = output.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    private static func sampleStore(in folder: URL) -> NoteStore {
        try? FileManager.default.removeItem(at: folder)
        let store = NoteStore(rootURL: folder)
        try? FileManager.default.createDirectory(at: store.mediaURL, withIntermediateDirectories: true)
        store.persists = false
        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        // A sample "screenshot".
        let imageName = "sample.png"
        let image = NSImage(size: NSSize(width: 640, height: 400), flipped: false) { rect in
            NSGradient(colors: [.systemTeal, .systemBlue, .systemIndigo])?.draw(in: rect, angle: -35)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 300, height: 180), xRadius: 18, yRadius: 18).fill()
            NSColor.white.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: NSRect(x: 390, y: 60, width: 190, height: 280), xRadius: 18, yRadius: 18).fill()
            return true
        }
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: store.mediaURL.appendingPathComponent(imageName))
        }

        var notes: [Note] = []
        notes.append(Note(kind: .text, text: "Ideas: drop screenshots on the corner, pin the wifi password", createdAt: ago(60 * 26)))
        notes.append(Note(kind: .text, text: "Groceries\n– oat milk\n– eggs\n– coffee beans", color: .yellow, createdAt: ago(60 * 3)))
        var file = Note(kind: .file, text: FileManager.default.currentDirectoryPath + "/Package.swift")
        file.createdAt = ago(42)
        notes.append(file)
        var img = Note(kind: .image, text: "")
        img.imageFile = imageName
        img.pixelWidth = 1280; img.pixelHeight = 800
        img.createdAt = ago(18)
        notes.append(img)
        var link = Note(kind: .link, text: "https://github.com/utsavg05/StickyEdges")
        link.title = "utsavg05/StickyEdges — sticky notes for your screen edge"
        link.createdAt = ago(6)
        notes.append(link)
        notes.append(Note(kind: .text, text: "Call Sam back about the lease — 4:30pm", createdAt: ago(1)))
        notes.append(Note(kind: .text, text: "Wi-Fi: Garden-5G · pw on the fridge", pinned: true, createdAt: ago(60 * 24 * 9)))
        notes.append(Note(kind: .text, text: "Flight QF12 · seat 34A", color: .blue, pinned: true, createdAt: ago(60 * 30)))
        store.replaceAll(with: notes)
        return store
    }
}
