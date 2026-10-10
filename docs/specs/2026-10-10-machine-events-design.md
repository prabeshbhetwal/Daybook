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
