import AppKit
import Combine

/// What a click on a note does (Settings ▸ Notes ▸ Clicking a note).
enum ClickAction: String, CaseIterable, Identifiable {
    case edit, copy
    var id: String { rawValue }
}

/// User preferences, stored in UserDefaults.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults: UserDefaults

    @Published var corner: ScreenCorner { didSet { defaults.set(corner.rawValue, forKey: Keys.corner) } }
    @Published var trigger: CornerTrigger { didSet { defaults.set(trigger.rawValue, forKey: Keys.trigger) } }
    /// Seconds the pointer has to rest in the corner when `trigger == .hover`.
    @Published var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Keys.hoverDelay) } }
    /// Show the little note that peeks out of the corner when the pointer arrives.
    @Published var showPeek: Bool { didSet { defaults.set(showPeek, forKey: Keys.showPeek) } }
    /// Hold a drag in the corner for a moment to open the panel instead of saving on release.
    @Published var dragToOpen: Bool { didSet { defaults.set(dragToOpen, forKey: Keys.dragToOpen) } }
    /// Seconds a drag has to rest in the corner before the panel opens.
    @Published var dragOpenDelay: Double { didSet { defaults.set(dragOpenDelay, forKey: Keys.dragOpenDelay) } }
    /// How large the corner's temporary catch area is while a drag is in progress.
    @Published var dragTriggerArea: CornerDragArea { didSet { defaults.set(dragTriggerArea.rawValue, forKey: Keys.dragTriggerArea) } }
    @Published var allDisplays: Bool { didSet { defaults.set(allDisplays, forKey: Keys.allDisplays) } }
    @Published var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) } }
    @Published var hotKey: KeyCombo? {
        didSet {
            if let hotKey, let data = try? JSONEncoder().encode(hotKey) {
                defaults.set(data, forKey: Keys.hotKey)
            } else {
                defaults.set(Data(), forKey: Keys.hotKey) // empty = explicitly turned off
            }
        }
    }
    @Published var fetchLinkPreviews: Bool { didSet { defaults.set(fetchLinkPreviews, forKey: Keys.fetchLinkPreviews) } }
    /// Delete unpinned notes after this many days (0 = never).
    @Published var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: Keys.retentionDays) } }
    @Published var hideConflictBanner: Bool { didSet { defaults.set(hideConflictBanner, forKey: Keys.hideConflictBanner) } }
    /// Clicking a note edits it in place (the default) or copies it.
    @Published var clickAction: ClickAction { didSet { defaults.set(clickAction.rawValue, forKey: Keys.clickAction) } }
    /// Unsaved text in the composer survives closing the panel and relaunching.
    @Published var draft: String { didSet { defaults.set(draft, forKey: Keys.draft) } }

    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: Keys.hasLaunchedBefore) }
        set { defaults.set(newValue, forKey: Keys.hasLaunchedBefore) }
    }

    /// Bump to show the guided setup again after a meaningful change.
    static let currentOnboardingVersion = 2
    var onboardingVersion: Int {
        get { defaults.integer(forKey: Keys.onboardingVersion) }
        set { defaults.set(newValue, forKey: Keys.onboardingVersion) }
    }
    var needsOnboarding: Bool { onboardingVersion < Self.currentOnboardingVersion }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        corner = ScreenCorner(rawValue: defaults.string(forKey: Keys.corner) ?? "") ?? .bottomRight
        trigger = CornerTrigger(rawValue: defaults.string(forKey: Keys.trigger) ?? "") ?? .click
        hoverDelay = defaults.object(forKey: Keys.hoverDelay) as? Double ?? 0.25
        showPeek = defaults.object(forKey: Keys.showPeek) as? Bool ?? true
        dragToOpen = defaults.object(forKey: Keys.dragToOpen) as? Bool ?? true
        dragOpenDelay = defaults.object(forKey: Keys.dragOpenDelay) as? Double ?? 0.6
        dragTriggerArea = CornerDragArea(rawValue: defaults.string(forKey: Keys.dragTriggerArea) ?? "") ?? .medium
        allDisplays = defaults.object(forKey: Keys.allDisplays) as? Bool ?? true
        showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        if let data = defaults.data(forKey: Keys.hotKey) {
            hotKey = data.isEmpty ? nil : (try? JSONDecoder().decode(KeyCombo.self, from: data)) ?? .default
        } else {
            hotKey = .default
        }
        fetchLinkPreviews = defaults.object(forKey: Keys.fetchLinkPreviews) as? Bool ?? true
        retentionDays = defaults.object(forKey: Keys.retentionDays) as? Int ?? 0
        hideConflictBanner = defaults.bool(forKey: Keys.hideConflictBanner)
        clickAction = ClickAction(rawValue: defaults.string(forKey: Keys.clickAction) ?? "") ?? .edit
        draft = defaults.string(forKey: Keys.draft) ?? ""
    }

    private enum Keys {
        static let corner = "corner"
        static let trigger = "trigger"
        static let hoverDelay = "hoverDelay"
        static let showPeek = "showPeek"
        static let dragToOpen = "dragToOpen"
        static let dragOpenDelay = "dragOpenDelay"
        static let dragTriggerArea = "dragTriggerArea"
        static let allDisplays = "allDisplays"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let hotKey = "hotKey"
        static let fetchLinkPreviews = "fetchLinkPreviews"
        static let retentionDays = "retentionDays"
        static let hideConflictBanner = "hideConflictBanner"
        static let clickAction = "clickAction"
        static let draft = "draft"
        static let hasLaunchedBefore = "hasLaunchedBefore"
        static let onboardingVersion = "onboardingVersion"
    }
}
