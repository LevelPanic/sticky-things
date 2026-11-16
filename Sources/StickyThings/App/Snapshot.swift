import AppKit
import StickyCore
import StickyDesign
import SwiftUI

/// `StickyThings --snapshot <folder>` renders every screen with realistic sample data to PNGs
/// (light and dark) and quits. Sample data goes through the real capture code.
@MainActor
enum Snapshot {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return false }
        let folder = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        PanelMaterial.flat = true

        let paths = StorePaths.temporary()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        guard let store = try? ItemStore(paths: paths, inMemory: true) else { exit(1) }
        let capture = CaptureService(store: store)
        fillSamples(store: store, capture: capture)
        let settings = Settings(defaults: UserDefaults(suiteName: "StickyThingsSnapshot")!)
        settings.corner = .bottomRight
        settings.hotKey = .default
        settings.draft = ""

        let panelSize = NSSize(width: PanelLayout.width, height: 640)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let model = PanelModel(store: store, capture: capture, settings: settings)
            model.isPresented = true
            model.panelHeight = 640
            model.conflictAction = name == "light" ? "Quick Note" : nil
            model.selection = store.items.first(where: { $0.kind == .link })?.id
            model.hoveredID = nil
            model.copiedID = store.items.first(where: { $0.kind == .text && !$0.pinned })?.id
            render(PanelView(model: model, store: store, settings: settings), size: panelSize, appearance: appearance,
                   to: folder.appendingPathComponent("panel-\(name).png"))

            let emptyStore = try! ItemStore(paths: StorePaths.temporary(), inMemory: true)
            let emptyModel = PanelModel(store: emptyStore, capture: CaptureService(store: emptyStore), settings: settings)
            emptyModel.isPresented = true
            emptyModel.panelHeight = 560
            render(PanelView(model: emptyModel, store: emptyStore, settings: settings),
                   size: NSSize(width: panelSize.width, height: 560), appearance: appearance,
                   to: folder.appendingPathComponent("empty-\(name).png"))
        }

        let onboarding = OnboardingModel(settings: settings)
        for step in [OnboardingModel.Step.welcome, .corner, .freeCorner, .tryIt] {
            onboarding.step = step
            render(OnboardingView(model: onboarding, settings: settings), size: NSSize(width: 580, height: 560),
                   appearance: .aqua, to: folder.appendingPathComponent("onboarding-\(step.rawValue)-\(step).png"))
        }

        for pane in [SettingsPane.corner, .general, .notes] {
            render(SettingsView(settings: settings, store: store, navigation: SettingsNavigation(pane: pane)), size: NSSize(width: 720, height: 560),
                   appearance: .darkAqua, to: folder.appendingPathComponent("settings-\(pane.rawValue).png"))
        }

        for phase in [CornerPeekModel.Phase.peek, .dropTarget] {
            let peek = CornerPeekModel(corner: .bottomRight)
            peek.phase = phase
            let view = ZStack(alignment: .bottomTrailing) {
                Palette.surfaceSunken.color
                CornerPeekView(model: peek)
            }
            .frame(width: 220, height: 220)
            render(view, size: NSSize(width: 220, height: 220), appearance: .darkAqua,
                   to: folder.appendingPathComponent("corner-\(phase == .peek ? "peek" : "drop").png"))
        }

        print("Snapshots written to \(folder.path)")
        exit(0)
    }

    static func render<V: View>(_ view: V, size: NSSize, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let background = appearance == .darkAqua ? NSColor(hex: 0x101010) : NSColor(hex: 0xE9E7E2)
        window.backgroundColor = background
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8)) // thumbnails load asynchronously
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        let output = NSImage(size: size)
        output.lockFocus()
        background.setFill()
        NSRect(origin: .zero, size: size).fill()
        rep.draw(in: NSRect(origin: .zero, size: size))
        output.unlockFocus()
        if let tiff = output.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    static func fillSamples(store: ItemStore, capture: CaptureService) {
        let now = Date()
        func save(_ fill: (NSPasteboard) -> Void, ago minutes: Double, source: String? = nil) {
            let pb = NSPasteboard(name: .init("snapshot-\(UUID().uuidString)"))
            defer { pb.releaseGlobally() }
            pb.clearContents()
            fill(pb)
            if case .saved(let items)? = try? capture.save(from: pb, source: source.map { SourceApp(bundleID: nil, name: $0) }),
               let id = items.first?.id {
                store.update(id) { $0.createdAt = now.addingTimeInterval(-minutes * 60) }
            }
        }
        func note(_ text: String, ago minutes: Double, tint: Tint = .none, pinned: Bool = false) {
            if case .saved(let items)? = capture.saveNote(text), let id = items.first?.id {
                store.update(id) {
                    $0.createdAt = now.addingTimeInterval(-minutes * 60)
                    $0.tint = tint
                    $0.pinned = pinned
                }
            }
        }

        note("Wi-Fi: Garden-5G · password is on the fridge", ago: 60 * 24 * 9, pinned: true)
        note("Flight QF12 · seat 34A", ago: 60 * 30, tint: .blue, pinned: true)
        note("Ideas: drop screenshots on the corner, pin the wifi password", ago: 60 * 26)
        save({ pb in
            let text = "Quarterly review: revenue up 12%, churn flat"
            let rtf = NSAttributedString(string: text, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
                .rtf(from: NSRange(location: 0, length: text.count), documentAttributes: [:])!
            pb.setData(rtf, forType: .rtf)
            pb.setString(text, forType: .string)
        }, ago: 60 * 5, source: "Pages")
        note("Groceries\n– oat milk\n– eggs\n– coffee beans", ago: 60 * 3, tint: .yellow)
        save({ pb in pb.setData(samplePDF(), forType: .pdf) }, ago: 70, source: "Preview")
        save({ pb in pb.writeObjects([URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/Package.swift") as NSURL]) },
             ago: 42, source: "Finder")
        save({ pb in pb.setData(sampleImage(), forType: .png) }, ago: 18, source: "Screenshot")
        note("https://github.com/utsavg05/StickyEdges", ago: 6)
        if let image = store.items.first(where: { $0.kind == .image }) {
            store.setCaption(image.id, to: "The new panel on the corner, before the spacing pass")
        }
        if let pdf = store.items.first(where: { $0.kind == .pdf }) {
            store.setCaption(pdf.id, to: "Signed lease, keep until the deposit comes back")
        }
        if let link = store.items.first(where: { $0.kind == .link }) {
            store.update(link.id) { $0.link?.title = "StickyEdges: sticky notes for your screen edge" }
        }
        note("Call Sam back about the lease at 4:30pm", ago: 1)
    }

    static func sampleImage() -> Data {
        let image = NSImage(size: NSSize(width: 640, height: 400), flipped: false) { rect in
            NSColor(hex: 0x2E3A46).setFill(); rect.fill()
            NSColor(hex: 0xF4F1EA).setFill()
            NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 360, height: 320), xRadius: 14, yRadius: 14).fill()
            NSColor(hex: 0xFFE27A).setFill()
            NSBezierPath(roundedRect: NSRect(x: 430, y: 40, width: 170, height: 150), xRadius: 14, yRadius: 14).fill()
            NSColor(hex: 0xD8D2C4).setFill()
            for row in 0..<5 { NSBezierPath(roundedRect: NSRect(x: 70, y: 300 - row * 46, width: 260 - row * 30, height: 18), xRadius: 9, yRadius: 9).fill() }
            return true
        }
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }

    static func samplePDF() -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        for page in 0..<3 {
            context.beginPDFPage(nil)
            context.setFillColor(NSColor(hex: 0x1F1B16).cgColor)
            context.fill(CGRect(x: 72, y: 680, width: 300, height: 28))
            context.setFillColor(NSColor(hex: 0xBDB6A8).cgColor)
            for line in 0..<14 { context.fill(CGRect(x: 72, y: 620 - line * 30, width: 460 - (line % 3) * 60 - page * 10, height: 10)) }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
