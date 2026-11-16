import SwiftUI

/// A small cross-process entry point: the Action Button, Control Center control and Home Screen
/// quick action all set a request that focuses the composer, including on a cold launch.
@MainActor
final class QuickCaptureRouter: ObservableObject {
    static let shared = QuickCaptureRouter()

    @Published private(set) var token = 0
    private var pending = false

    func request() {
        pending = true
        token += 1
    }

    /// True once per request, so the app focuses the composer only once.
    func consume() -> Bool {
        let shared = QuickCaptureFlag.consume()
        defer { pending = false }
        return pending || shared
    }
}
