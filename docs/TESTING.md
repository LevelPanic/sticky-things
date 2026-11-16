# Testing

Seven layers, from fastest to most realistic. The Mac layers use throwaway libraries and private pasteboards; the iOS layer builds the app and its extensions. The Mac self-test and layout audit open real windows: run them on an unlocked Mac and don't type or click while they run.

```bash
make test        # 1–3: 46 unit tests (core, design, app logic)
make selftest    # 4: drives the real Mac panel window (57 checks, behavior + the grid)
make layout      # 5: every Mac panel state, light and dark, checked against the grid, with captures
make snapshots   # 6: renders every Mac screen to build/snapshots
make ios-build   # 7: builds the iOS app, Share extension and Control widget
```

## 1. Core (`packages/StickyCore/Tests/StickyCoreTests`)

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
  * captions: saved, searchable, cleared, and old items without a caption still decode
  * retention keeps pinned items
  * garbage collection
  * one-time v1 import
  * duplicate pastes

## 2. Design system (`packages/StickyDesign/Tests/StickyDesignTests`)

* **`ContrastTests`:** WCAG ratios for every token pair, in light and dark.
* **`DesignLintTests`:** fails the build on design drift (see [DESIGN.md](DESIGN.md)).
* **`InlineEditHandleTests`:** a late editor never unhooks the one that replaced it; two platform views for the same edit leave the survivor in charge; an editor from another edit is not treated as a duplicate.

## 3. App logic (`apps/macos/Tests/StickyThingsTests`)

`PanelModel` without any UI:

* paste rules (save instantly vs. paste inline)
* arrow keys moving away from the corner in both layouts
* one-click copy selecting and confirming
* what a click does: edits notes by default, copies links, images and hidden password copies, copies everything in copy mode; the setting is remembered; editing what you're editing keeps the edit
* the selection following where you work (composer, search, empty space, typing, every way an edit ends)
* hover moving between cards (leaving one never clears the next)
* inline edit + undo, and how each ending behaves (Save, Cancel, clicking elsewhere, the panel closing)
* captions: start, save, cancel, remove, undo, searchable text, and the ⌘⇧E shortcut reaching media but not notes
* drag settings: defaults, persistence, and the three trigger-area sizes
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
* **What it checks (57 checks):**
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
  * a caption on an image: the Caption button starts editing, Return saves it, and it is searchable
  * a drag grows the corner to its trigger area, arms it, waits for the delay, then opens the panel; the corner shrinks after the drag
  * Delete + Undo, Pin and the pinned chip
  * ↑ / Return
  * Quick Look with the panel staying open
  * two-step Esc
* **How it clicks:** SwiftUI controls through accessibility; AppKit text fields with real synthesized clicks (`Pointer.click`).
* **What it can't check:** real pointer *hover*, drags from other apps, and the tap on empty space itself (SwiftUI ignores synthesized clicks; the self-test runs the action that tap triggers). SwiftUI reads the real cursor position, so synthetic mouse moves don't produce hover, and posting real events needs permission. Those are in the manual pass below.

## 5. Layout audit (`StickyThings --layout <folder>`, `make layout`)

* **How it works:** it opens the real panel with sample data and walks it through every state, in dark and light: items, a selected card, typing two lines, searching, editing a note in place, editing a caption, opened from a top corner, and empty. Then it opens the real Settings window and visits every pane in both appearances (24 states in all).
  * For each state it writes a capture of the real window (glass included; apps can capture their own windows without permission) and a `.txt` with every element's frame.
  * It checks each state against `LayoutRules`: the outer and content columns, the 36 pt search field with centered text, the two-line composer (text inset, toolbar line, hint on the column), trailing buttons 4 pt in, header buttons centered on the search field, 28 pt control rows, a 12 pt margin and 8 pt between blocks, list spacing, the edit bar, and captions on the content column with their Save button on the card edge.
* **Settings** is native, so its rules cover what the system can't: the corner preview centered in its pane, every sidebar row present, and the window title matching the pane.
* **How it measures:** elements (buttons, text, cards) through the app's own accessibility tree. Layout boxes come from SwiftUI itself (`layoutProbe`), because a SwiftUI group reports the union of its children, and a short bottom-anchored scroll view reports an offset frame.
* **It catches regressions:** planting the old mistakes back (composer text off-center, section headers off the column) fails the audit on exactly those rules.
* **`STICKY_LAYOUT_DUMP=1`** prints the raw accessibility tree with frames, for debugging a rule.

## 6. Snapshots (`StickyThings --snapshot <folder>`)

These render the panel (light and dark, full and empty), every onboarding step, Settings panes and the corner states. Sample data goes through the real capture code and includes captions on the image and PDF. Glass can't be rendered offscreen, so snapshots use a flat surface.

## 7. iOS (`apps/ios`)

`make ios-build` compiles the iOS app, its Share extension and the Control widget for the simulator without signing. The shared `StickyCore` unit tests from layer 1 run on the Mac and cover the same storage and item code the iOS app uses.

**Simulator smoke test.** Build, install into an iPhone simulator, and launch with these debug arguments:

```bash
xcrun simctl install booted "build/ios/Build/Products/Debug-iphonesimulator/Sticky Things.app"
xcrun simctl launch booted app.stickythings.StickyThings --demo
xcrun simctl launch booted app.stickythings.StickyThings --composer
xcrun simctl launch booted app.stickythings.StickyThings --detail
```

`--demo` seeds a throwaway library, `--composer` opens the quick capture sheet, and `--detail` opens an item's detail screen. The current screenshots in `docs/ios-*.png` come from this path.

**Manual device pass.** The system parts do not exist in the simulator:

* **Action Button:** Settings ▸ Action Button ▸ Controls ▸ Sticky Things ▸ New Sticky Thing. Press it from the Lock Screen and from the Home Screen; the composer should appear without an "Open in Sticky Things?" prompt, and the keyboard should be up.
* **Control Center and Lock Screen:** add the New Sticky Thing control to both.
* **Share sheet:** share a link from Safari, text from Notes, a photo from Photos, a PDF from Files and a large file from another app. Each should save into the same library and appear in the app.
* **Siri and Shortcuts:** "New sticky thing in Sticky Things" opens the composer. "Save to Sticky Things" with text saves while the app stays closed.
* **Spotlight:** save a note, search for it from the Home Screen, tap the result. The item detail should open. A concealed copy must not appear.
* **Paste:** copy text/image on the Mac or iPhone and tap the system Paste button in the composer.
* **Quick Look and Share:** open an item detail, preview an image/PDF, and share a file through the system sheet.
* **iPad:** drag a link from Safari, a photo from Photos and a file from Files into the list; drag a row out to another app; use ⌘N to open the composer.
* **App Group:** install the app and share extension with the `group.app.stickythings` capability, save from the share sheet, and confirm the item is in the app. Without the capability the extension falls back to its own container.
* **Dynamic Type and dark mode:** raise the text size and switch appearance; controls and cards should reflow without clipping.

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

**Drag to open.** With Settings ▸ Corner ▸ "Open the panel when I hold a drag at the corner" on, drag a file toward the corner: the catch area grows while the drag is held, the note shakes, and the panel opens after the delay without pulling focus from Finder. Drop inside the panel and the item lands at the top. Try each trigger area (Small, Medium, Large), a quick release on the corner (direct save), and Cancel (Esc) mid-drag.

**Captions.** On an image, PDF, file, folder and multi-file card: add a caption with the speech-bubble button, ⌘⇧E and the right-click menu. Check Return saves, Esc cancels, clicking elsewhere saves, long text wraps and grows the editor, a saved caption appears under the item and in search, Remove Caption works, and ⌘Z restores it. Notes and links should have no caption button.

**Pointer.** Hover reveals the buttons, and they stay while the pointer rests on them. Click a card, then empty space: the outline goes. Edit a note, click empty space: the edit is saved and the caret is back in the composer. The first click works even right after opening. Right-click shows the menu.

**Look.** The panel's corners are round on light and dark backgrounds, with no square outline. Open `build/layout` after `make layout` and read the captures in both appearances.

**Plus** the design checklist in [DESIGN.md](DESIGN.md).
