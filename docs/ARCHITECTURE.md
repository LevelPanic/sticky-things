# Architecture

Sticky Things is a monorepo. A shared Swift core powers the Apple apps, while each app uses the native UI and system surfaces of its platform. A future Windows or Android app can read the same SQLite schema and blob layout without adopting SwiftUI.

```text
packages/StickyCore      items, lossless capture model, SQLite, blobs, files   (no SwiftUI; macOS + iOS)
packages/StickyDesign    tokens + components                                  (macOS design system)
apps/macos               the Mac app: corner, panel, onboarding, settings, menu bar
apps/ios                 the iPhone app, Share extension and Control widget
```

## The one idea: capture losslessly, give back exactly

People can throw *anything* in: text from any app, rich text, links, screenshots, PDFs, files, Figma layers, password-manager copies. Whatever comes in has to come back out unchanged. So an item is not reduced to text or an image. It keeps everything the pasteboard had.

```text
⌘V / drop / corner drop
        │
        ▼
PasteboardSnapshotter ──► CapturedClip           every NSPasteboardItem × every type (bytes in memory)
        │                                         skips only noise, unsafe and oversized types
        ▼
Classifier ──► kind, text, title, link, size      pure function: how to *show* it (never touches disk)
        │
        ▼
CaptureService ──► Item                           blobs → BlobStore (SHA-256, deduplicated)
        │                                         files → FileLibrary (APFS clone of the file)
        ▼
ItemStore (SQLite + in-memory list) ──► SwiftUI
        │
        ▼
PasteboardWriter                                  replays every item and type in order; files are
                                                  handed out as fresh clones from an outbox
```

The diagram shows the Mac path. On iOS the same `CapturedClip` comes from `ItemProviderCapture` (share sheet, drop, paste) and output goes through the system share sheet, Quick Look, copy and paste, not `PasteboardWriter`.

* **`Item`** (`StickyCore/Model/Item.swift`)
  * `kind` decides how the item is drawn.
  * `snapshot` is the lossless pasteboard copy, as `[SnapshotItem]`, each holding `[Representation(type, blob)]`.
  * `files` holds our stored copies of files.
  * `caption` is text you add to a non-text item (image, PDF, file, folder, color). It is UI metadata, never part of the captured data, so copying the item still gives back exactly what came in.
  * Items typed in the app have an empty snapshot; their `text` is the content.
* **`Classifier`** decides the kind:
  * Files win.
  * Image data beats text, unless the text is real: spreadsheets add a picture of the cells.
  * PDF data, then links, then rich text, then plain text, then colors.
  * Anything else is `other`, shown as "Data from Figma" and still given back exactly.
* **Duplicates.** A fingerprint (a hash of every type's bytes) stops the same paste from being saved twice in a row.

## Storage

The Mac library lives in `~/Library/Application Support/Sticky Things/`. The iOS app and its Share extension use the same layout inside the App Group container `group.app.stickythings/Sticky Things/`.

| Path | What |
|---|---|
| `library.sqlite` | One row per item: indexed columns (id, created, pinned, kind) plus the full item as JSON. WAL mode; every change is its own transaction. |
| `blobs/ab/abcdef…` | Content-addressed data. Two items with the same screenshot share one file. |
| `files/<item-id>/<original name>` | Copies of stashed files. On the same APFS volume this is a clone: instant, and no extra space until one side changes. |
| `staging/` | File promises being received (Photos, Mail, Safari images, Preview pages), and iOS share providers that arrive as data. |
| `notes-v1-imported.json` | The version 1 notes file, kept after the one-time import. |

* **Caches** (`~/Library/Caches/app.stickythings/` on Mac, the app's temporary directory on iOS) can be deleted at any time. They hold Quick Look temp files, drag files and **outbox** clones.
* **Garbage collection** runs at launch. It removes blobs and file folders that no item references, and an hour of grace keeps undo safe.
* **Retention** (Settings ▸ Notes) deletes unpinned items older than N days.
* **iOS App Group.** The app, Share extension, and Control widget are separate processes. The Entitlements files declare `group.app.stickythings`; `StickyAppGroup.paths` is the single entry point that keeps them on the same library. Without the capability, each process falls back to its own Application Support folder.

## The app layer

| Piece | Job |
|---|---|
| `CornerManager` / `CornerWindow` | A 6×6 pt always-on-top window in each "hard" screen corner. It stays tiny at rest, grows into a catch area while a drag is in progress, peeks on hover, and acts as a drop target. Holding a drag there shakes the note and opens the panel after a delay; a quick drop saves straight away. |
| `DragSessionWatcher` | Watches the pressed mouse button and pointer movement, because AppKit has no public notification for a drag started in another app. It tells the corners when a drag begins and ends. |
| `PanelController` / `QuickPanel` | A borderless `NSPanel` on system glass (`NSGlassEffectView`). It takes the keyboard without making your current app inactive, like Spotlight. Focus goes back where it was. |
| `PanelModel` | Every panel action: copy, edit, pin, delete/undo, paste, drop, Quick Look, keyboard. Views only call these, so behavior is unit-tested. |
| `ItemCard`, `PanelView` | SwiftUI views built from `StickyDesign` components. |
| `SettingsView` / `SettingsWindowController` | Native Settings: a `NavigationSplitView` sidebar, the pane title in the toolbar, grouped forms. `SettingsNavigation` holds the pane so the menu bar's "Set Up Corner…" can switch to it. |
| `OnboardingModel` / `OnboardingView` | First run: pick a corner, free it from macOS Hot Corners (live status), then try it once. |
| `SelfTest`, `LayoutAudit`, `Snapshot` | `--selftest` drives the real UI and checks the grid; `--layout` walks the real panel through every state, captures it and checks `LayoutRules`; `--snapshot` renders every screen to PNGs. |

### iOS

| Piece | Job |
|---|---|
| `Library` | Wraps the shared `ItemStore` and `CaptureService`, owns search/filter state, and forwards store changes to SwiftUI. The store opens after the first view frame so the composer appears immediately. |
| `RootView`, `ItemRow`, `ItemDetailView` | Native list, persistent ChatGPT-style composer, context menus, swipe actions, search, item detail, system share sheet and Quick Look. |
| `StickyThingsShare` extension | Receives text, URLs, images and files from other apps. `ItemProviderCapture` normalizes providers into a `CapturedClip`; the extension saves it into the shared App Group library. |
| `StickyThingsWidgets` | A `ControlWidget` for Control Center, the Lock Screen and the Action Button. It runs `OpenStickyThingIntent`, an `OpenIntent` shared with the app, so the system launches Sticky Things without a URL confirmation. |
| `StickyThingsWidget` | A separate WidgetKit extension for the Home Screen and Lock Screen accessories. It reads pinned and recent items from the App Group, downsamples image thumbnails, shows count and relative time, and links each row to `stickythings://item/<uuid>`. |
| `QuickCaptureFlag` | The small App Group flag the control writes and the app consumes when it becomes active; it focuses the composer. |
| `StickyIntents` | App Shortcuts and Siri actions: New Sticky Thing and Save to Sticky Things. |
| `SpotlightIndexer` | Indexes item titles, captions and text in the private on-device Spotlight index; concealed items are never indexed. |

### Decisions worth knowing

* **The panel's hit area is solid.** The window ignores no mouse events, and its background is real system glass. Transparent pixels let clicks and hovers fall through to the window behind, which is what broke hover in v1.
* **The window is the panel's shape.** The content view clips to the rounded corners, so the glass's own shadow can't fill the square corners and make macOS outline a rectangle.
* **Hover wraps the card's buttons.** `.onHover` sits after the overlay that holds the buttons, so resting on them still counts as hovering the card.
* **The selection follows where you're working.** The outlined card is what Return, ⌘C and its buttons act on. Clicking a card, ↑ ↓ and Edit select it. Clicking the composer or search (`KeyTextView.onClick`, sent even when the field already has the keyboard), clicking empty space (a tap on the panel's background, which only fires where nothing else takes the click), typing a note, or finishing an edit clears it. The rule lives in `PanelModel` ("Where you're working"), not in views.
* **The model owns the open edit.** One `InlineEditHandle` serves the whole list, so a click on empty space can *save* the edit, the same as clicking away, instead of forcing focus somewhere. An editor that finishes late never unhooks the one that replaced it.
* **A click does one thing, and you choose it.** `PanelModel.click` edits a note in place (the default) or copies it (`Settings.clickAction`); anything that can't be edited in place, or is a hidden password copy, is copied. VoiceOver's default action on a card is the same `click`. Starting an edit you're already in keeps it (no rebuild), so a double-click is harmless.
* **The corner has two drop speeds.** A quick drop on it saves without opening anything. Holding the drag there for the configured delay (with a short shake and a configurable catch area) opens the panel so the thing can be dropped into the stack, with its caption editor and the rest of the panel one step away. Opening this way does not activate the app or take the keyboard away from the drag's source.
* **Captions are not capture content.** `Item.caption` is stored next to the lossless snapshot, not in it, so adding words to an image or PDF never changes what that item gives back when copied. Captions are searchable and editable on the card with the same inline editor as notes.
* **iOS is designed for iOS, not shrunk from the Mac.** The Mac's floating panel, hot corner and pointer grid have no place on a phone. The iOS app uses a native list, search, sheets, context menus, swipe actions, the system share sheet, Quick Look, Paste, Photos and Files pickers, and the system entry points people already know.
* **The composer paints before the library opens.** SwiftUI builds the shell, list placeholder and bottom composer first; `Library.load` opens SQLite after that frame, then defers garbage collection, the old-note import and Spotlight indexing by a beat. Along with a launch-screen color asset, this keeps the path from the Action Button to a blinking cursor short and avoids blocking the first paint on disk work.
* **One library, several processes.** The iOS app, Share extension and Control widget are separate sandboxes. App Group storage plus `ItemProviderCapture` keep them on one library and one lossless item format. The control uses an `OpenIntent` with a shared App Group flag, not a custom URL, so the system launches the app directly instead of asking "Open in Sticky Things?".
* **Spotlight is private and selective.** iOS indexes item titles, captions and text in the on-device Spotlight index. Concealed password-manager copies are never indexed. The index is not synced anywhere.
* **The Home Screen widget is a second extension, not part of the control.** `ControlWidget` is not a `Widget`, so the Control Center control and the Home Screen widget live in separate extensions with separate bundle ids. Both read the App Group and both reload when the app writes. The widget loads at most six items and downsamples image blobs so the timeline stays cheap.
* **No background pasteboard reads on either platform.** macOS goes through Edit ▸ Paste; iOS pastes only when someone uses the system edit menu in the composer or a text field.
* **Nothing is hover-only.** A clicked card is selected (or being edited), and a selected card keeps its buttons. Every action is also in the right-click menu, a keyboard shortcut and a VoiceOver action.
* **⌘V goes through the main menu's Edit ▸ Paste.** That is how macOS tells a user paste apart from a background read (pasteboard privacy, macOS 15.4+). The app never reads the clipboard on its own.
* **Focus is deterministic.** When a window becomes key, AppKit focuses the first text field, which would be search. The controller explicitly focuses the composer, and the self-test checks it.
* **Files are handed out as clones.** Finder's ⌥⌘V *moves* a pasted file, so we never put our stored copy on the clipboard.

See [PLATFORM.md](PLATFORM.md) for the macOS and iOS behavior behind these decisions, [DESIGN.md](DESIGN.md) for the design system, and [TESTING.md](TESTING.md) for how each layer is tested.
