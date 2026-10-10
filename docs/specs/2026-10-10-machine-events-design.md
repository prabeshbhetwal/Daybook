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
