# Testing

Five layers, from fastest to most realistic. None of them need Accessibility or Screen Recording permission, and none touch your real library or clipboard.

```bash
make test        # 1–3: unit, design (contrast + lint), app logic
make selftest    # 4: drives the real panel window
make snapshots   # 5: renders every screen to build/snapshots
```

## 1. Core (`Tests/StickyCoreTests`)

These cover everything about capture and storage, using private pasteboards (`NSPasteboard(name:)`) and temporary folders.

* **Classification of every kind:**
  * text and links
  * rich text (whose plain text stays searchable)
  * images (copied images with a URL still count as images; spreadsheet text with a picture still counts as text)
  * PDFs with page counts
  * files, folders and multiple files
  * unknown app data
* **Snapshotting:**
  * every item and type is kept, private types included
  * noise and markers are dropped
  * oversized types are skipped instead of failing
  * Finder-style multi-file copies
* **Round trips:**
  * whatever goes in comes back byte for byte (RTF, private types, source marker)
  * stored files survive the original being deleted
  * what's handed out is a clone, so Finder's ⌥⌘V can't move our copy away
* **Storage:**
  * persistence across launches
  * edit, delete, undo and search (case- and accent-insensitive)
  * retention keeps pinned items
  * garbage collection
  * one-time v1 import
  * duplicate pastes

## 2. Design system (`Tests/StickyDesignTests`)

* **`ContrastTests`:** WCAG ratios for every token pair, in light and dark.
* **`DesignLintTests`:** fails the build on design drift (see [DESIGN.md](DESIGN.md)).

## 3. App logic (`Tests/StickyThingsTests`)

`PanelModel` without any UI:

* paste rules (save instantly vs. paste inline)
* arrow keys moving away from the corner in both layouts
* one-click copy selecting and confirming
* hover moving between cards (leaving one never clears the next)
* inline edit + undo
* delete selecting a neighbor + undo
* ⌘1 for pinned items
* filters and search
* corner geometry and shortcut labels

## 4. UI self-test (`StickyThings --selftest`)

* **How it works:** it opens the *real* panel and drives it through the app's own accessibility tree, as VoiceOver does. That works in-process with no permissions.
  * It presses buttons, performs each card's named actions and types into the real text views.
  * Synthesized mouse events don't reach SwiftUI controls, so accessibility is the dependable route. Every action being reachable this way also means it works for VoiceOver users.
* **What it checks (26 checks):**
  * the panel window's corners are fully transparent (it captures its own window, which needs no permission)
  * the composer, not search, has focus on open
  * Return saves and ⌘V saves anything
  * one click copies and keeps the card selected
  * the Copy and Edit buttons work without hover
  * editing in place
  * Delete + Undo, Pin and the pinned chip
  * ↑ / Return
  * Quick Look with the panel staying open
  * two-step Esc
* **What it can't check:** real pointer *hover* and drags from other apps. SwiftUI reads the real cursor position, so synthetic mouse moves don't produce hover, and posting real events needs permission. Those are in the manual pass below.

## 5. Snapshots (`StickyThings --snapshot <folder>`)

These render the panel (light and dark, full and empty), every onboarding step, Settings panes and the corner states. Sample data goes through the real capture code. Glass can't be rendered offscreen, so snapshots use a flat surface.

## Manual pass (each release)

**Drag matrix.** Drag each of these onto the panel *and* onto the corner, then copy it back out and drag it back out:

* Finder (one file, several files, a folder)
* Preview (title-bar icon, a sidebar page, a selection)
* Photos
* Safari (an image, a link, text)
* Mail (an attachment)
* Notes / Pages (rich text)
* the screenshot thumbnail
* a 1Password copy (should show blurred)

**Pointer.** Hover reveals the buttons, and they stay while the pointer rests on them. The first click works even right after opening. Right-click shows the menu.

**Look.** The panel's corners are round on light and dark backgrounds, with no square outline.

**Plus** the design checklist in [DESIGN.md](DESIGN.md).
