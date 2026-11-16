import SwiftUI
import UIKit

/// A small cross-process entry point: the Control Center / Action Button control opens
/// `stickythings://new`, and this makes sure the composer appears even on a cold launch.
@MainActor
final class QuickCaptureRouter: ObservableObject {
    static let shared = QuickCaptureRouter()

    @Published private(set) var token = 0
    private var pending = false

    func request() {
        pending = true
        token += 1
    }

    /// True once per request, so the app opens the composer only once.
    func consume() -> Bool {
        let shared = QuickCaptureFlag.consume()
        defer { pending = false }
        return pending || shared
    }
}

extension Notification.Name {
    static let quickCapture = Notification.Name("app.stickythings.quickCapture")
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        guard shortcutItem.type == "new" else {
            completionHandler(false)
            return
        }
        QuickCaptureRouter.shared.request()
        NotificationCenter.default.post(name: .quickCapture, object: nil)
        completionHandler(true)
    }
}

@main
struct StickyThingsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
