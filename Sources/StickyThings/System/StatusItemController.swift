import AppKit

/// Optional menu bar icon: click to open the panel, right-click for a menu.
@MainActor
final class StatusItemController: NSObject {
    private var item: NSStatusItem?
    var onToggle: ((NSRect, NSScreen) -> Void)?
    var onSettings: (() -> Void)?
    var hotKeyDescription: () -> String? = { nil }

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                button.image = Self.templateIcon()
                button.image?.accessibilityDescription = "Sticky Things"
                button.target = self
                button.action = #selector(clicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.toolTip = "Sticky Things"
            }
            self.item = item
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isRightClick {
            showMenu()
        } else if let window = sender.window, let screen = window.screen ?? NSScreen.main {
            onToggle?(window.frame, screen)
        }
    }

    private func showMenu() {
        guard let item, let button = item.button else { return }
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Sticky Things", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        if let shortcut = hotKeyDescription() { open.title += "   \(shortcut)" }
        menu.addItem(open)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Sticky Things", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        button.performClick(nil)
        item.menu = nil
    }

    @objc private func openFromMenu() {
        guard let window = item?.button?.window, let screen = window.screen ?? NSScreen.main else { return }
        onToggle?(window.frame, screen)
    }

    @objc private func openSettings() { onSettings?() }

    /// A sticky note with its bottom-right corner folded — drawn so it works as a template image.
    static func templateIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let fold: CGFloat = 5.5
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 3.5, y: 15))          // top-left
            body.line(to: NSPoint(x: 14.5, y: 15))         // top-right
            body.line(to: NSPoint(x: 14.5, y: 3 + fold))   // down the right side
            body.line(to: NSPoint(x: 14.5 - fold, y: 3))   // diagonal fold
            body.line(to: NSPoint(x: 3.5, y: 3))           // bottom-left
            body.close()
            body.lineWidth = 1.5
            body.lineJoinStyle = .round
            NSColor.black.setStroke()
            body.stroke()

            let flap = NSBezierPath()
            flap.move(to: NSPoint(x: 14.5, y: 3 + fold))
            flap.line(to: NSPoint(x: 14.5 - fold, y: 3 + fold))
            flap.line(to: NSPoint(x: 14.5 - fold, y: 3))
            flap.close()
            NSColor.black.setFill()
            flap.fill()

            let lines = NSBezierPath()
            lines.lineWidth = 1.4
            lines.lineCapStyle = .round
            lines.move(to: NSPoint(x: 6, y: 11.5)); lines.line(to: NSPoint(x: 12, y: 11.5))
            lines.move(to: NSPoint(x: 6, y: 8.2)); lines.line(to: NSPoint(x: 9.5, y: 8.2))
            lines.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
