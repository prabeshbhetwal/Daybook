# Machine events

Date: 2026-10-10
Status: approved 2026-10-10 (plan); built on `claude/mac-sleep-restart-shutdown-logging-46d69a`

## Why

Daybook could not say why recording stopped. Sleep started an away period
and power-off saved state, but nothing recorded *which* event it was, and a
crash, a force quit or a power cut left no trace at all. History guessed a
hole's cause from how the last app stretch ended. `AppUsageTracker.suspend()`
ends every stretch `.systemLock`, so sleep, shut down and quit holes all read
"Mac locked"; anything else read "The Mac may have been asleep or off…".

Goal: record every event that interrupts recording, with its time, and show
it in History. The events are sleep, wake (every wake), display off and on,
lock and unlock, user switch, log out, restart, shut down, quit, update
relaunch, crash, force quit, power loss, kernel panic and Mac start-up.

## Decisions

| Question | Decision |
|---|---|
| Where causes show | History gap rows name the cause, and each day gets a folded "Mac events" list. The away card is unchanged. |
| Dark wakes | Every wake is listed; none is merged. |
| Display sleep vs system sleep | Recorded and labelled apart. Session timing is unchanged: both still call the same sleep handler. |
| Storage | New files `machine-events.jsonl` (append-only) and `run-state.json` (the run marker). `fc.state`, `sessions.json` and `app-usage.json` are untouched. |
| Rejected: new `AwayTrigger` cases | `AwayTrigger` is decoded with no fallback. An older build would throw on a new case and set the whole live snapshot aside (`PersistenceStore.loadState`). Labels need evidence, not a new engine state. |
| Rejected: new `UsageEndReason` cases | Same downgrade risk for every app-use record. |
| Rejected: macOS's own shutdown cause (`pmset -g log`, unified log) | Not found on this Mac three days after a boot. Not relied on. |

## How each event is caught

| Event | Seen | Source |
|---|---|---|
| Sleep, wake, display off/on | Live | `NSWorkspace` notifications, one kind per notification (`EventMonitor`) |
| Lock, unlock | Live | `com.apple.screenIsLocked` / `…Unlocked` |
| User switched out / in | Live | `sessionDidResignActive` / `…BecomeActive` |
| Log out | Live, at quit | `kAEQuitReason` on the quit Apple event, read in `applicationShouldTerminate` (`kAEReallyLogOut`, `kAELogOut`) |
| Restart, shut down | At quit, confirmed next launch | The same reason (`kAERestart`, `kAEShutDown` and their dialog variants), kept in the marker. Another app can still call it off after Daybook has quit, so the next launch records it only if the boot changed, and records "Daybook quit" if not |
| Shut down, restart or log out (unnamed) | Next launch | `willPowerOff` arrived but no quit followed; kept in the marker, not the log |
| Quit | Live | A quit with no reason (⌘Q, the Quit button) |
| Update relaunch | Live | Sparkle's `updaterWillRelaunchApplication` |
| Crash | Next launch | No clean exit, and a `~/Library/Logs/DiagnosticReports/Daybook*.ips` written after the run began whose body's `"pid"` is the run's (a test build's crash is not this run's) |
| Force quit | Next launch | No clean exit, same boot, no crash report |
| Power lost | Next launch | No clean exit and a new `kern.bootsessionuuid` |
| Kernel panic | Next launch | As power lost, plus a `/Library/Logs/DiagnosticReports/*.panic` since the last heartbeat (admin-readable only) |
| Mac started | Next launch | `kern.boottime`, when the boot differs from the marker's |

An event found at the next launch carries a window: `at` is the run's last
heartbeat, `latest` the report, boot or launch by which it had happened.

A log out, restart or shut down is dated when macOS announced it
(`willPowerOff`), not when its quit arrived. The quit can come minutes
later while other apps ask to save, but recording stopped at the
announcement, so the event sits where the hole begins.

## The run marker

`run-state.json` holds `bootSessionID`, `launchedAt`, `heartbeat`, `exit` and
`pid`. It is written at launch, by its own 60-second heartbeat (separate from
`SessionStore`'s ticker, which rests while nobody is at the Mac), at every
event and at quit. `exit` is nil while running. A launch saves its own marker
before it records the previous run's ending, so a launch that cannot save
never leaves the old marker to be read and recorded twice. Backups drop the
marker, as they drop the instance lock: restored, it would read as a crash.
`RunMarker.previousRun` turns the previous marker and the launch evidence into
events:

| Exit recorded | Same boot | Report | Events added |
|---|---|---|---|
| none (first run) | – | – | Daybook opened |
| quit, log out, update | yes | – | Daybook opened |
| quit, log out, update | no | – | Mac started, Daybook opened |
| restart or shut down | no | – | Mac restarted / shut down, Mac started, Daybook opened |
| restart or shut down | yes | – | Daybook quit (the restart was called off), Daybook opened |
| unnamed power-off | any | – | Shut down, restarted or logged out; then as above |
| nil | any | crash report after launch | Daybook crashed (then Mac started if rebooted) |
| nil | yes | none | Daybook was force quit |
| nil | no | panic report | Mac restarted after a problem, Mac started |
| nil | no | none | Mac lost power or was forced off, Mac started |

A power-off announced but not followed by a quit within two minutes was
called off by another app; the heartbeat clears it.

## Naming a hole

`StoryChronology.gapReason(for:usage:events:)` takes the most telling event
whose window overlaps the hole (from two seconds before it, since the
recording stops a moment after the event): power lost, panic, crash, force
quit, shut down, restart, log out, unnamed power-off, update, quit, sleep,
user switch, lock, display off. A lock or a dark display after a stretch that
ended for want of input is what idleness does, so "No input" stands. With no
event, the old rule applies unchanged, so days recorded before this change
read as they did.

`EventMonitor` calls `onMachineEvent` after each existing closure, so writing
the log (about 1 ms) never moves the moment the engine reads.

## Checks

708–718 (`MachineEventChecks`, `MachineEventStoryChecks`): the verdict table
(including a called-off shut down and another process's crash), the log's
round trip (torn line, unknown kind), report dating and pid, the boot ID,
quit-reason mapping, a full recorder round trip (deferred restart, called-off
power-off, unnamed power-off), gap naming (including an event at the hole's
end), unchanged old days, the day's event list, and History redrawing a day
its log has grown for. The backup-clone check also covers the run marker.

Not covered by a check: a write that fails part-way through a line. The next
append then starts a new line (`lastLineOpen`); the reviewer's probe showed
the earlier behaviour lost that append.

## Hand checks

Restart, shut down, log out, `pmset sleepnow`, `pmset displaysleepnow`,
`kill -9`, `kill -SEGV`, menu-bar Quit, and optionally a held power button.
Each ends by opening today's "Mac events" list. The restart check is the only
proof that this menu-bar app receives `kAEQuitReason`.

## Amendment, 10 October 2026: gaps explain themselves

The folded list at the foot of the day put seven raw events, oldest first,
under a story told newest first, away from the hole they explained. Approved
design: direction A of the "Daybook Mac events" canvas, with its gap-row state
sheet.

| Question | Decision |
|---|---|
| Where events show | Inside the gap they explain. A gap is now a card; one whose cause is a machine event unfolds into a scale bar and one line per stretch. |
| Raw events or stretches | Stretches (`GapAnatomy`, Core). A lock and its unlock are one "Mac locked" stretch; display-off time is that stretch's detail. The deepest state wins on overlap: uncertain > off > asleep > locked > nothing recorded. |
| Which events belong to a hole | One rule, `MachineEvent.falls(in:)`, for the hole's name, its card and the pins: from 2 s before the hole, and by the whole window of an event found afterwards (dated from its last heartbeat). Recording before the hole shows the Mac was awake and unlocked, so earlier events are ignored. A closer with no opener (an unlock alone) counts from the hole's start or the last launch inside it. |
| Crash, force quit, power cut, panic | A dashed "some time in this window" stretch from the last heartbeat to `latest`, then "Daybook not running" until the launch that found it (a launch at `latest` itself counts). The Mac may have started long before, so the stretch never says "Mac off". |
| Sub-minute stretches | Nothing recorded or locked under a minute joins a neighbour at least as deep, the deeper first (a lid's close joins the sleep; the seconds before recording resumes join the lock). A neighbour grows by at most a minute at each end; an off stretch or a crash window never grows. A short lock between stretches of nothing stays a lock. The same minute the story already leaves unsaid between recordings. |
| Events outside any gap | A run's end (shut down, restart, log out, quit, update, crash) not inside a gap becomes a pin row on the rule, with when Daybook was back, inside a session too: the session's shape names a stop only where a recorded stretch ended at the lock screen. |
| Away answers | An answer splits a hole and each piece keeps the hole's name. A piece is read against the whole hole (`GapAnatomy.of(_:in:events:)`) and always unfolds. |
| The raw list | Kept, folded, newest first, "All N Mac events". |
| Fills | Lighter is nearer the desk: stripes (nothing recorded), locked, asleep, off; dark appearance runs the other way. The window frame uses `StoryStyle.attentionInk`. |
| Expand all | Opens gaps whose reason is a machine event. |

Checks 732–744 (`GapAnatomyChecks`): the screenshot's day (nothing recorded,
then one locked stretch with its display-off time, the trailing sliver
absorbed), sleep under a lock, a crash window, a restart cutting a lock, only
events inside the hole counting, the pin rule, a heartbeat-dated power cut
(named once, not pinned), the launch that found a force quit, a piece of a
split hole, slivers, Expand all with pins kept out of quiet runs, the limits
on slivers (a short lock stays; a minute's growth at most), and stretches cut
exactly to the hole. A
mutation run with sliver folding and pins removed failed 732, 736 and 737.
The fix-reviewer's findings on the first version are all fixed; the store's
choice of the whole hole for a split piece has no check, since away answers
are engine internals a check cannot set.
