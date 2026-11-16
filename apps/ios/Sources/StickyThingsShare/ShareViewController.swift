import StickyCore
import StickyIOSDesign
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
            VStack(alignment: .leading, spacing: StickySpace.l) {
                header
                preview
                if let error {
                    Text(error)
                        .font(StickyType.meta)
                        .foregroundStyle(StickyPalette.danger)
                }
                Spacer(minLength: StickySpace.s)
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
                .tint(StickyPalette.accent)
                .controlSize(.large)
                .disabled(loading || saving || clip?.isEmpty != false)
            }
            .padding(StickySpace.l)
            .background(StickyPalette.page)
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
        HStack(spacing: StickySpace.m) {
            Image(systemName: "note.text")
                .font(.title2.weight(.semibold))
                .frame(width: StickyMetrics.rowIcon, height: StickyMetrics.rowIcon)
                .background(
                    RoundedRectangle(cornerRadius: StickyRadius.m, style: .continuous)
                        .fill(StickyTintPalette.paper(.yellow))
                )
                .foregroundStyle(StickyTintPalette.ink(.yellow))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: StickySpace.xxs) {
                Text("Save to Sticky Things").font(StickyType.cardTitle)
                Text(loading ? "Reading what you shared…" : "Ready to keep it on this iPhone.")
                    .font(StickyType.meta)
                    .foregroundStyle(StickyPalette.textSecondary)
            }
        }
    }

    @ViewBuilder private var preview: some View {
        if loading {
            RoundedRectangle(cornerRadius: StickyRadius.l, style: .continuous)
                .fill(StickyPalette.surface)
                .frame(height: 140)
                .overlay(ProgressView())
        } else if let clip, let text = clip.plainText, !text.isEmpty, clip.fileURLs.isEmpty {
            ScrollView {
                Text(text)
                    .font(StickyType.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(StickySpace.l)
            }
            .frame(maxHeight: 220)
            .stickyCard()
        } else if let clip, let image = sharedImage(clip) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: StickyRadius.l, style: .continuous))
        } else if let first = clip?.fileURLs.first {
            HStack(spacing: StickySpace.m) {
                StickyKindTile(kind: .file, size: StickyMetrics.rowIcon)
                VStack(alignment: .leading, spacing: StickySpace.xs) {
                    Text(first.lastPathComponent).font(StickyType.button).lineLimit(2)
                    Text(clip.map { $0.fileURLs.count == 1 ? "File" : "\($0.fileURLs.count) files" } ?? "")
                        .font(StickyType.meta)
                        .foregroundStyle(StickyPalette.textSecondary)
                }
                Spacer()
            }
            .padding(StickySpace.l)
            .stickyCard()
        } else {
            Text("Nothing readable was shared.")
                .font(StickyType.body)
                .foregroundStyle(StickyPalette.textSecondary)
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
