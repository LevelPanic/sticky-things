# Testing

Six layers, from fastest to most realistic. None of them need Accessibility or Screen Recording permission, and none touch your real library or clipboard. The self-test and the layout audit open real windows: run them on an unlocked Mac and don't type or click while they run.

```bash
make test        # 1–3: unit, design (contrast + lint), app logic
make selftest    # 4: drives the real panel window (behavior + the grid)
make layout      # 5: every panel state, light and dark, checked against the grid, with captures
make snapshots   # 6: renders every screen to build/snapshots
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
* what a click does: edits notes by default, copies links, images and hidden password copies, copies everything in copy mode; the setting is remembered; editing what you're editing keeps the edit
* the selection following where you work (composer, search, empty space, typing, every way an edit ends)
* hover moving between cards (leaving one never clears the next)
* inline edit + undo, and how each ending behaves (Save, Cancel, clicking elsewhere, the panel closing)
* Return in the composer saves typed text even while a card is selected
* editing a link keeps it a link
* delete selecting a neighbor + undo
* ⌘1 for pinned items
* filters and search
* corner geometry and shortcut labels

## 4. UI self-test (`StickyThings --selftest`)

* **How it works:** it opens the *real* panel and drives it through the app's own accessibility tree, as VoiceOver does. That works in-process with no permissions.
  * It presses buttons, performs each card's named actions and types into the real text views.
  * Synthesized mouse events don't reach SwiftUI controls, so accessibility is the dependable route. Every action being reachable this way also means it works for VoiceOver users.
* **What it checks (49 checks):**
  * a click edits a note by default without copying it, a click on an image copies it, and with clicks set to copy a click copies and selects
  * the outline follows where you're working: real clicks in the composer and search clear it, typing a note clears it, clicking the composer ends an edit and clears its outline, empty space saves an open edit and returns to the composer
  * the composer's toolbar line shows the ⇧↩ hint and Save
  * the panel follows the grid (`LayoutRules`, see [DESIGN.md](DESIGN.md#panel-grid)): empty, with items, mid-edit, and opened from a top corner
  * the panel window's corners are fully transparent (it captures its own window, which needs no permission)
  * the composer, not search, has focus on open
  * Return saves and ⌘V saves anything
  * a click edits a note (default) or copies it (copy mode) and keeps the card selected
  * the Copy and Edit buttons work without hover
  * editing in place: Save and Cancel show, Return saves, Esc cancels, the Save button saves, clicking the composer ends the edit (typed or not) and the composer still saves, closing the panel keeps the edit
  * Delete + Undo, Pin and the pinned chip
  * ↑ / Return
  * Quick Look with the panel staying open
  * two-step Esc
* **How it clicks:** SwiftUI controls through accessibility; AppKit text fields with real synthesized clicks (`Pointer.click`).
* **What it can't check:** real pointer *hover*, drags from other apps, and the tap on empty space itself (SwiftUI ignores synthesized clicks; the self-test runs the action that tap triggers). SwiftUI reads the real cursor position, so synthetic mouse moves don't produce hover, and posting real events needs permission. Those are in the manual pass below.

## 5. Layout audit (`StickyThings --layout <folder>`, `make layout`)

* **How it works:** it opens the real panel with sample data and walks it through every state, in dark and light: items, a selected card, typing two lines, searching, editing in place, opened from a top corner, and empty. Then it opens the real Settings window and visits every pane in both appearances (22 states in all).
  * For each state it writes a capture of the real window (glass included; apps can capture their own windows without permission) and a `.txt` with every element's frame.
  * It checks each state against `LayoutRules`: the outer and content columns, the 36 pt search field with centered text, the two-line composer (text inset, toolbar line, hint on the column), trailing buttons 4 pt in, header buttons centered on the search field, 28 pt control rows, a 12 pt margin and 8 pt between blocks, list spacing, and the edit bar.
* **Settings** is native, so its rules cover what the system can't: the corner preview centered in its pane, every sidebar row present, and the window title matching the pane.
* **How it measures:** elements (buttons, text, cards) through the app's own accessibility tree. Layout boxes come from SwiftUI itself (`layoutProbe`), because a SwiftUI group reports the union of its children, and a short bottom-anchored scroll view reports an offset frame.
* **It catches regressions:** planting the old mistakes back (composer text off-center, section headers off the column) fails the audit on exactly those rules.
* **`STICKY_LAYOUT_DUMP=1`** prints the raw accessibility tree with frames, for debugging a rule.

## 6. Snapshots (`StickyThings --snapshot <folder>`)

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

**Pointer.** Hover reveals the buttons, and they stay while the pointer rests on them. Click a card, then empty space: the outline goes. Edit a note, click empty space: the edit is saved and the caret is back in the composer. The first click works even right after opening. Right-click shows the menu.

**Look.** The panel's corners are round on light and dark backgrounds, with no square outline. Open `build/layout` after `make layout` and read the captures in both appearances.

**Plus** the design checklist in [DESIGN.md](DESIGN.md).
