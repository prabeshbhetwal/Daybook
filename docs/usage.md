# Using FocusContinuity

The detailed guide to the app's surfaces, controls and review tools. For what
the project is and how it is built, start with the [README](../README.md).

## Surfaces

The main window reads one day at a time; History reads longer stretches.
Each question has one place, so the same figures are not shown twice. Opening
a historical day never substitutes today's data.

| Surface | Question it answers | Main content |
|---|---|---|
| Story | What happened on this day? | Focus-led summary, chronological stretches, named rest, app use and honest recording gaps; goal, app use, rhythm and streak in the rail |
| Calendar | Which day, or which span? | A date picker under the date label: a dot marks days with anything recorded; in History, click a first and last day to read that span |
| Session controls | What should I do now? | Intent, work type, Start, Pause, Resume, Away, Stop and pending-away decisions |
| History | How have my days, weeks and months gone? Where is that session? | Search first, with app and category filters; ranges of 7 or 30 days (by day), 3 months (by week) or 12 months (a calendar for each month); a when-you-focus grid, category shares and goal rates; gated pace, quality and continuity statements |
| Awards | What milestones have I earned? | Achievements derived from recorded evidence, with their criteria |
| Settings | How should the app behave? | Real persisted controls, privacy evidence and diagnostics |

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Command-1`, `Command-2` | The day's story, History |
| `Command-6` | Awards |
| `Command-7` | Session controls |
| `Command-,` | Settings |
| `Command-F` | Find in History, from anywhere in the window |
| Escape | Dismiss a native sheet/app detail or cancel an inline rename |

## Reading the story

Current work is at the top of the timeline; earlier work and rest continue
downwards. Click an entry's full header to expand it. Inspect an app from the
rail to see that day's recorded visits. The arrows step a day; the date label
opens the calendar. In History a picked bar or month unfolds in place, down to
a single day's story; a found session previews its day in the rail, and **Open
as a story** reads it on the front page. Choose **Arrange cards** to reorder the
rail; dragging is active only while arranging, and each card also offers
keyboard Move up / Move down.

An expanded entry offers a pencil for renaming and changing category,
**Continue this**, **Add note** (typed or dictated in the app), **Remove** and
**See full report**. Notes belong to the exact stretch they were written on and
are kept beside the session archive, never inside it, so a note can never alter
recorded time or an Undo. Where power was observed while a stretch ran, the
entry shows it factually (**Battery · 78% → 64%**, **Plugged in** or
**Plugged in, charging**), and a stretch with no observation shows no power
line at all rather than an invented reading.

## Starting focus

When starting focus, choose a suggestion from the activity field's menu or
write your own name. Choosing an item only fills the draft. Start explicitly to
begin work; started names are remembered locally for reuse. **Work type** is a
separate, labelled classification, not a restriction on the name you can enter.

The compact menu-bar popover intentionally remains Focus-only. It provides the
current action, up to three continuation choices, quiet break context, and
**Open FocusContinuity**, **Settings** and **Quit**. Opening the app reveals
the Story without automatically presenting the session sheet; use **Session
controls** or `Command-7` when you want that sheet.

## Activity rules

**Activity rules** (Settings → Sessions) are opt-in. Each rule names an
activity, a work type, the applications that belong to it and how long an app
must be in front before the activity begins (30 s to 30 min; 3 min by default).
When rules are on they replace the legacy heuristic rather than run beside it.
One activity owns any moment: an app that belongs to several rules records its
use once and asks a quiet choice (for example **Coding or Research?**) in the
session controls and the menu panel instead of starting two sessions. An
explicit activity you started is never relabelled. Every automatic start says
why it happened and offers **Undo**; the application picker lists installed
apps from the standard application folders and apps already observed, with
**Add application…** for anything missed.

## Correcting a session

Expand its entry and choose **Rename** or **Change type**. These change the
whole thread, including its stretches on other days, but never alter time
boundaries or app-use evidence. A failed save leaves the old record intact and
exposes Retry. The saved-action row sits beside the affected interval, so
changing a session to Break does not remove its **Undo**. Undo restores only
the corrected field and preserves later work. Running work retains its type and
thread identity on relaunch.

Away decisions also have a saved-action row with **Undo**. A break you named in
the prompt reads by that name; an unnamed one offers **Name it**. Undo makes
that interval uncounted and reopens its classification in place; subsequent
work is unchanged. The latest away receipt survives relaunch. Re-answering can
count the original interval as focus, record it as a break or leave it
uncounted without replaying the current-session transition. Conflicting later
edits are protected, storage failures remain retryable, and interrupted writes
cannot insert the same interval twice. Historical reclassification does not
evict unrelated newer work when the archive is full. Cross-day actions disclose
their full scope before Undo. A failed answer keeps the question and typed
reason visible, including in the popover and away prompts; its Retry cannot
save a different correction made elsewhere.

## How the figures are counted

Historical sessions and app use are clipped by local calendar day, so a
cross-midnight session contributes only its proper portion to each day.
History's solid bars are logged focus and the pale bar behind each is recorded
app use; focus averages use focused days. The daily goal ring uses
focused-active credit; the current streak is explicitly recent even while
browsing older days. Running focus is included in the day's story and in
History without writing synthetic records into the archive.

The Story preserves separate stretches of resumed work so a later stretch does
not swallow a break or recording gap. Gaps are not assumed to be work or rest.
An app-only day still displays its observed use. Each History row states its
focused time and session count; the rail preview adds recorded app use and the
longest stretch.

The headline says time **logged across focus sessions**. That total can exceed
recorded app use without an arithmetic error: these are independently recorded
measures, and uncovered session time is disclosed separately. The **Shape of
it** chart divides a session's span into eight intervals and shows actual
app-use coverage. Empty intervals stay empty; the chart does not infer typing
intensity.

## Settings

Settings groups the backed controls into five compact pages:

| Page | Controls and information |
|---|---|
| General | Login item, menu bar time, appearance, density, Story time gutter, entry expansion and the tour |
| Sessions | Daily goal, activity rules and their application picker, legacy automatic sessions, automatic gap and milestones |
| Away & Breaks | Absence thresholds, full-screen prompt threshold and break reminders |
| Recording | App recording and the number of recent app visits initially shown |
| Privacy | Local storage, accuracy epoch, preserved backup, Reveal data folder and diagnostics |

Each page or changed search result opens at its first control; search retains
the result's group context. Long paths and recovery text wrap and are
selectable. System appearance clears the override and follows macOS; Reduce
Motion always follows the system. The window always opens on the day's story.
Recent-visit limits never reduce totals, and the app detail can reveal its
full list for the day. Unsupported sync, export, retention and
destructive data controls are not presented as working features.

## Review modes

The binary also supports review modes:

```bash
./FocusContinuity.app/Contents/MacOS/FocusContinuity --gallery
./FocusContinuity.app/Contents/MacOS/FocusContinuity --snapshot ./snapshots
FC_SNAPSHOT_ONLY=welcomeStep ./FocusContinuity.app/Contents/MacOS/FocusContinuity --snapshot ./snapshots
./FocusContinuity.app/Contents/MacOS/FocusContinuity --onboarding
./FocusContinuity.app/Contents/MacOS/FocusContinuity --fixture-window reviewHistorySelection
./FocusContinuity.app/Contents/MacOS/FocusContinuity --fixture-window storyDecision
./scripts/build-fixture-app.sh storyShape
```

These review modes use `SnapshotScenario`, temporary archives and isolated
preferences. `--fixture-window` opens the real production shell with an
injected fixture clock and no live-history coordinator or system monitors. Use
it for native sheets, keyboard focus, appearance, corrections and navigation;
fixture changes are disposable. `--snapshot` renders light/dark day stories,
History ranges and a picked day, session controls, Settings, Awards, the
tour's opener and first step, and compact prompts through offscreen AppKit
hosting, including native controls and real scroll views.
`FC_SNAPSHOT_ONLY=<scenario>` renders one scenario; the whole matrix takes
several minutes. `--onboarding` forces the tour on a Mac that has already
answered it.

The snapshot composition is static, so it cannot establish native interaction
behaviour; a successful PNG count is not a visual or interaction acceptance
result. Fixture stores also disable the operational ticker so real idle sampling
cannot advance or pause their synthetic sessions.

For native UI automation, use the app emitted by `build-fixture-app.sh`. It has
a separate bundle identifier and a fixture-only executable; even a relaunch
with no arguments cannot construct the production coordinator or open normal
data. The scenario lives in that disposable bundle's metadata. Do not give
automation tools a copy of the production executable and rely solely on
`--fixture-window`: Launch Services or the tool may relaunch it without those
arguments.
