import AppKit
import StickyCore
import StickyDesign
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: ItemStore
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(spacing: 0) {
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
        .frame(width: PanelLayout.width, height: model.panelHeight)
        .panelBackdrop()
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .overlay { if model.isDropTargeted { dropOverlay } }
        .accessibilityIdentifier("panel")
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.xs) {
                searchField
                IconButton(model.keepOpen ? "Let Panel Close" : "Keep Panel Open",
                           symbol: model.keepOpen ? "pin.fill" : "pin", isOn: model.keepOpen) { model.keepOpen.toggle() }
                IconButton("Settings", symbol: "gearshape") { model.openSettings() }
            }
            FilterBar(options: Self.filterOptions, selection: $model.filter)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Space.m)
        .padding(.top, Space.m)
        .padding(.bottom, Space.s)
    }

    static let filterOptions: [FilterBar<ItemFilter>.Option] = [
        .init(id: .all, title: "All", symbol: "square.stack"),
        .init(id: .notes, title: "Notes", symbol: "text.alignleft"),
        .init(id: .links, title: "Links", symbol: "link"),
        .init(id: .images, title: "Images", symbol: "photo"),
        .init(id: .files, title: "Files", symbol: "doc"),
    ]

    private var searchField: some View {
        HStack(spacing: Space.s - 2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textTertiary.color)
            KeyTextView(text: $model.search, height: $model.searchHeight,
                        placeholder: store.items.isEmpty ? "Search" : "Search \(store.items.count) items",
                        fontSize: 13, singleLine: true, focusToken: model.searchFocus,
                        onCommand: model.handleSearchCommand, identifier: "search")
                .frame(height: model.searchHeight)
                .accessibilityIdentifier("search")
            if model.isSearching {
                IconButton("Clear search", symbol: "xmark.circle.fill", size: Metrics.minHitTarget) {
                    model.search = ""
                    model.composerFocus += 1
                }
            }
        }
        .padding(.leading, Space.m - 2)
        .padding(.trailing, Space.xs)
        .frame(height: 32)
        .background(Capsule().fill(Palette.surfaceSunken.color))
        .overlay(Capsule().strokeBorder(Palette.border.color))
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
        .padding(.horizontal, Space.m)
        .padding(.bottom, Space.s)
    }

    private func errorBanner(_ message: String) -> some View {
        Banner(symbol: "externaldrive.badge.exclamationmark", message: message) { EmptyView() }
            .padding(.horizontal, Space.m)
            .padding(.bottom, Space.s)
    }

    private var pinnedStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s - 2) {
                ForEach(Array(model.pinnedItems.enumerated()), id: \.element.id) { index, item in
                    PinnedChip(item: item, index: index, model: model)
                }
            }
            .padding(.horizontal, Space.m)
        }
        .padding(.bottom, Space.s)
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
                LazyVStack(alignment: .leading, spacing: Space.s) {
                    Color.clear.frame(height: 0).id(Self.listStart)
                    ForEach(sections) { section in
                        SectionHeader(section.id)
                        ForEach(section.items) { item in
                            ItemCard(item: item, model: model)
                                .id(item.id)
                                .transition(.opacity.combined(with: .offset(y: model.listFlowsUp ? 8 : -8)))
                        }
                    }
                    Color.clear.frame(height: 0).id(Self.listEnd)
                }
                .padding(.horizontal, PanelLayout.listPadding)
                .padding(.vertical, Space.xs)
                .animation(Motion.standard, value: model.listItems.map(\.id))
            }
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

    private var composer: some View {
        let canSubmit = !settings.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: Space.s - 2) {
            HStack(alignment: .bottom, spacing: Space.s) {
                KeyTextView(text: $settings.draft, height: $model.composerHeight,
                            placeholder: "Write a note or paste anything",
                            fontSize: 14, maxLines: 8, focusToken: model.composerFocus,
                            onCommand: model.handleComposerCommand,
                            onPaste: model.paste(from:),
                            onFocusChange: { focused in DispatchQueue.main.async { model.composerFocused = focused } },
                            identifier: "composer")
                    .frame(height: model.composerHeight)
                    .accessibilityIdentifier("composer")
                Button(action: model.submitComposer) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(canSubmit ? Palette.accent : Palette.textDisabled.color)
                        .frame(width: Metrics.minHitTarget + 4, height: Metrics.minHitTarget + 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(!canSubmit)
                .help("Save Note (↩)")
                .accessibilityLabel("Save note")
            }
            .padding(.leading, Space.m + 2)
            .padding(.trailing, Space.xs)
            .padding(.vertical, Space.s - 1)
            .background(RoundedRectangle(cornerRadius: Radius.l + 4, style: .continuous).fill(Palette.surfaceRaised.color))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.l + 4, style: .continuous)
                    .strokeBorder(model.composerFocused ? Palette.accent.opacity(0.6) : Palette.border.color,
                                  lineWidth: model.composerFocused ? 1.5 : 1)
            )
            if model.selection != nil {
                KeyHint("↩", "copies it and closes the panel").padding(.horizontal, Space.xs).transition(.opacity)
            } else if model.composerFocused && settings.draft.isEmpty {
                KeyHint("⌘V", "saves whatever you copied").padding(.horizontal, Space.xs).transition(.opacity)
            }
        }
        .animation(Motion.quick, value: model.selection == nil)
        .padding(.horizontal, Space.m)
        .padding(.top, model.anchorAtBottom ? Space.s - 2 : 0)
        .padding(.bottom, model.anchorAtBottom ? Space.m : Space.s)
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
            VStack(spacing: Space.s - 2) {
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
            .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Palette.surfaceSunken.color))
        }
        .padding(Space.xl)
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(Palette.textSecondary.color)
            Text(text).font(TypeScale.callout).foregroundStyle(Palette.textPrimary.color).fixedSize(horizontal: false, vertical: true)
        }
    }
}
