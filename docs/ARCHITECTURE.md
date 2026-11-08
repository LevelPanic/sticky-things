# Architecture

Sticky Things is three Swift modules. Each layer only depends on the ones above it, and each has its own tests.

```text
StickyCore      items, lossless capture, storage, clipboard output        (no SwiftUI)
StickyDesign    tokens + components (the design system)                   (no app logic)
StickyThings    the app: corner, panel, onboarding, settings, menu bar
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

* **`Item`** (`StickyCore/Model/Item.swift`)
  * `kind` decides how the item is drawn.
  * `snapshot` is the lossless pasteboard copy, as `[SnapshotItem]`, each holding `[Representation(type, blob)]`.
  * `files` holds our stored copies of files.
  * Items typed in the app have an empty snapshot; their `text` is the content.
* **`Classifier`** decides the kind:
  * Files win.
  * Image data beats text, unless the text is real: spreadsheets add a picture of the cells.
  * PDF data, then links, then rich text, then plain text, then colors.
  * Anything else is `other`, shown as "Data from Figma" and still given back exactly.
* **Duplicates.** A fingerprint (a hash of every type's bytes) stops the same paste from being saved twice in a row.

## Storage

All of it lives in `~/Library/Application Support/Sticky Things/`:

| Path | What |
|---|---|
| `library.sqlite` | One row per item: indexed columns (id, created, pinned, kind) plus the full item as JSON. WAL mode; every change is its own transaction. |
| `blobs/ab/abcdef…` | Content-addressed data. Two items with the same screenshot share one file. |
| `files/<item-id>/<original name>` | Copies of stashed files. On the same APFS volume this is a clone: instant, and no extra space until one side changes. |
| `staging/` | File promises being received (Photos, Mail, Safari images, Preview pages). |
| `notes-v1-imported.json` | The version 1 notes file, kept after the one-time import. |

* **Caches** (`~/Library/Caches/app.stickythings/`) can be deleted at any time. They hold Quick Look temp files, drag files and **outbox** clones.
* **Garbage collection** runs at launch. It removes blobs and file folders that no item references, and an hour of grace keeps undo safe.
* **Retention** (Settings ▸ Notes) deletes unpinned items older than N days.

## The app layer

| Piece | Job |
|---|---|
| `CornerManager` / `CornerWindow` | A 6×6 pt always-on-top window in each "hard" screen corner. It grows into a peeking sticky on hover and acts as a drop target for drags. |
| `PanelController` / `QuickPanel` | A borderless `NSPanel` on system glass (`NSGlassEffectView`). It takes the keyboard without making your current app inactive, like Spotlight. Focus goes back where it was. |
| `PanelModel` | Every panel action: copy, edit, pin, delete/undo, paste, drop, Quick Look, keyboard. Views only call these, so behavior is unit-tested. |
| `ItemCard`, `PanelView` | SwiftUI views built from `StickyDesign` components. |
| `OnboardingModel` / `OnboardingView` | First run: pick a corner, free it from macOS Hot Corners (live status), then try it once. |
| `SelfTest`, `Snapshot` | `--selftest` drives the real UI; `--snapshot` renders every screen to PNGs. |

### Decisions worth knowing

* **The panel's hit area is solid.** The window ignores no mouse events, and its background is real system glass. Transparent pixels let clicks and hovers fall through to the window behind, which is what broke hover in v1.
* **Nothing is hover-only.** Clicking a card copies it *and selects it*, and a selected card keeps its buttons. Every action is also in the right-click menu, a keyboard shortcut and a VoiceOver action.
* **⌘V goes through the main menu's Edit ▸ Paste.** That is how macOS tells a user paste apart from a background read (pasteboard privacy, macOS 15.4+). The app never reads the clipboard on its own.
* **Focus is deterministic.** When a window becomes key, AppKit focuses the first text field, which would be search. The controller explicitly focuses the composer, and the self-test checks it.
* **Files are handed out as clones.** Finder's ⌥⌘V *moves* a pasted file, so we never put our stored copy on the clipboard.

See [PLATFORM.md](PLATFORM.md) for the macOS behavior behind these decisions, [DESIGN.md](DESIGN.md) for the design system, and [TESTING.md](TESTING.md) for how each layer is tested.
