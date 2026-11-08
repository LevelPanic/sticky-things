# Sticky Things: notes for the next session

A native macOS menu-bar app that replaces Apple's Quick Note hot corner. Click a screen corner (or press ⌃⌥N), a panel opens from it, and you can paste or drag in anything, copy it back in one click, and edit notes in place. The owner treats it as a real product: "quick notes that are actually quick", intuitive like Bartender.

Keep this file current. After any change that moves the status, the known gaps or the conventions below, update this file (and the docs it points to) in the same commit.

## Read first

| Doc | When |
|---|---|
| [README.md](README.md) | What the user sees, keys, install |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Modules, data flow, storage layout, key decisions |
| [docs/PLATFORM.md](docs/PLATFORM.md) | macOS pasteboard, drag, file promise, privacy, focus and Hot Corners behavior, and how we handle each |
| [docs/DESIGN.md](docs/DESIGN.md) | Design tokens, components, writing rules, what the lint test enforces |
| [docs/TESTING.md](docs/TESTING.md) | The five test layers and the manual drag matrix |

## Commands

```bash
make test        # 28 unit tests: StickyCore, StickyDesign (contrast + design lint), PanelModel
make selftest    # drives the real panel through in-process accessibility (25 checks, throwaway library)
make snapshots   # renders every screen to build/snapshots (offscreen, flat surface instead of glass)
make install     # release build, copy to /Applications, relaunch (scripts/build-app.sh --install)
make run         # build and launch from ./build
make icon        # redraw Resources/AppIcon.icns + .png
```

Before calling work done: `make test` and `make selftest` both green, then `make install` so the user is running the latest build.

## Layout

- `Sources/StickyCore`: items, lossless pasteboard capture, SQLite + content-addressed blob store, file library (APFS clones), clipboard and drag output. No SwiftUI.
- `Sources/StickyDesign`: tokens (`Tokens.swift`, `Palette.swift`) and shared components. No app logic.
- `Sources/StickyThings`: the app. `App/` (delegate, `SelfTest`, `Snapshot`), `Panel/`, `Corner/`, `Onboarding/`, `Settings/`, `System/`.
- `Tests/<Module>Tests` mirror the three modules.

Toolchain on the owner's Mac: macOS 26.1 (Apple Silicon), Xcode 26.1, Swift 6.2.1. SwiftPM with Swift 5 language mode, deployment target macOS 14. Bundle id `app.stickythings.StickyThings`, URL scheme `stickythings://` (`open`, `toggle`, `settings`, `setup`, `add?text=`).

User data lives in `~/Library/Application Support/Sticky Things/` (`library.sqlite`, `blobs/`, `files/`, `staging/`); caches and the outbox in `~/Library/Caches/app.stickythings/`. Never point tests or the self-test at the real library.

## Conventions

- **Design system.** Use tokens only (spacing, radius, type, motion, colors); `DesignLintTests` fails on drift. Impeccable "Operate" rules: tinted neutrals, system accent, sticky yellow only as a note surface, no bounce, Reduce Motion crossfades, at least 11 pt text, 28 pt icon buttons.
- **Writing.** No em dashes, no exclamation marks. Labels are verb + object in Title Case. Glossary: item, note, Save, Delete, Pin. Prefer Undo over confirmation dialogs.
- **Nothing hover-only.** Every action is reachable by click (selected cards keep their buttons), right-click menu, keyboard shortcut and a named VoiceOver action.
- **Accessibility modifiers go before overlays** on a view, or the overlay's buttons disappear from the accessibility tree (this broke VoiceOver and the self-test once).
- **New UI behavior gets a self-test check** in `App/SelfTest.swift` (find by `accessibilityIdentifier`, act with AX press or named actions). New capture or storage behavior gets a `StickyCoreTests` case using a private `NSPasteboard(name:)` and a temp folder.
- **Pasteboard.** ⌘V must go through the main menu's Edit ▸ Paste (pasteboard privacy, macOS 15.4+). Never read the clipboard in the background. Hand files out as outbox clones, because Finder's ⌥⌘V moves pasted files.

## Gotchas already hit

- Synthesized `NSEvent` clicks don't reach SwiftUI controls. Drive UI through accessibility instead.
- When a window becomes key, AppKit focuses the first text field (search). `PanelController.focusComposer()` fixes it, and the self-test checks it.
- Transparent window pixels let hover and clicks fall through. The panel keeps `ignoresMouseEvents = false` on a real glass background.
- Long SwiftUI expressions hit type-checker timeouts. Split them into small views or helper functions.
- Photos, Mail, Safari images and Preview pages arrive as file promises (`NSFilePromiseReceiver`), not file URLs.

## Working in this environment

- Claude's sandbox here can't post real input events or take screenshots. Verify UI with `--selftest` and `--snapshot`, and ask the owner to check real pointer hover and drags from other apps.
- Never change the owner's system settings (Hot Corners, `com.apple.dock` defaults) yourself. The onboarding's "Turn Off Quick Note" button is for the owner to press.
- Commit only when asked. Keep personal content (the owner's wallpaper, notes, paths) out of committed docs and screenshots.

## Status (2026-11-08)

- **v1** (commit `51b29ac`): first working corner panel, JSON storage.
- **v2** (commit "Sticky Things v2: throw in anything…", 2026-11-08): three-module restructure, lossless capture of anything, SQLite storage with one-time v1 import, one-click copy, edit in place, Quick Look, drag out, Impeccable-based design system with contrast and lint tests, guided Hot Corners setup, new icon, accessibility-driven self-test. Installed in /Applications and running; the owner's 2 v1 notes migrated; the owner turned off their bottom-right Quick Note hot corner.

**Waiting on the owner:** confirm real hover on cards, the first click right after opening, and the drag matrix in docs/TESTING.md (Finder, Preview, Photos, Safari, Mail, Notes, screenshot thumbnail, 1Password).

**Known gaps (candidates for next):**
- Dragging a multi-file item out carries only the first file (copying gives all of them).
- Concealed items (password-manager copies) show blurred but aren't encrypted on disk.
- Glass can't be rendered in offscreen snapshots, so the real look is only checked by hand.
