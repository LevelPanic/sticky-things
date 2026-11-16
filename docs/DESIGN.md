# Design system

Sticky Things follows [Impeccable](https://impeccable.style) in its **Operate** mode, adapted to macOS. A tool should feel familiar and native, and keep its brand to a few specific details:

* the sticky-note paper
* the corner peek
* the drop into the corner

Everything lives in `Sources/StickyDesign`. Views never use raw values, and two tests enforce that (below).

## Tokens

| Group | Where | Rules |
|---|---|---|
| Color | `Tokens/Palette.swift` | Semantic names (`surfaceRaised`, `textSecondary`, …), each with a light and dark value derived from OKLCH. Neutrals are tinted toward the paper hue (hue 95, chroma ≤ 0.008), so they read as neutral, not cream. Interactive tint is the user's **system accent color**. Hints use `Palette.hint`, the system placeholder tone, so guidance reads like the field's placeholder and never like a control; it strengthens with Increase Contrast. Sticky yellow is a *surface* (the sticky, note paper, the icon), never text. |
| Type | `TypeScale` | One family (SF Pro), a fixed scale, nothing under 11 pt, and no bold inside the panel. Sizes: 11 caption/meta/section, 12 callout, 13 body, 14 composer, 15 title, 22 onboarding display (semibold). |
| Space | `Space` | A 4 pt grid: 2, 4, 8, 12, 16, 24, 32. Section headers get more space above than below. No one-off nudges (`Space.s - 2`): use a token or add one. |
| Radius | `Radius` | Concentric: an inner radius equals the outer radius minus the padding. Field 18 (half the field height), panel 30 (field + the 12 pt margin, so fields sit concentric in the corners), card 14, buttons 6. |
| Elevation | `Elevation` | One method per appearance. Light mode uses a soft shadow tinted with the ink color; dark mode uses a lighter fill plus a border. The panel's elevation is the system window shadow. |
| Motion | `Motion` | Zero-bounce springs (`.smooth`) for state, ease-out for hover. Exits are about 75% of the entrance. With Reduce Motion, everything is a short crossfade and the panel doesn't travel. The corner's held-drag shake is a short ease-in-out wobble, skipped with Reduce Motion. |
| Size | `Metrics` | Icon buttons and control rows (filter pills, pinned chips) are 28 pt (the HIG default) and no target is under 24 pt (WCAG 2.5.8). Text fields are 36 pt on one line. |

## Panel grid

Every measurement in the panel comes from this grid. `LayoutRules` (in `App/LayoutAudit.swift`) checks it against frames measured from the running panel, in every state, to half a point.

**Columns**

* **Outer column, x = 12 to width − 12.** Every container starts and ends here: the search field, the first filter pill, the first pinned chip, cards, banners, the composer, the empty-state tips.
* **Content column, x = 24.** A container's content starts 12 pt in: card text, section headers, the composer's text, the search icon, the selected filter's icon, chip icons, banner icons.
* **Trailing buttons inside a container sit 4 pt in:** the send button, the clear-search button, a card's action bar. In a 36 pt field that's 4 pt on every side, so the button is concentric with the field's end.

**Rows**

* A **12 pt margin** above the first block and below the last.
* **8 pt between blocks:** header row, filters, pinned strip, banners, list, composer.
* **In the list:** 8 pt between cards, 8 pt below a section header, and 16 pt above a header that follows a card. The first header gets no extra space.
* Nothing appears or disappears around the composer, so focusing or typing never moves the layout. What Return does lives in its placeholder ("Write a note or press ⌘V to save anything", or "Press Return to copy the selected item" while one is selected).

**Fields** (`FieldChrome`, used by search and the composer)

* Radius 18 and the same 1 pt border, which turns accent with focus. The fill says the role: **raised** where things are made (the composer), **sunken** where they're found (search).
* **Search** is one line: 36 pt, a capsule, text vertically centered (`KeyTextView.singleLineHeight`). Content 12 pt in; the icon gets a 16 pt slot, then 8 pt to the text.
* **The composer** is two lines in one field, like the inline editor's bar:
  * the text on top, across the full width (x = 24 to width − 24), 8 pt below the field's top;
  * 2 pt below it, a 28 pt toolbar line: the "⇧↩ new line" hint on the content column, buttons on the right, 4 pt apart, with Save in the corner 4 pt in. New composer features add buttons to this line, left of Save. Clicking the empty part of the line focuses the text;
  * with one line of text it's 63 pt tall. More text grows it upward; the toolbar stays put.

**Control rows** are 28 pt. Filter segments are 4 pt apart and every icon-only one is a 28 pt square. Pinned chips are 8 pt apart, because they're separate objects, not segments of one control.

**Cards** pad 12 pt. Image cards frame the picture 8 pt in, and their caption steps back to the content column and the 12 pt bottom edge. Captions on every kind start on the content column (x = 24); image cards get there through the smaller picture inset, row cards through the card padding.

**Icons** align by their layout box. SF Symbols carry side bearings, so an icon's ink may sit up to 2 pt inside the column, never outside it.

## Components

| Component | Notes |
|---|---|
| `IconButton` | 28 pt target, 13 pt symbol, a 6 pt plate drawn only with state layers (hover 6–8%, pressed 10–12%). Always labelled (tooltip + VoiceOver). Pressed darkens; nothing scales. |
| `FieldChrome` | The shared shape of the search field and the composer (see Panel grid). |
| `Chip` | Pinned items: a 28 pt capsule (one control row), content 12 pt in, 12 pt medium text, at most 160 pt wide. |
| `FilterBar` | All · Notes · Links · Images · Files. The selected filter shows its title with its content 12 pt in; the rest are 28 pt icon squares with tooltips, 4 pt apart. |
| `CardSurface` | Opaque (legible over any wallpaper), radius 14. States: hover (lighter fill), selected (2 pt accent ring), copied (accent wash). |
| `Caption` | Text you add to an image, PDF, file or folder. It sits on the content column under the item, uses the body size, wraps to four lines on the card, and is searchable. Its editor is the same inline editor as notes, with a ⇧↩ hint and Save/Cancel. |
| `ToastView` | An inverse capsule with at most one action. 2.5 s, or 6 s when it offers Undo; ⌘Z works while it shows. |
| `Banner` | For problems that persist (a busy hot corner, storage trouble). Warning surface, no stroke, the problem and the fix in one sentence, then buttons. |
| `KeyHint` | One 11 pt hint: "⇧↩ new line" on the composer's toolbar line and under an inline edit. One weight, in the hint tone (the paper's secondary ink on tinted notes), so it never looks like a button. Always shown, so nothing moves. |
| `InlineTextEditor` | Edits in place with the card's own font and padding. Keeps rich text as RTF when asked. Return (or ⌘↩) saves, ⇧↩ starts a new line, Esc cancels, and leaving it any other way saves. The card shows Cancel and Save under it (small system buttons, Save prominent) and a ⇧↩ hint. An `InlineEditHandle` lets those buttons end the edit. It tracks every live platform view for one edit, because a growing card in a lazy list can make SwiftUI build two; a duplicate leaving never ends the live edit. |
| `KeyTextView` | The composer and search field: an `NSTextView` with a placeholder, ⌘V interception and auto-height. |
| `MiniStickyNote` | The brand illustration and the only place gradients are allowed. |
| `ScreenPreview` | A drawn Mac screen (desktop tinted with your accent color, menu bar, a window, the Dock) for the corner picker and the setup guide. Drawn, never your wallpaper: decoration never asks for a permission. |

## Interaction

* **A click on a card** does one thing, chosen in Settings ▸ Notes ▸ Clicking a note: it **edits a note in place** (the default) or **copies it**. Links, images, files and hidden password copies can't be edited in place, so a click copies them either way. Copy (button, ⌘C) and Edit (button, ⌘E, double-click) stay one step away in both modes.
* **Selection** (the 2 pt accent outline) means "Return, ⌘C and these buttons act on this card". It follows where you're working: clicking a card, ↑ ↓ and Edit select it; clicking the composer, search or empty space, typing a note, or finishing an edit clears it. Never leave an outline on something you've moved away from.
* **Field chrome belongs to the field:** clicking a field's icon, padding or toolbar line puts the caret in its text. Clicking an inline editor's padding keeps the edit.
* **Captions belong to media and documents.** A card for an image, PDF, file, folder, color or app data shows a speech-bubble button instead of Edit. It opens a caption editor on the content column; Return or Save keeps it, Esc cancels, and clicking elsewhere saves. ⌘⇧E does the same from the keyboard, and the right-click menu can add, edit or remove the caption. Notes and links don't get one: their text is the item.
* **Empty space is neutral:** it clears the selection and saves an open edit (like clicking away), and the caret goes back to the composer only when an edit ended.

## Settings

Settings uses the system's own layout, like System Settings: a native sidebar (`NavigationSplitView` + `List`), the pane's title in the toolbar (`navigationTitle`, bridged with `sceneBridgingOptions`), and grouped `Form`s. Nothing there is positioned by hand, so the sidebar, title and forms line up the way every Mac app's do. Our own content inside a form (the corner preview) uses tokens and is checked by `make layout` (centered in its pane, every sidebar row present, window title = pane). Corner ▸ the drag controls set whether holding a drag opens the panel, its delay, and the catch area (Small 44, Medium 72, Large 120 pt).

## Writing

* **Labels:** a verb plus an object, in Title Case for buttons and menus ("Turn Off Quick Note", "Copy and Close", "Keep Panel Open"). Never OK, Submit or Yes.
* **Glossary:**
  * *item*: anything saved
  * *note*: text only
  * *caption*: your own text on an image, PDF, file or folder
  * *Save* (not Add or Stash)
  * *Delete* (not Remove)
  * *Pin*
* **Errors** say what happened and what to do: "“Report.pdf” has been moved or deleted."
* **Style:** sentence case everywhere else. No em dashes, no exclamation marks, no emoji as icons.

## Enforced automatically (`swift test`)

* **`ContrastTests`:** every text/surface pair in light and dark. Text needs ≥ 4.5:1, primary text ≥ 7:1, ink on every note paper ≥ 7:1, and borders and icons ≥ 3:1. Hints need ≥ 3:1 and must stay quieter than secondary text.
* **`DesignLintTests`:** scans the UI source and fails on:
  * bouncy or spring animations
  * uppercased or tracked labels
  * decorative gradients
  * SwiftUI materials or glass below the panel
  * raw colors outside the palette
  * text under 11 pt
  * em dashes or exclamation marks in UI copy
  * vague button labels
  * one-off nudges of tokens (`Space.s - 2`, `Radius.l + 4`)
  * reading the desktop picture (it can need a Files & Folders permission; decoration never asks for one)
* **`LayoutRules`** (the self-test and `make layout`): the Panel grid above, measured on the real panel.

## Checked by hand each release

1. **Glass.** Check the panel over white, black and busy wallpapers, with Reduce Transparency and Increase Contrast on.
2. **Squint test.** The composer, the newest item and the sections should read in that order.
3. **VoiceOver.** Each card reads its kind, title and age, and its actions (Copy, Edit, Pin, Delete) work.
4. **No-hover pass.** Every action works from the keyboard and the right-click menu.
5. **Slop scan.** No purple gradients, glows, nested cards, letter-spaced caps, or a border paired with a wide shadow.
6. **Adaptivity.** Try every corner on every display, the notched top corners, and the Dock on each side.
