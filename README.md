# Daybook

A native macOS focus tracker that refuses to guess. It records focus sessions
and local app use, then tells the day back as a story, keeping what you
declared, what the Mac observed and what nobody recorded as separate,
labelled measures.

![The Day story: an expanded session with its apps, app activity and the evidence rail](docs/screenshots/day-story.png)

**SwiftUI · AppKit · Swift Charts · macOS 14+** ·
no Xcode project, one dependency (Sparkle, for updates), no telemetry ·
hundreds of headless checks

## Why it exists

Most time trackers treat "the app was in front" as "you were working". That
turns a locked screen, a meeting away from the desk or a laptop left open over
lunch into invented productivity. Daybook is built around one rule:
**evidence comes before interpretation.**

- A focus session is something you declare. App use is something the Mac
  observed. They are never added together.
- When you step away, the app asks what happened instead of deciding for you.
- Where nothing was recorded, the story says so.

## Screenshots

| History, a day open and a session picked, dark appearance | History, opened to this week |
|---|---|
| ![History in dark mode: one timeline unfolded to a day, with a picked session described in the rail](docs/screenshots/history-dark.png) | ![History in light mode: this week's days under their week, with the week described in the rail](docs/screenshots/history.png) |

| Menu bar | Away decision |
|---|---|
| ![Menu bar popover with a running session and quick switches](docs/screenshots/menu-bar-popover.png) | ![Away prompt asking how 22 minutes away should count](docs/screenshots/away-prompt.png) |

## The hard parts

**An honest time model.** The app keeps related measures apart and names each
one on screen:

| Measure | Meaning |
|---|---|
| **Focused** | Declared focus-session time, clipped to the day or period shown |
| **Focused-active** | Focus that overlaps observed hands-on app use; the only time that earns goal credit |
| **Recorded app use** | Observed foreground time; never presented as deliberate work |
| **Focus without app-use coverage** | Session time the recorder cannot corroborate; disclosed, never added to Mac use |
| **Break / Away** | Explicit rest or absence; never counted as focus |

A session that crosses midnight contributes only its share to each day. A
logged total can exceed recorded app use, and the Day view explains why rather
than hiding the difference.

**Absence without guessing.** Locks, sleep and idle time end in a decision:
break, working, away or start fresh. While a decision is open, every other
session action routes back to it, including the global hotkey. Corrections
(rename, change type, re-answer an away) apply to the whole thread across days,
never move time boundaries, survive relaunch, and can be undone field by field.
Writes are atomic, a failed save keeps the old record and offers Retry, and an
interrupted write cannot record the same interval twice.

**Data that ages honestly.** App-use history is a versioned envelope with an
accuracy epoch. Data recorded before a recorder fix is preserved and marked as
less certain wherever an exact claim would mislead; it is never silently
rewritten. Older formats are backed up byte for byte before migration.

**Cheap to leave running.** A menu bar app runs all day, so idle cost matters.
Profiling showed that SwiftUI windows keep re-rendering on every data update
even when closed, and the hidden menu bar panel alone was costing about 45 ms
of work each second. Closed windows and panels now rest until shown again, and
the app's CPU use during normal work went from 0.9% to 0.1%.

**Private by construction.** Tracking stores app identity and time ranges,
never content. The session names, intents and notes you write are content, and
they are kept on the Mac. Two things can reach another server: the update check
asks GitHub for the latest version, and dictating a note uses Apple's speech
recognition, which runs on the Mac where your language supports that and
otherwise may send the audio to Apple. A backup, made only when you ask for
one, is copied into iCloud Drive, which syncs it like any other document. The
app asks for no Accessibility,
Automation, Screen Recording or Input Monitoring permission; idle detection
uses system counters, not event content. The prompts you will see are
notifications (at first launch, for break reminders), and microphone and
speech recognition (only when you dictate a note). Launch at login, if you turn
it on, adds a login item.

## How it is verified

- **Hundreds of headless checks** run from the app binary itself (`--selftest`). They
  use an injected clock, isolated preferences and temporary archives, so they
  cover session state transitions, cross-midnight clipping, wake and presence
  handling, persistence failures, accuracy epochs, corrections and Undo,
  accessibility targets, settings effects and where rendered controls and
  edges actually land, without touching real data.
- **Every push** runs the same checks on GitHub Actions, on macOS 26 and in
  UTC ([`check.yml`](.github/workflows/check.yml)), so they hold on the older
  system and away from the Sydney Mac they are written on.
- **A snapshot matrix** renders every surface in light, dark and system
  appearance through offscreen AppKit hosting, with real native controls, for
  visual review (`--snapshot`). The screenshots above come from it.
- **A fixture-only app** (`scripts/build-fixture-app.sh`) has its own bundle
  identifier and cannot open real data, so native UI automation can run safely.
- **The build is strict**: Swift 5 mode with warnings as errors, a strict deep
  signature check, and tests run before the local app is replaced. If anything
  fails, including during the swap, the previous app is put back.

## How the work is organised

Features move through written documents before and after the code, and all of
them are in [`docs/`](docs):

1. **Spec**: the problem, the decisions and what is out of scope.
   Example: [honest session time](docs/specs/2026-08-17-honest-session-time-design.md).
2. **Plan**: small, testable steps with the checks each one must pass.
   Example: [complete Story interactions](docs/plans/2026-08-31-complete-story-interactions.md).
3. **Review**: an audit against the spec, then verification of every finding.
   Example: [design and behaviour audit](docs/reviews/2026-08-31-design-and-behaviour-audit.md)
   and its [remediation verification](docs/reviews/2026-08-31-story-remediation-verification.md).

[`PRODUCT.md`](PRODUCT.md) holds the product principles and
[`DESIGN.md`](DESIGN.md) the design system. Commit messages describe
the change they make, so `git log` reads as a changelog. The code is also kept lean on
purpose: a recent pass removed about 7,300 lines of views, members and build
machinery that nothing used any more, with no change in behaviour.

## Features

- Today told as a story, with its goal, app use, rhythm and streak beside it
- Focus sessions with pause, away, breaks and threads you can continue later
- Optional activity rules that start sessions from the apps you use, always
  saying why and offering Undo
- History as one timeline that unfolds: years into months, months into weeks,
  weeks into days, days into sessions, each a step in from its parent, back to
  the first recorded day and no further. A chart of each day heads it, the
  top periods are cards with their days and category split, and the rail
  describes whichever row is open. Jump to date opens a calendar that shows
  each day's focus
- Search at the top of History: sessions by name, note, app, category or date (⌘F)
- History states only what the record supports: category shares, best two
  hours, goal rates, the best month or day, and the current month's pace,
  quality and continuity
- Custom categories with icons, colours, daily goals and break reminders
- Session notes with in-app dictation, full session reports and named breaks
- Awards derived from recorded evidence, with their criteria shown
- A global shortcut (Control-Option-Space) that starts or ends a session from
  any app; record your own in Settings
- Backups to iCloud Drive on request, and updates from GitHub Releases,
  checked automatically or on demand
- A twelve-chapter first-run tour that can be skipped or replayed
- Full keyboard operation, VoiceOver labels, light and dark appearance, and a
  whole-interface zoom from 80% to 140% (⌘+, ⌘−, ⌘0 or a slider in Settings)

The full guide to every surface and control is in [docs/usage.md](docs/usage.md).

## Build and run

Requirements: macOS 14 or later and the Apple Command Line Tools (`swiftc`).
Xcode is not needed.

```bash
./build.sh          # Build and replace the local app after verification
./build.sh --run    # Build, verify and open Daybook.app
./build.sh --test   # Build, run the checks, then replace the local app
./build.sh --check  # Build and run the checks without replacing the app
```

Replacing the local app relaunches it if it was running from that folder, so
it never keeps running from files the swap deleted.

The binary is built with `-Osize` and stripped of local symbols. To profile
with `sample`, build once with `FC_KEEP_SYMBOLS=1 ./build.sh`.

The first build downloads Sparkle 2.10.0 into `.build/vendor` and checks it
against a pinned SHA-256.

The app is ad-hoc signed and not notarised. `scripts/release.sh <version>`
runs the checks, builds, signs the update and publishes it to
[GitHub Releases](https://github.com/prabeshbhetwal/Daybook/releases) with its
feed; installed copies update through Sparkle and accept only updates signed
with the project's EdDSA key, which stays in the Keychain.

Builds that replace the local app take a lock at `.build/promotion.lock`, so a
second build waits its turn. If a build is killed outright, remove that
directory once no build is running.

## Architecture

```text
Core                     App                            Design / Surfaces
──────────────────      ───────────────────────────    ──────────────────────────
SessionEngine            AppCoordinator                 MainWindowView / native sheets
AppUsageTracker          SessionStore (+ read models)   Story columns / rail / calendar
AppUsageArchive          SettingsModel                  History / Insights / Awards
DailyGoal                MainWindowModel                Focus / Settings / Popover
PeriodStats              Persistence wiring             Tokens / StoryStyle / controls
PresenceGate             Day and History projections    Away / Reward
StoryChronology
DateFormats
```

- **Core** is UI-free: the session state machine, usage tracking, clipping,
  goals, periods, persistence formats and pure calculations.
- **App** owns macOS event wiring and publishes read models. It is the only
  boundary for session actions, settings, refresh coalescing and navigation.
- **Design / Surfaces** renders those models. Views never read storage or
  recalculate time.

One one-second ticker, in `SessionStore`, drives presence checks, usage
checkpoints, live figures and break evaluation. The UI adds no timers of its
own.

Data lives in `~/Library/Application Support/Daybook/`: `sessions.json` for
sessions, and for app use a snapshot, `app-usage.json` (a versioned v2
envelope), plus `app-usage-journal.jsonl`, the changes since that snapshot.
`sessions.json` and the snapshot are replaced atomically. Each change to app
use is one line appended to the journal, and the snapshot is rewritten only
when the journal grows long, so the history is never trimmed. If a crash cuts
the last line short, the next launch drops that one change and keeps
everything before it.

Until October 2026 the app was called FocusContinuity. Its first launch under
the new name carries the data folder and preferences across and deletes
nothing.

## Repository layout

```text
Sources/
  Core/                 Time accounting, persistence, periods and pure models
  App/                  macOS coordination, SessionStore and settings/navigation
  Design/               Semantic tokens and reusable SwiftUI components
  Surfaces/             Screens, popover, prompts, gallery and snapshots
  Verification/         Focused regression groups and isolated native-window mode
  SelfTest.swift        Headless check suite
build.sh                Build, signing, checks and local install
scripts/                Releases, the Sparkle fetch, the fixture app and probes
docs/                   Specs, plans, reviews, design references and screenshots
.github/workflows/      Every self-check on each push
```

## Contributing

Keep the Core → App → Design/Surfaces boundary intact. Add a focused headless
check before changing behaviour, preserve recorded evidence rather than
rewriting it, and run `./build.sh --check` before committing.

## License

MIT. See [LICENSE](LICENSE).
