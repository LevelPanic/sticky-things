#if DEBUG
import StickyCore
import UIKit

/// `--demo` seeds a throwaway-looking library for simulator screenshots and manual UI checks.
@MainActor
enum DemoContent {
    static func seedIfRequested(in library: Library) {
        guard CommandLine.arguments.contains("--demo"), library.store.items.isEmpty else { return }
        let store = library.store
        let capture = library.capture

        if case .saved(let items)? = capture.saveNote("Wi-Fi: Garden-5G · password is on the fridge"),
           let id = items.first?.id {
            store.update(id) { $0.pinned = true; $0.tint = .yellow }
        }
        if case .saved(let items)? = capture.saveNote("Flight QF12 · seat 34A, gate 26"),
           let id = items.first?.id {
            store.update(id) { $0.pinned = true; $0.tint = .blue }
        }
        if case .saved(let items)? = capture.saveNote("Ideas: a tiny capture button in Control Center, captions on screenshots, a shared Mac/iOS library"),
           let id = items.first?.id {
            store.update(id) { $0.tint = .pink }
        }
        _ = capture.saveNote("https://github.com/LevelPanic/sticky-things")
        _ = capture.saveNote("Call Sam back about the lease at 4:30pm")

        let image = sampleImage()
        if let data = image.pngData() {
            library.saveImage(data, type: UTI.png)
        }
        if let image = store.items.first(where: { $0.kind == .image }) {
            store.setCaption(image.id, to: "The quick capture sheet, before the spacing pass")
        }
    }

    private static func sampleImage() -> UIImage {
        let size = CGSize(width: 1200, height: 800)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.18, green: 0.23, blue: 0.28, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let card = UIBezierPath(roundedRect: CGRect(x: 70, y: 90, width: 1060, height: 620), cornerRadius: 42)
            UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1).setFill()
            card.fill()

            let yellow = UIBezierPath(roundedRect: CGRect(x: 760, y: 430, width: 280, height: 210), cornerRadius: 28)
            UIColor(red: 1, green: 0.89, blue: 0.48, alpha: 1).setFill()
            yellow.fill()

            UIColor(red: 0.85, green: 0.83, blue: 0.78, alpha: 1).setFill()
            for row in 0..<5 {
                let line = UIBezierPath(roundedRect: CGRect(x: 130, y: 190 + row * 78, width: 520 - row * 44, height: 24), cornerRadius: 12)
                line.fill()
            }
        }
    }
}
#endif
