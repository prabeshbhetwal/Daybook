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
- Tells the day newest-first, with **Day**, **Week** and **Month** scopes
  and supporting focus, app-use, rhythm and current-streak tiles.
- Shows exact tracked time in Week and only evidence-backed statements in
  Insights.
- Offers searchable History and native sheets for session controls, Insights,
  Awards and Settings, without losing the selected story.
- Offers editable activity suggestions and remembers recently started names.
- Allows durable session-name/type corrections and contextual away-decision Undo.
- Shows recorded app-use shapes in expanded sessions and at most four top apps
  in the supporting rail.
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
./build.sh --test   # Build and test, then promote the verified local app
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

The main window has one persistent scope selector. Scopes retain the date you
are inspecting; opening a historical story never substitutes today's data.

| Surface | Question it answers | Main content |
|---|---|---|
| Day | What happened on this calendar day? | Focus-led summary, chronological stretches, named rest, app use and honest recording gaps |
| Week | How did the days compare? | Focus summary, exact tracked bars, focused work-type composition and selected-day preview |
| Month | How was focus distributed? | Date-and-duration calendar, relative focus intensity, weekly totals and selected-day preview |
| Session controls | What should I do now? | Intent, work type, Start, Pause, Resume, Away, Stop and pending-away decisions |
| History | Where is an older record? | Search by date/app/work type, intersection filters and inline day evidence |
| Insights | What patterns are supported? | Gated pace, rhythm, quality and continuity statements |
| Awards | What milestones have I earned? | Achievements derived from recorded evidence, with their criteria |
| Settings | How should the app behave? | Real persisted controls, privacy evidence and diagnostics |

Keyboard shortcuts:

| Shortcut | Action |
|---|---|
| `Command-1`, `Command-2`, `Command-3` | Day, Week, Month |
| `Command-4`, `Command-5`, `Command-6` | History, Insights, Awards |
| `Command-7` | Session controls |
| `Command-,` | Settings |
| Escape | Dismiss a native sheet/app detail or cancel an inline rename |

Current work is at the top of the timeline; earlier work and rest continue
downwards. Click an entry's full header to expand it. Inspect an app from the rail to see
its scoped recorded visits. Select a calendar day or Week bar for a preview,
then use **Open as a story** for that date's full chronology. History rows expand
in place; **Open this day's story** is an explicit drill-in, not an automatic
redirect. Choose **Arrange cards** to reorder the rail; dragging is active only
while arranging, and each card also offers keyboard Move up / Move down.

An expanded entry offers **Rename**, **Change type**, **Continue this** and
**Add note**. Notes belong to the exact stretch they were written on and are
kept beside the session archive, never inside it, so a note can never alter
recorded time or an Undo. Where power was observed while a stretch ran, the
entry shows it factually — **Battery · 78% → 64%**, **Plugged in** or
**Plugged in, charging** — and a stretch with no observation shows no power
line at all rather than an invented reading.

**Activity rules** (Settings → Sessions) are opt-in. Each rule names an
activity, a work type, the applications that belong to it and how long an app
must be in front before the activity begins (30 s to 30 min; 3 min by
default). When rules are on they replace the legacy heuristic rather than run
beside it. One activity owns any moment: an app that belongs to several rules
records its use once and asks a quiet choice — for example **Coding or Research?** — in the session
controls and the menu panel instead of starting two sessions. An explicit
activity you started is never relabelled. Every automatic start says why it
happened and offers **Undo**; the application picker lists installed apps
from the standard application folders and apps already observed, with
**Add application…** for anything missed.

The compact menu-bar popover intentionally remains Focus-only. It provides the
current action, up to three continuation choices, quiet break context, and
**Open FocusContinuity**, **Settings** and **Quit**.
Opening the app reveals the Story without automatically presenting the session
sheet; use **Session controls** or `Command-7` when you want that sheet.

When starting focus, choose a suggestion from the activity field's menu or write
your own name. Choosing an item only fills the draft. Start explicitly to begin
work; started names are remembered locally for reuse. **Work type** is a separate,
labelled classification, not a restriction on the name you can enter.

## Time and evidence model

FocusContinuity keeps related measures separate:

| Measure | Meaning |
|---|---|
| **Focused** | Declared focus-session time, clipped to the relevant day or period |
| **Focused-active** | Declared focus time that overlaps authoritative hands-on app-use evidence; used for goals and pace |
| **Recorded app use / Tracked** | Local observed app-use time; not presented as deliberate work |
| **Within / outside session spans** | Temporal membership of observed use; spans can contain pauses and do not themselves establish goal credit |
| **Focus without app-use coverage** | Credited session work that recording cannot corroborate; never added to the observed Mac-use total |
| **Break / Away** | Explicit rest or absence; not counted as focus |
| **Watching** | Normally pauses focus; Meetings and Learning can continue while watching, without inventing hands-on app use |

An extended absence creates an honest decision rather than guessing. While a
decision is unresolved, ordinary start/stop/pause/continue actions—including
the global hotkey—are blocked and route back to the existing decision surface.

Historical sessions and app use are clipped by local calendar day, so a
cross-midnight session contributes only its proper portion to each day.
Week bars and their average use tracked time; focus averages use focused days.
The Month heatmap uses focused duration relative to that month's largest value,
not the current goal. Its numbers remain the source of truth. The daily goal
ring uses focused-active credit; the current streak is explicitly recent even
while browsing older periods. Running focus is included in Day, Week, Month
and History without writing synthetic records into the archive.

The Story preserves separate stretches of resumed work so a later stretch does
not swallow a break or recording gap. Gaps are not assumed to be work or rest.
An app-only day still displays its observed use. History states Tracked, Focused
and Sessions once in its table header, with exact values beneath them.

The headline says time **logged across focus sessions**. That total can exceed
recorded app use without an arithmetic error: these are independently recorded
measures, and uncovered session time is disclosed separately. The **Shape of it**
chart divides a session's span into eight intervals and shows actual app-use
coverage. Empty intervals stay empty; the chart does not infer typing intensity.

### Correct a session

Expand its entry and choose **Rename** or **Change type**. These change the whole
thread, including its stretches on other days, but never alter time boundaries
or app-use evidence. A failed save leaves the old record intact and exposes Retry.
The saved-action row sits beside the affected interval, so changing a session to
Break does not remove its **Undo**. Undo restores only the corrected field and
preserves later work. Running work retains its type and thread identity on relaunch.

Away decisions also have a green saved-action row with **Undo**. Undo makes that
interval uncounted and reopens its classification in place; subsequent work is
unchanged. The latest away receipt survives relaunch. Re-answering can count the
original interval as focus, record it as a break or leave it uncounted without
replaying the current-session transition. Conflicting later edits are protected,
storage failures remain retryable, and interrupted writes cannot insert the same
interval twice. Historical reclassification does not evict unrelated newer work
when the archive is full.
Cross-day actions disclose their full scope before Undo. A failed answer keeps
the question and typed reason visible, including in the popover and away prompts;
its Retry cannot save a different correction made elsewhere.

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
usage is never rewritten; Day, Week, Month, History and Insights qualify or exclude
it where an authoritative claim would otherwise be misleading. Legacy v1 data is
backed up byte-for-byte before migration and can be located from **Settings →
Privacy**.

## Architecture

```text
Core                     App                            Design / Surfaces
──────────────────      ───────────────────────────    ──────────────────────────
SessionEngine            AppCoordinator                 MainWindowView / native sheets
AppUsageTracker          SessionStore (+ read models)   Story columns / rail / calendar
AppUsageArchive          SettingsModel                  History / Insights / Awards
DailyGoal                MainWindowModel                Focus / Settings / Popover
PeriodStats              Persistence wiring             Tokens / StoryStyle / controls
PresenceGate             Story scope projections        Away / Reward
StoryChronology
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

Settings groups the existing backed controls into five compact pages:

| Page | Controls and information |
|---|---|
| General | Launch scope, System/Light/Dark appearance, density, Story time gutter and entry expansion |
| Sessions | Daily goal, activity rules and their application picker, legacy automatic sessions, automatic gap and milestones |
| Away & Breaks | Absence thresholds, full-screen prompt threshold and break reminders |
| Recording | App recording and the number of recent app visits initially shown |
| Privacy | Local storage, accuracy epoch, preserved backup, Reveal data folder and diagnostics |

Each page or changed search result opens at its first control; search retains
the result's group context. Long paths and recovery text wrap
and are selectable. System appearance clears the override and follows macOS;
Reduce Motion always follows the system. The launch-scope preference applies
on the next app launch. Recent-visit limits never reduce totals, and the app
detail can reveal its full scoped list. Unsupported sync, export, retention and
destructive data controls are not presented as working features.

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
./FocusContinuity.app/Contents/MacOS/FocusContinuity --fixture-window storyMonth
./FocusContinuity.app/Contents/MacOS/FocusContinuity --fixture-window storyDecision
./scripts/build-fixture-app.sh storyShape
```

These review modes use `SnapshotScenario`, temporary archives and isolated
preferences. `--fixture-window` opens the real production shell with an injected
fixture clock and no live-history coordinator or system monitors. Use it for
native sheets, keyboard focus, appearance, corrections and navigation; fixture
changes are disposable. `--snapshot` renders light/dark Story scopes, selected
days, History, session controls, Settings, Insights, Awards and compact prompts
through offscreen AppKit hosting, including native controls and real scroll views.
Its explicit static-sheet composition cannot establish native interaction behaviour.
Do not treat a successful PNG count as a visual or interaction acceptance result.
Fixture stores also disable the operational ticker so real idle sampling cannot
advance or pause their synthetic sessions. `storyShape`, `storyMeeting`,
`storyLive`, `storyDecision` and `focusSaveFailure` cover the interaction follow-up;
quick/full failure snapshots check wrapped feedback in the compact prompts.

For native UI automation, use the app emitted by **build-fixture-app.sh**. It has
a separate bundle identifier and a fixture-only executable; even a relaunch with
no arguments cannot construct the production coordinator or open normal data.
The scenario lives in that disposable bundle's metadata. Do not give automation
tools a copy of the production executable and rely solely on `--fixture-window`:
Launch Services or the tool may relaunch it without those arguments. The direct
command remains available for controlled launches that retain the flag.

## Repository layout

```text
Sources/
  Core/                 Time accounting, persistence, periods and pure models
  App/                  macOS coordination, SessionStore and settings/navigation
  Design/               Semantic tokens and reusable SwiftUI components
  Surfaces/             Product screens, popover, prompts, gallery and snapshots
  Verification/         Focused regression groups and isolated native-window mode
  SelfTest.swift        Headless verification suite
build.sh                Direct Swift build, signing, promotion and test entry point
scripts/                Release-concurrency and fixture-only native verification
docs/       Approved designs, specifications and implementation plans
```

Generated bundles, build state, snapshots, Codex worktrees and internal
execution reports are ignored. Commit source, tests, documentation and scripts
that directly describe or build the project; do not force-add generated apps or
agent scratch reports.

## Project documentation

- [Current Story design system](DESIGN.md)
- [Product context and principles](PRODUCT.md)
- [Story remediation plan](docs/plans/2026-08-31-story-audit-remediation.md)
- [Design and behaviour audit](docs/reviews/2026-08-31-design-and-behaviour-audit.md)
- [Story remediation and verification](docs/reviews/2026-08-31-story-remediation-verification.md)
- [Story interaction follow-up and verification](docs/reviews/2026-08-31-story-interaction-verification.md)
- [Complete Story interactions — design](docs/specs/2026-08-31-story-interaction-model-design.md), [session controls and activity rules proposal](docs/specs/2026-08-31-session-controls-and-activity-rules-proposal.md), [plan](docs/plans/2026-08-31-complete-story-interactions.md) and [verification](docs/reviews/2026-08-31-complete-story-interactions-verification.md)
- [Stabilisation design](docs/specs/2026-08-28-focuscontinuity-stabilisation-design.md)
- [Build and repository hardening plan](docs/plans/2026-08-28-build-repository-hardening.md)

## Contributing

Keep the Core → App → Design/Surfaces boundary intact. Add a focused headless
regression before changing behaviour, preserve user evidence rather than
rewriting it, and run `./build.sh --check` before committing. For release-path
changes, also run the concurrency harness after a promoted `./build.sh --test`.
