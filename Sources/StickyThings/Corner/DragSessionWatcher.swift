import AppKit
import StickyDesign

/// Tells the corner when the user is dragging something anywhere on the Mac.
///
/// AppKit has no public notification for "a drag started in another app", and a drag session
/// does not deliver its mouse events to us. It does leave two signals readable process-wide:
/// the mouse button is down, and the pointer moves. So watch the button going down, then sample
/// the button and cursor while it is held. A drag of a few points counts; a click does not.
///
/// The corner only grows into its catch area while this says a drag is in progress, so at rest
/// it stays the same tiny, out-of-the-way target it always was.
@MainActor
final class DragSessionWatcher {
    var onDragChange: ((Bool) -> Void)?

    private var downMonitor: Any?
    private var localDownMonitor: Any?
    private var poll: Timer?
    private var pressOrigin: NSPoint?
    private var dragging = false

    func start() {
        guard downMonitor == nil else { return }
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
        localDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.mouseDown()
            return event
        }
    }

    func stop() {
        if let downMonitor { NSEvent.removeMonitor(downMonitor) }
        if let localDownMonitor { NSEvent.removeMonitor(localDownMonitor) }
        downMonitor = nil
        localDownMonitor = nil
        stopPolling()
        setDragging(false)
    }

    private func mouseDown() {
        pressOrigin = NSEvent.mouseLocation
        startPolling()
    }

    private func startPolling() {
        guard poll == nil else { return }
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        // Drags run the source app's run loop in event tracking mode; a new window appearing
        // under the pointer must not wait for that to end.
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func sample() {
        guard NSEvent.pressedMouseButtons & 1 == 1 else {
            stopPolling()
            pressOrigin = nil
            setDragging(false)
            return
        }
        let location = NSEvent.mouseLocation
        guard let origin = pressOrigin else { pressOrigin = location; return }
        guard !dragging else { return }
        let moved = hypot(location.x - origin.x, location.y - origin.y)
        if moved >= Space.xs { setDragging(true) }
    }

    private func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    private func setDragging(_ value: Bool) {
        guard value != dragging else { return }
        dragging = value
        onDragChange?(value)
    }
}
