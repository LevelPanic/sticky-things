import AppKit
import StickyDesign
import SwiftUI

/// The guided first run: pick a corner → free it from macOS's own hot corner → try it once.
@MainActor
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable, Comparable {
        case welcome, corner, freeCorner, tryIt, done
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    @Published var step: Step = .welcome
    /// What macOS runs from the chosen corner (e.g. "Quick Note"), or nil when it's free.
    @Published private(set) var conflict: String?
    /// Hot-corner actions on every corner, for the picker.
    @Published private(set) var cornerActions: [ScreenCorner: String] = [:]
    @Published private(set) var cornerTried = false
    @Published private(set) var waitingForDock = false

    let settings: Settings
    var onFinish: () -> Void = {}
    private var poll: Timer?

    init(settings: Settings) {
        self.settings = settings
        refresh()
    }

    var stepsShown: [Step] { [.welcome, .corner, .freeCorner, .tryIt] }

    func start() {
        refresh()
        // Re-read the Dock's settings every second so changes made in System Settings show up live.
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        poll?.invalidate()
        poll = nil
    }

    func refresh() {
        var actions: [ScreenCorner: String] = [:]
        for corner in ScreenCorner.allCases {
            if let action = MacHotCorners.conflictingAction(for: corner) { actions[corner] = action }
        }
        if actions != cornerActions { cornerActions = actions }
        let current = actions[settings.corner]
        if current != conflict { withAnimation(Motion.standard) { conflict = current } }
        if current == nil { waitingForDock = false }
    }

    func choose(_ corner: ScreenCorner) {
        settings.corner = corner
        cornerTried = false
        refresh()
    }

    func next() {
        var target = Step(rawValue: step.rawValue + 1) ?? .done
        if target == .freeCorner && conflict == nil { target = .tryIt }
        go(to: target)
    }

    func back() {
        var target = Step(rawValue: max(0, step.rawValue - 1)) ?? .welcome
        if target == .freeCorner && conflict == nil { target = .corner }
        go(to: target)
    }

    func go(to target: Step) {
        withAnimation(Motion.emphasized) { step = target }
        if target == .done { finish() }
    }

    /// One click: set the macOS hot corner to "–" and restart the Dock.
    func freeCornerForMe() {
        waitingForDock = true
        MacHotCorners.disable(settings.corner)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func openHotCornersSettings() {
        MacHotCorners.openHotCornersSettings()
    }

    /// The app calls this whenever a corner is clicked/hovered open.
    func cornerActivated() {
        guard step == .tryIt, !cornerTried else { return }
        withAnimation(Motion.emphasized) { cornerTried = true }
    }

    func finish() {
        stop()
        settings.onboardingVersion = Settings.currentOnboardingVersion
        onFinish()
    }
}
