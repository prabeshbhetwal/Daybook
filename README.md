# FocusContinuity

FocusContinuity is a private, native macOS focus-session tracker. It records
focus sessions and local app-use evidence while being deliberately honest about
locks, sleep, idle time, breaks and uncertainty. The menu-bar popover is for
the next action; the main window explains what happened without presenting
foreground time as deliberate work.

It is built with SwiftUI, AppKit and Swift Charts. There is no Xcode project,
package dependency, web service, account, telemetry or model: `build.sh`
invokes `swiftc` directly.

## What it does

- Tracks declared focus sessions, pauses, away decisions, breaks and threads.
- Records local foreground app-use stretches, trims unattended idle tails and
  excludes known system processes.
- Keeps an evidence-led main window with **Focus**, **Today**, **Review**,
  **Insights** and **Settings** tabs.
- Shows exact tracked time in Review and only evidence-backed statements in
  Insights.
- Preserves historical app-use records, qualifying data from before the
  corrected recorder's accuracy epoch instead of silently repairing it.
- Provides local light/dark snapshot scenarios for product review.

## Requirements

- macOS 13 or later
- Apple Command Line Tools with `swiftc`, AppKit and SwiftUI
- An arm64 or Intel macOS host (the build targets the host architecture)

The code builds in Swift 5 language mode with warnings treated as errors. It
does not require Xcode, Swift Package Manager or third-party dependencies.

## Build and run

From the repository root:

```bash
./build.sh          # Build and replace the local app after verification
./build.sh --run    # Build, verify and open FocusContinuity.app
./build.sh --test   # Build, promote the local app and run the headless suite
./build.sh --check  # Stage, strictly verify and test without replacing the app
```

The generated `FocusContinuity.app` is locally ad-hoc signed. It passes the
project's deep signature check, but it is not notarised or distributable.

For release-safety verification after a promoted local build:

```bash
./scripts/test-build-concurrency.sh
codesign --verify --deep FocusContinuity.app
```

The concurrency harness validates staged promotion, stale recovery, ownership,
symlink and fail-closed guard handling. It deliberately creates temporary build
fixtures under `.build/`; those artefacts are ignored.

## Use the app

The main window has one persistent tab rail.

| Tab | Question it answers | Main content |
|---|---|---|
| Focus | What should I do now? | Start, pause, away/stop actions, current thread and break context |
| Today | What happened on this calendar day? | Activity ribbon, selected inspector, sessions, app evidence and recap |
| Review | How did time change across a period? | Period answer, exact tracked Week/Month bars, selected-day detail and searchable History |
| Insights | What patterns are supported? | Gated pace, rhythm, quality and continuity statements |
| Settings | How should the app behave? | Real persisted controls, privacy evidence and diagnostics |

Keyboard shortcuts:

| Shortcut | Action |
|---|---|
| `Command-1` … `Command-5` | Select Focus, Today, Review, Insights or Settings |
| `Command-,` | Open Settings in the main window |
| Left / Right | Move across the focused tab rail |
| Escape | Clear Today’s current ribbon/session selection without changing the day |

The compact menu-bar popover intentionally remains Focus-only. It provides the
current action, up to three continuation choices, quiet break context, and
**Open FocusContinuity**, **Settings** and **Quit**.

## Time and evidence model

FocusContinuity keeps related measures separate:

| Measure | Meaning |
|---|---|
| **Focused** | Declared focus-session time, clipped to the relevant day or period |
| **Focused-active** | Declared focus time that overlaps authoritative hands-on app-use evidence; used for goals and pace |
| **Tracked / At the Mac** | Local observed app-use time; not presented as deliberate work |
| **Break / Watching / Away** | Explicit rest or uncertainty states; never silently counted as focus |

An extended absence creates an honest decision rather than guessing. While a
decision is unresolved, ordinary start/stop/pause/continue actions—including
the global hotkey—are blocked and route back to the existing decision surface.

Historical sessions and app use are clipped by local calendar day, so a
cross-midnight session contributes only its proper portion to each day.
Review bars use exact tracked time; work-type composition is separate.

Review reads as one workbench: the period answer, then the tracked-by-day
trend, then the day you select from it. Selecting a bar or a History row
explains that day inline and keeps you in Review — moving to Today is the
separate, named **Open in Today** action on the selected-day detail. History
states its date range in one compact control and names Tracked, Focused and
Sessions once in a table header rather than beside every value.

## Privacy and local storage

Everything stays on the Mac.

- App-use recording stores local app identity and time ranges, not content.
- Monitoring does not capture text typed in other apps. Session names entered
  directly into FocusContinuity are stored locally as part of session history.
- No Accessibility, Automation, Screen Recording or Input Monitoring permission
  is requested. Idle and input-density checks use system counters rather than
  event content.
- Session history is stored atomically in
  `~/Library/Application Support/FocusContinuity/sessions.json`.
- App use is stored beside it in `app-usage.json` as a versioned v2 envelope.

The v2 app-use envelope has an `accurateFrom` timestamp. Earlier preserved
usage is never rewritten; Today, Review, History and Insights qualify or exclude
it where an authoritative claim would otherwise be misleading. Legacy v1 data is
backed up byte-for-byte before migration and can be located from **Settings →
Data and privacy**.

## Architecture

```text
Core                     App                            Design / Surfaces
──────────────────      ───────────────────────────    ──────────────────────────
SessionEngine            AppCoordinator                 MainWindowView
AppUsageTracker          SessionStore (+ read models)   Focus / Today / Review
AppUsageArchive          SettingsModel                  Insights / Settings
DailyGoal                MainWindowModel                Popover / Away / Reward
PeriodStats              Persistence wiring             Tokens / reusable controls
PresenceGate
```

- **Core** is UI-free logic and data: the session state machine, usage tracking,
  clipping, goals, periods, persistence formats and pure calculations.
- **App** owns macOS event wiring and publishes canonical read models. It is the
  boundary for session actions, settings, refresh coalescing and navigation.
- **Design / Surfaces** renders those models. Views do not read storage files or
  recalculate time accounting.

The single one-second ticker lives in `SessionStore`. It observes presence,
flushes usage checkpoints, refreshes live figures and evaluates breaks; no
second repeating timer is introduced by the UI.

## Settings

Settings exposes only backed controls across eight groups:

1. General
2. Focus sessions
3. Away and breaks
4. Automatic and rewards
5. Tracking and apps
6. Appearance
7. Data and privacy
8. Advanced

Appearance, interface density and timeline labels are persisted preferences
with real effects in the main window, popover and Today ribbon. **Sessions per
app** controls the newest grouped session rows shown for the currently selected
Today app. Advanced is diagnostic and read-only; unsupported launch, export,
retention, editing and destructive controls are not displayed.

## Tests and visual review

`Sources/SelfTest.swift` is a headless suite using isolated defaults and
temporary directories. It covers session transitions, focus accounting,
presence after wake, usage persistence, historical clipping, accuracy epochs,
Review/History/Insights evidence gates, Settings effects, accessibility and
release recovery.

The binary also supports review modes:

```bash
./FocusContinuity.app/Contents/MacOS/FocusContinuity --gallery
./FocusContinuity.app/Contents/MacOS/FocusContinuity --snapshot ./snapshots
```

`--gallery` and `--snapshot` use the same `SnapshotScenario` catalogue. The
matrix covers Focus, Today, Review (including a selected first day, a selected
last day and a selected History row), Insights, all Settings groups, compact Away
and Reward states in light/dark; main-window scenarios also render at minimum
and comfortable widths. `ImageRenderer` may show placeholder interiors for
native AppKit fields or menus, so use the live Gallery when native control
chrome itself needs inspection.

## Repository layout

```text
Sources/
  Core/                 Time accounting, persistence, periods and pure models
  App/                  macOS coordination, SessionStore and settings/navigation
  Design/               Semantic tokens and reusable SwiftUI components
  Surfaces/             Product screens, popover, prompts, gallery and snapshots
  SelfTest.swift        Headless verification suite
build.sh                Direct Swift build, signing, promotion and test entry point
scripts/                Release-concurrency verification
docs/superpowers/       Approved designs, specifications and implementation plans
```

Generated bundles, build state, snapshots, Codex worktrees and internal
execution reports are ignored. Commit source, tests, documentation and scripts
that directly describe or build the project; do not force-add generated apps or
agent scratch reports.

## Project documentation

- [Current interface design](docs/superpowers/specs/2026-08-29-interface-redesign-design.md)
- [Interface implementation plan](docs/superpowers/plans/2026-08-29-interface-redesign.md)
- [Stabilisation design](docs/superpowers/specs/2026-08-28-focuscontinuity-stabilisation-design.md)
- [Build and repository hardening plan](docs/superpowers/plans/2026-08-28-build-repository-hardening.md)

## Contributing

Keep the Core → App → Design/Surfaces boundary intact. Add a focused headless
regression before changing behaviour, preserve user evidence rather than
rewriting it, and run `./build.sh --check` before committing. For release-path
changes, also run the concurrency harness after a promoted `./build.sh --test`.
