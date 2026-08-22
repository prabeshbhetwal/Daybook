# Honest Session Time — Design

**Date:** 2026-08-17
**Status:** Approved

## Problem

The app reported `5h 43m of 4h — Goal met` on a day with `At the Mac 2h 38m`. Every
figure was arithmetically correct and the result was still false: the user had not
focused for four hours.

Four separate causes, found from live data on the author's machine:

1. **`SessionEngine` never consults `IdleMonitor`.** A session counts wall-clock from
   Start to Stop. Only screen lock, sleep, the Away button and manual Pause subtract
   anything. Walking away without locking counts fully as work.
2. **"I was away" kept the session running.** The gap was excluded but the session
   continued, so one session spanned an entire day and its elapsed figure measured the
   span of the work rather than any stretch actually worked.
3. **`RunningApp.openFor` is `reference.timeIntervalSince(launched)`** — process uptime.
   Rendered as `Now: Claude 6h 50m` directly above `Claude 53m` in Top Apps. Two numbers,
   similar labels, unrelated quantities.
4. **The popover is `frame(width: 320)` with unbounded height** and no scroll region, so
   its lower half runs off a 14" display once Settings is expanded.

## Goals

- A session's elapsed time reflects time actually spent working.
- The daily goal can only be filled by time the user demonstrably worked, on work they
  declared.
- Every figure on screen states which quantity it is, and no two figures with similar
  labels measure different things.
- The popover fits any screen from an 11" Air upward.

## Non-goals

- Recording individual pause intervals in `SessionRecord`. See "Known limits".
- Making the idle threshold configurable. There are already three away thresholds.
- Changing the break-reminder tiers.

## Design

### 1. Idle auto-pause

`SessionEngine` gains one event:

```swift
case idleObserved(seconds: TimeInterval)
```

`SessionStore`'s existing one-second ticker samples `IdleMonitor` and posts it. No new
timer — the app's single repeating timer remains the session ticker.

| State | Condition | Effect |
|---|---|---|
| `.running` | `seconds >= idlePauseThreshold` (600) | `enterPause(reason: .idle, at: now − seconds)` |
| `.paused(.idle)` | `seconds < idlePauseThreshold` | `leavePause()` |
| `.paused(anything else)` | — | no effect |

**The pause is backdated** to the moment input actually stopped, so the ten minutes that
prove the user is gone are themselves excluded. The visible consequence is that the timer
jumps back by up to ten minutes when it pauses. This is the correction being applied
honestly and happens only when nobody is watching.

Only `.idle` pauses auto-resume. A pause the user pressed stays pressed until they say
otherwise — the app must not undo a deliberate act.

`PauseReason.idle` is a new case, persisted as `"idle"`, decoding to `.manual` on
unknown values as the existing cases do.

Ten minutes is deliberately tolerant. Reading a long document, thinking, or taking a call
are work the keyboard cannot see; a three-minute rule would punish them. Lunch still gets
caught.

### 2. The goal counts session ∩ hands-on

New pure type in `Core`:

```swift
enum FocusedActiveTime {
    static func seconds(on day: Date,
                        records: [SessionRecord],
                        usage: [AppUsageSession],
                        running: (start: Date, end: Date)?,
                        calendar: Calendar) -> TimeInterval
}
```

Both sides are clipped to the day, merged to remove self-overlap, then intersected:

- **Focus ranges** — archived records where `workType.countsAsFocus`, plus the running
  session's span. Merged so two overlapping records cannot count one second twice.
- **Hands-on ranges** — `AppUsageArchive.sessions` (already system-process filtered and
  idle-trimmed at three minutes).

`GoalProgress.achieved` consumes this instead of `archive.workSeconds(on:)`.

`todayTotal`, `weekBars`, `currentStreak` and `bestStreak` keep using recorded
`workSeconds` — they describe sessions, and a session that happened is a fact regardless
of keyboard activity. Only the goal, which is a claim about effort, uses the intersection.

### 3. The away answers all end the session

`SessionEngine.apply(_ decision:)` becomes symmetric. Every answer except *I was working*
archives the running session ending at `awayStarted`, then begins a new one starting at
`returnedAt`:

| Decision | Archives old at departure | New session | Extra |
|---|---|---|---|
| `.mergeTime` | no | — | gap added back as work |
| `.tookBreak` | yes | same `threadID` | writes a `.breakTime` record for the gap |
| `.continueSession` | yes | same `threadID` | — |
| `.resetTimer` | yes | new `threadID` | — |

Thread continuity is what separates them: *Continue Today* groups by `threadID`, so an
afternoon split by lunch still reads as one piece of work while the archive holds honest
blocks with real gaps between them.

`archiveCurrentSession` already refuses anything under `minimumRecordedSession` (30 s), so
a bounced answer cannot litter the archive.

### 4. Glance lines

- `RunningApp.openFor` is redefined as **seconds in the current unbroken stretch**, taken
  from the usage tracker's open segment rather than the process launch date. The label
  `Now: Claude 12m` then means what it says and reconciles with Top Apps.
- `Longest unbroken stretch` becomes `Longest stretch in one app today`, so it cannot be
  read as a session figure.

### 5. Responsive popover

A `PopoverMetrics` helper reads `NSScreen.main?.visibleFrame` at body evaluation:

```swift
struct PopoverMetrics {
    let width: CGFloat        // 320, or 560 when the screen affords it
    let maxHeight: CGFloat    // 80% of visibleFrame.height
    let twoColumn: Bool
}
```

Layout becomes pinned-scroll-pinned:

- **Pinned top** — `At the Mac` / streak, goal bar, the live timer and its controls.
- **Scrolling middle** — timeline, Continue Today, Top Apps, glance lines, Settings.
- **Pinned bottom** — Open Dashboard / Quit.

In two-column mode Top Apps sits beside the timeline, roughly halving the height. The
height cap applies in both modes, because expanded Settings can overflow either.

### 6. Which clock is which

- **Menu bar** — the current session only, never a day total.
- **Popover hero timer** — the same figure.
- **Day totals live in the popover** and are labelled as such: `At the Mac` (hands-on
  today) and the goal bar (focused today).

§1 and §3 are what make this true rather than nominal: with idle pausing and absences
ending sessions, the menu-bar figure becomes "this stretch of work", which is the only
thing a glanceable timer should show.

## Known limits

**Where inside a record the pauses fell is still unknown.** §2 intersects session
*spans* with hands-on stretches; `SessionRecord` does not store its pause intervals.
Each record's credit is capped at its recorded `workSeconds` (2026-08-22), which closes
the worst case — a distraction pause is hands-on by definition, and its whole length
used to fill the focus goal — without a schema change. What remains open is
distribution, not size: a record with spare work inside its span can still have a
paused-but-hands-on minute counted in place of a worked-but-hands-off one, because
nothing records which minute was which.

**The goal becomes materially harder.** Today's `5h 43m` becomes something below
`2h 38m`. That is the intended correction, but the 4 h default is now likely unreachable
for most days and the user should expect to lower it.

## Testing

Headless, against the injected clock, in `SelfTest.swift`:

1. Idle past the threshold pauses backdated; the excluded seconds equal the idle time.
2. Input resumes an `.idle` pause; input does **not** resume a `.manual` one.
3. `.idle` survives a persistence round-trip.
4. `FocusedActiveTime`: disjoint ranges yield zero; a session with no usage yields zero;
   usage with no session yields zero; partial overlap yields exactly the overlap;
   overlapping records do not double-count.
5. Each away answer archives at the departure moment and starts the new session at the
   return moment, with the right thread identity.
6. `openFor` reports stretch length, not process uptime.
7. `PopoverMetrics` caps height below a small screen's `visibleFrame` and picks one
   column when the screen is narrow.

Added by the 2026-08-22 audit, all headless against the injected clock:

8. The menu bar's glance stays on today while the dashboard browses history (73).
9. A second absence while the away card is up is excluded from whichever session survives
   the answer — *I was away* and *I was working* alike (74); and it survives a relaunch,
   with an absence still open at the quit measured from its start (78).
10. An absence that outgrows `longAwayCap` ends the session where input stopped on every
    path: lid open with no lock (75), idle-then-locked with the unlock as the first event
    heard (77), and a restore whose first sample already shows input (77). Only `.idle`
    and `.away` pauses qualify; a `.manual` pause is the user's to end.
11. A record's goal credit is capped at its worked seconds, so a distraction pause —
    hands-on by definition — cannot fill the focus goal (76).
12. Sessions, Focused and Longest on the stat row follow the selected day; Longest is
    named by the session's intent, not the busiest app (79).
