import AppKit
import StickyCore
import StickyDesign
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: ItemStore
    @ObservedObject var settings: Settings

    /// The grid (docs/DESIGN.md, checked by the self-test): a 12 pt margin on every side,
    /// 8 pt between blocks, containers from x = 12 to width − 12, their content 12 pt in.
    var body: some View {
        VStack(spacing: PanelLayout.gap) {
            header
            if let action = model.conflictAction { conflictBanner(action) }
            if let error = store.lastError { errorBanner(error) }
            if !model.pinnedItems.isEmpty && !model.isFiltering { pinnedStrip }
            if model.anchorAtBottom {
                itemsArea
                composer
            } else {
                composer
                itemsArea
            }
        }
        .padding(.vertical, PanelLayout.inset)
        .frame(width: PanelLayout.width, height: model.panelHeight)
        // Empty space: anything with its own click (cards, buttons, chips, fields) handles it
        // first, so this only fires where nothing is.
        .contentShape(Rectangle())
        .onTapGesture { model.clickedBackground() }
        .coordinateSpace(name: LayoutRegistry.space)
        .panelBackdrop()
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .overlay { if model.isDropTargeted { dropOverlay } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("panel")
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: PanelLayout.gap) {
            HStack(spacing: Space.s) {
                searchField
                HStack(spacing: Space.xs) {
                    IconButton(model.keepOpen ? "Let Panel Close" : "Keep Panel Open",
                               symbol: model.keepOpen ? "pin.fill" : "pin", isOn: model.keepOpen) { model.keepOpen.toggle() }
                        .accessibilityIdentifier("keep-open")
                    IconButton("Settings", symbol: "gearshape") { model.openSettings() }
                        .accessibilityIdentifier("settings")
                }
            }
            FilterBar(options: Self.filterOptions, selection: $model.filter)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("filters")
        }
        .padding(.horizontal, PanelLayout.inset)
    }

    static let filterOptions: [FilterBar<ItemFilter>.Option] = [
        .init(id: .all, title: "All", symbol: "square.stack"),
        .init(id: .notes, title: "Notes", symbol: "text.alignleft"),
        .init(id: .links, title: "Links", symbol: "link"),
        .init(id: .images, title: "Images", symbol: "photo"),
        .init(id: .files, title: "Files", symbol: "doc"),
    ]

    private var searchField: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.textTertiary.color)
                .frame(width: Metrics.fieldIcon, alignment: .leading) // the glyph itself on the content column
            KeyTextView(text: $model.search, height: $model.searchHeight,
                        placeholder: store.items.isEmpty ? "Search" : "Search \(store.items.count) items",
                        fontSize: 13, singleLine: true, focusToken: model.searchFocus,
                        onCommand: model.handleSearchCommand,
                        onFocusChange: { focused in DispatchQueue.main.async { model.searchFocused = focused } },
                        onClick: { model.pointedAtSearch() },
                        identifier: "search")
                .frame(height: model.searchHeight)
                .accessibilityIdentifier("search")
            if model.isSearching {
                IconButton("Clear Search", symbol: "xmark.circle.fill") {
                    model.search = ""
                    model.composerFocus += 1
                }
                .accessibilityIdentifier("clear-search")
            }
        }
        .padding(.leading, Metrics.fieldInset)
        .padding(.trailing, model.isSearching ? Metrics.fieldButtonInset : Metrics.fieldInset)
        .fieldChrome(.sunken, focused: model.searchFocused)
        // The icon and padding are part of the field: clicking them goes to the text.
        .contentShape(RoundedRectangle(cornerRadius: Radius.field))
        .onTapGesture { model.pointedAtSearch(focus: true) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search-field")
    }

    private func conflictBanner(_ action: String) -> some View {
        Banner(message: "macOS also opens \(action) from this corner, so both appear. Turn it off to give the corner to Sticky Things.",
               onDismiss: model.hideConflictBanner) {
            Button("Turn Off \(action)") { model.disableMacHotCorner() }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .help("Sets the macOS hot corner to “–” and restarts the Dock")
            Button("Open Hot Corners…") { MacHotCorners.openHotCornersSettings() }
                .controlSize(.small)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("banner")
        .padding(.horizontal, PanelLayout.inset)
    }

    private func errorBanner(_ message: String) -> some View {
        Banner(symbol: "externaldrive.badge.exclamationmark", message: message) { EmptyView() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("error-banner")
            .padding(.horizontal, PanelLayout.inset)
    }

    /// Scrolls edge to edge so chips can pass under the panel's margin; the first chip still
    /// starts on the outer column.
    private var pinnedStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(Array(model.pinnedItems.enumerated()), id: \.element.id) { index, item in
                    PinnedChip(item: item, index: index, model: model)
                }
            }
            .padding(.horizontal, PanelLayout.inset)
        }
        .frame(height: Metrics.controlRow)
        .accessibilityIdentifier("pinned")
    }

    // MARK: Items

    private struct Section: Identifiable {
        let id: String
        var items: [Item]
    }

    private var sections: [Section] {
        var result: [Section] = []
        for item in model.listItems {
            let title = RelativeTime.section(item.createdAt)
            if result.last?.id == title { result[result.count - 1].items.append(item) } else { result.append(Section(id: title, items: [item])) }
        }
        if model.listFlowsUp {
            result = result.reversed().map { Section(id: $0.id, items: $0.items.reversed()) }
        }
        return result
    }

    @ViewBuilder private var itemsArea: some View {
        ZStack(alignment: model.anchorAtBottom ? .bottom : .top) {
            if model.listItems.isEmpty {
                if model.isFiltering { noResults } else if store.items.isEmpty { EmptyStateView(settings: settings) } else { allPinned }
            } else {
                list
            }
            if let toast = model.toast {
                toastView(toast)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutProbe("items")
    }

    private func toastView(_ toast: Toast) -> some View {
        let undo: (() -> Void)? = toast.canUndo ? { model.undo() } : nil
        let shift: CGFloat = model.anchorAtBottom ? 6 : -6
        return ToastView(text: toast.text, symbol: toast.symbol, isError: toast.isError,
                         actionTitle: toast.canUndo ? "Undo" : nil, action: undo)
            .padding(.vertical, Space.s)
            .transition(AnyTransition.opacity.combined(with: .offset(y: shift)))
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // The end markers sit outside the lazy stack so its spacing doesn't pad the ends.
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id(Self.listStart)
                    LazyVStack(alignment: .leading, spacing: PanelLayout.gap) {
                        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                            SectionHeader(section.id, isFirst: index == 0)
                            ForEach(section.items) { item in
                                ItemCard(item: item, model: model)
                                    .id(item.id)
                                    .transition(.opacity.combined(with: .offset(y: model.listFlowsUp ? 8 : -8)))
                            }
                        }
                    }
                    Color.clear.frame(height: 0).id(Self.listEnd)
                }
                .padding(.horizontal, PanelLayout.inset)
                .animation(Motion.standard, value: model.listItems.map(\.id))
            }
            .accessibilityIdentifier("list")
            .scrollIndicators(.automatic)
            .defaultScrollAnchor(model.listFlowsUp ? .bottom : .top)
            .keepsNewestEndAnchored(model.listFlowsUp)
            .onAppear { scrollToNewest(proxy) }
            .onChange(of: model.openToken) { _, _ in scrollToNewest(proxy) }
            .onChange(of: model.isFiltering) { _, _ in scrollToNewest(proxy) }
            .onChange(of: model.scrollRequest) { _, request in
                guard let request else { return }
                withAnimation(Motion.standard) { proxy.scrollTo(request.id) }
            }
        }
    }

    /// Lazy stacks only estimate heights, so anchor explicitly on the newest end.
    private func scrollToNewest(_ proxy: ScrollViewProxy) {
        let target = model.listFlowsUp ? Self.listEnd : Self.listStart
        let anchor: UnitPoint = model.listFlowsUp ? .bottom : .top
        proxy.scrollTo(target, anchor: anchor)
        DispatchQueue.main.async { proxy.scrollTo(target, anchor: anchor) }
    }

    private static let listStart = "list-start"
    private static let listEnd = "list-end"

    private var noResults: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass").font(.system(size: 22)).foregroundStyle(Palette.textTertiary.color)
            Text(model.isSearching ? "No items match “\(model.search)”" : "No \(model.filter.rawValue) yet")
                .font(TypeScale.body).foregroundStyle(Palette.textSecondary.color)
            if model.isSearching {
                Button("Clear Search") { model.search = ""; model.composerFocus += 1 }.buttonStyle(.link).font(TypeScale.callout)
            } else if model.filter != .all {
                Button("Show All Items") { model.filter = .all }.buttonStyle(.link).font(TypeScale.callout)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var allPinned: some View {
        Text("Everything is pinned above.\nNew items stack up here.")
            .font(TypeScale.footnote)
            .foregroundStyle(Palette.textSecondary.color)
            .multilineTextAlignment(.center)
            .frame(maxHeight: .infinity)
    }

    // MARK: Composer

    /// Two lines in one field: the text on top (full width, on the content column), and a
    /// toolbar below it with the ⇧↩ hint on the left and the buttons on the right, 4 pt in from
    /// the bottom corner. Text grows upward; the toolbar stays put. Nothing appears or
    /// disappears around it, so focusing or typing never moves the layout.
    private var composer: some View {
        let canSubmit = !settings.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: PanelLayout.composerLineGap) {
            KeyTextView(text: $settings.draft, height: $model.composerHeight,
                        placeholder: composerPlaceholder,
                        fontSize: Self.composerFontSize, maxLines: 8, focusToken: model.composerFocus,
                        onCommand: model.handleComposerCommand,
                        onPaste: model.paste(from:),
                        onFocusChange: { focused in DispatchQueue.main.async { model.composerFocused = focused } },
                        onClick: { model.pointedAtComposer() },
                        identifier: "composer")
                .frame(height: model.composerHeight)
                .padding(.horizontal, Metrics.fieldInset)
                .accessibilityIdentifier("composer")
            composerToolbar(canSubmit: canSubmit)
        }
        .padding(.top, PanelLayout.composerTopInset)
        .padding(.bottom, Metrics.fieldButtonInset)
        .fieldChrome(.raised, focused: model.composerFocused)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("composer-field")
        .padding(.horizontal, PanelLayout.inset)
    }

    /// The composer's bottom line. Buttons line up on the right, 4 pt apart, newest feature
    /// leftmost; Save always stays in the corner. Clicking the empty part focuses the text.
    private func composerToolbar(canSubmit: Bool) -> some View {
        HStack(spacing: Space.xs) {
            KeyHint("⇧↩", "new line")
                .accessibilityIdentifier("composer-hint")
            Spacer(minLength: Space.s)
            Button(action: model.submitComposer) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canSubmit ? Palette.accent : Palette.textDisabled.color)
                    .frame(width: Metrics.iconButton, height: Metrics.iconButton)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(!canSubmit)
            .help("Save Note (↩)")
            .accessibilityLabel("Save note")
            .accessibilityIdentifier("send")
        }
        .padding(.leading, Metrics.fieldInset)
        .padding(.trailing, Metrics.fieldButtonInset)
        .frame(height: Metrics.controlRow)
        .contentShape(Rectangle())
        .onTapGesture { model.pointedAtComposer(focus: true) }
    }

    static let composerFontSize: CGFloat = 14

    /// The composer's hint: what Return does right now.
    private var composerPlaceholder: String {
        model.selection != nil && model.editingID == nil
            ? "Press Return to copy the selected item"
            : "Write a note or press ⌘V to save anything"
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
            .strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            .background(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).fill(Palette.accent.opacity(0.1)))
            .overlay(
                VStack(spacing: Space.s) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 26, weight: .medium))
                    Text("Drop to save").font(TypeScale.title)
                }
                .foregroundStyle(Palette.accent)
            )
            .allowsHitTesting(false)
    }
}

/// Layout boxes that accessibility can't report faithfully (a SwiftUI group reports the union of
/// its children, and a short bottom-anchored scroll view reports an offset frame). Recorded only
/// while the self-test or the layout audit runs.
@MainActor
enum LayoutRegistry {
    static let space = "panel"
    static var isRecording = false
    static var frames: [String: CGRect] = [:]
}

extension View {
    /// Records this view's frame in panel coordinates (origin top-left) for `LayoutRules`.
    func layoutProbe(_ id: String) -> some View {
        background(GeometryReader { proxy in
            let frame = proxy.frame(in: .named(LayoutRegistry.space))
            Color.clear
                .onAppear { if LayoutRegistry.isRecording { LayoutRegistry.frames[id] = frame } }
                .onChange(of: frame) { _, new in if LayoutRegistry.isRecording { LayoutRegistry.frames[id] = new } }
        })
    }
}

private extension View {
    /// Lazy stacks only estimate row heights; on macOS 15+ keep the newest end pinned while
    /// rows measure themselves and thumbnails load, so the last card is never cut off.
    @ViewBuilder func keepsNewestEndAnchored(_ bottom: Bool) -> some View {
        if #available(macOS 15.0, *) {
            self.defaultScrollAnchor(bottom ? .bottom : .top, for: .initialOffset)
                .defaultScrollAnchor(bottom ? .bottom : .top, for: .sizeChanges)
        } else {
            self
        }
    }
}

/// A pinned item: one click copies, double-click opens, right-click for more.
struct PinnedChip: View {
    let item: Item
    let index: Int
    @ObservedObject var model: PanelModel

    var body: some View {
        Chip(item.headline, symbol: symbol, tint: item.kind.isTextual ? item.tint.swatch : nil,
             isHighlighted: model.copiedID == item.id)
            .onTapGesture { model.copy(item) }
            .simultaneousGesture(TapGesture(count: 2).onEnded { model.activate(item) })
            .onDrag { PasteboardWriter.itemProvider(for: item, store: model.store) }
            .contextMenu { CardMenuItems(item: item, model: model, compact: false) }
            .help(index < 9 ? "Click to copy. ⌘\(index + 1) copies it and closes the panel." : "Click to copy")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pinned \(item.kind.label.lowercased()), \(item.headline)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.copy(item) }
            .accessibilityAction(named: "Unpin") { model.togglePin(item) }
            .accessibilityIdentifier("pin-\(item.id.uuidString)")
    }

    private var symbol: String {
        switch item.kind {
        case .text, .richText: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .file, .files: return "doc"
        case .folder: return "folder"
        case .color: return "paintpalette"
        case .other: return "shippingbox"
        }
    }
}

/// What you see before you've saved anything: teaches the next step.
struct EmptyStateView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(spacing: Space.l) {
            MiniStickyNote(size: 52, foldCorner: .topLeft)
                .rotationEffect(.degrees(-6))
                .elevation(.sticky)
            VStack(spacing: Space.s) {
                Text("Nothing saved yet").font(TypeScale.title).foregroundStyle(Palette.textPrimary.color)
                Text("Write below and press Return, or press ⌘V to save whatever you copied. You can also drop files, PDFs, images and links here.")
                    .font(TypeScale.callout)
                    .foregroundStyle(Palette.textSecondary.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 260)
            VStack(alignment: .leading, spacing: Space.s) {
                row("cursorarrow.click", "Click the \(settings.corner.name.lowercased()) corner of your screen to open this panel")
                row("tray.and.arrow.down", "Drag anything onto that corner to save it without opening the panel")
                if let combo = settings.hotKey { row("keyboard", "Press \(combo.displayString) in any app") }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Palette.surfaceSunken.color))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("empty-tips")
        }
        .padding(.horizontal, PanelLayout.inset)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("empty-state")
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(Palette.textSecondary.color)
            Text(text).font(TypeScale.callout).foregroundStyle(Palette.textPrimary.color).fixedSize(horizontal: false, vertical: true)
        }
    }
}
