import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: NoteStore
    @ObservedObject var settings: Settings

    static let width: CGFloat = 384
    static let margin: CGFloat = 30 // transparent room for the shadow and the open animation
    static let cornerRadius: CGFloat = 26
    /// Snapshots render offscreen where Liquid Glass can't, so they use a flat background.
    nonisolated(unsafe) static var flatBackground = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if let action = model.conflictAction { conflictBanner(action) }
            if !model.pinnedNotes.isEmpty && !model.isSearching { pinnedStrip }
            if model.anchorAtBottom {
                notesArea
                composer
            } else {
                composer
                notesArea
            }
        }
        .frame(width: Self.width, height: model.panelHeight)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .panelBackground(cornerRadius: Self.cornerRadius)
        .overlay { if model.isDropTargeted { dropOverlay } }
        .scaleEffect(model.isPresented ? 1 : 0.86, anchor: model.scaleAnchor)
        .opacity(model.isPresented ? 1 : 0)
        .padding(Self.margin)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                KeyTextView(text: $model.search, height: $model.searchHeight,
                            placeholder: store.notes.isEmpty ? "Search" : "Search \(store.notes.count) notes",
                            fontSize: 13, singleLine: true, focusToken: model.searchFocus,
                            onCommand: model.handleSearchCommand)
                    .frame(height: model.searchHeight)
                if model.isSearching {
                    Button { model.search = ""; model.composerFocus += 1 } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(.background.opacity(0.4)))
            .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))

            CircleIconButton(symbol: model.keepOpen ? "pin.fill" : "pin",
                             help: model.keepOpen ? "Panel stays open — click to let it close on its own" : "Keep the panel open while you work",
                             size: 28, tint: model.keepOpen ? .accentColor : .primary) {
                model.keepOpen.toggle()
            }
            CircleIconButton(symbol: "gearshape", help: "Settings (⌘,)", size: 28) { model.openSettings() }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func conflictBanner(_ action: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("macOS \(action) also opens from this corner, so both will pop up. Turn it off to let Sticky Things take over.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { model.hideConflictBanner() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Hide this tip")
            }
            HStack(spacing: 8) {
                Button("Turn Off \(action) Corner") { model.disableMacHotCorner() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .help("Sets the macOS hot corner to “–” and restarts the Dock")
                Button("Hot Corners…") { MacHotCorners.openSystemSettings() }
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.3)))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var pinnedStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(model.pinnedNotes.enumerated()), id: \.element.id) { index, note in
                    PinnedChip(note: note, index: index, model: model, isFlashing: model.flashID == note.id)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
    }

    // MARK: List

    private struct Section: Identifiable {
        let id: String
        var notes: [Note]
    }

    private var sections: [Section] {
        var result: [Section] = []
        for note in model.listNotes {
            let title = RelativeTime.section(note.createdAt)
            if result.last?.id == title { result[result.count - 1].notes.append(note) } else { result.append(Section(id: title, notes: [note])) }
        }
        if model.listFlowsUp {
            result = result.reversed().map { Section(id: $0.id, notes: $0.notes.reversed()) }
        }
        return result
    }

    @ViewBuilder private var notesArea: some View {
        let notes = model.listNotes
        ZStack(alignment: model.anchorAtBottom ? .bottom : .top) {
            if notes.isEmpty {
                if model.isSearching { noResults } else if store.notes.isEmpty { emptyState } else { allPinnedState }
            } else {
                list
            }
            if let toast = model.toast {
                ToastView(toast: toast, undo: model.undo)
                    .padding(.vertical, 8)
                    .transition(.move(edge: model.anchorAtBottom ? .bottom : .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    Color.clear.frame(height: 0).id(Self.listStart)
                    ForEach(sections) { section in
                        Text(section.id.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)
                            .padding(.top, 6)
                        ForEach(section.notes) { note in
                            NoteCard(note: note, model: model, isSelected: model.selection == note.id,
                                     isFlashing: model.flashID == note.id)
                                .id(note.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: model.listFlowsUp ? .bottom : .top).combined(with: .opacity),
                                    removal: .opacity.combined(with: .scale(scale: 0.95))))
                        }
                    }
                    Color.clear.frame(height: 0).id(Self.listEnd)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.listNotes.map(\.id))
            }
            .defaultScrollAnchor(model.listFlowsUp ? .bottom : .top)
            .onAppear { scrollToNewest(proxy) }
            .onChange(of: model.openToken) { _, _ in scrollToNewest(proxy) }
            .onChange(of: model.isSearching) { _, _ in scrollToNewest(proxy) }
            .onChange(of: model.scrollRequest) { _, request in
                guard let request else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(request.id) }
            }
        }
    }

    /// Lazy stacks only estimate heights, so anchor explicitly on the newest note.
    private func scrollToNewest(_ proxy: ScrollViewProxy) {
        let target = model.listFlowsUp ? Self.listEnd : Self.listStart
        let anchor: UnitPoint = model.listFlowsUp ? .bottom : .top
        proxy.scrollTo(target, anchor: anchor)
        DispatchQueue.main.async { proxy.scrollTo(target, anchor: anchor) }
    }

    private static let listStart = "list-start"
    private static let listEnd = "list-end"

    private var emptyState: some View {
        VStack(spacing: 14) {
            MiniStickyNote(size: 64, foldCorner: .topLeft)
                .rotationEffect(.degrees(-6))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            VStack(spacing: 6) {
                Text("Your corner stash").font(.system(size: 15, weight: .semibold))
                Text("Type a note and press ↩, or press ⌘V to save whatever is on your clipboard — text, links, screenshots, files.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                hint("cursorarrow.click", "Click the \(settings.corner.name.lowercased()) corner of your screen to open this")
                hint("tray.and.arrow.down", "Drag anything onto the corner to stash it")
                if let combo = settings.hotKey { hint("keyboard", "Or press \(combo.displayString) from anywhere") }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.background.opacity(0.35)))
        }
        .padding(24)
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            Text(text).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 26)).foregroundStyle(.tertiary)
            Text("No notes match “\(model.search)”").font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(30)
        .frame(maxHeight: .infinity)
    }

    private var allPinnedState: some View {
        Text("Everything is pinned above.\nNew notes will stack up here.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxHeight: .infinity)
    }

    // MARK: Composer

    private var composer: some View {
        let isEditing = model.editingID != nil
        let text = model.composerText.wrappedValue
        let canSubmit = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            if isEditing {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                    Text("Editing note")
                    Spacer()
                    Button("Cancel") { model.cancelEditing() }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
            HStack(alignment: .bottom, spacing: 8) {
                KeyTextView(text: model.composerText, height: $model.composerHeight,
                            placeholder: isEditing ? "Edit note…" : "Type a note, or ⌘V to paste anything…",
                            fontSize: 14, maxLines: 8, focusToken: model.composerFocus,
                            onCommand: model.handleComposerCommand,
                            onPaste: model.handlePaste,
                            onFocusChange: { focused in DispatchQueue.main.async { model.composerFocused = focused } })
                    .frame(height: model.composerHeight)
                Button(action: model.submitComposer) {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(canSubmit ? Color.accentColor : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .help(isEditing ? "Save changes (↩)" : "Save note (↩)")
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.background.opacity(0.6)))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(model.composerFocused ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.1),
                                  lineWidth: model.composerFocused ? 1.5 : 1)
            )
            keyHints
        }
        .padding(.horizontal, 12)
        .padding(.top, model.anchorAtBottom ? 6 : 0)
        .padding(.bottom, model.anchorAtBottom ? 10 : 8)
    }

    private var keyHints: some View {
        let browse = model.anchorAtBottom ? "↑" : "↓"
        return HStack(spacing: 10) {
            keyHint("↩", model.selection != nil ? "copy" : "save")
            keyHint("⇧↩", "new line")
            keyHint(browse, "browse")
            keyHint("⌘V", "paste")
            keyHint("esc", "close")
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key).font(.system(size: 10, weight: .semibold, design: .rounded))
            Text(label).font(.system(size: 10))
        }
        .foregroundStyle(.tertiary)
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
            .background(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).fill(Color.accentColor.opacity(0.12)))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 30))
                    Text("Drop to save").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.accentColor)
            )
            .allowsHitTesting(false)
    }
}

// MARK: - Pieces

struct PinnedChip: View {
    let note: Note
    let index: Int
    let model: PanelModel
    let isFlashing: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(note.shortTitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 170)
        .foregroundStyle(note.color.paper == nil ? Color.primary : Color.black.opacity(0.8))
        .background(Capsule().fill(note.color.paper.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.background.opacity(hovering ? 0.75 : 0.55))))
        .overlay(Capsule().strokeBorder(isFlashing ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isFlashing ? 2 : 1))
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .onTapGesture { model.copy(note, closeAfter: false) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.open(note) })
        .onDrag { NoteActions.itemProvider(for: note, store: model.store) }
        .help(index < 9 ? "Click to copy · ⌘\(index + 1) copies and closes\n\(note.kind == .text ? note.text : note.shortTitle)" : note.shortTitle)
        .contextMenu {
            Button("Copy") { model.copy(note, closeAfter: false) }
            if note.kind == .text { Button("Edit") { model.beginEditing(note) } } else { Button("Open") { model.open(note) } }
            Button("Unpin") { model.togglePin(note) }
            Divider()
            Button("Delete", role: .destructive) { model.delete(note) }
        }
    }

    private var icon: String {
        switch note.kind {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}

struct ToastView: View {
    let toast: Toast
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.symbol).font(.system(size: 11, weight: .bold))
            Text(toast.text).font(.system(size: 12, weight: .medium))
            if toast.hasUndo {
                Button("Undo", action: undo)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}

extension View {
    /// Liquid Glass on macOS 26, a vibrant material before that.
    @ViewBuilder
    func panelBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if PanelView.flatBackground {
            self.background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(.primary.opacity(0.12)))
        } else if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.14)))
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        }
    }
}
