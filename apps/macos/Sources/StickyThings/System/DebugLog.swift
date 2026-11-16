import Foundation

/// Opt-in diagnostics: `defaults write app.stickythings.StickyThings debugLogging -bool YES`
/// writes to ~/Library/Application Support/Sticky Things/debug.log.
enum DebugLog {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "debugLogging") }

    static func write(_ message: String) {
        guard isEnabled else { return }
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sticky Things/debug.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(line.utf8).write(to: url)
        }
    }
}
