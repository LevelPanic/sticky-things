import StickyCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []
        let root = ShareView(providers: providers) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        let host = UIHostingController(rootView: root)
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }
}

private struct ShareView: View {
    let providers: [NSItemProvider]
    let onFinish: () -> Void

    @State private var clip: CapturedClip?
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                header
                preview
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 8)
                Button {
                    save()
                } label: {
                    if saving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Save to Sticky Things", systemImage: "tray.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(loading || saving || clip?.isEmpty != false)
            }
            .padding(20)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Sticky Things")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinish() }
                }
            }
            .task { await prepare() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Save to Sticky Things").font(.headline)
                Text(loading ? "Reading what you shared…" : "Ready to keep it on this iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var preview: some View {
        if loading {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .frame(height: 140)
                .overlay(ProgressView())
        } else if let clip, let text = clip.plainText, !text.isEmpty, clip.fileURLs.isEmpty {
            ScrollView {
                Text(text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
            .frame(maxHeight: 220)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground)))
        } else if let clip, let image = sharedImage(clip) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if let first = clip?.fileURLs.first {
            HStack(spacing: 12) {
                Image(systemName: "doc")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(first.lastPathComponent).font(.body.weight(.medium)).lineLimit(2)
                    Text(clip.map { $0.fileURLs.count == 1 ? "File" : "\($0.fileURLs.count) files" } ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground)))
        } else {
            Text("Nothing readable was shared.")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sharedImage(_ clip: CapturedClip) -> UIImage? {
        guard let data = clip.firstData(UTI.images)?.data else { return nil }
        return UIImage(data: data)
    }

    private func prepare() async {
        let loaded = await ItemProviderCapture.clip(from: providers)
        await MainActor.run {
            clip = loaded
            loading = false
        }
    }

    private func save() {
        guard let clip, !clip.isEmpty else { return }
        saving = true
        Task { @MainActor in
            do {
                let store = try ItemStore(paths: StickyAppGroup.paths)
                let capture = CaptureService(store: store)
                let accessed = clip.fileURLs.filter { $0.startAccessingSecurityScopedResource() }
                defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }
                _ = try capture.save(clip, source: nil)
                WidgetCenter.shared.reloadAllTimelines()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onFinish()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}
