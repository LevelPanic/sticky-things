import AppIntents
import StickyCore

/// Siri and Shortcuts: get to a blank composer without hunting for the app.
struct NewStickyThingIntent: AppIntent {
    static let title: LocalizedStringResource = "New Sticky Thing"
    static let description = IntentDescription("Open Sticky Things with a new note ready to type.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        QuickCaptureFlag.request()
        await MainActor.run { QuickCaptureRouter.shared.request() }
        return .result()
    }
}

/// Siri and Shortcuts: save a piece of text or a link without opening the app.
struct SaveStickyThingIntent: AppIntent {
    static let title: LocalizedStringResource = "Save to Sticky Things"
    static let description = IntentDescription("Save text or a link to your Sticky Things library.")
    static let openAppWhenRun = false

    @Parameter(title: "Text")
    var text: String

    init() {}

    init(text: String) {
        self.text = text
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let saved = await MainActor.run { () -> Bool in
            guard let store = try? ItemStore(paths: StickyAppGroup.paths) else { return false }
            return CaptureService(store: store).saveNote(text) != nil
        }
        return .result(dialog: saved ? "Saved to Sticky Things." : "There was nothing to save.")
    }
}

struct StickyThingsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewStickyThingIntent(),
            phrases: [
                "New sticky thing in \(.applicationName)",
                "Make a sticky thing in \(.applicationName)",
            ],
            shortTitle: "New Sticky Thing",
            systemImageName: "note.text"
        )
        AppShortcut(
            intent: SaveStickyThingIntent(),
            phrases: ["Save to \(.applicationName)"],
            shortTitle: "Save to Sticky Things",
            systemImageName: "tray.and.arrow.down"
        )
    }
}
