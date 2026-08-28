# FocusContinuity

A native macOS focus-session tracker that keeps your time honest across screen locks,
sleeps and app switches. Menu bar first: a SwiftUI popover with a focused intent field,
one-click start, live timer, streak and weekly rhythm — plus a Today window for depth.
No dock icon.

It distinguishes a **micro-break** (step away for coffee — the session continues
silently) from an **extended break** (a resolve card records what happened); an absence
past the configured long-away cap ends the session where it began.
It also auto-pauses when a distraction app stays frontmost, and auto-resumes when you
return to a work app.

Pure Swift: SwiftUI + Swift Charts for the surfaces, AppKit where macOS requires it,
and a UI-free `Core` that holds all logic. No SPM, no third-party packages, no Xcode
project — `build.sh` drives `swiftc` directly.

**Toolchain note:** this machine has Command Line Tools without Xcode, whose SDK ships no
`SwiftUIMacros` plugin. `@State` and `@Observable` therefore do not compile, and all view
state lives in `ObservableObject` + `@Published`. `@Binding`, `@Environment`, `@FocusState`
and `@AppStorage` work normally.

## Build

```bash
./build.sh
```

Produces a generated, locally ad-hoc-signed `FocusContinuity.app` in the repository root,
compiled for the host architecture with a macOS 13.0 deployment target. Warnings are
errors. The bundle is neither notarised nor distributable.

```bash
./build.sh --run     # build, then open the app
./build.sh --test    # build, then run the headless self-test
./build.sh --check   # stage, strictly verify and self-test without replacing the root app
```

Git tracks source, tests and documentation only. Generated app bundles, snapshots,
`.build`, worktrees and Finder metadata are ignored; do not force-add them.

Two extra launch modes, for design review:

```bash
./FocusContinuity.app/Contents/MacOS/FocusContinuity --gallery
./FocusContinuity.app/Contents/MacOS/FocusContinuity --snapshot ./snapshots
```

`--gallery` opens a window showing every surface state (first run, idle, running, paused,
needs-resolution, broken streak) in light and dark. `--snapshot` renders those same states
to PNG, which works without a Screen Recording grant and doubles as a visual regression
artefact. `TextField` and material backgrounds do not render under `ImageRenderer`; use
`--gallery` or the live app to review those.

## Test

```bash
./build.sh --test
```

The headless logic self-test runs against an injected clock — no UI, no notifications, no
run loop. It covers elapsed arithmetic across pause cycles, the 5 s debounce, micro-break
accumulation, extended-break escalation, an unanswered away card (the gap stays excluded,
the clock keeps running, a quit weekend does not become work), a night-long absence ending
the session where the user left, cross-midnight work splitting between its days so both
keep their streak, manual Away, category
precedence, away-event coalescing, negative clock-skew clamping, the `Codable`
round-trip, an exhaustive sweep of every `(state, event)` pair, restore across a gap
longer than the threshold, the distraction dwell guard and its cancellation, the pure
helpers (title formatting, archive ring cap, defaults, corrupt-blob tolerance), and
decision-time accounting, the archive queries (today, sessions, longest, week bars), the
25-minute streak rule, archive reload and corrupt-file recovery, quick-start ranking,
discrete session start/stop, away time inside a session, the dashboard computations
(timeline ordering and clipping across midnight, app rankings, focus quality, gated
insights), idle trimming, and a regression for the running-session figures. The period
tests pin the week and month bounds, the average-over-active-days rule, the empty period,
the grouped reverse-chronological log, and that the one-pass rollup cannot drift from the
piecewise accessors. The purpose and thread tests pin the static map, behaviour-resolved
ambiguity, override precedence, the density floors and the synthetic-event caveat, thread
grouping and ordering with the running session folded in, legacy records decoding as
single-segment threads, and side-app derivation. Exit code is 0 on success, 1 on failure.

The binary can also be run directly:

```bash
FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest
```

## State machine

```
enum SessionState { case idle, running, paused(reason:), awaitingUserDecision(away:lastApp:) }
```

| From | Event | Guard | To |
|---|---|---|---|
| `idle` | launch / first work activation | — | `running` |
| `running` | screen lock / sleep | — | `running` (records the away interval only) |
| `running` | unlock / wake | away < 5 s | `running` (interval discarded) |
| `running` | unlock / wake | 5 s ≤ away < threshold | `running` (away added to paused total) |
| `running` | unlock / wake | away ≥ threshold | `awaitingUserDecision` (resolve card) |
| `running` | break app frontmost | 20 s continuous dwell | `paused(.distractionApp)` |
| `running` | work / neutral app | — | `running` (pending pause cancelled) |
| `paused` | work app frontmost | — | `running` (pause duration accumulated) |
| `paused` | neutral app frontmost | — | `paused` (unchanged) |
| `paused` | manual resume | — | `running` |
| `paused` | unlock / wake | — | `paused` (interval dropped — the pause already accounts for it) |
| `running` | Away | — | `paused(.away)` (also stops background recording) |
| `paused` | Away | — | `paused(.away)` (reason changes, pause clock untouched) |
| `awaitingUserDecision` | any system event | — | `awaitingUserDecision` (recorded, never transitions) |
| `running` | Stop | — | `idle` (writes a SessionRecord) |
| `awaitingUserDecision` | manual resume | — | `running` (escape hatch, break stays excluded) |
| `awaitingUserDecision` | I was working | — | `running` (away added back as work) |
| `awaitingUserDecision` | I was away | — | `running` (away stays excluded) |
| `awaitingUserDecision` | Start fresh | — | `running` (old session archived ending where the away began) |
| `awaitingUserDecision` | Away | — | `paused(.away)` (answers the question and starts a new absence) |
| any | Start | — | `running` (any running session is archived first) |

`transition(on:)` switches exhaustively over `(state, event)`. Unlisted pairs are
documented no-ops — never a crash — and `onStateChanged` fires exactly once per real
transition.

### Timing

`elapsed = (now − sessionStart) − totalPaused − currentPauseSoFar`, all wall-clock so
that sleep counts as real elapsed time. Any negative interval is clamped to zero and
logged. `sessionStart` is never mutated except on reset.

Two intervals are deliberately *not* counted as work: the paused interval, and the away
interval. The away is excluded **the moment it is noticed**, before anyone answers, so an
ignored question leaves the honest total standing rather than the flattering one — an
overnight sleep used to read as nine hours of work on the goal bar until the card was
dismissed. *I was working* is the only answer that adds it back.

The full away ladder, both middle thresholds settable under **Stepping away**:

| Away | What happens | Setting |
|---|---|---|
| under 5 s | ignored entirely | fixed |
| 5 s – *ask after* | not counted, no interruption | 5/10/15/30/60 m, default 15 m |
| *ask after* – *end after* | the resolve card | — |
| over *end after* | session ends where you left | 1–8 h, default 4 h |

The upper cap exists because nobody answers "was that a break?" about a night's sleep with
"I was working", and a session held open across one produced records spanning thirty-two
hours — which forced every per-day figure in the app to guess which day the work belonged
to. Sessions shorter than 30 s are never written at all.

### Which day does work belong to?

A record carries `start`, `end` and `workSeconds`, and its span is normally larger than
its work. `SessionRecord.workSeconds(in:)` spreads the work evenly across the span and is
the **single rule** every per-day query uses — `todayTotal`, `weekBars`, `currentStreak`,
`bestStreak`, `focusedSameWeekdayLastWeek`, the goal bar, the pace median, and
`focusQuality`.

It replaces filing each record under the day it *ended*, which was the largest single
source of wrong numbers here. A session begun Friday afternoon and stopped Sunday evening
gave all of Friday's work to Sunday: Friday then read as a day with no focus, blanking its
bar, dropping out of the pace median as "inactive", and breaking the streak through it.
Measured on the author's own archive, the streak read **3** when the honest answer was
**5**. Spreading is a guess about when inside the span the work happened; end-day
attribution was a guess too, and an unbounded one. The span cap above keeps the guess
small.

The running session is split the same way by `SessionEngine.elapsedToday()`, so a session
started before midnight cannot donate last night's hours to this morning's goal.

The time that passes while the card is up **is** counted. That rule once ran the other
way, written for a blocking alert that has since been replaced by a passive card: with
nothing in the way, those minutes are ordinary working minutes, and discarding them made
the session look stopped until the question was answered. The one exception is *Start
fresh*, where they belong to the session beginning on your return rather than to the one
that ended when you walked away.

### Events

State is driven by `NSWorkspace.shared.notificationCenter`
(sleep/wake/activate/power-off/session switch) and `DistributedNotificationCenter`
(`com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`). The sole repeating ticker is
the one-second `SessionStore` ticker. It samples idle presence (and reports that evidence
to the engine), flushes app-usage checkpoints, refreshes live figures and evaluates break
reminders. Presence still requires an unlock or confirmed human input after wake, so a
wake alone cannot create usage.

### App purpose

A third classification, orthogonal to the two above it. `AppCategory` answers *should this
app pause my session?*; `WorkType` answers *what did you say this session was?*;
`AppPurpose` answers *what is this tool?* — coding, writing/AI, design, communication,
research, media or utility. Collapsing any pair breaks something: Terminal and Figma are
both `work`, but one is coding and the other design.

Browsers and AI clients carry no fixed purpose. Chrome reading documentation and Chrome
playing a film are the same bundle identifier, and reading the URL or window title would
need an Accessibility grant — permanently out of scope. They are resolved by behaviour
instead: `InputDensity` reports **active** (at least 12 keystrokes a minute, or 4 clicks a
minute alongside some typing), **passive**, or **absent**, and an ambiguous app takes its
active purpose only when the person is producing something. Scrolling and mouse movement
never qualify — a film plays happily while a hand rests on a trackpad.

The counters come from `CGEventSource.counterForEventType`, which reads cumulative counts
per event type and never event content, so like `IdleMonitor` it needs no Input Monitoring
grant. Verified 2026-08-13: no prompt, and the counters advance under real input. They also
advance for synthetically posted events while the idle timer does not, so a sample taken
while nobody is present clears the window outright rather than being stored — a delta
measured across an absence would be a lie.

Density is sampled **at event boundaries only** — app activation, lock, unlock, wake —
and never independently on a timer. Sampling on activation also measures each app's
stretch on its own terms, so a browser's purpose is decided by the input that happened
while it was frontmost rather than by typing that happened in an editor minutes earlier.

### Categories

`userOverride[bundleID]` → built-in map → `.neutral`. Overrides persist to
`UserDefaults`; the built-in map is code-constant. Browsers, Finder, Mail, Notes and
System Settings are neutral — neutral apps never move the state machine. No
Accessibility or Automation permission is requested or required.

### What is not an app

`loginwindow` is frontmost for the whole time a screen is locked or asleep, and
tracking it as usage made a night away the busiest "app" of the day — measured
at 5h 57m, 80% of tracked time. Idle trimming cannot catch this: waking the Mac
is itself input, so the idle timer has already reset by the time the stretch
closes and only its tail is trimmed.

System processes are therefore excluded outright — the lock screen, the screen
saver, the authentication agent, Spotlight, the Dock. They are filtered on read
as well as refused on write, so stretches already recorded stop distorting the
totals without rewriting history that was honestly captured at the time.

### Honest time

Foreground time is not the same as attention. Screen Time is criticised for counting an
app as in use whenever it is frontmost, even when nobody is at the keyboard, and the naive
implementation here had the same flaw. `IdleMonitor` reads
`CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .null)` — a timestamp,
not event content, so it needs no Input Monitoring grant — and the tracker stops counting
after three minutes without input, trimming the idle tail off the stretch.

Verified on this machine: `.hidSystemState` advances one second per real second and
prompted for nothing. `.combinedSessionState`, the obvious-looking alternative, returned
44221 seconds on an actively used Mac and is unusable.

### Memory

App icons are rasterised once at the size actually drawn and cached as small bitmaps.
`NSWorkspace.icon(forFile:)` returns an image carrying 32 representations up to
2048×2048: measured on this machine, caching eight of those whole costs **1296 MB** once
decoded, against **5 MB** rasterised. The dashboard also computes its day slice once per
refresh and shares it across every query, rather than rescanning the usage array for each.

That day slice is a single slot, so a period view walks it once per day and asking for the
pieces separately re-walks them: days, log, totals and summary computed independently cost
93 passes over the usage array for a month, and **33 MB** resident against 17 MB for Day.
`PeriodStats.rollup` produces all four from one walk; Month and Day now both idle at
**17 MB**.

### Persistence

Split by purpose. `UserDefaults` holds preferences and the live session snapshot
(written on every transition, on `willPowerOff` and on terminate). Session history lives
in `~/Library/Application Support/FocusContinuity/sessions.json` — a plain Codable file,
written atomically, capped at 5000 records. A corrupt file is renamed aside with a
timestamp rather than discarded, so a parse failure can neither wedge launch nor destroy
history silently.

App usage lives beside it in `app-usage.json` as a version-2 envelope containing its
metadata (`schemaVersion: 2`, `accurateFrom`) and unchanged usage sessions. The
`accurateFrom` date marks where corrected usage recording is authoritative; earlier usage
is retained but qualified in historical views. Loading a legacy raw array preserves every
session field, copies its original bytes to
`app-usage-v1-backup-<unix timestamp>.json`, then writes the v2 envelope. Open stretches
use one stable identity: periodic checkpoints replace that record rather than appending
fragments, and later idle evidence can shorten or remove its provisional tail.

Everything is local. Nothing is transmitted, and no Accessibility, Automation, Screen
Recording or Input Monitoring permission is requested — the global hotkey uses Carbon's
`RegisterEventHotKey`, which needs no TCC grant.

On launch the snapshot is restored *before* the frontmost app is seeded, and the gap since
it was written is resolved through the same extended-break path a live lock/wake takes.

## Surfaces

**Menu bar popover** (320pt, `.ultraThinMaterial`) answers the whole day without opening
the dashboard: today's focused time, streak and tracked total; the live timer or the intent
field; the day's timeline band; the top four apps with real icons and shares; one line each
for what is running and the day's first insight; and the break countdown. Every block has a
designed empty state — a section that renders nothing is treated as a defect.

### Automatic sessions

The app starts a session itself once focused work has held for five minutes, and
**backdates it to when the stretch actually began** — the wait is credited, not
discarded. It pauses when the work stops and ends only if that pause outlives
your break length, so a ten-minute detour does not split an afternoon in two.

**No model is used, local or remote.** The decision is *(purpose mix, input
density, dwell, switch rate) → focused work?* — five numbers in, one boolean
out, which a scoring function with a dozen coefficients answers. A local LLM
would cost 1–3 GB resident against an app that idles at 17 MB, run inference on
every app switch on battery, need `llama.cpp` or MLX (MLX requires macOS 14; the
target is 13), and make the one thing this app sells — a defensible number —
non-deterministic. Every automatic decision instead carries its own explanation,
built from measured values: *"Warp 6m · 3.1 switches/min"*.

**Hysteresis is the design, not a tuning detail.** macOS Focus flips on and off
again shortly after; that is flapping, and it is what makes automatic modes feel
stupid. Starting requires a score at or above 0.65; stopping requires 0.35 or
below. A score drifting anywhere between the two changes nothing at all. A
started session additionally cannot end for three minutes, measured from when it
really started rather than from the backdated time — otherwise backdating would
let the very next evaluation undo it. There is a regression test that feeds a
score oscillating inside the band and asserts every decision is "do nothing".

Music counts toward "focused work with music" only while a player actually
reports itself playing, read from the players' own public broadcast
notifications. Spotify sitting open and paused since login is not music playing,
and saying otherwise would be exactly the fabrication this app refuses
everywhere else.

**Pressing Start continues, rather than replaces.** If a session is already
running on the same work type — including one the app started itself — Start
claims it: same clock, same thread, nothing archived, and the session becomes
the user's so nothing automatic will end it. A different work type is different
work, so that starts a new session and archives the old one. The button says
which it will do.

**It only ever ends its own guesses.** A session you started by hand is never
paused or stopped automatically. The app may reconsider what it decided; it does
not reconsider what you decided. Undoing an auto-started session discards its
record rather than archiving it — a guess you rejected is not history.

### The session log

Grouped by app by default. Chronologically it answered "what was I doing at
3pm", which is rarely the question — one real day held 27 rows with the same app
scattered through ten of them, so working out how long that app had taken meant
scrolling and adding up. Grouped, it is one row per app with a share bar and a
total, expanding to that app's own chronology. `By time` restores the
chronological view for the days when that *is* the question.

Expanding an app gives its longest and average session, its visit count, a chart
of its own shape — hourly on a day, per-day across a week or month, empty days
included — and every session beneath. Longest against average is the point: the
same hour and a half is one long sitting or forty glances, and only those two
figures together say which.

Apps under 30 seconds collapse behind a single line. They are honest
measurements, but a five-second Finder visit costs the same row as an app that
took an hour. Nothing is discarded and no share moves — the percentages are
computed over the whole period whether the tail is showing or not. A lone
straggler is never collapsed, since the line would cost the row it saves.

Grouping it this way made the old Top apps section a second copy of the same
list — same apps, same totals, same shares, a few hundred points further down —
so its bar and hourly strip moved into the log and the duplicate was removed.
The log is period-aware and Top apps never was, so a week or month view now
answers which apps took it. The compact Top apps list remains in the popover,
where there is no room for the log.

### Learning from corrections

The app records whether you keep or undo the sessions it starts, per app, and
moves the score that app must reach before it starts another. Undo a few Chrome
sessions and it becomes harder to convince about Chrome; leave Xcode sessions
standing and it starts them sooner.

Three rules keep it from becoming erratic. It needs at least three answers about
an app before it moves at all — adapting to a single undo is how automatic modes
earn their reputation. The shift is bounded, so a run of undos can make it
cautious but never mute it, and it can never drift past the stop threshold or
starting and stopping would fight. And it moves only the *threshold*: no amount
of learning changes what the archive says happened.

This is the idea worth taking from the AgentDB plugins — store observations,
score them, let corrections move the answer — implemented natively in about a
hundred lines. The plugins themselves cannot ship here: they are MCP servers,
and this is a `swiftc` binary with no SPM, no network and no dependencies. It is
counter arithmetic, not machine learning, and is not described as such.

### Design

Three tonal surfaces (`Surface.ground`, `.card`, `.well`) plus two hairlines; the system
accent is the only accent; a seven-colour data palette assigned by each day's app rank so
one app is one colour on every surface that day; fixed colours per work type; SF Rounded
numerals with tabular digits for the timer and the stat band. The goal ring is the
signature element — in the popover's hero card, in the dashboard's stat band, and as the
menu-bar glyph (a template image rasterised inside the existing tick). Settings live in a
standard `Settings` scene (⌘, or the popover's gear); the popover is a glance surface:
hero, Today, Top apps, Continue today, footer. All tokens are light/dark pairs built with
`NSColor(name:dynamicProvider:)` — no asset catalog.

### Daily goal

A target in focused hours, default four. Progress is judged against **your own
history, not the clock**: `typicalByNow` is the median focused time you had
reached by this hour of day across your last fourteen *active* days. A linear
target would imply a fixed working day with a fixed start, which is false for
most people.

Below three active days there is no median worth quoting, so no pace is shown at
all rather than one derived from a day or two. For roughly the first week the
line is simply absent.

### Rewards

Earned moments appear in a panel that **cannot take focus**: an `NSPanel` whose
`canBecomeKey` and `canBecomeMain` are hardwired false, shown with
`orderFrontRegardless()`. That is an OS-level guarantee rather than politeness,
and it is why this is not an `NSAlert`.

Three rules govern what may be said:

- **Earned by data.** No reward fires unless the number behind it is real — no
  streak record without an actual previous best, no pace without a median. Same
  gate the Insights already pass.
- **Rate limited.** At most four a day, one per kind per day, and never within
  45 minutes of the last. Cheap praise stops landing almost immediately.
- **No invented comparisons.** "More than last Thursday" requires last Thursday
  to have data; without it the message carries today's figure alone rather than
  inventing a baseline.

The rate limits are checked *before* the evidence is gathered. Building the
context walks the archive twice and fourteen days of history besides; doing that
on every app switch only to discover a cooldown was already running cost 4.7% CPU
in a background utility. Asking the cheap question first returns it to 0.0%.

### Threads and Continue

Segments of one piece of work share a `threadID`. Continuing a session earlier in the day
starts a **new record with the same thread** rather than reopening the old one, so each
stretch keeps an honest start and end and a four-hour lunch is never rendered as worked
time. Records written before threads existed decode with a fresh thread each, so every old
session becomes its own single-segment thread — which is the truth about it.

The popover's **Continue today** section lists the day's threads, newest last-touched
first: what it was, the total across every segment, the segment count, and the apps it was
worked in. The running thread shows `running` in place of the Continue button.

Continuing restores the context as well as the timer: if the thread's primary app is still
running it is brought forward, and if it was quit during the break nothing is launched —
reopening an app you deliberately closed would be worse than doing nothing.

**Side apps are derived, never stored.** The primary app is the focused-purpose app with
the most attended time inside the thread's segments — a browser open beside an editor all
afternoon is support, not subject — and side apps are everything else above a 60-second
floor. The usage archive already holds that truth; a stored copy would go stale the moment
the grouping rules changed.

### Break reminders

Measured on **continuous computer use**, session or not: the case that hurts is working for
hours without ever pressing Start. Idle time is already excluded by the tracker, so this is
real work.

Three tiers, because the fatigue is three different things and one interval cannot address
all of them:

| Worked | Break | What it is for |
|---|---|---|
| 20 min | 30 s | Eyes and posture — the 20-20-20 rule |
| 50 min | 5 min | Attention; cognitive load has built up |
| 90 min | 15 min | The ultradian trough, where pushing on costs more than it returns |

**A tier resets on a gap of its own length.** That single rule is what makes the tiers
independent rather than three copies of one timer: look away for thirty seconds and the
eye-strain clock restarts, while the fifty- and ninety-minute clocks carry on unaware. No
extra state is needed to stop micro-breaks from postponing the deep one.

The deepest due tier wins, so ninety minutes is never reported as a stretch break.
Escalation is immediate — reaching the ultradian threshold does not wait out the cognitive
tier's quiet period — while a repeat at or below the last tier waits for that tier's own
interval. Nothing fires twice inside a minute.

The prompt names the app that took most of the stretch, and reports **what was actually
worked** rather than the threshold that was crossed: *"You have been in Xcode for 1h 3m. A
five-minute reset is due."* A stretch with no clear owner (nothing above 40%) names no app
rather than picking whichever was frontmost at the instant the timer expired.

Delivered twice: the non-activating HUD, which carries the reason and stays up for twelve
seconds, and a notification for when you are looking elsewhere. Neither pauses the session
and neither takes focus; with notification authorisation denied, the HUD and the popover
countdown still work.

There is **no interval setting**. What counts as enough rest is a property of the fatigue
being rested, not a preference — thirty seconds will never fix ninety minutes of
concentration whatever it is set to. The settings panel states the three tiers instead, so
the reasoning is available before the first interruption rather than only during one.

The older three-zone layout:

```
2h 20m                                    🔥 7      ← today's focus · streak
──────────────────────────────────────────────
What are you working on?                          ← focused on open, Return starts
[Deep work ▾]  [ ▶ Start Focus ]
──────────────────────────────────────────────
Quick start   [Refactor] [Standup] [Email]        ← derived from the last 14 days
──────────────────────────────────────────────
▁▂▅▃▆▂█  Th F Sa Su M Tu W                        ← weekly rhythm, today accented
Open Dashboard                            Quit
```

While a session runs, the hero becomes an SF Mono timer with Pause, **Away** and Stop.
Away is the one absence the app never has to guess at: it stops the session *and*
background recording until you press **I'm back** or touch a work app.

After an unannounced absence the hero becomes a resolve card — *"Away 9h 17m — not
counted. Your session is still running."* — offering *I was away* / *I was working* /
*Start fresh*. It blocks nothing: the clock, the totals and background recording all keep
going whether or not it is answered. Nothing ever steals focus.

**Menu bar item** has four ambient states: glyph when idle, glyph plus elapsed while
running, dimmed with ⏸ when paused, and a badge when an absence needs resolving.

**Dashboard window** is one column of cards on a flat ground, top to bottom: the title
band (day, date, streak, goal; Day · Week · Month and a date stepper with a calendar),
the **hero** (the goal ring, the running session's stretch clock and controls, and the
day's Tracked · Focused · Sessions), the apps running now as chips, a **Summary** — the
day in four or five sentences written from the same figures, every clause gated on its
data, with a Copy button — four KPI cards each with a week of shape beneath the number,
the hourly **Rhythm** beside the goal ring, the **Sessions** card beside the day
**Timeline**, then App share · Work type · Insights and the App usage table.

The date is the master context. On a past day every card, the hero included, shows that
day and nothing that moves: the hero's clock becomes the day's focused total, the ring is
that day's goal, and the running session stays in the menu bar and on today. A session
is a *thread* — work that carried on across breaks — so `Sessions 1` and `1 session ·
7 stretches` describe one thing; hovering a session lights its stretches on the
timeline, clicking narrows the page to it, Esc clears.

### Day, Week, Month

One segmented control above the chart switches the period. **Day** shows the 24-hour
timeline; **Week** and **Month** replace it with daily bars of exact tracked time, over an
axis spanning the whole period — so a month with one busy week reads as one busy week, not
as a busy month. Work-type composition stays in the separate donut rather than changing
bar height. A dashed rule marks the average.

The stat row above it reads **Tracked · Active days · Average/day · Longest session**. The
average divides by **active** days, not calendar days: averaging a five-day week over seven
understates every working day by nearly a third. `4 of 7` states the denominator so the
figure cannot be misread. With nothing recorded, longest reads `—` rather than `0s`.

Below the chart, the **session log** lists every grouped session in the period, newest
first, grouped under day headers carrying that day's total. Each row is a clock range, the
app's icon and name, `· N visits` where grouping merged separate visits, and the attended
duration — the evidence behind the rankings further down.

Top apps and Focus quality stay scoped to the selected day even in Week and Month, so their
headers name it (`Top apps · Thu 13 Aug`).

The timeline is divided into uniform hour columns. Hovering names the app under the
pointer with its clock range and duration; clicking a segment expands that app's stretches
for the hour. Dates are reached with a `‹ Wed 13 Aug ›` stepper, bounded at your earliest
record and at today.

Every figure carries its context — a delta, a share, a name — and the Summary and the
Insights are computed and gated: a sentence or an insight with no data behind it does not
appear rather than showing zero. No model is involved anywhere; the words are the figures.

**⌃⌥Space** starts or stops a session from anywhere. macOS 13 exposes no API to open a
`MenuBarExtra` programmatically, so the hotkey acts directly rather than opening the
popover.

## Files

```
build.sh                          Compile, bundle, sign; --run / --test
Assets/AppIcon.png                Icon source; build.sh renders the .icns
Sources/
  Core/                           No SwiftUI — fully testable headless
    SessionState.swift              State, event and model types, constants
    SessionEngine.swift             State machine, time arithmetic, start/stop
    SessionArchive.swift            Codable file store + today/week/streak queries
    PeriodStats.swift               Day/week/month rollups and the session log
    AppPurpose.swift                What an app is for; behaviour-resolved ambiguity
    InputDensity.swift              Active / passive / absent from input counters
    SessionThread.swift             Thread grouping, primary and side apps
    FocusScore.swift                Signals to a 0...1 score that explains itself
    AutoSessionDetector.swift       Start/pause/end, with hysteresis
    DailyGoal.swift                 Target and the personal median
    RewardEngine.swift              Gated, rate-limited congratulations
    PurposeLearner.swift            Learns how eagerly to start, per app
    PersistenceStore.swift          UserDefaults preferences and live snapshot
    CategoryManager.swift           Bundle ID → AppCategory + suggested WorkType
    Notifier.swift                  Local notifications, degrades to a no-op
  App/
    FocusContinuityApp.swift        @main, argument gate, scenes
    AppCoordinator.swift            Lifecycle, ownership, monitor wiring
    SessionStore.swift              The one bridge: engine → @Published
    SessionStore+Dashboard.swift    Dashboard figures, charts, the selected period
    SessionStore+History.swift      Timeline inspection, per-app history, threads
    SettingsModel.swift             Settings window bridge to PersistenceStore
    EventMonitor.swift              Workspace + distributed notifications (AppKit)
    HotKeyMonitor.swift             Carbon global hotkey, no TCC grant
  Surfaces/
    Popover/
      PopoverView.swift             Menu bar popover: frame, metrics, scroll
      HeroCard.swift                Goal ring beside the timer / start form / away card
      GlanceCards.swift             Today timeline, Top apps, Continue today
      PopoverFooter.swift           Break countdown and the three icon buttons
    Settings/
      SettingsView.swift            ⌘, window: Goal · Away and breaks · Automatic · Display
    ContinueTodaySection.swift      Today's threads, resumable in one click
    RewardHUD.swift                 Non-activating panel; cannot take focus
    Dashboard/
      DashboardView.swift           Two-column dashboard shell
      DayTimelineView.swift         24-hour Canvas timeline
      DashboardHero.swift           Goal ring, running session, today's headline figures
      DashboardCharts.swift         Sparkline, rhythm bars, work-type donut, running-now chips
      DashboardSections.swift       Top apps, Running now, Insights, Focus quality
      PeriodViews.swift             Stat band, period chart, session log
    GalleryView.swift               --gallery state catalogue and fixtures
    Snapshotter.swift               --snapshot PNG renderer
  Design/
    DesignTokens.swift              Surfaces, palette, type, radii, formatters
    PopoverMetrics.swift            Panel size from the screen it opens on
    MenuBarGlyph.swift              Goal ring as a template image for the status item
    Components/Components.swift     Start button, away card, menu-bar label
    Components/Cards.swift          Card modifier, stat card, bar, swatch, icon button
    Components/GoalRing.swift       The signature ring
    Components/InfoTip.swift        Plain-English explanations on hover
    Components/AppIcon.swift        Cached app icons; palette forwarder
  SelfTest.swift                    Headless logic self-test
docs/superpowers/
  specs/                            Design specs
  plans/                            Implementation plans
```

Retired AppKit files (`main.swift`, `MenuBarController.swift`, `AlertPresenter.swift`,
`AppDelegate.swift`) are kept in `_trash/` rather than deleted.
