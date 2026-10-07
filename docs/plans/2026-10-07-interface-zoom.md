# Interface Zoom Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Zoom setting (80–140%, ⌘+ / ⌘− / ⌘0) that scales Daybook's whole interface — text, spacing, icons, frames and native controls — live, in every window.

**Architecture:** One `@Observable` value (`ZoomModel.shared`, App layer) holds the zoom. Design tokens, type roles and every length literal compute base × zoom when read, so SwiftUI's Observation re-renders exactly the views that read a length, keeping their state. Pure step and geometry rules live in Core (`InterfaceZoom`); a `build.sh` guard keeps raw lengths out.

**Tech Stack:** Swift 5 language mode, SwiftUI + AppKit, Observation (macOS 14), `swiftc` via `build.sh`, headless self-checks.

**Spec:** `docs/specs/2026-10-07-interface-zoom-design.md`

## Global Constraints

- Deployment target macOS 14.0 from Task 1 on. Swift 5 mode, `-warnings-as-errors`.
- Steps, as percents: 80, 90, 100, 110, 120, 130, 140. Default 100. Stored under `fc.interfaceZoom` as a `Double` scale (1.2 for 120%).
- At 100% every length equals today's value exactly (`scale` is exactly `1.0`): product snapshots must not change.
- Layering: Core stays UI-free (`InterfaceZoom` is pure). `ZoomModel` lives in App. Design and Surfaces read it; Core never does.
- Zoom is applied once, where a number becomes a length: a token, or `N.zoomed` at the call site. A component never rescales a size it is given.
- Fixed by design, and marked `// zoom: fixed` where a literal remains: hairlines (≤ 1pt), `MenuBarLabelView`, `MenuBarGlyph`, `Typography.menuBar`.
- Read lengths in `body` (or a helper `body` calls), never in `init` or a stored `let`.
- Edit Swift by exact text. Files stay ≤ 300 lines; split at ~250.
- `build.sh` runs only with the sandbox disabled. Never launch a built Daybook except with `--fixture-window`, `--snapshot` or `--selftest`; live data is off limits.
- New checks: suites `InterfaceZoomChecks` and `ZoomWindowChecks`, each appended at the end of `registeredTests` when created; preferences in an isolated `fc-selftest-zoom-…` suite; any check that moves the shared zoom does so only inside `withZoom`.
- Commits: one plain present-tense subject saying what is now true, wrapped prose body, trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

**The length guard** (Task 7 adds it to `build.sh`; Tasks 4–6 use it to list their sites). `NUM` matches a number other than 0 or 1:

```bash
NUM='-?([2-9]|[1-9][0-9]+|1\.[0-9]*[1-9])(\.[0-9]+)?([^0-9.]|$)'
LENGTH_PATTERNS=(
  "\.padding\(([^()]*, *)?$NUM"
  "spacing: *$NUM"
  "(^|[^A-Za-z])(width|height|minWidth|maxWidth|idealWidth|minHeight|maxHeight|idealHeight): *$NUM"
  "cornerRadius: *$NUM"
  "lineWidth: *$NUM"
  "\.offset\(.*(x|y): *$NUM"
  "(^|[^A-Za-z.])(size|diameter): *$NUM"
  "(top|leading|bottom|trailing): *$NUM"
)
# Scope: Sources/App Sources/Design Sources/Surfaces; skip lines with "zoom: fixed".
```

This extends the spec's §3 list with `lineWidth`, `size:`/`diameter:` and inset labels, which the survey found as lengths too (293 sites in all).

## Review Focus

1. **Truncation at 80%.** SF Pro is relatively wider at small sizes, so a label that fits a zoomed column at 100% can truncate at 80%. Task 12 reviews the 80% snapshots for "…" against the 100% set.
2. **Tall surfaces on a 13-inch screen at 140%.** The away prompt and the menu-bar panel must stay usable when the zoomed content is taller than the screen. Task 12 renders `awayFull` and the panel at 140% inside a 1470 × 956 frame.
3. **Zoom changed while a sheet or editor panel is open.** Settings as a native sheet, the category editor and the update panel must grow, not clip. Task 9 tests the resize hook; Task 11 checks it by hand in the fixture window.
4. **Odd stored values.** `defaults write … fc.interfaceZoom` may hold a percent (120), a string, a negative or NaN. Task 2 pins each.
5. **Growing a window near a screen edge.** A window at the bottom-right corner must grow and stay on screen. Task 9 pins `grownFrame` at the edges.

---

### Task 1: Daybook requires macOS 14

**Files:**
- Modify: `build.sh` (`DEPLOYMENT_TARGET="13.0"`), `scripts/release.sh:144`, `README.md:10`, `README.md:143`, `CLAUDE.md` (lines 5, 22, 78)

- [ ] **Step 1: Claim the work.** Read the latest entries on the sessions board, then add one line to it: `10-07 HH:MM | Text zoom settings and keyboard controls | claim | branch claude/text-zoom-settings-keyboard-332791: interface zoom (spec 2026-10-07); touches Design tokens, Typography, build.sh and length literals across Sources/Design and Sources/Surfaces`.
- [ ] **Step 2: Change 13.0 → 14.0** in all six places (`macos13.0` → `macos14.0` in the CLAUDE.md commands, `macOS 13+` / `macOS 13 or later` → 14 in the README, `<sparkle:minimumSystemVersion>14.0` in release.sh).
- [ ] **Step 3: Verify.** Run `./build.sh --check`. Expected: `passed/total` all pass, no warnings. If a redundant `#available(macOS 14, *)` warns, remove that check and rerun.
- [ ] **Step 4: Commit.** Subject: `Daybook now needs macOS 14 or later`.

### Task 2: The zoom value is stored, snapped and observable

**Files:**
- Create: `Sources/Core/InterfaceZoom.swift`, `Sources/App/ZoomModel.swift`, `Sources/Design/Zoomed.swift`, `Sources/Verification/InterfaceZoomChecks.swift`
- Modify: `Sources/Core/PersistenceStore.swift` (`Key`, a property beside `interfaceDensityRawValue`, the self-test key list near line 700), `Sources/App/SettingsModel.swift`, `Sources/App/AppCoordinator.swift:519`, `Sources/Verification/StoryFixtureApp.swift`, `Sources/Verification/SelfTest/SelfTest+Registry.swift`

**Interfaces:**
- Produces:
  - `enum InterfaceZoom { static let percents: [Int]; static let defaultPercent: Int; static func nearestPercent(toScale: Double) -> Int; static func stepped(_ percent: Int, by delta: Int) -> Int; static func canStep(_ percent: Int, by delta: Int) -> Bool; static func controlSizeShift(forPercent: Int) -> Int }`
  - `PersistenceStore.interfaceZoomPercent: Int { get set }` (key `fc.interfaceZoom`, stored as `Double(percent) / 100`)
  - `@Observable final class ZoomModel { static let shared; private(set) var percent: Int; var scale: CGFloat { CGFloat(percent) / 100 }; func apply(percent: Int) }`
  - `SettingsModel.interfaceZoom: Double { get set }` (scale; the setter snaps, writes the store, then `ZoomModel.shared.apply`)
  - `extension BinaryInteger { var zoomed: CGFloat }`, `extension BinaryFloatingPoint { var zoomed: CGFloat }`
  - `InterfaceZoomChecks.withZoom<T>(_ percent: Int, _ body: () -> T) -> T` (restores the previous percent)

- [ ] **Step 1: Write the failing checks** in `InterfaceZoomChecks` and register the suite at the end of `registeredTests`:

```swift
("A stored zoom snaps to a step, and anything unreadable is 100%", storedZoomSnaps),
// nearestPercent(toScale: 1.37) == 140, (0.5) == 80, (1.25) == 130 (ties round up),
// (120) == 140, (-1) == 80, (.nan) == 100, (.infinity) == 100.
// Through an isolated store: missing key → 100; set("1.2" as String) → 100;
// set(1.2 as Double) → 120; interfaceZoomPercent = 90 writes exactly 0.9.
("Zoom steps stop at 80% and 140%", zoomStepsStopAtEnds),
// stepped(140, by: 1) == 140, stepped(80, by: -1) == 80, stepped(100, by: 1) == 110,
// stepped(105, by: 1) == 120 (snaps to 110 first); canStep(140, by: 1) == false,
// canStep(80, by: -1) == false, canStep(100, by: 0) == false, canStep(110, by: -1) == true.
("The control-size band shifts below 100% and above 110%", controlBand),
// controlSizeShift: 80, 90 → -1; 100, 110 → 0; 120, 130, 140 → +1.
("The zoom setting saves, reloads and reaches every window", zoomSettingRoundTrips),
// SettingsModel over an isolated store: interfaceZoom = 1.3 → store percent 130,
// ZoomModel.shared.percent == 130; a new SettingsModel on the same defaults reads 1.3;
// interfaceZoom = 1.26 stores 130. Wrapped in withZoom(100).
("Lengths written as N.zoomed scale with the zoom", zoomedLiterals),
// withZoom(140): 10.zoomed == 14, 12.5.zoomed == 17.5; withZoom(100): 12.zoomed == 12 exactly.
```

- [ ] **Step 2: Run** `./build.sh --check`. Expected: compile failure on the missing names.
- [ ] **Step 3: Implement** the produced interfaces. `nearestPercent`: non-finite → 100; clamp `scale * 100` to 80…140; round to the nearest 10, half up. `stepped` snaps with `nearestPercent(toScale: Double(percent) / 100)` and then moves along `percents`. The store getter reads `defaults.object(forKey:)` and accepts only an `NSNumber`. Add `Key.interfaceZoom` to the self-test key list. Seed `ZoomModel.shared.apply(percent:)` from `settings.interfaceZoom` in `AppCoordinator.applicationDidFinishLaunching`, after `applyApplicationAppearance`, and in `StoryFixtureContext.init` from its settings.
- [ ] **Step 4: Run** `./build.sh --check`. Expected: all pass.
- [ ] **Step 5: Prove it bites** (add-check §5). In a scratch copy, make `nearestPercent` return 100 for every input; the first check must fail. Remove the copy.
- [ ] **Step 6: Commit.** Subject: `The zoom setting is stored, snapped to a step and observed by every window`.

### Task 3: Type roles and design tokens follow the zoom

**Files:**
- Create: `scripts/compare-snapshots.swift`
- Modify: `Sources/Design/Typography.swift`, `Sources/Design/DesignTokens.swift` (21 length constants, `Space`, `Radius` except `capsule`, `Density`, `popoverWidth`), `Sources/Design/StoryStyle.swift` (3 + 4 `EdgeInsets`), `Sources/Design/PopoverMetrics.swift`, `Sources/Design/Components/TabRail.swift`, `Sources/Surfaces/Story/StoryView.swift` (`railWidth`), the `InterfaceDensity.Layout` statics in `DesignTokens.swift`, `Sources/Verification/InterfaceZoomChecks.swift`

**Interfaces:**
- Consumes: `ZoomModel.shared.scale`, `withZoom` (Task 2).
- Produces: every listed token is a `static var` of the same name and type. `Typography.Size` keeps its base `let`s. `scripts/compare-snapshots.swift <dirA> <dirB>` prints one line per differing PNG and exits 1 if any differ beyond tolerance (a channel difference above 1/255, or more than 8 differing pixels).

- [ ] **Step 1: Capture the 100% baseline.** In a temp tree (CLAUDE.md, Runtime probes) at the current HEAD: `./build.sh --test`, then `./Daybook.app/Contents/MacOS/Daybook --snapshot "$TMPDIR/fc-zoom-baseline"` (about 20 minutes; run it in the background). Keep the folder until Task 12.
- [ ] **Step 2: Write the failing check:**

```swift
("Every type role and spacing token is its base size times the zoom", tokensScale),
// For p in [80, 100, 140], inside withZoom(p): for every Typography.Role,
// Typography.pointSize(of: role) == role.baseSize * p/100;
// Space.m == 12 * p/100; Radius.panel == 16 * p/100; StoryLayout.railWidth == 300 * p/100;
// Radius.capsule == 999 at every p.
```

Roles become data so the check reads no `Font` internals. Add `enum Typography.Role: CaseIterable`, one case per role in `answer(compact:field:)` included, with `baseSize` from `Typography.Size`. Add `static func pointSize(of: Role) -> CGFloat`. Each role's `Font` is built from `pointSize(of:)`. `menuBar` and `fitted` are not roles.
- [ ] **Step 3: Run** `./build.sh --check`. Expected: the new check fails at 80% and 140%.
- [ ] **Step 4: Convert** each listed `static let` length to a computed `static var` returning `base * ZoomModel.shared.scale` (`labelSymbol` too; `menuBar` stays fixed). Keep durations, opacities and counts as `let`.
- [ ] **Step 5: Run** `./build.sh --check`. Expected: all pass.
- [ ] **Step 6: Diff at 100%.** Re-render the baseline scenarios from this tree into `$TMPDIR/fc-zoom-t3`, then run `swift scripts/compare-snapshots.swift "$TMPDIR/fc-zoom-baseline" "$TMPDIR/fc-zoom-t3"`. Expected: exit 0.
- [ ] **Step 7: Commit.** Subject: `Type roles and design tokens grow and shrink with the zoom`.

### Tasks 4–6: Length literals become zoomed (three disjoint, parallel tasks)

Each task owns only its folders. Same steps in each:

- [ ] **Step 1: List the sites.** Run the guard's patterns over the task's folders. Record the count in the commit body.
- [ ] **Step 2: Convert.** Use a token when the value matches one (`12` padding → `Tokens.Space.m`), otherwise `N.zoomed`. Turn each `static let name: CGFloat = N` length in these folders into a computed `static var`. Mark deliberately fixed lines `// zoom: fixed`. Move any length read in `init` or a stored `let` into `body`. Pass custom `Layout` and `Canvas` code its lengths from `body`.
- [ ] **Step 3: Verify.** Guard patterns over the folders print nothing; `./build.sh --check` passes; the full snapshot matrix (background, ~20 min) matches the baseline (`compare-snapshots` exit 0).
- [ ] **Step 4: Commit.**

| Task | Folders | Sites | Subject |
|---|---|---|---|
| 4 | `Sources/Design` (components), `Surfaces/{Main,Popover,Awards,Dashboard,Insights,Onboarding,AwayPrompt}`, loose `Sources/Surfaces/*.swift` | ~78 | `Shared components and the smaller surfaces draw their lengths at the zoom` |
| 5 | `Surfaces/{Settings,Focus,Today,Review}` | ~125 | `Settings, Focus, Today and Review draw their lengths at the zoom` |
| 6 | `Surfaces/{Story,History}` | ~111 | `The story and History draw their lengths at the zoom` |

`MenuBarGlyph.swift` and `MenuBarLabelView` (Task 4) are fixed: mark their lines, convert nothing. `AppIcon`, `GoalRing` and other components that take `size:`/`diameter:` use it as passed; their callers zoom.

### Task 7: The build fails on a raw length

**Files:**
- Modify: `build.sh` (a `lengths_outside_zoom` function beside `type_outside_roles`), `CLAUDE.md` (Conventions: one bullet on zoomed lengths, the guard and `// zoom: fixed`)

- [ ] **Step 1: Add the guard** using `NUM` and `LENGTH_PATTERNS` from Global Constraints. Scope it to `Sources/App`, `Sources/Design` and `Sources/Surfaces`, skip lines containing `zoom: fixed`, and fail with: `error: the lines above set a length outside the zoom; use a token or N.zoomed (Sources/Design/Zoomed.swift)`.
- [ ] **Step 2: Verify.** Run `./build.sh --check`. Expected: all pass.
- [ ] **Step 3: Mutation.** In a scratch copy add `.padding(12)` to one Surfaces file and run `./build.sh --check`. Expected: the guard error names that line. Remove the copy.
- [ ] **Step 4: Commit.** Subject: `A length written outside the zoom fails the build`.

### Task 8: Native controls step their size with the zoom

**Files:**
- Modify: `Sources/Design/Zoomed.swift` (add `Tokens.Zoom`), the 9 `.controlSize` sites, `Sources/Design/Components/ActivityChooser.swift` (`chevron`), the root of `MainWindowView`, `PopoverView`, the panels' hosting roots and the away prompt views, `Sources/Verification/InterfaceZoomChecks.swift`

**Interfaces:**
- Consumes: `InterfaceZoom.controlSizeShift(forPercent:)`, `ZoomModel.shared.percent`.
- Produces: `enum Tokens.Zoom { static var rootControlSize: ControlSize; static func controlSize(_ requested: ControlSize) -> ControlSize }`. The order is `.mini, .small, .regular, .large, .extraLarge`, clamped at both ends.

- [ ] **Step 1: Write the failing check:**

```swift
("Native controls step one size below 100% and above 110%", controlSizesStep),
// withZoom(80): rootControlSize == .small, controlSize(.small) == .mini, controlSize(.mini) == .mini;
// withZoom(100): rootControlSize == .regular, controlSize(.large) == .large;
// withZoom(140): rootControlSize == .large, controlSize(.large) == .extraLarge,
// controlSize(.extraLarge) == .extraLarge.
```

- [ ] **Step 2: Run** `./build.sh --check`. Expected: FAIL (missing `Tokens.Zoom`).
- [ ] **Step 3: Implement.** Apply `.controlSize(Tokens.Zoom.rootControlSize)` at each window and panel root, and route the 9 explicit sites through `controlSize(_:)`. Build `chevron` per zoom percent (cache one image per percent) with a `16.zoomed` canvas. Size the `labelSymbol` point size from the zoomed role.
- [ ] **Step 4: Run** `./build.sh --check` and the 100% snapshot diff. Expected: all pass, exit 0.
- [ ] **Step 5: Commit.** Subject: `Checkboxes, pop-ups and switches step their size with the zoom`.

### Task 9: Windows and panels follow the zoom while open

**Files:**
- Create: `Sources/Design/Components/ZoomWindowFit.swift` (an `NSViewRepresentable` anchor like `WindowDormancy`), `Sources/App/ZoomFollower.swift`, `Sources/Verification/ZoomWindowChecks.swift`
- Modify: `Sources/Core/InterfaceZoom.swift`, `Sources/Surfaces/Main/MainWindowView.swift:86`, `Sources/App/AppCoordinator.swift:639` (`contentMinSize`), `Sources/Surfaces/Settings/UpdateCountdownPanel.swift`, `Sources/Surfaces/RewardHUD.swift`, `Sources/Surfaces/AwayPrompt/AwayQuickPanel.swift`, `Sources/Surfaces/Settings/CategoryEditorPanel.swift:24`, `Sources/Surfaces/Focus/ActivityEditorPanel.swift:18`, `SelfTest+Registry.swift`

**Interfaces:**
- Produces:
  - `InterfaceZoom.windowMinimum(base: CGSize, scale: CGFloat, visible: CGSize) -> CGSize`: each side is base × scale, capped at visible − 40.
  - `InterfaceZoom.grownFrame(_ frame: CGRect, toFit minimum: CGSize, within visible: CGRect) -> CGRect`: when either side is below `minimum`, grows that side, keeps the top-left corner, then moves the frame the shortest distance that puts it inside `visible`. A frame already at least `minimum` is returned unchanged; it never shrinks.
  - `final class ZoomFollower { init(_ onChange: @escaping () -> Void) }`: re-arms `withObservationTracking` on `ZoomModel.shared.percent` and calls `onChange` on the main queue after each change; tracking stops when the follower is released.

- [ ] **Step 1: Write the failing checks** in `ZoomWindowChecks` and register the suite at the end:

```swift
("The window's minimum grows with the zoom but never past the screen", minimumCapped),
// base 980×680: scale 1.4, visible 2560×1400 → 1372×952; scale 1.4, visible 1470×900 → 1372×860;
// scale 0.8 → 784×544.
("A window grows to the new minimum and stays on screen", windowGrowsOnScreen),
// AppKit coordinates (bottom-up). visible (0, 0, 1470, 900), minimum 1372×860:
// (100, 100, 1000, 700) → (98, 0, 1372, 860)   [top-left kept would give y −60 → 0; x 100 → 98]
// (400, 150, 1000, 700) → (98, 0, 1372, 860)   [bottom-right overflow shifts left and up]
// (0, 200, 1500, 900)   → (0, 200, 1500, 900)  [already at least the minimum: untouched]
("A zoom change reaches each follower once, and a released follower hears nothing", followerFires),
// Two changes → two calls; after releasing the follower, a third change → no call.
```
- [ ] **Step 2: Run** `./build.sh --check`. Expected: FAIL (missing names).
- [ ] **Step 3: Implement.**
  - `MainWindowView`'s `.frame(minWidth:minHeight:)` reads `windowMinimum` from the window's screen visible size (main screen when no window yet).
  - `ZoomWindowFit` in its background holds a `ZoomFollower` that applies `grownFrame` to its window.
  - `AppCoordinator`'s preview window sets `contentMinSize` from `windowMinimum`.
  - The two editor panels' `width` become computed (their hosting views already use `.preferredContentSize`).
  - `UpdateCountdownPanel` sets `sizingOptions = [.preferredContentSize]`.
  - `RewardHUD` and `AwayQuickPanel` keep a `ZoomFollower` that reruns their existing measure-and-`setFrame` path.
- [ ] **Step 4: Run** `./build.sh --check`. Expected: all pass.
- [ ] **Step 5: Commit.** Subject: `Windows and panels resize as the zoom changes and stay on screen`.

### Task 10: Settings has a Zoom slider

**Files:**
- Modify: `Sources/App/SettingsModel.swift` (`SettingsControlKey.zoom` → `\SettingsModel.interfaceZoom`), `Sources/Surfaces/Settings/SettingsSidebar.swift:195` (append `.zoom` after `.density`) and the settings search terms, `Sources/Surfaces/Settings/SettingsGroups.swift` (`appearance`, after the Interface density row), `Sources/Verification/InterfaceZoomChecks.swift`

**Interfaces:**
- Consumes: `SettingsModel.interfaceZoom` (Task 2).

- [ ] **Step 1: Write the failing check:**

```swift
("Settings search finds Zoom by zoom, text size, bigger, smaller and scale", zoomIsSearchable),
// Each term returns SettingsControlKey.zoom among its results, in the Appearance section.
```

- [ ] **Step 2: Run** `./build.sh --check`. Expected: FAIL. The existing every-key-has-a-row checks may also fail once `.zoom` exists; both are fixed in Step 3.
- [ ] **Step 3: Implement the row.**
  - `preferenceRow("Zoom", detail: "Makes text, spacing and controls larger or smaller in every Daybook window.")`.
  - It holds a `Slider(value: $model.interfaceZoom, in: 0.8...1.4, step: 0.1)` with minimum label `Text("A")` in `Tokens.Typography.caption` and maximum label `Text("A")` in `Tokens.Typography.heading`.
  - Then the percentage (`"\(percent)%"`, monospaced digits) and `Button("Actual Size") { model.interfaceZoom = 1 }`, shown only when the percent is not 100.
  - Accessibility: label `"Zoom"`, value `"\(percent) percent"`.
- [ ] **Step 4: Run** `./build.sh --check`, then `FC_SNAPSHOT_ONLY=settingsAppearance` snapshots at 100% (new row expected) and look at the image.
- [ ] **Step 5: Commit.** Subject: `Settings has a Zoom slider under Interface density`.

### Task 11: ⌘+, ⌘− and ⌘0 zoom from the View menu

**Files:**
- Create: `Sources/Surfaces/Main/ZoomCommands.swift`, `Sources/App/ZoomKeyMonitor.swift` (only if Step 1 shows it is needed)
- Modify: `Sources/App/DaybookApp.swift` (`.commands`), `Sources/Verification/StoryFixtureApp.swift` (`.commands`), `Sources/Verification/ZoomWindowChecks.swift`

**Interfaces:**
- Consumes: `InterfaceZoom.stepped`, `InterfaceZoom.canStep`, `SettingsModel.interfaceZoom`.
- Produces: `struct ZoomCommands: Commands { let settings: SettingsModel }`. Writes go through `settings.interfaceZoom`, so the slider, the stored value and every window agree.

- [ ] **Step 1: Measure the keys.** In a probe app (Runtime probes), a `CommandGroup(after: .toolbar)` holds `Button("Zoom In").keyboardShortcut("+", modifiers: .command)` and logs its action. Drive it with real key events from `osascript -e 'tell application "System Events" to keystroke "=" using command down'` (and `"+"` with Shift, and key codes 69/78 for keypad + and −). Record which combinations fire. If ⌘= or keypad ± do not, `ZoomKeyMonitor` adds an `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` that handles exactly those, only when the key window belongs to Daybook. If System Events access is refused, ask the user to press the keys in the fixture window instead.
- [ ] **Step 2: Write the failing check:**

```swift
("Zoom In, Zoom Out and Actual Size disable at their limits", zoomMenuLimits),
// ZoomCommands.availability(percent:) -> (zoomIn: Bool, zoomOut: Bool, actualSize: Bool):
// 140 → (false, true, true); 80 → (true, false, true); 100 → (true, true, false).
```

- [ ] **Step 3: Run** `./build.sh --check`. Expected: FAIL.
- [ ] **Step 4: Implement** `ZoomCommands`. Zoom In ⌘+, Zoom Out ⌘−, Actual Size ⌘0, with `.disabled` from `availability`. Wire it into both apps' `.commands`, and add `ZoomKeyMonitor` if Step 1 requires it, installed by `AppCoordinator` at launch.
- [ ] **Step 5: Verify by hand.**
  - Run `--fixture-window storyDay` from a temp-tree build.
  - Press ⌘+ four times and confirm the window, the Settings sheet (open it first) and its slider all move to 140%.
  - Click into a text field (a session note), press ⌘− and confirm the zoom changes and the field's text is unchanged.
  - Press ⌘0 and confirm everything returns to 100%.
  - The fixture has no menu-bar panel. List "⌘+ with the menu-bar panel key" in the PR as a check for the user once the build is installed; installing replaces their running app, so only on their word.
- [ ] **Step 6: Commit.** Subject: `⌘+, ⌘− and ⌘0 zoom the interface from the View menu`.

### Task 12: Zoom is verified at every size and handed off

**Files:**
- Modify: `Sources/Surfaces/Snapshotter.swift` (read `FC_SNAPSHOT_ZOOM`, apply it to `ZoomModel.shared` before rendering, scale `shellSize`, add `-zoom<percent>` to filenames when not 100)

- [ ] **Step 1: Full 100% diff.** Render the whole matrix into `$TMPDIR/fc-zoom-final` and compare against the baseline. Expected: exit 0. Any difference is a regression: fix it in the task that owns the file.
- [ ] **Step 2: 80% and 140%.** Use `FC_SNAPSHOT_ZOOM=0.8` and `1.4` for `storyDay`, `reviewHistorySelection`, `settingsAppearance` and `awayFull`, plus the popover presentation. Review each image for clipping and for "…" that the 100% image lacks (Review Focus 1–2). Render `awayFull` and the popover at 140% into a 1470 × 956 shell as well.
- [ ] **Step 3: CPU.** Build the baseline (Task 2's commit) and HEAD in temp trees. Run each with `--fixture-window storyLive` and sample `top -l 30 -s 1 -stats cpu -pid <pid>` for 30 s. Expected: HEAD's mean is within 0.5 percentage points of the baseline's.
- [ ] **Step 4: Suite and CI.** `./build.sh --check` passes locally, and `TZ=Europe/Berlin ./build.sh --check` passes too. Push the branch and open a PR; the macos-26 check must be green.
- [ ] **Step 5: Hand off.** Log `ready` on the sessions board with the PR number and check count, then remove the temp trees and `$TMPDIR/fc-zoom-*`, running `lsregister -u` on any launched bundle first. Do not push to main.
- [ ] **Step 6: Commit** (the Snapshotter change, before Step 4's push). Subject: `Snapshots can be rendered at any zoom`.
