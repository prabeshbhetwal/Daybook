# Interface zoom

Date: 2026-10-07
Status: approved in conversation 2026-10-07; spec awaiting review

## Why

Daybook's type and layout are fixed in points. On a large external display the
12pt body text and 300pt rail read small; on a 13-inch laptop the 980 × 680
window takes most of the screen. macOS does not scale fixed-size SwiftUI
fonts, so the app has to do it itself.

Goal: one zoom setting, changed in Settings or with ⌘+ / ⌘− / ⌘0, that makes
the whole interface larger or smaller together, so text, gaps, icons and
controls keep their proportions at every size.

## Decisions

| Question | Decision |
|---|---|
| What grows | The whole interface: text, spacing, corner radii, icons, frames and native controls. |
| Range | 80% to 140% in 10% steps: 80, 90, 100, 110, 120, 130, 140. Default 100%. |
| Where | Every Daybook window: main window, its sheets, menu-bar panel, away prompt, category and activity editors, update panel, reward HUD. Not the menu-bar item. |
| How | Design tokens and type roles compute base × zoom from one observable value. Views re-render through Observation and keep their state. |
| Rejected: root zoom | Scaling each window's root with `scaleEffect` enlarges already-drawn bitmaps: text is soft (evidence §11). |
| Rejected: environment plumbing | Every view would declare an environment read and every token read would change: about 1,000 edits for the same result. |
| Minimum macOS | 14 (Observation). Was 13. |
| Shortcuts | View menu: Zoom In ⌘+ (⌘= also), Zoom Out ⌘−, Actual Size ⌘0. |
| Setting | Settings › General › Interface, under Interface density: a Zoom slider. |

## 1. The zoom value

- `InterfaceZoom` (Core) is pure: the seven steps, `nearestStep(to:)`, `stepped(from:by:)`, and the bounds. It holds no state.
- `PersistenceStore` stores the zoom as a `Double` under `fc.interfaceZoom`. Reading it: a missing, non-finite or non-numeric value gives 1.0; any other value snaps to the nearest step within 0.8–1.4. Only steps are ever written.
- `ZoomModel` (App) is an `@Observable` object with one shared instance and one property, `scale: CGFloat`. `SettingsModel.interfaceZoom` writes the store and then `ZoomModel.shared.scale`; at launch the coordinator seeds it from the store before any window is built. Nothing else writes it. It is read and written on the main thread only.
- Self-checks never move the shared zoom without restoring it: they use a scoped helper (`withZoom(_:_:)`) that sets a value and puts back the previous one.

## 2. Tokens and type roles

Each token that is a length in points becomes a computed `static var` returning base × `ZoomModel.shared.scale`. Its base value is unchanged, so at 100% every token equals today's value.

- `Tokens.Typography`: every role. `Typography.Size` keeps the base points (the scale checks still hold it to its shape); the roles multiply by the zoom. `labelSymbol` (the AppKit symbol configuration) scales too.
- `Tokens.Space`, `Tokens.Radius` (not `capsule`), `Tokens.Density` lengths, `InterfaceDensity.Layout` metrics, `StoryLayout.railWidth`, `StoryStyle` insets.
- Every other `static let name: CGFloat = N` that is a length in points. Durations, opacities, fractions and counts stay `let`.

A view reading a token during `body`, directly or through a helper it calls, re-renders when the zoom changes; a view reading none does not (evidence §11). A token read outside `body` is captured once, so it is read in `body`, never in `init` or a stored `let`. A custom `Layout` or a `Canvas` closure receives its lengths from the `body` that builds it.

## 3. Literals and the guard

- Every raw length literal in `Sources/Surfaces` and `Sources/Design` becomes a token, or `N.zoomed` when no token fits (`.padding(12.zoomed)`). `zoomed` exists on `BinaryInteger`, `BinaryFloatingPoint` and `CGFloat`.
- Zoom is applied once, where a number becomes a length. A component never rescales a size it is given: `AppIcon(size: 20.zoomed)` scales at the call site, and `AppIcon` uses `size` as passed. `fitted(_:weight:)` stays unscaled because its callers pass a size derived from an already-zoomed frame.
- `build.sh` gains a guard beside the type guard. A line in `Sources/App`, `Sources/Design` or `Sources/Surfaces` fails the build when it passes a bare number other than 0 or 1 to `.padding`, `spacing:`, a frame dimension (`width:`, `height:`, `minWidth:` … `maxHeight:`), `cornerRadius:` or `.offset`. A deliberately fixed length carries a trailing `// zoom: fixed` comment, which the guard skips.
- About 280 literal sites and 52 constants change. The work is mechanical and splits by folder.

## 4. What stays fixed

- Hairlines: 1pt separators and strokes of 1pt or less.
- The menu-bar item: `MenuBarLabelView`, `Typography.menuBar` (system size) and `MenuBarGlyph`. macOS fixes the menu bar's height.
- System-drawn surfaces: menus, tooltips, alerts, open and save panels, the title bar.
- Thick strokes (a goal ring's) are not raw literals: they derive from the ring's zoomed diameter.

## 5. Native controls

Checkboxes, switches, pop-ups, segmented controls and sliders are drawn by AppKit at a control size, not a font size.

| Zoom | Root control size |
|---|---|
| 80%, 90% | `.small` |
| 100%, 110% | `.regular` |
| 120%, 130%, 140% | `.large` |

Each window root sets the control size for its zoom. The nine explicit uses (`.large` ×6, `.small` ×3) become `Tokens.Zoom.controlSize(.large)`, which shifts the requested size by the same band (−1, 0, +1 step) within `.mini` … `.extraLarge`. On macOS 26 a bordered menu is sized by its label image (2026-10-06 finding); the `ActivityChooser` chevron canvas height becomes a zoomed length so it grows with the menu.

## 6. Windows and panels

- **Main window.** Its minimum becomes 980 × 680 × zoom, each side capped to the main screen's visible frame less 40pt, so 140% still fits a 13-inch laptop. When the zoom grows past the window's current size, the window grows to the new minimum, keeping its top-left corner and staying on screen.
- **Sheets.** Each native sheet re-renders with the window; sizes they take from the window's size need no change.
- **Menu-bar panel.** Sized by its content; it follows the zoom on its own.
- **Panels** (category editor, activity editor, update countdown, reward HUD) and the **away prompt**: each panel's frame follows the zoom while it is open, not only when next opened. The mechanism is chosen per panel in the plan (fitting size from the hosting view, or a resize on change); none may clip its content after a zoom change.

## 7. The setting

Settings › General, in the Interface panel (the Appearance section), directly under Interface density:

```
Zoom      A  ──●──┼──┼──┼──┼──┼──  A     120%   [Actual Size]
```

- A `Slider` over 0.8…1.4 with step 0.1, a small "A" as its minimum label and a large "A" as its maximum label, the percentage after it, and an Actual Size button shown only when the zoom is not 100%.
- Each step applies at once. The Settings page zooms with everything else, so the page itself is the preview.
- `SettingsControlKey.zoom` maps to `\SettingsModel.interfaceZoom` and joins the Appearance section's keys after `.density`. Settings search finds it by "zoom", "text size", "bigger", "smaller" and "scale".
- Accessibility: label "Zoom", value read as "120 percent".

## 8. Menu and shortcuts

A `ZoomCommands` group in the View menu (`CommandGroup(after: .toolbar)`), wired into `DaybookApp` and `StoryFixtureApp`:

| Item | Shortcut | Disabled when |
|---|---|---|
| Zoom In | ⌘+ | at 140% |
| Zoom Out | ⌘− | at 80% |
| Actual Size | ⌘0 | at 100% |

- ⌘= (no Shift) and the keypad's + and − must also work. The plan first measures which of these the menu's key equivalents already catch. Any not caught get a local key-down monitor in the App layer, active only while a Daybook window is key.
- The shortcuts work while the menu-bar panel is key, as well as in the main window.
- ⌘+, ⌘=, ⌘− and ⌘0 are unused today. A focused text field does not claim them.

## 9. Minimum macOS 14

`build.sh` target and `LSMinimumSystemVersion`, `scripts/release.sh` (`sparkle:minimumSystemVersion`), README (two places) and the commands in `CLAUDE.md` move from 13.0 to 14.0. A copy on macOS 13 keeps the version it has; the update feed stops offering it newer ones. Existing `#available(macOS 14, *)` checks are removed only if the compiler warns about them.

## 10. Checks

New self-checks, added with the `add-check` skill at the end of the registry:

1. Stored values snap: 1.37 → 1.4, 0.5 → 0.8, NaN, a string and a missing key → 1.0.
2. At 80%, 100% and 140%, every type role's point size and every `Space` and `Radius` token equal base × zoom; hairlines and `capsule` do not move.
3. Stepping stops at the ends: Zoom In is disabled at 140%, Zoom Out at 80%, Actual Size at 100%.
4. The setting round-trips through an isolated defaults suite and reaches `ZoomModel`.
5. The control-size band and its shift, including the `.mini` and `.extraLarge` limits.
6. The window minimum is capped to the visible frame.

Evidence beyond the suite:

- **No change at 100%.** Snapshots of the existing scenarios before and after the change are pixel-identical. This is the refactor's proof that today's interface is untouched.
- **New snapshot scenarios** at 80% and 140% (story day, History, Settings General, menu-bar panel), reviewed by eye for clipping.
- **Guard mutation.** Reintroducing a raw literal fails `build.sh`.
- **CPU.** Idle main-window CPU measured before and after; accepted within 0.5 percentage points of the 3–5% baseline.
- **macOS 26.** CI runs the suite and the new snapshots on `macos-26`.

## 11. Evidence (probes, 2026-10-07, macOS 27)

- Root `scaleEffect` at 140%: layout and hit-testing of a text field are correct, but SwiftUI text layers keep `contentsScale` 2.0 under a 1.4 transform, so they are drawn at 1× and enlarged as bitmaps. AppKit's own label re-rasterised at 2.8. Root zoom is soft wherever SwiftUI draws text.
- AppKit bounds scaling of the hosting view misplaces controls.
- An `@Observable` value read through static token properties: changing it from 1.0 to 1.4 re-rendered the views that read a token (directly, through a helper property, and inside a `ScrollView`), kept their `@State` (41 stayed 41), and did not re-render a view that read no token.

## Out of scope

- Zoom per window, pinch-to-zoom, and following macOS's own Text size setting.
- Steps outside 80–140%.
- Redesigning layouts for very large sizes: at 140% the existing layout is enlarged, not rearranged.
