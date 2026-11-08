import AppKit
import Quartz

/// Space-bar previews through the system Quick Look panel (PDFs, images, documents, video…).
@MainActor
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private(set) var urls: [URL] = []
    var isVisible: Bool { QLPreviewPanel.sharedPreviewPanelExists() && (QLPreviewPanel.shared()?.isVisible ?? false) }

    func toggle(urls: [URL]) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if isVisible {
            panel.orderOut(nil)
            return
        }
        guard !urls.isEmpty else { return }
        self.urls = urls
        panel.makeKeyAndOrderFront(nil)
        panel.level = .statusBar + 1 // above our panel
        panel.reloadData()
    }

    /// Keep an open preview in sync with the keyboard selection.
    func show(urls: [URL]) {
        guard isVisible, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        panel.reloadData()
    }

    func close() {
        if isVisible { QLPreviewPanel.shared()?.orderOut(nil) }
    }

    // Called by the window that takes control of the panel (see QuickPanel).
    func attach(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    func detach(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { urls.indices.contains(index) ? urls[index] as NSURL : nil }
    }
}
