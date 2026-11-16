import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // no Dock icon; lives in the corner (and the menu bar)
    withExtendedLifetime(delegate) {
        app.run()
    }
}
