# Sticky Things: notes for the next session

A native quick-capture app for macOS and iOS. On Mac it replaces Apple's Quick Note hot corner: click (or press ⌃⌥N), a panel opens, and you can paste or drag in anything. On iPhone it is built around the Action Button, Control Center, Lock Screen, share sheet, Siri, Shortcuts and Spotlight. Both apps share one library format. The owner treats it as a real product: "quick notes that are actually quick", intuitive like Bartender.

Keep this file current. After any change that moves the status, the known gaps or the conventions below, update this file (and the docs it points to) in the same commit.

## Read first

| Doc | When |
|---|---|
| [README.md](README.md) | What the user sees, keys, install |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Modules, data flow, storage layout, key decisions |
| [docs/PLATFORM.md](docs/PLATFORM.md) | macOS pasteboard, drag, file promise, privacy, focus and Hot Corners behavior; iOS Share extensions, App Groups, paste privacy and system entry points |
| [docs/DESIGN.md](docs/DESIGN.md) | Mac design tokens, components, writing rules; the iOS design approach; what the lint test enforces |
| [docs/TESTING.md](docs/TESTING.md) | The seven test layers (unit, design, app logic, self-test, layout audit, snapshots, iOS build) and the manual pass |

## Commands

```bash
make test        # 46 unit tests: StickyCore, StickyDesign (contrast + design lint), PanelModel
make selftest    # drives the real panel through in-process accessibility (57 checks incl. the grid, captions and drag-open, throwaway library)
make layout      # every panel state and Settings pane, light and dark: rules + captures and frames in build/layout
make snapshots   # renders every screen to build/snapshots (offscreen, flat surface instead of glass)
make install     # release build, copy to /Applications, relaunch (scripts/build-app.sh --install)
make run         # build and launch from ./build
make icon        # redraw apps/macos/Resources/AppIcon.icns + .png
make ios-project # regenerate apps/ios/StickyThings.xcodeproj from project.yml
make ios-build   # build the iOS app, Share extension, Home Screen widget and Control widget
make ios-open    # open the iOS project in Xcode
```

Before calling Mac work done: `make test`, `make selftest` and (for any visual change) `make layout` all green, look at the captures in `build/layout`, then `make install` so the user is running the latest build. Before calling iOS work done: `make ios-build` succeeds, then run the simulator smoke path in docs/TESTING.md. The Action Button and Control Center need a signed device.

## Layout

- `packages/StickyCore`: items, lossless capture model, SQLite + content-addressed blob store, file library (APFS clones), clipboard and drag output on Mac. The model and storage layers are cross-platform; AppKit capture/output and UIKit `NSItemProvider` capture are conditional. No SwiftUI.
- `packages/StickyDesign`: tokens (`Tokens.swift`, `Palette.swift`) and shared components. macOS-only for now.
- `apps/macos`: the macOS app. `Sources/StickyThings/` holds `App/` (delegate, `SelfTest`, `LayoutAudit` + `LayoutRules`, `Snapshot`), `Panel/`, `Corner/`, `Onboarding/`, `Settings/`, `System/`; `Resources/` holds the bundle files.
- `apps/ios`: `Sources/StickyThingsIOS` (app), `Sources/StickyThingsWidgets` (Control widget), `Sources/StickyThingsWidget` (Home Screen and Lock Screen widget), `Sources/StickyThingsShare` (Share extension), `Sources/Shared` (App Intents used by app + widget); `project.yml` generates the checked-in Xcode project.
- `packages/<Module>/Tests` and `apps/macos/Tests` mirror the Mac modules. iOS currently has no XCTest target; its shared core is covered by StickyCoreTests, and the system surfaces need the manual device pass.

Toolchain on the owner's Mac: macOS 26.1 (Apple Silicon), Xcode 26.1, Swift 6.2.1, iOS simulator 26.0 available. SwiftPM with Swift 5 language mode, deployment targets macOS 14 and iOS 18. Bundle id `app.stickythings.StickyThings` (same on both platforms), URL scheme `stickythings://` (`open`, `toggle`, `settings`, `setup`, `add?text=`), App Group `group.app.stickythings`.

Mac user data lives in `~/Library/Application Support/Sticky Things/` (`library.sqlite`, `blobs/`, `files/`, `staging/`); caches and the outbox in `~/Library/Caches/app.stickythings/`. iOS uses `group.app.stickythings/Sticky Things/`. Never point tests or the self-test at the real library.

## Conventions

- **Panel grid** (docs/DESIGN.md#panel-grid, enforced by `LayoutRules`): containers x = 12 to width − 12, content at x = 24, trailing buttons 4 pt in, 12 pt margin, 8 pt between blocks, fields radius 18 (search 36 pt; the composer is a text line plus a 28 pt toolbar line with the ⇧↩ hint and Save, room for more buttons left of Save), 28 pt control rows, panel radius 30. New panel elements get an accessibility identifier (or `layoutProbe` for layout boxes) and a rule.
- **Design system.** Use tokens only (spacing, radius, type, motion, colors); `DesignLintTests` fails on drift, including one-off nudges like `Space.s - 2`. Impeccable "Operate" rules: tinted neutrals, system accent, sticky yellow only as a note surface, no bounce, Reduce Motion crossfades, at least 11 pt text, 28 pt icon buttons.
- **Writing.** No em dashes, no exclamation marks. Labels are verb + object in Title Case. Glossary: item, note, Save, Delete, Pin. Prefer Undo over confirmation dialogs.
- **Selection follows where you're working** (docs/DESIGN.md#interaction; rule in `PanelModel`, "Where you're working"). New things you can click either select a card or call `pointedAtComposer`/`pointedAtSearch`/`clickedBackground`; anything that ends an edit goes through `finishEditing`. The model owns the open edit via `editHandle`; save or cancel through it rather than moving focus.
- **Clicks:** a card click goes through `PanelModel.click` (never call `copy` from a card's tap directly). It edits notes by default or copies them (`Settings.clickAction`, Settings ▸ Notes); links, images, files and concealed items always copy. `beginEditing` on the card already being edited keeps the edit.
- **Captions** are `Item.caption`, separate from the lossless snapshot. Media/documents (image, PDF, file, folder, files, color, other) get a speech-bubble button, ⌘⇧E, a right-click item and a VoiceOver action; notes and links do not. The editor is the same `InlineTextEditor`, with its own `captionEditHandle` and `captionEditSession`.
- **Corner drags** have two speeds: release quickly to save directly, hold for `Settings.dragOpenDelay` to shake and open the panel. `DragSessionWatcher` polls the pressed button and pointer because AppKit has no global drag notification; corners only grow to `dragTriggerArea` while that says a drag is in progress. A drag-open uses `PanelController.showForDrop` and must not make the panel key or activate the app.
- **iOS is a platform-native design, not the Mac panel stretched.** Use the HIG: `List`, `.searchable`, sheets, context menus, swipe actions, `ContentUnavailableView`, system share sheet, Quick Look, PhotosPicker and fileImporter. The Mac grid does not apply. Shared copy rules still do.
- **iOS system entry points are required.** The Action Button, Control Center and Lock Screen control use `OpenStickyThingIntent` (an `OpenIntent` in `Sources/Shared`, target membership both the app and the widget extension), never a custom URL, so iOS does not prompt "Open in Sticky Things?". It writes `QuickCaptureFlag` in the App Group; the app consumes it on launch/active and opens the composer. Home Screen quick actions, App Shortcuts/Siri and Spotlight have their own entry points.
- **iOS extensions share the App Group.** The app, Share extension, Control widget and Home Screen widget use `group.app.stickythings`; `StickyAppGroup.paths` is the only storage entry point. The Share extension normalizes providers with `ItemProviderCapture` and saves through the shared `CaptureService`. Never give an extension its own database path.
- **Widgets reload on writes.** `WidgetCenter.shared.reloadAllTimelines()` runs after saves, deletes, pins, caption edits and note edits in the app and Share extension. The Home Screen widget reads pinned/recent items, filters concealed copies, and deep-links rows with `stickythings://item/<uuid>`. Keep its timeline light; downsample image thumbnails in the widget process.
- **iOS paste is user-initiated.** Use SwiftUI's system `PasteButton`; never read `UIPasteboard` in the background. Share extensions and pickers are the permission-free way to receive content.
- **The iOS project is generated.** Edit `apps/ios/project.yml`, Sources and Resources, then run `make ios-project` and commit the regenerated `StickyThings.xcodeproj`. Do not hand-edit the pbxproj.
- **Nothing hover-only.** Every action is reachable by click (selected cards keep their buttons), right-click menu, keyboard shortcut and a named VoiceOver action.
- **Accessibility modifiers go before overlays** on a view, or the overlay's buttons disappear from the accessibility tree (this broke VoiceOver and the self-test once).
- **New UI behavior gets a self-test check** in `App/SelfTest.swift` (find by `accessibilityIdentifier`, act with AX press or named actions). New capture or storage behavior gets a `StickyCoreTests` case using a private `NSPasteboard(name:)` and a temp folder.
- **Settings is native** (`NavigationSplitView`, title in the toolbar, grouped `Form`s). Don't hand-position titles, sidebars or paddings there; style only our own content with tokens. Wording follows the glossary ("items", not "things").
- **No permission for decoration.** Never read the desktop picture or other user files to make something look nice (lint-enforced for `desktopImageURL`); draw it (`ScreenPreview`).
- **Pasteboard.** ⌘V must go through the main menu's Edit ▸ Paste (pasteboard privacy, macOS 15.4+). Never read the clipboard in the background. Hand files out as outbox clones, because Finder's ⌥⌘V moves pasted files.

## Gotchas already hit

- Synthesized `NSEvent` clicks don't reach SwiftUI controls. Drive UI through accessibility instead.
- When a window becomes key, AppKit focuses the first text field (search). `PanelController.focusComposer()` fixes it, and the self-test checks it.
- Transparent window pixels let hover and clicks fall through. The panel keeps `ignoresMouseEvents = false` on a real glass background.
- `.onHover` must come *after* any overlay that holds buttons. Placed before it, resting the pointer on the buttons counts as leaving the card and they vanish (v2.0 bug).
- `NSGlassEffectView` as a window's content draws its shadow into the square corners, and macOS then outlines a rectangle. `PanelChrome` clips the content view to the rounded shape.
- `NSViewRepresentable` text views: SwiftUI reuses platform views and skips `dismantleNSView`, AppKit skips `resignFirstResponder` for views removed from the window, and `textDidEndEditing` needs a change first. `InlineTextEditor` ends edits on resign *and* on leaving the window, takes focus in `viewDidMoveToWindow`, and each edit gets `.id(editSession)`. See docs/PLATFORM.md.
- A growing card in a lazy list can make SwiftUI build **two** platform views for one edit. Both must not finish the edit or update the shared height: `InlineEditHandle` tracks live owners per edit token, and a zero-width measurement copy neither attaches nor focuses (v2.9, found when adding captions).
- There is no public notification for a drag session started in another app. `DragSessionWatcher` watches the left button going down and samples `pressedMouseButtons` plus `mouseLocation` while it is held; only then do corners grow into their drag catch area. Global mouse monitoring does not need Accessibility; key monitoring does.
- Return in the composer must save typed text even when a card is selected (it used to copy the selected card and close the panel).
- The self-test needs an unlocked, idle Mac. While the screen is locked the panel can't become key, and if the owner types or clicks during a run their input lands in the test panel or closes it. Either way many text checks fail. Check `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]` and rerun before trusting a failing run.
- Measuring SwiftUI: an outer `.accessibilityIdentifier` on a non-element container overrides every identifier inside it (make it `.accessibilityElement(children: .contain)` first). A SwiftUI group's AX frame is the union of its children, and a short bottom-anchored `ScrollView` reports an offset frame; use `layoutProbe` for layout boxes. AX reports SF Symbols' ink, not their layout box.
- Focus doesn't tell you where the user clicked: clicking a field that already has the keyboard, or a non-focusable SwiftUI view, changes no responder. Text fields report clicks via `StickyTextView.mouseDown` (`onClick`); empty space via the panel's background tap.
- AppKit text views accept synthesized clicks (`Pointer.click` in the self-test; post the mouse-up first or the tracking loop waits). SwiftUI controls don't; use accessibility.
- Reading the desktop picture triggered a Files & Folders prompt (the owner's wallpaper lives under ~/Desktop). Anything that touches user files outside our library can prompt; check before adding it.
- Long SwiftUI expressions hit type-checker timeouts. Split them into small views or helper functions.
- Photos, Mail, Safari images and Preview pages arrive as file promises (`NSFilePromiseReceiver`), not file URLs.
- **XcodeGen's `info:` block generates and overwrites the plist at that path.** Keep custom plists in `apps/ios/Resources` and point `INFOPLIST_FILE` at them instead. This silently stripped `NSExtension` and the URL scheme once.
- A custom URL scheme opened from the shell or a control can show an "Open in Sticky Things?" confirmation on iOS. Controls use `OpenStickyThingIntent` (`OpenIntent`, target membership app + widget) and an App Group flag instead. Keep the URL scheme for automation and links, not for the Action Button.
- Share extensions and widget extensions are separate processes. They see nothing in the app sandbox; the App Group entitlements and `StickyAppGroup.paths` are mandatory. An unsigned simulator build may not share the container, so test the Share extension with a signed build.
- The Action Button and Control Center picker do not exist in the simulator. Build and test the control there, but assign it on a device.
- `quickLookPreview` lives in the QuickLook-exported SwiftUI module on iOS; add `import QuickLook`.
- A wide image in a ScrollView can widen the entire detail layout. Give thumbnails `.frame(maxWidth: .infinity)` before a fixed height and clip them; `.scaledToFill` alone will overflow.
- `apps/ios/Sources/StickyThingsWidget/` is a separate WidgetKit extension from the Control extension. A normal `Widget` cannot live in the same extension as a `ControlWidget` because `ControlWidget` is not a `Widget`, so they are two targets that both read the App Group.
- A widget deep link to `stickythings://item/<uuid>` goes through the app's `onOpenURL`; keep the identifier parsing stable. Widget taps to the app's own scheme are fine; do not use a custom URL for the Action Button control, which needs an `OpenIntent`.
- Widget timelines must not block the main actor with large files. `WidgetLibrary` downsamples image blobs to 420 px and only reads six items.

## Working in this environment

- Claude's sandbox here can't post input events (`CGPreflightPostEventAccess` is false) or screenshot other apps. It *can* capture the app's own windows (`WindowCapture` in `SelfTest.swift`; `STICKY_SELFTEST_CAPTURES=<folder> make selftest` saves them), which is how to check real glass, corners and layout.
- iOS builds work headlessly with Xcode 26.1. `make ios-build` builds the app and extensions; `xcrun simctl boot 'iPhone 17 Pro'`, install the `.app` from `build/ios/Build/Products/Debug-iphonesimulator`, and launch with `--demo`, `--composer` or `--detail` for screenshots. `xcrun simctl io 'iPhone 17 Pro' screenshot <path>` captures them. Action Button, Control Center and Share sheet pickers need a device or UI interaction.
- SwiftUI hover reads the real cursor, so synthetic mouse moves can't test it. Ask the owner to check hover and drags from other apps.
- Never change the owner's system settings (Hot Corners, `com.apple.dock` defaults) yourself. The onboarding's "Turn Off Quick Note" button is for the owner to press.
- Commit only when asked. Keep personal content (the owner's wallpaper, notes, paths) out of committed docs and screenshots.

## How the owner works

- Reports problems with annotated screenshots from real use, and expects the root cause fixed properly ("not a jugaad", no forcing), verified before it's called done, and tested so it can't come back (mutation-test new checks: break the fix, see the check fail, restore).
- Design bar: "line for line, column for column", a real design system, consistent proportions and whitespace; native macOS and iOS where the system already does it. Each platform should feel purposely designed for it, not ported.
- Wants this file, the docs and memory kept current with every change, and commits only when asked.

## Status (2026-11-16)

- **v1** (commit `51b29ac`): first working corner panel, JSON storage.
- **v2** (commit "Sticky Things v2: throw in anything…", 2026-11-08): three-module restructure, lossless capture of anything, SQLite storage with one-time v1 import, one-click copy, edit in place, Quick Look, drag out, Impeccable-based design system with contrast and lint tests, guided Hot Corners setup, new icon, accessibility-driven self-test. Installed in /Applications and running; the owner's 2 v1 notes migrated; the owner turned off their bottom-right Quick Note hot corner.
- **v2.1** (2026-11-08, from the owner's first real use): hover buttons no longer vanish while the pointer rests on them, and the panel's corners are round with no square outline. The self-test now checks the corners from a capture of the real window.
- **v2.2** (2026-11-08, from the owner's report that edit had no save and clicking the composer mid-edit froze the panel): editing shows Cancel and Save, Return saves, ⇧Return adds a line, Esc cancels, and clicking elsewhere or closing the panel saves. Fixed the stuck edit mode, Return in the composer copying the selected card and closing, edits lost on close, and "Edit Link" opening an empty edit mode. The composer's "↩ copies it and closes the panel" hint now only shows when Return really does that.
- **v2.3** (2026-11-08, design pass at the owner's request: "line for line, column for column"): one panel grid (above) in tokens and `FieldChrome`; the composer is a 36 pt capsule like search with centered text (it sat 14/7 pt off-center); hints moved into the placeholder so nothing jumps; section headers, image captions and the empty-state tips moved onto the columns; filter pills and chips on one 28 pt row; panel radius 30 (concentric); the composer no longer flashes a scroller; `make layout` audit + 4 grid checks in the self-test; lint against one-off nudges.
- **v2.4** (2026-11-08, owner's request): the composer is two lines in one field: text on top, a toolbar line below with "⇧↩ new line" and Save (room for more buttons). Grid rules and a self-test check cover it.
- **v2.5** (2026-11-08, owner's report): the card outline no longer lingers. Selection follows where you're working (composer, search, empty space, typing, ending an edit), empty space saves an open edit, and field chrome clicks focus their field. 5 self-test checks with real clicks on the text fields, mutation-tested.
- **v2.6** (2026-11-08, owner: the "new line" hint looked like a button): hints use `Palette.hint` (system placeholder tone, ≥ 3:1, quieter than secondary text, tested) in one weight; on tinted notes they use the paper's secondary ink.
- **v2.7** (2026-11-08, owner's request): a click on a note edits it in place by default; Settings ▸ Notes ▸ "Clicking a note" switches to copying. Links, images, files and hidden password copies always copy. Fixed: starting an edit you're already in rebuilt the editor (a double-click would have ended the edit).
- **v2.8** (2026-11-08, owner: Settings asked for a permission and had design issues): the corner preview is drawn (`ScreenPreview`, accent-tinted desktop) instead of reading the wallpaper from ~/Desktop, so no Files & Folders prompt; lint bans `desktopImageURL`. Settings rebuilt on native layout (sidebar, title in the toolbar, grouped forms) with tokens and glossary wording; `make layout` captures and checks every pane.
- **v2.9** (2026-11-12, owner's request): holding a drag in the corner now shakes the note and opens the panel after a configurable delay (default 0.6 s), after growing a configurable catch area (Small 44 / Medium 72 / Large 120 pt). A quick drop still saves directly. `DragSessionWatcher` supplies the missing global drag signal by sampling the pressed button and pointer. Images, PDFs, files, folders, colors and app data can now carry a searchable, undoable caption: card button, ⌘⇧E, right-click menu, VoiceOver action, and the inline editor. Fixed the inline editor's duplicate platform-view bug (a growing card in a lazy list built two; a zero-width copy stole focus and height) with token-aware `InlineEditHandle` tracking and readiness gating.
- **v3.0** (2026-11-16, owner's request): the repo is now a monorepo with `apps/macos`, `apps/ios`, `packages/StickyCore` and `packages/StickyDesign`. The macOS app is unchanged apart from its paths; its tests, self-test and layout audit still pass. `StickyCore` now builds on iOS with the AppKit capture and output behind `#if os(macOS)`. The new iOS app uses the same SQLite library in the App Group `group.app.stickythings`, with an Action Button / Control Center / Lock Screen control, a Share extension, Siri and Shortcuts intents, Spotlight indexing, system Paste, Quick Look, share sheet, context menus, swipe actions, iPad drag and drop, and a native list/composer/detail design. The control uses a real `OpenIntent` plus an App Group flag, so no URL confirmation. iOS simulator screenshots are in `docs/ios-*.png`. XcodeGen owns the checked-in iOS project.
- **v3.1** (2026-11-16, owner's request): a native Home Screen widget extension (`StickyThingsWidget`) with small, medium, large and Lock Screen accessory sizes. It reads pinned and recent items from the App Group, adds item deep links, a New Sticky Thing button in the large size, dynamic paper/ink colors, image thumbnails downsampled to 420 px, and an hourly timeline. The app and Share extension call `WidgetCenter.shared.reloadAllTimelines()` after writes. It is a separate extension from the Control widget because `ControlWidget` is not a `Widget`.

**Waiting on the owner:** the iPhone system pass: assign the control to the Action Button, add it to Control Center, add the Home Screen widget in every size, share a link/photo/PDF through the Share extension, ask Siri/Shortcuts, tap a Spotlight result, and test on an iPad. Earlier Mac questions still stand: drag-to-open feel, caption editing, click-to-edit, empty-space outline, layout/composer, Save/Cancel bar, hover buttons, round corners, and the drag matrix in docs/TESTING.md.

**Known gaps (candidates for next):**
- No iCloud/CloudKit sync between the Mac library and the iOS App Group library yet.
- The iOS app has no XCTest target; the shared core is covered by `StickyCoreTests`, and the system surfaces need the device pass.
- The iOS Share extension and widget require the App Group capability to be provisioned for device builds; unsigned simulator builds may not share the container.
- Action Button, Control Center and the Share sheet picker cannot be driven from the simulator or this headless environment.
- The onboarding window looks consistent but isn't covered by `LayoutRules` or `make layout` (only offscreen snapshots).
- The tap on empty space can't be automated (SwiftUI ignores synthesized clicks); the self-test runs the action it triggers.
- Dragging a multi-file item out carries only the first file (copying gives all of them).
- Concealed items (password-manager copies) show blurred but aren't encrypted on disk.
- `--snapshot` renders offscreen on a flat surface. The real glass look is only seen in self-test window captures and by hand; moving snapshots to own-window captures would make them true to life.
