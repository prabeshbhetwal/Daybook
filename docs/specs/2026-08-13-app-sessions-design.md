# App Sessions and Timeline Drill-Down — Design Spec

**Date:** 2026-08-13
**Status:** Approved for planning
**Extends:** `2026-08-13-timeline-refinement-design.md`

---

## 1. Goal

Stop fragmenting a single working session into slivers, make the app rows drill down to
hourly detail, and finish the two rough edges in the current build.

## 2. The fragmentation problem

Observed: WhatsApp on one evening recorded as `25s`, `33m`, `11s`, `6s`, `+1 more`; Dia as
four visible stretches plus `+5 more`. Switching to a browser for four minutes and back
produces two "sessions" where the user experienced one.

**Cause.** `AppUsageArchive.record` merges a new stretch into the previous one for the same
app only when the gap is under 120 seconds. Anything longer starts a new record, and the
merge is destructive — once written, the fact that a gap existed is gone.

## 3. The session model — raw recording, smart grouping

Two layers, deliberately separated.

**Layer 1: stretches (raw).** What the tracker records, unchanged in fidelity: one
continuous run of an app being frontmost, idle-trimmed. The 120-second record-time merge
is **removed** — merging at write time destroys the evidence grouping needs.

**Layer 2: sessions (derived).** Computed at display time by grouping consecutive stretches
of the same app. Because grouping is derived, changing the rule re-groups all existing
history instead of requiring it to be re-recorded.

### 3.1 Why each stretch ended

Grouping needs to know whether a gap was a quick detour or a real break, so each stretch
records why it closed:

```swift
enum UsageEndReason: String, Codable {
    case appSwitch    // another app came to the front
    case idle         // no input for longer than the idle cutoff
    case systemLock    // screen locked, machine slept, or power off
    case stillOpen    // flushed while running; the stretch continues
}
```

This is one enum on a struct we already write, so the cost is a few bytes per record.

### 3.2 The grouping rule

Two consecutive stretches of the same app join into one session when **any** of:

- **Quick detour** — the gap is under `sessionGap` (default 5 minutes, settable) and the
  earlier stretch ended by `.appSwitch`. You looked something up and came back.
- **Stepped away** — the gap is under `awayBridge` (default 15 minutes), the earlier
  stretch ended by `.idle`, and **no other app was used during the gap**. You left the desk
  and returned to the same work.

They stay separate when **any** of:

- The earlier stretch ended by `.systemLock`. A locked screen is an explicit boundary.
- Another app accumulated `sessionGap` or more of usage inside the gap. That is a genuine
  context switch, not a detour.
- The gap exceeds both bounds above.

This is the hybrid: a tunable gap from the display-time approach, plus attention awareness
from knowing why the stretch ended and what happened in between.

### 3.3 What is displayed

`Top apps` and `Earlier today` show **sessions**, not stretches. A session displays its
span, its total attended time (the sum of its stretches, excluding the gaps), and its
stretch count when greater than one — `10:55 pm – 11:58 pm · 36m over 5 visits`. The gap
time is never counted as usage; only the visible span includes it.

## 4. Background media — designed, deferred, with the reason

`kAudioHardwarePropertyProcessObjectList` is unavailable on macOS 13 (returns
`kAudioHardwareUnknownPropertyError`), so per-process audio attribution needs private API
and is out. `kAudioDevicePropertyDeviceIsRunningSomewhere` works but only says *something*
is playing, not what.

More importantly, **time is exclusive**: if Spotify's background playback counted as
Spotify usage while you worked in an editor, the day would sum to more than the day and
every app's share would be wrong. Background media therefore does not belong in app usage.

If it is wanted later, the honest shape is a separate "media playing" annotation drawn as a
thin strip beneath the timeline, driven by the system-wide audio flag plus a user-declared
list of media apps — an assertion by the user, not a detection. Not built now.

## 5. Drill-down

### 5.1 Top apps row expands to hourly stats

Clicking a row expands it to a small hour-by-hour bar strip for that app across the day:
one bar per hour of the timeline window, height proportional to minutes used in that hour,
filled in **the app's own timeline colour** so the row and the band agree. Beneath it, the
app's sessions with span and duration.

### 5.2 Earlier today: `+N more` expands

`+N more` becomes a button that reveals the remaining sessions for that app. State is a
`Set<String>` of bundle ids on the store, matching how Top apps expansion already works.

### 5.3 Date stepper wrapping

"Today" wraps to two lines in the narrow header. The button gets `.fixedSize()` and the
label a minimum width, so it can never wrap.

## 6. Verification

- Grouping tests: quick detour joins; a lock between stretches splits; another app's usage
  inside the gap splits; a long idle gap with nothing else used joins; gap time is excluded
  from the session total but included in its span.
- A migration test: records written before `endReason` existed decode with a default of
  `.appSwitch` and still group.
- Hourly bucketing test: minutes land in the right hour, including a stretch that spans an
  hour boundary.
- Snapshots for an expanded Top apps row and an expanded `+N more`.

## 7. Out of scope

Week views, editing records, and the media annotation in §4.
