# Menu Bar at a Glance and Break Reminders — Design Spec

**Date:** 2026-08-13
**Status:** Approved for planning

---

## 1. Goal

Make the menu bar popover answer the whole day without opening the dashboard, and add a
break reminder that speaks after a real stretch of work.

## 2. Defects being fixed

| # | Defect | Cause |
|---|---|---|
| G-1 | ~150pt of dead space in the popover, seven weekday labels with no bars | The `WeekChart` empty state was specified in the dashboard plan (Task 4 Step 4) and never implemented. All-zero bars draw nothing while the frame keeps its height |
| G-2 | The per-app section renders nothing useful in the popover | It sits inside a `ScrollView` with a 260pt cap in a 320pt-wide popover, so it is cramped and easily empty-looking |

G-1 is a process failure, not a design one: the fix was written down and skipped.

## 3. The popover, rebuilt

Still 320pt wide, `.ultraThinMaterial`. Everything below is visible without scrolling; the
only scrolling region is the app list, and it is bounded.

```
┌──────────────────────────────────────┐
│ 2h 28m today            🔥 1  ⏱ 4h 12m│  totals: focused · streak · tracked
│                                      │
│ 02:28:42                             │  live timer, SF Mono
│ Refactor · Deep work                 │
│ [Pause] [Stop]                       │
│ ────────────────────────────────────  │
│ ▓▓░▓▓▓▓░░▓▓▓  ← day band, 28pt tall  │  the same Canvas, compact
│ 8a    11a    2p    5p                │
│ ────────────────────────────────────  │
│ ▣ Xcode      3h 20m ███████░  65%    │  top 4 apps, real icons
│ ▣ Chrome       55m  ██░░░░░░  18%    │
│ ▣ Terminal     35m  █░░░░░░░  11%    │
│ ────────────────────────────────────  │
│ Now: Claude 7h 32m · Finder          │  running, one compact line
│ Longest: Xcode 2h · 62% in session   │  one insight line
│ ────────────────────────────────────  │
│ Break in 12m   Show [5] ▾  Track ⬤   │  settings row
│ Open Dashboard                  Quit │
└──────────────────────────────────────┘
```

**What changed and why**

- The weekly bar chart is **replaced by the day band**. A week of bars answers "how has my
  week gone"; the popover's job is "what is happening today", and the band already exists
  and reads better at 28pt than seven bars do.
- The per-app list is **the same ranked rows as the dashboard**, capped at four, with real
  icons, bars and totals. No nested scroll region.
- **Running now** collapses to a single line: the longest-open app plus a count.
- One insight line, chosen as the first gated insight for today.
- Break countdown sits in the settings row: `Break in 12m`, or `Break due` when overdue.

**Empty states.** Each block states what is missing rather than rendering blank: no usage
yet, no session yet, no insight yet. G-1 must not be able to recur — the day band already
has a designed empty state, and the `WeekChart` empty state is implemented as part of this
work even though the popover no longer uses it, because the dashboard still does.

## 4. Break reminders

### 4.1 What is measured

**Continuous computer use**, whether or not a focus session is running. The usage tracker
already excludes idle time, so this is real work, not a frontmost app on an untouched
machine.

`workedContinuously` = the sum of tracked stretches running backwards from now, stopping at
the first gap of `breakLength` or longer. That gap is what counts as having taken the break.

### 4.2 When it speaks

Once `workedContinuously` reaches `workInterval`, one notification is posted:

> **Time to stretch**
> You have been working 50m. Take a 10 minute break.

Then it stays quiet until either the break is taken (a gap of `breakLength`) or another
full `workInterval` elapses — so a long day gets a nudge per interval, never a stream.

### 4.3 Settings

Three controls, in the popover's settings row behind a `Breaks` disclosure so the row stays
one line when collapsed:

| Setting | Default | Options |
|---|---|---|
| Reminders | On | On / Off |
| Work interval | 50 min | 25 / 50 / 90 min |
| Break length | 10 min | 5 / 10 / 15 min |

Persisted in `UserDefaults` alongside the other preferences.

### 4.4 Honest limits

Notification delivery depends on the authorisation granted at first launch. If it is
denied, the countdown in the popover still works and the menu bar still shows `Break due`,
so the feature degrades to the surfaces we control rather than failing silently.

The reminder is never blocking and never pauses the session: it is a nudge, and the
research this product is built on is explicit that punishment mechanics make people quit.

## 5. Architecture

```
Core/BreakReminder.swift    NEW. Pure: given stretches and now, how long have you
                            worked continuously, and is a reminder due?
Core/PersistenceStore       Three new preferences
App/SessionStore            Publishes `breakCountdown` and posts the notification
Surfaces/PopoverView        Rebuilt per §3
Design/Components           `WeekChart` empty state (G-1), compact rows
```

`BreakReminder` is pure and headless so the interval logic is fully covered by the
self-test — the same reason every other figure lives in `Core`.

## 6. Verification

- `workedContinuously` tests: a gap shorter than the break length does not reset it; a gap
  at or over it does; idle-trimmed stretches count only their attended time.
- Due/not-due tests at the interval boundary, and that a second reminder does not fire
  until another interval has passed.
- `WeekChart` renders its empty state when every bar is zero (G-1 regression).
- Popover snapshots: idle, running, no-usage-yet, break-due.

## 7. Out of scope

Scheduling reminders by time of day, per-app break rules, and any blocking or enforcing
behaviour.
