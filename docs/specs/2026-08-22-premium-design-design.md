# Premium Design (Direction A) — Design

Date: 2026-08-22. Status: approved direction, spec for review.

## Problem

The app's numbers are now right; its surfaces do not look like they are. Every element
sits at one visual level — plain rows, hairline dividers, flat background — so the eye has
nowhere to land. The hero timer floats; the goal, the most important figure in the app, is a
3pt bar; the popover spends nearly half its height on a twenty-row settings form; app and
category colours are saturated defaults that read as a developer tool; the dashboard has no
hero and a tall void beneath its content. The one well-designed thing — the stat row's big
numerals under small-caps labels — is the standard the rest should rise to.

The user's brief: *make it look like a million dollars, in the app and on the menu bar.*
The chosen direction is **native-premium** — Things 3 / Apple Fitness / Cron: tonal
surfaces, one accent, a restrained data palette, a clear type scale, an 8pt rhythm, a
signature goal ring, and motion that reports value changes rather than decorates.

## Goals

1. Three tonal surface levels and a card vocabulary shared by the popover and the dashboard.
2. One accent (the system accent) for everything interactive; a curated seven-colour data
   palette for apps and a fixed semantic set for work types, identical on every surface.
3. A goal ring as the app's signature element: in the hero, in the dashboard stat band, and
   as the menu-bar glyph.
4. Settings moved out of the popover into a standard macOS Settings window (⌘,), so the
   popover is a glance surface again and fits a 13" screen without the scroll machinery.
5. A dashboard with a title band, a stat band where every figure carries its own context
   line, and card-based sections that stop the ground reading as emptiness.
6. Motion limited to value changes: ring fills, numeric digit transitions, row hover.
7. Nothing that costs a permission, a timer, a package, or a macro.

## Non-goals

- No new data, metrics or rules. Every figure shown already exists; this spec moves and
  dresses them. (One exception: a previous-period total for the Week/Month stat band, which
  is one extra rollup call.)
- No custom brand accent. The system accent is the accent.
- No onboarding flow, no illustrations, no sound.
- No change to `PopoverMetrics`' sizing rules beyond removing the settings region from the
  scroll budget.
- No light-only or dark-only treatment; every token is a light/dark pair.

## Design

### 1. Foundations

All tokens live in `Sources/Design/DesignTokens.swift`. Colours are light/dark pairs built
with `NSColor(name:dynamicProvider:)` wrapped as `Color`, so no asset catalog is needed and
the pair flips with the system appearance. Values below are starting points, to be tuned on
screen in the live app; the *names* are the contract.

**Surfaces** (`Tokens.Surface`)

| Token | Light | Dark | Use |
|---|---|---|---|
| `ground` | `#F4F4F6` | `#1C1C1E` | window / popover ground |
| `card` | `#FFFFFF` | `#2A2A2D` | cards, the hero, the away card |
| `well` | `#ECECEF` | `#141416` | bar tracks, timeline gaps, ring track |
| `hairline` | black 8% | white 9% | card borders, row separators |
| `hover` | black 4% | white 6% | row hover |

The popover uses `.regularMaterial` behind `ground` when the hosting window is non-opaque
(verified live, see Known limits); otherwise `ground` alone.

**Data palette** (`Tokens.Palette.app(rank:)`, rank 0…6; 6 is "Other")

| Rank | Name | Light | Dark |
|---|---|---|---|
| 0 | blue | `#4A7BE0` | `#7DA2F2` |
| 1 | teal | `#2E9E86` | `#5CC4AB` |
| 2 | amber | `#D08A2A` | `#E6AE5B` |
| 3 | violet | `#8A6CD4` | `#AE97E8` |
| 4 | rose | `#CF5F7C` | `#E58AA3` |
| 5 | cyan | `#4695B5` | `#78BBD5` |
| 6 | other | `#8E8E93` | `#98989D` |

Assigned by the day's rank (busiest app = 0), the rule `DashboardStats` already uses for
`colorIndex`; the same index drives the popover strip, the dashboard timeline, the session
log bars and the Earlier list, so one app is one colour on every surface that day.

**Work types** (`Tokens.Palette.workType(_:)`)

| Work type | Colour |
|---|---|
| `.deepWork` | `Color.accentColor` |
| `.meetings` | palette amber |
| `.admin` | slate `#6C7A93` / `#93A1BB` |
| `.learning` | palette violet |
| `.breakTime` | warm grey `#A39E98` / `#7E7973` |

**Type** (`Tokens.Typography`)

| Token | Font |
|---|---|
| `heroTimer` | `.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit()` |
| `stat` | `.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit()` |
| `ringLabel` | `.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit()` |
| `title` | `.system(size: 20, weight: .semibold)` |
| `sectionLabel` | `.system(size: 11, weight: .semibold)`, uppercased, `.kerning(0.7)`, secondary |
| `row` | `.callout` |
| `detail` | `.caption`, secondary |
| `menuBar` | unchanged (system font, monospaced digits) |

SF Mono leaves the app: the timer and stat numerals use SF Rounded with tabular digits,
which reads as a product rather than a terminal.

**Spacing and radii.** `Tokens.Space` keeps 4/8/12/16/24 and gains `xxl = 32`.
`Tokens.Radius`: `card = 12`, `control = 8`, `swatch = 5`, `bar = 3`. Card padding is 16
(12 when `PopoverMetrics.dense`). Everything sits on the 8pt grid.

**Iconography.** SF Symbols, `.hierarchical` rendering, 15pt in rows, 13pt in detail lines.
App icons come from `AppIcon.swift` as today; each row also carries a 6pt colour swatch
keyed to the palette rank, so the colour legend is the row itself.

### 2. Components

New files under `Sources/Design/Components/` unless noted. Every component takes plain
values so the gallery can drive it from fixtures.

| Component | Signature | Notes |
|---|---|---|
| `Card` | `View.card(padding: CGFloat = 16, surface: Color = Surface.card)` | background, `Radius.card`, hairline stroke |
| `SectionLabel` | `SectionLabel(_ text: String, trailing: String? = nil)` | `Typography.sectionLabel`; trailing in `Typography.detail` |
| `GoalRing` | `GoalRing(progress: Double, diameter: CGFloat, lineWidth: CGFloat, label: String? = nil, isMet: Bool)` | `Circle().trim` over a `well` track, accent fill, round caps; `isMet` shows a checkmark in place of the label; animates on `progress` |
| `StatCard` | `StatCard(label: String, value: String, context: String? = nil, contextTint: Color? = nil)` | `Typography.stat` value; context line in `Typography.detail`, optionally tinted (delta up = teal, down = secondary) |
| `DataBar` | `DataBar(share: Double, tint: Color)` | 6pt, `Radius.bar`, `well` track |
| `AppSwatch` | `AppSwatch(rank: Int, bundleID: String?)` | app icon when available, else a rounded square in the palette colour; always a 6pt dot in the palette colour beside it |
| `IconButton` | `IconButton(systemImage: String, help: String, action: () -> Void)` | 28pt circle, `hover` background, `.help` |
| `MenuBarGlyph` | `static func image(progress: Double, paused: Bool, attention: Bool) -> NSImage` | 16×16 template ring rendered with `ImageRenderer` at 2×; in `Sources/Design/` |

Changed in `Components.swift`: `StartButton` (accent-filled, `Radius.control`, never full width),
`ResolveCard` (card style, option buttons as pills, the same four answers), `MenuBarLabel`
(uses `MenuBarGlyph`). `GoalBar.swift` is superseded by `GoalRing` plus a one-line goal
caption and moves to `_trash/`.

### 3. Menu bar item

The status item shows a **ring glyph** and, while a session runs, the session's elapsed.
The ring is the day's goal progress, so the item says something even when nothing is
running. States:

| State | Glyph | Text |
|---|---|---|
| idle | ring at today's progress | — |
| running | ring | `1h 23m` |
| paused | ring, pause mark inside | `⏸ 1h 23m`, secondary |
| awaiting decision | ring with a dot at the top-right | as running |
| goal met | ring closed, check inside | as state |

The glyph is a **template** image (monochrome), so it follows the menu bar's own
appearance and never fights the user's wallpaper. It is re-rendered inside the existing
one-second tick via the label view's body — `elapsed` and `goal` are already published —
and costs one 32×32 raster per second while running. No new timer. If `ImageRenderer`
ever yields nil, the label falls back to the `infinity` symbol it uses today.

### 4. Popover

Width and density come from `PopoverMetrics` unchanged: 560 two-column when the screen
allows, 320 single. With Settings gone, the scrolling middle is only needed on the
smallest screens; the pinned-header / measured-middle / pinned-footer structure stays as
the safety net.

Top to bottom:

1. **Header line** — `At the Mac 5h 10m` left, streak (`flame` + `7 days`) right. `Typography.detail`.
2. **Hero card.** Left: `GoalRing` 64pt, label = `63%` (or the check when met). Right:
   running → timer in `Typography.heroTimer`, intent in `.callout` secondary, goal caption
   (`2h 31m of 4h · 1h 42m behind usual`, with the existing tooltips), and a controls row:
   `IconButton` pause/resume, `IconButton` away (`door.right.hand.open`), `Stop` as an
   accent-filled pill. Idle → `Ready when you are` in `Typography.title`, the intent field, the
   work-type menu, and `Start Focus`; quick starts as chips below when there are any. Away
   (marked) → `I'm back` filled, `Stop` plain. Awaiting → the `ResolveCard` replaces the
   hero's right half.
3. **Today card** — the timeline strip, segments in palette colours with `Radius.swatch`
   corners, gaps as `well`, hour labels in `Typography.detail`. Full width.
4. **Top apps** and **Continue today** — two cards side by side when two-column, stacked
   when single. Rows: `AppSwatch` · name · `DataBar` · duration · share. `topAppCount` from
   metrics. Continue rows keep the running marker and the `Continue` pill.
5. **Footer** — break countdown left (`eye` + `Look away in 20m`, `Typography.detail`); right:
   three `IconButton`s with tooltips — `rectangle.grid.2x2` *Open Dashboard*, `gearshape`
   *Settings…*, `power` *Quit FocusContinuity*. ⌘, and ⌘Q also work.

Nothing is stretched to fill width; cards size to content and the ground shows between them.

### 5. Dashboard

Window minimum 900×620, vertical `ScrollView`, ground background. Two columns as today —
left flexible (min 480), right fixed 280 — but every section is a card.

1. **Title band.** Left: `Today` / `Yesterday` / `Wed 13 Aug` in `Typography.title`, beneath it
   the full date · streak · goal status in `Typography.detail`. Right: Day · Week · Month segmented,
   the day stepper with the date picker, `Today` link when not on today.
2. **Active session bar** (when a session exists): a card with timer, intent, and the
   controls row; the `ResolveCard` when awaiting. Absent when idle — the popover owns
   starting.
3. **Stat band.** Four `StatCard`s plus a ring card (`GoalRing` 64pt with `2h 31m` inside,
   `of 4h` beneath). Day: Tracked (context: `+3h 5m vs yesterday`), Sessions (context:
   `longest 1h 35m · Refactor`), Focused (context: `10% of tracked`), Quality (value: top
   work-type share e.g. `Deep work 100%`, context: `0 switches / session`). Week/Month:
   Tracked (context: vs the previous period), Active days (`6 of 7`), Average / day
   (`across active days`), Longest stretch (app name). The previous-period figure is one
   added `PeriodStats` call.
4. **Left column.** Session log card (header: `SectionLabel("Session log", trailing: "4
   apps")` + the grouping segmented control; rows as in the popover; the existing minor-apps
   fold). Then the Timeline card (Day) or the Period chart card (Week/Month) with bars in
   the work-type colours and the average line. Then a compact Focus quality card (work-type
   split bar + the two figures).
5. **Right column.** Running now, Earlier, Insights — three cards. `Earlier` reads *Earlier
   today* on today and *Earlier that day* otherwise; insight headlines drop "today" (the
   title band names the day). Cards are content-sized; the ground beneath them is the
   layout, not a void.

### 6. Settings window

A standard `Settings` scene (⌘,), opened from the popover gear via
`NSApp.activate(ignoringOtherApps:)` then `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)`
— `SettingsLink` is macOS 14 and this app targets 13. `TabView` with four tabs, each a
`Form` in `.formStyle(.grouped)`, width 480:

| Tab | Rows | Footer copy |
|---|---|---|
| Goal | Daily goal (`dailyGoalOptions`) | Counts only focus sessions while you were actually using the Mac. Your usual pace compares today with the same hour on your last fourteen working days. |
| Away and breaks | Ask me after (`thresholdOptions`); End session after (`longAwayCapOptions`); Remind me to take breaks (toggle) | The ladder (*under 5 s ignored · up to the threshold not counted · up to the cap you are asked · past it the session ends where you left*), then the three break tiers with their reasons. |
| Automatic | Start sessions for me; Auto-session gap (`breakLengthOptions`); Celebrate milestones | Sessions the app starts can be undone from the notice; one it ends on its own ends where the work stopped. |
| Display | Sessions per app; Record app usage (toggle) | Recording is local, names and bundle identifiers only. |

A new `SettingsModel: ObservableObject` (`Sources/App/SettingsModel.swift`) wraps the
`PersistenceStore` properties the settings edit and calls `onChange` — wired to
`store.refresh()` — after each write. `SessionStore` loses its settings accessors
(`dailyGoal`, `autoSessionsEnabled`, `rewardsEnabled`, `remindersEnabled`, `breakLength`,
`breakThreshold`, `longAwayCap`, `menuSessionCount`); it keeps reading `engine.store` for
behaviour. `setTrackingEnabled` stays on `SessionStore`, which owns the tracker;
`SettingsModel` exposes `isTrackingEnabled` and forwards through an injected
`onTrackingChanged: (Bool) -> Void`. The popover's `settingsAlwaysOpen` harness hook goes
away with the section.

### 7. Motion

- `GoalRing`: `.animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)`.
- Timer and stat values: `.contentTransition(.numericText())` (macOS 13).
- Rows: `.onHover` sets a `hover` background; no other hover effects.
- No appear/disappear transitions in the popover — it must open instantly.

### 8. Copy

Sentence case everywhere. Labels keep their current words where they are already right
(`At the Mac`, `Continue today`, `Top apps`). Day-aware wording as in §5. No punctuation
on labels; explanatory footers end with a period. Tooltips (`InfoTip`) are unchanged in
content and move with their figures.

### 9. File structure

Create:
- `Sources/Design/Components/Card.swift`, `GoalRing.swift`, `StatCard.swift`, `DataBar.swift`,
  `AppSwatch.swift`, `IconButton.swift`, `SectionLabel.swift`
- `Sources/Design/MenuBarGlyph.swift`
- `Sources/App/SettingsModel.swift`
- `Sources/Surfaces/Settings/SettingsView.swift`
- `Sources/Surfaces/Popover/HeroCard.swift`, `GlanceCards.swift`, `PopoverFooter.swift`

Modify:
- `Sources/Design/DesignTokens.swift` — `Surface`, `Palette`, `Type`, `Radius`, `Color(light:dark:)`
- `Sources/Design/Components/Components.swift` — `StartButton`, `ResolveCard`, `MenuBarLabel`
- `Sources/Surfaces/PopoverView.swift` → moves to `Sources/Surfaces/Popover/PopoverView.swift`,
  keeps frame/metrics/scroll only; settings section removed
- `Sources/Surfaces/Dashboard/DashboardView.swift`, `DashboardSections.swift`,
  `DayTimelineView.swift`, `PeriodViews.swift` — restyle to cards and the palette
- `Sources/Surfaces/ContinueTodaySection.swift` — rows and pills
- `Sources/App/FocusContinuityApp.swift` — `Settings` scene
- `Sources/App/SessionStore.swift` — settings accessors out, `previousPeriodTracked` in
- `Sources/Core/PeriodStats.swift` — `previousPeriodTracked(for:containing:)`
- `Sources/Surfaces/Snapshotter.swift`, `GalleryView.swift` — new states, no settings render
- `Sources/SelfTest.swift` — tests below

Move to `_trash/`: `Sources/Surfaces/GoalBar.swift`.

Files stay under 500 lines: the popover split and the settings extraction are what bring
`PopoverView` and `SessionStore` back under the rule.

## Global constraints (carried verbatim)

- Not a git repository; no `git init`.
- No Xcode: `@State` and `@Observable` do not compile. View state lives in `ObservableObject`
  + `@Published`, consumed via `@StateObject` / `@ObservedObject` / `@EnvironmentObject`.
- `Sources/Core/` imports Foundation and CoreGraphics only.
- Exactly one repeating `Timer`: the one-second ticker in `SessionStore.startTicker()`.
- No new TCC permissions. No third-party packages. macOS 13.0 target.
- Files under 500 lines; no working files in the root; never delete — move to `_trash/`.
- Snapshot harness (`ImageRenderer`) cannot draw `TextField`, `Toggle`, `Picker`,
  `DisclosureGroup`, `.borderless` buttons, materials or `ScrollView` — those are verified in
  the live app.

## Known limits

- **Materials.** `ImageRenderer` draws no material; the popover's backing is judged live
  and falls back to `ground` if the hosting window is opaque.
- **Menu-bar glyph** is a raster, not a symbol; it is template-tinted so it matches, but it
  cannot use the symbol's own weight scaling.
- **System accent.** With a grey accent the ring and Stop pill go grey too; that is the
  user's choice and the design accepts it.
- **Palette legibility** is tuned by eye on this machine's displays; the values are starting
  points and live in one place.

## Testing

Headless in `SelfTest.swift`:

1. `Palette.app(rank:)` returns seven distinct colours in both appearances and clamps ranks
   past six to "other"; `Palette.workType(_:)` is total over `WorkType.allCases`.
2. `PeriodStats.previousPeriodTracked` equals `rollup(for: previous period).summary.tracked`
   for week and month, and zero with no data.
3. `SettingsModel`: every property writes through to `PersistenceStore` and fires `onChange`
   once per write (suite-scoped `UserDefaults`).
4. `MenuBarGlyph.image` returns a non-nil template image for each state.
5. `PopoverMetrics` (72) unchanged.

Harness: `--snapshot` renders every state on both surfaces without a collapsed region;
`--gallery` gains the hero idle/running/awaiting cards and a stat band. The Settings window
is not renderable headless.

Live, with screenshots kept with the plan: popover at 13" and 14" in light and dark, with
the away card up; dashboard on Today, Yesterday, Week; Settings from ⌘, and from the gear;
the menu-bar glyph in all five states.
