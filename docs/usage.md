# Using Daybook

The detailed guide to the app's surfaces, controls and review tools. For what
the project is and how it is built, start with the [README](../README.md).

## Surfaces

The main window reads one day at a time; History reads the whole record.
Each question has one place, so the same figures are not shown twice. Opening
a historical day never substitutes today's data.

| Surface | Question it answers | Main content |
|---|---|---|
| Story | What happened on this day? | Focus-led summary, chronological stretches, named rest, app use and honest recording gaps; goal, app use, rhythm and streak in the rail |
| Calendar | Which day? | Opens from Jump to date in History. Each date shows its focus, or a dot if the Mac only saw app use. A tick marks a met goal, and the month's sum sits in its header |
| Session controls | What should I do now? | The centre of the bar on the story: the activity, its category and Start; while a session runs, the clock, its name and Pause, Away and Stop in the same place. Pause keeps recording app use; Away records nothing until you're back. An away question, a quiet activity choice or an automatic session's Adopt and Undo appear on a line under the bar only while they exist |
| History | How have my years, months, weeks and days gone? Where is that session? | One timeline that unfolds. It opens on the smallest period holding your whole record: this week's days, this month's weeks, this year's months, or every year. Click a row to open it: a year into its months, a month into its weeks, a week into its days, a day into its sessions, each one step in from its parent; one row is open per level. Each row shows its focus, its focused days or sessions, and a thin bar per month or day. Nothing is drawn from before the first recorded day or after today. Search at the top, with app and category filters. The rail describes the deepest open row, or the session you click: category shares, best two hours, goal rates and apps for a period, its best month or day, the day's strip and notes, a session's stretches and full note. Pace, quality and continuity are stated only for the current month, and only when the record supports them |
| Awards | What milestones have I earned? | Achievements derived from recorded evidence, with their criteria |
| Settings | How should the app behave? | Real persisted controls, privacy evidence and diagnostics |

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Command-1`, `Command-2` | The day's story, History |
| `Command-6` | Awards |
| `Command-7` | The story, with the cursor in the activity field |
| `Command-,` | Settings |
| `Command-F` | Find in History, from anywhere in the window |
| `Command-+`, `Command-−` | Zoom In and Zoom Out, in the View menu: the whole interface a step larger or smaller, from 80% to 140% |
| `Command-0` | Actual Size: the interface back to 100% |
| Up, Down | In History, move through the rows |
| Return | In History, open or fold the row; select a session |
| Left, Right | In History, fold or open the row |
| Escape | In History, fold the deepest open row |
| `Option-Command-N` | Start focus |
| `Option-Command-P` | Pause, or resume a paused session |
| `Option-Command-A` | Away |
| `Option-Command-S` | Stop the session |
| `Control-Option-Space` | From any app: start a session, end the running one, or bring up a waiting away card. Record a different chord in Settings › General, or turn it off there; a chord needs Control or Option, and one another app already holds is refused with the old one kept. Control-Option chords are released while VoiceOver is on, because that is VoiceOver's own modifier |
| `Command-]`, `Command-[` | Next and previous card in the welcome tour |
| Escape | Dismiss a native sheet/app detail or cancel an inline rename |

The Session keys run the same actions as the buttons, and each is unavailable
when the session's state offers no such button: Start only when idle, Away
only while running. Settings › General lists every key under Keyboard, says
whether the global shortcut is working, lets you record another, and replays the welcome tour.

## Reading the story

Current work is at the top of the timeline; earlier work and rest continue
downwards. Click an entry's full header to expand it. Inspect an app from the
rail to see that day's recorded visits. The story is always today. In
History, click a row to open it in place and the rail describes it; **Jump to
date** opens a day straight away. Choose **Arrange cards** to reorder the
rail. While arranging, drag a card, or use the up and down arrows in its header
or its right-click menu; VoiceOver offers Move up and Move down.

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
**Open Daybook**, **Settings** and **Quit**. Opening the app reveals
the Story with the session controls in its bar; **Session controls** or
`Command-7` put the cursor in the activity field.

## Activity rules

**Activity rules** (Settings → Sessions) are opt-in. Each rule names an
activity, a work type, the applications that belong to it and how long an app
must be in front before the activity begins (30 s to 30 min; 3 min by default).
When rules are on they replace guessing from the app in front rather than run beside it.
One activity owns any moment: an app that belongs to several rules records its
use once and asks a quiet choice (for example **Coding or Research?**) in the
session controls and the menu panel instead of starting two sessions. Rules
only start a session when none is running: once one is going, moving to
another rule's apps does not switch it, so alternating between a browser and
an editor stays one session until you stop it or step away. An explicit
activity you started is never relabelled. Every automatic start says
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

Removing a session and changing how a break counts ask first, with a
**Don't ask again** tick. Ticked and confirmed, the next one happens without
the question; Undo still reverses it. Settings › General › Confirmations turns
either question back on. Deleting a rule, resetting a category and discarding
an unsaved note always ask, because Undo cannot reverse them.

## How the figures are counted

Historical sessions and app use are clipped by local calendar day, so a
cross-midnight session contributes only its proper portion to each day.
History's row bars are logged focus, one per month or day; focus averages use
focused days. The daily goal ring uses focused-active credit. Running focus is
included in the day's story and in
History without writing synthetic records into the archive.

The Story preserves separate stretches of resumed work so a later stretch does
not swallow a break or recording gap. Gaps are not assumed to be work or rest.
An app-only day still displays its observed use. Each History row states its
focused time; the rail adds recorded app use and, for a day, the longest stretch.

The headline says time **logged across focus sessions**. That total can exceed
recorded app use without an arithmetic error: these are independently recorded
measures, and uncovered session time is disclosed separately. The **Shape of
it** chart divides a session's span into eight intervals and shows actual
app-use coverage. Empty intervals stay empty; the chart does not infer typing
intensity.

## Settings

Settings groups the backed controls into seven pages:

| Page | Controls and information |
|---|---|
| General | Login item, menu bar icon and time, Dock icon, the global shortcut and the window's keys, whether removing a session or changing how a break counts asks first, the tour, appearance, density, zoom (80% to 140%, the same steps as the View menu), Story time gutter, entry expansion and folding quiet stretches |
| Sessions | Daily goal, what usual pace compares with, how far back activity suggestions look, the streak's daily minimum, the category new sessions start as, the shortest session kept, how long an ended session is offered to continue, categories, guessing sessions from the app in front, ending a paused automatic session, and milestones |
| Activities | Activity rules, their application picker, and whether they run |
| Away & Breaks | Absence thresholds, full-screen prompt threshold and break reminders |
| Recording | App recording, how many apps a card lists and how many recent app visits are shown |
| Privacy | Local storage, when app use was first measured precisely, the backup of older app use, backups (schedule, destination, how long automatic ones are kept, the last and next backup, Back Up Now and Show Backups), and Reveal data folder |
| About & Updates | Automatic update checks, how often and what happens when one is found, Check Now, and diagnostics |

Each page or changed search result opens at its first control; search retains
the result's group context. Long paths and recovery text wrap and are
selectable. System appearance clears the override and follows macOS; Reduce
Motion always follows the system. The window always opens on the day's story.
Recent-visit limits never reduce totals, and the app detail can reveal its
full list for the day. Unsupported sync, export, retention and
destructive data controls are not presented as working features.

### Backups

A backup copies the data folder and the app's preferences into a new dated
folder under **Daybook Backups**, in iCloud Drive or a folder you choose with
**Choose Folder…** (another disk, another service's synced folder, a network
share). **Back up automatically** offers Off, Every 6 hours, Every day (the
default for a new install) and Every week. An install from before automatic
backups starts with them off, so an update never uploads history on its own;
today's story offers them once, with **Back up every day** or **Not now**.
Changing where backups go starts that destination afresh: the next check backs
up there. The running app checks every half hour, a minute
after launch and on wake, so a Mac that was asleep or shut down at the due
time backs up soon after. Automatic backups are named with "(automatic)" and
are kept **Forever** by default, or for a year, 3 months, a month, 2 weeks or
a week; expired ones go to the Trash at the next backup, the newest always
stays, and a backup made with **Back Up Now** is never removed. Settings shows
whether iCloud Drive is on, the last backup and whether it has finished
uploading to iCloud, the next one, and why the latest attempt failed if it did:
iCloud Drive off, or the chosen folder's disk not connected. A failed attempt
is retried at the next check, and a copy that fails part-way leaves nothing
behind. The data folder is cloned where the app writes it, so a backup never
catches a file mid-write, and the slow copy to iCloud Drive or another disk
runs in the background.

## Review modes

The binary also supports review modes:

```bash
./Daybook.app/Contents/MacOS/Daybook --gallery
./Daybook.app/Contents/MacOS/Daybook --snapshot ./snapshots
FC_SNAPSHOT_ONLY=welcomeStep ./Daybook.app/Contents/MacOS/Daybook --snapshot ./snapshots
FC_SNAPSHOT_ZOOM=1.4 ./Daybook.app/Contents/MacOS/Daybook --snapshot ./snapshots
./Daybook.app/Contents/MacOS/Daybook --onboarding
./Daybook.app/Contents/MacOS/Daybook --fixture-window reviewHistorySelection
./Daybook.app/Contents/MacOS/Daybook --fixture-window storyDecision
./scripts/build-fixture-app.sh storyShape
```

These review modes use `SnapshotScenario`, temporary archives and isolated
preferences. `--fixture-window` opens the real production shell with an
injected fixture clock and no live-history coordinator or system monitors. Use
it for native sheets, keyboard focus, appearance, corrections and navigation;
fixture changes are disposable. `--snapshot` renders light/dark day stories,
History opened to a day, with a session picked, searched and with three days recorded, session controls, Settings, Awards, the
tour's opener and first step, and compact prompts through offscreen AppKit
hosting, including native controls and real scroll views.
`FC_SNAPSHOT_ONLY=<scenario>` renders one scenario; the whole matrix takes
several minutes. `FC_SNAPSHOT_ZOOM=<scale>` renders at a zoom, 1.4 for 140%,
snapped to the nearest step, and Settings shows that zoom on its slider; a
zoomed image's name ends in `-zoom140`, and a value that is not a number is
reported and rendered at 100%. The two can be combined. `--onboarding` forces the tour on a Mac that has already
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
