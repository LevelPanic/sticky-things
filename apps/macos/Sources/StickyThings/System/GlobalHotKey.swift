import AppKit
import Carbon.HIToolbox

/// A system-wide shortcut via Carbon's RegisterEventHotKey (no Accessibility permission needed).
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var current: KeyCombo?
    /// True while the settings recorder is listening, so the old shortcut doesn't fire.
    var isSuspended = false {
        didSet {
            guard isSuspended != oldValue else { return }
            if isSuspended { unregisterKey() } else if let current { _ = registerKey(current) }
        }
    }

    @discardableResult
    func register(_ combo: KeyCombo?) -> Bool {
        unregisterKey()
        current = combo
        guard let combo, !isSuspended else { return combo == nil }
        installHandlerIfNeeded()
        return registerKey(combo)
    }

    private func registerKey(_ combo: KeyCombo) -> Bool {
        let id = EventHotKeyID(signature: OSType(0x5354_4B59), id: 1) // 'STKY'
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { hotKeyRef = nil }
        return status == noErr
    }

    private func unregisterKey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { GlobalHotKey.shared.onPress?() }
            }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}
