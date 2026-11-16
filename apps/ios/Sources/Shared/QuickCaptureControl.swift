import AppIntents
import Foundation

/// Shared by the app and the Control Center extension. The intent is an `OpenIntent`, so the
/// system launches Sticky Things directly instead of showing an "Open in" URL confirmation.
enum StickyDestination: String, AppEnum {
    case compose

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Sticky Things"
    static var caseDisplayRepresentations: [StickyDestination: DisplayRepresentation] = [
        .compose: "New Sticky Thing",
    ]
}

struct OpenStickyThingIntent: OpenIntent {
    static let title: LocalizedStringResource = "New Sticky Thing"
    static let description = IntentDescription("Open Sticky Things with a new note ready to type.")
    static let openAppWhenRun = true

    @Parameter(title: "Screen")
    var target: StickyDestination

    init() {
        target = .compose
    }

    init(target: StickyDestination) {
        self.target = target
    }

    func perform() async throws -> some IntentResult {
        QuickCaptureFlag.request()
        return .result()
    }
}

/// The app group flag the control writes and the app consumes when it becomes active.
enum QuickCaptureFlag {
    private static let suite = "group.app.stickythings"
    private static let key = "pendingQuickCapture"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: suite) }

    static func request() {
        defaults?.set(true, forKey: key)
    }

    static func consume() -> Bool {
        guard let defaults, defaults.bool(forKey: key) else { return false }
        defaults.set(false, forKey: key)
        return true
    }
}
