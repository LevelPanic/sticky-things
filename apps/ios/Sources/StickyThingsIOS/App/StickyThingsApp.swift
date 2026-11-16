import SwiftUI
import UIKit

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
        completionHandler(true)
    }
}

@main
struct StickyThingsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
    }
}
