# Design system

Sticky Things follows [Impeccable](https://impeccable.style) in its **Operate** mode, adapted to macOS. A tool should feel familiar and native, and keep its brand to a few specific details:

* the sticky-note paper
* the corner peek
* the drop into the corner

Everything lives in `Sources/StickyDesign`. Views never use raw values, and two tests enforce that (below).

## Tokens

| Group | Where | Rules |
|---|---|---|
| Color | `Tokens/Palette.swift` | Semantic names (`surfaceRaised`, `textSecondary`, …), each with a light and dark value derived from OKLCH. Neutrals are tinted toward the paper hue (hue 95, chroma ≤ 0.008), so they read as neutral, not cream. Interactive tint is the user's **system accent color**. Sticky yellow is a *surface* (the sticky, note paper, the icon), never text. |
| Type | `TypeScale` | One family (SF Pro), a fixed scale, nothing under 11 pt, and no bold inside the panel. Sizes: 11 caption/meta/section, 12 callout, 13 body, 14 composer, 15 title, 22 onboarding display (semibold). |
| Space | `Space` | A 4 pt grid: 2, 4, 8, 12, 16, 24, 32. Section headers get more space above than below. |
| Radius | `Radius` | Concentric: an inner radius equals the outer radius minus the padding. Panel 24, card 14, buttons 6. |
| Elevation | `Elevation` | One method per appearance. Light mode uses a soft shadow tinted with the ink color; dark mode uses a lighter fill plus a border. The panel's elevation is the system window shadow. |
| Motion | `Motion` | Zero-bounce springs (`.smooth`) for state, ease-out for hover. Exits are about 75% of the entrance. With Reduce Motion, everything is a short crossfade and the panel doesn't travel. |
| Size | `Metrics` | Icon buttons are 28 pt (the HIG default) and no target is under 24 pt (WCAG 2.5.8). |

## Components

| Component | Notes |
|---|---|
| `IconButton` | 28 pt target, 13 pt symbol, a 6 pt plate drawn only with state layers (hover 6–8%, pressed 10–12%). Always labelled (tooltip + VoiceOver). Pressed darkens; nothing scales. |
| `Chip` | Pinned items: a 24 pt capsule with a 28 pt hit area, 12 pt medium text, at most 160 pt wide. |
| `FilterBar` | All · Notes · Links · Images · Files. The selected filter shows its title; the rest show icons with tooltips. |
| `CardSurface` | Opaque (legible over any wallpaper), radius 14. States: hover (lighter fill), selected (2 pt accent ring), copied (accent wash). |
| `ToastView` | An inverse capsule with at most one action. 2.5 s, or 6 s when it offers Undo; ⌘Z works while it shows. |
| `Banner` | For problems that persist (a busy hot corner, storage trouble). Warning surface, no stroke, the problem and the fix in one sentence, then buttons. |
| `KeyHint` | One 11 pt hint line, shown only when it helps (focused and empty, or an item selected). |
| `InlineTextEditor` | Edits in place with the card's own font and padding. Keeps rich text as RTF. Esc, ⌘↩ or a click elsewhere finishes, and the result can be undone. |
| `KeyTextView` | The composer and search field: an `NSTextView` with a placeholder, ⌘V interception and auto-height. |
| `MiniStickyNote` | The brand illustration and the only place gradients are allowed. |

## Writing

* **Labels:** a verb plus an object, in Title Case for buttons and menus ("Turn Off Quick Note", "Copy and Close", "Keep Panel Open"). Never OK, Submit or Yes.
* **Glossary:**
  * *item*: anything saved
  * *note*: text only
  * *Save* (not Add or Stash)
  * *Delete* (not Remove)
  * *Pin*
* **Errors** say what happened and what to do: "“Report.pdf” has been moved or deleted."
* **Style:** sentence case everywhere else. No em dashes, no exclamation marks, no emoji as icons.

## Enforced automatically (`swift test`)

* **`ContrastTests`:** every text/surface pair in light and dark. Text needs ≥ 4.5:1, primary text ≥ 7:1, ink on every note paper ≥ 7:1, and borders and icons ≥ 3:1.
* **`DesignLintTests`:** scans the UI source and fails on:
  * bouncy or spring animations
  * uppercased or tracked labels
  * decorative gradients
  * SwiftUI materials or glass below the panel
  * raw colors outside the palette
  * text under 11 pt
  * em dashes or exclamation marks in UI copy
  * vague button labels

## Checked by hand each release

1. **Glass.** Check the panel over white, black and busy wallpapers, with Reduce Transparency and Increase Contrast on.
2. **Squint test.** The composer, the newest item and the sections should read in that order.
3. **VoiceOver.** Each card reads its kind, title and age, and its actions (Copy, Edit, Pin, Delete) work.
4. **No-hover pass.** Every action works from the keyboard and the right-click menu.
5. **Slop scan.** No purple gradients, glows, nested cards, letter-spaced caps, or a border paired with a wide shadow.
6. **Adaptivity.** Try every corner on every display, the notched top corners, and the Dock on each side.
