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
| Log out, restart, shut down | At quit, confirmed next launch | `kAEQuitReason` on the quit Apple event, read in `applicationShouldTerminate` (`kAEReallyLogOut`/`kAELogOut`, `kAERestart`, `kAEShutDown` and the dialog variants), kept in the marker. Another app can still call it off after Daybook has quit, so the next launch confirms it: a new boot for a restart or shut down, a login session begun after the quit for a log out. Otherwise it reads "Restart / Shut down / Log out cancelled after Daybook quit" |
| Quit by another app | Live | A quit Apple event with no reason from any sender but loginwindow or the Dock (`keySenderPIDAttr`, named through `NSRunningApplication` or `proc_pidpath`): "Daybook quit by System Settings", "… by osascript" |
| Shut down, restart or log out (unnamed) | Next launch | `willPowerOff` arrived and no named quit followed; kept in the marker, never written as such. The next launch settles it: a new boot is "Mac restarted or shut down", a new login session is "Logged out", neither is "Daybook quit" |
| Quit | Live | A quit with no reason (⌘Q, the Quit button, the Dock) |
| macOS updated | Next launch | The boot is new and `kern.osversion`/the version differs from the marker's: "macOS updated to 27.3 (…)", dated at boot |
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
| restart or shut down | yes | – | Restart / Shut down cancelled after Daybook quit, Daybook opened |
| log out | yes | – | Logged out if the login session began after the quit, else Log out cancelled after Daybook quit |
| unnamed power-off | no | – | Mac restarted or shut down, Mac started, Daybook opened |
| unnamed power-off | yes | – | Logged out if the login session began after it, else Daybook quit |
| any, on a new boot | no | – | macOS updated to … first, when the version differs |
| nil | any | crash report after launch | Daybook crashed (then Mac started if rebooted) |
| nil | yes | none | Daybook was force quit |
| nil | no | panic report | Mac restarted after a problem, Mac started |
| nil | no | none | Mac lost power or was forced off, Mac started |

A power-off announced but not followed by a quit within two minutes was
called off by another app; the heartbeat clears it.

### Why the power-off notice names nothing (10 October, evening)

The first build took `willPowerOff` as proof of a log out, restart or shut
down. That evening Sir turned on haptic feedback, granted Input Monitoring
with Touch ID (tccd: `kTCCServiceListenEvent` modified, 17:35:02), and System
Settings quit Daybook to apply it (AppKit: "Handling Quit AppleEvent",
17:35:03) and reopened it at 17:35:43. AppKit announced a power-off for that
quit too; the event carried no reason; the Mac did not reboot and the login
session never ended (`last`: console since 14:14). The day read "Shut down,
restarted or logged out".

A throwaway SwiftUI menu-bar probe confirmed that a reason, when a quit
carries one, is readable in `applicationShouldTerminate` (`isQuit=true
attr='rest'`), so the reason was absent rather than missed. Exits are now
named from evidence only: the reason, the sender, the boot, the login
session and the macOS version. No timing threshold separates a restart from
a shut down: an update, a FileVault unlock or an app that holds up a restart
can each take any time. When macOS gave no reason and the Mac booted again,
the event reads "Mac restarted or shut down", beside "Mac started up" and
its time. The marker keeps the reason's four letters and the sender, so a
surprising exit can be traced.

Sir's hand check at 19:56 the same evening showed what System Settings
actually sends: its Quit & Reopen comes from
`com.apple.settings.PrivacySecurity.extension` with reason `rlgo`
(`kAEReallyLogOut`), macOS's own log-out code, which is why AppKit announces
a power-off for it. The first version of this fix let a reason win over the
sender and kept it as a log out. The sender now decides first: a reason
counts only from loginwindow or a sender that cannot be told. A marker the
earlier build left with another app's sender is read at the next launch as
that app's quit. After that Quit & Reopen, Launch Services reopened Daybook
by bundle identifier and chose a stale copy (an old worktree's build), not
the main checkout's quarantined one; stale registrations are a matter for
where the live app lives.

Three rules from the review of this fix:

- "Cancelled" is a claim and needs evidence: a restart or shut down reads
  cancelled only when the previous run knew its boot, a log out only when
  the login records are readable. Otherwise only the quit is certain, and it
  reads "Daybook quit".
- loginwindow quits apps only for macOS's own log out, restart or shut down,
  so its quit always waits for the next launch, however long after the
  announcement it came. The two-minute grace now only clears an announcement
  that no quit followed.
- The marker keeps the first quit's reason and sender;
  `applicationWillTerminate`'s second call, which has no event, does not
  erase them.

Entries the first build wrote as an unnamed power-off are read on load by
what followed them: a "Mac started up" before the next "Daybook opened"
reads "Mac restarted or shut down", otherwise "Daybook quit". The file keeps
what was written.

The live app ran translocated after System Settings reopened it: the main
checkout is under the iCloud-synced Desktop, which re-quarantines the bundle
after `build.sh` clears the flag (`build.sh` notes this). That is a separate
matter for where the live app lives.

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
| Kinds from #29 | Quit by another app, the three cancelled kinds and "restarted or shut down" end a run like a quit (off until Daybook opens; pinned when they left no hole). macOS updated is dated at the boot, so it counts as a start. Every line shows `event.title`, so the quitting app and the macOS version stay. |
| Events outside any gap | A run's end (shut down, restart, log out, quit, update, crash) not inside a gap becomes a pin row on the rule, with when Daybook was back, inside a session too: the session's shape names a stop only where a recorded stretch ended at the lock screen. |
| Away answers | An answer splits a hole and each piece keeps the hole's name. A piece is read against the whole hole (`GapAnatomy.of(_:in:events:)`) and always unfolds. |
| The raw list | Kept, folded, newest first, "All N Mac events". |
| Fills | Lighter is nearer the desk: stripes (nothing recorded), locked, asleep, off; dark appearance runs the other way. The window frame uses `StoryStyle.attentionInk`. |
| Expand all | Opens gaps whose reason is a machine event. |

Checks 738–750 (`GapAnatomyChecks`, after #29's `MachineEventExitChecks`): the screenshot's day (nothing recorded,
then one locked stretch with its display-off time, the trailing sliver
absorbed), sleep under a lock, a crash window, a restart cutting a lock, only
events inside the hole counting, the pin rule, a heartbeat-dated power cut
(named once, not pinned), the launch that found a force quit, a piece of a
split hole, slivers, Expand all with pins kept out of quiet runs, the limits
on slivers (a short lock stays; a minute's growth at most), and stretches cut
exactly to the hole. A
mutation run with sliver folding and pins removed failed what are now 738,
742 and 743.
The fix-reviewer's findings on the first version are all fixed; the store's
choice of the whole hole for a split piece has no check, since away answers
are engine internals a check cannot set.

## Amendment, 10 October 2026, late: a stop no event explains

The tracker ends a stretch `.systemLock` not only at the lock screen, sleep
or quit but also when Spotlight, Control Centre, Notification Centre, the
Dock, WindowManager or a password prompt comes forward
(`AppUsageArchive.systemProcesses`), when recording is turned off and on Step
away. None of these logs an event, so such a hole fell back to "Mac locked".

| Question | Decision |
|---|---|
| A hole that ended `.systemLock` with no event in it, after the log began | `StoryGapReason.recordingStopped`: "Not recorded", hint "Recording stopped while Spotlight, Control Centre or a password prompt was in front, or app recording was off." (Sir's wording.) Since the log began a lock leaves its own event, and `falls(in:)` already counts one reported late (the screen saver's password delay). |
| Before the log | Unchanged: "Mac locked", no hint. The log begins at `machineEventLog.events.first?.at`; a hole whose stop came before it, even one the first launch ends, is pre-log. |
| How Core learns the start | `StoryChronology.build(…, eventLogStart:)` from `SessionStore.storyMoments(on:)`; the History cache key carries it beside the event count. Core reads no storage. |
| Same rule elsewhere | The session card's "Along the way" sentence leaves such a stop out (`SessionShape+Stops`, branch `claude/session-shape-unexplained-stops`). |
| Daybook on its way out | Once a restart, shut down or log out is announced Daybook can record a little more before it quits, so its hole can start more than 2 s after the event. A live run ending at or before the stop with no "Daybook opened" since makes the hole `.unknown` ("Not recorded", the old hint): the event's pin beside it names it, and the Spotlight hint would be false (fix-reviewer). |

Not done: such a hole is not named by the event itself, which would need
`falls(in:)` to reach back to it for the card and the pins as well. The
session card and the gap share the rule but not the code; one helper can
replace both once the session-shape branch lands.
