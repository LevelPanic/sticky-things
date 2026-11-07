import AppKit

/// Reads (and, only when the user clicks the button, changes) macOS's own hot corners,
/// so Sticky Things can tell you when Quick Note is still sitting in the same corner.
enum MacHotCorners {
    private static let dock = "com.apple.dock" as CFString

    /// The hot-corner action macOS runs for `corner` without holding a modifier key, or nil.
    static func conflictingAction(for corner: ScreenCorner) -> String? {
        CFPreferencesAppSynchronize(dock)
        let modifier = CFPreferencesCopyAppValue("wvous-\(corner.dockKey)-modifier" as CFString, dock) as? Int ?? 0
        guard modifier == 0 else { return nil } // only fires while a key is held: no clash
        let raw = CFPreferencesCopyAppValue("wvous-\(corner.dockKey)-corner" as CFString, dock) as? Int
        // Since macOS 12 the bottom-right corner opens Quick Note unless the user changed it.
        let action = raw ?? (corner == .bottomRight ? 14 : 0)
        return name(for: action)
    }

    static func name(for action: Int) -> String? {
        switch action {
        case 0, 1: return nil
        case 2: return "Mission Control"
        case 3: return "Application Windows"
        case 4: return "Desktop"
        case 5: return "Start Screen Saver"
        case 6: return "Disable Screen Saver"
        case 7: return "Dashboard"
        case 10: return "Put Display to Sleep"
        case 11: return "Launchpad"
        case 12: return "Notification Center"
        case 13: return "Lock Screen"
        case 14: return "Quick Note"
        default: return "a hot corner action"
        }
    }

    /// Sets the macOS hot corner to "–" (nothing) and restarts the Dock so it takes effect.
    static func disable(_ corner: ScreenCorner) {
        CFPreferencesSetAppValue("wvous-\(corner.dockKey)-corner" as CFString, 1 as CFNumber, dock)
        CFPreferencesSetAppValue("wvous-\(corner.dockKey)-modifier" as CFString, 0 as CFNumber, dock)
        CFPreferencesAppSynchronize(dock)
        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["Dock"]
        try? killall.run()
    }

    /// Opens System Settings › Desktop & Dock (the Hot Corners… button is at the bottom).
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
