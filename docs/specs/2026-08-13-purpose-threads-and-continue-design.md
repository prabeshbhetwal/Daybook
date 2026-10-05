# Purpose, Threads and Continue — Design

**Date:** 2026-08-13
**Slice:** 1 of 4 (A + B). Slices C (auto sessions) and D (learning) get their own
spec → plan → implementation cycles.

## Goal

Continue a focus session started earlier the same day, and record what else ran
alongside it. Segments of the same work link into one thread; the apps that were
not the main tool are surfaced as side apps rather than being lost or counted as
the session's subject.

To decide whether a stretch of time is focused work or something else, apps need
a **purpose** — an axis the codebase does not currently have.

## The three axes

The codebase already has two classifications. This adds a third. They are
orthogonal and collapsing any pair would break existing behaviour.

| Axis | Question it answers | Set by |
|---|---|---|
| `AppCategory` | Should this app pause my session? | Built-in map + user override |
| `WorkType` | What kind of work did I say this session was? | The user, per session |
| `AppPurpose` **(new)** | What is this app *for*? | Built-in map + behaviour |

`AppCategory` cannot serve as purpose: Terminal and Figma are both `.work` but
one is coding and the other design. `WorkType` cannot serve either: it records a
declaration by the user about a session, not a fact about a tool.

## AppPurpose

```swift
enum AppPurpose: String, Codable, CaseIterable {
    case coding, writingAI, design, communication, research, media, utility
}
```

`utility` is the default for anything unmapped — Finder, Settings, installers.
It is deliberately not `unknown`: an unmapped app is usually a utility, and a
name that describes the common case reads better in the UI than one that
describes the lookup failure.

**Focused purposes** are `coding`, `writingAI`, `design`. A stretch dominated by
these is focus work. `communication` is a meeting, `media` is not work, and
`research` is ambiguous on its own — it supports focus work but rarely
constitutes it.

### The ambiguous set

Browsers and general AI clients carry no fixed purpose. Chrome reading
documentation and Chrome playing a film are the same bundle identifier, and
without an Accessibility grant the app can never see the URL or window title.
That grant is out of scope permanently: the project promises no new TCC
permissions, and a feature that needs one is dropped rather than weakening the
promise.

They are resolved by behaviour instead. `PurposeMap` marks them `ambiguous(
active:passive:)` — Chrome is `research` when there is sustained input and
`media` when there is not.

## InputDensity

Verified on this machine before this design was written:

- `CGEventSource.counterForEventType(.hidSystemState, eventType:)` returns live
  cumulative counts per event type — `keyDown=32539`, `mouseMoved=502690` — and
  prompted for no permission. It reads counts, never event content, so it needs
  no Input Monitoring grant, the same reasoning that makes the existing idle
  timer permissible.
- The counters advance under real input: `+1 keyDown`, `+1 leftMouseDown`,
  `+141 mouseMoved` over six seconds.
- **Caveat, measured:** the counters also advance for synthetically posted
  events, while `secondsSinceLastEventType` does not. Density is therefore only
  read when the idle timer agrees somebody is present; otherwise it is discarded.

```swift
struct InputSample: Equatable {
    let at: Date
    let keys: UInt32
    let clicks: UInt32
    let scrolls: UInt32
    let idleSeconds: TimeInterval
}

enum InputActivity: String, Equatable { case absent, passive, active }
```

`InputDensity` keeps a ring of the last **15 samples** — five minutes at the
20-second cadence — so memory is constant regardless of how long the app runs.
Over that window it reports:

- `absent` — the idle timer is past its existing three-minute cutoff.
- `active` — at least **12 keystrokes per minute**, or at least **4 clicks per
  minute** with any keystrokes at all. Somebody is producing something.
- `passive` — present, but below both floors. Scrolling and watching.

Mouse movement is counted but never on its own qualifies as `active`: a film
plays happily while a hand rests on a trackpad.

All four numbers — cadence, ring size, key floor, click floor — live in
`FocusConstants` beside the existing constants, not scattered in the classifier.

## Sampling

Auto-detection in slice C needs samples while no session runs, which the current
architecture does not produce — nothing polls today. Slice 1 introduces the
sampler so the signal exists and is tested, at **20 seconds**, and:

- suspends on screen lock and on sleep, resuming on unlock and wake through the
  existing `EventMonitor` hooks;
- takes no sample when the idle timer already says the user is absent;
- writes nothing to disk. Samples live only in the bounded in-memory ring.

The README states *"Nothing polls."* That claim becomes false and will be
rewritten to say exactly what polls, how often, and when it is suspended. A
promise quietly broken is worse than a promise revised in the open.

## Threads

```swift
struct SessionRecord {
    // …existing fields…
    var threadID: UUID      // new
}
```

A first session gets a fresh `threadID`. Continuing an earlier session starts a
**new record sharing that thread**, rather than reopening the old one — each
contiguous stretch stays an honest record with a real start and end, and a
four-hour lunch never renders as worked time.

Legacy records decode with a fresh `threadID` per record via a custom
`init(from:)`, exactly as `AppUsageSession.endReason` already handles legacy
data. Old records therefore each become a single-segment thread, which is the
truth about them.

```swift
struct ThreadSummary: Identifiable, Equatable {
    let threadID: UUID
    let name: String
    let workType: WorkType
    let totalWorked: TimeInterval
    let segments: Int
    let firstStart: Date
    let lastEnd: Date
    let isRunning: Bool
}
```

`SessionArchive.threads(on:)` groups the day's records by `threadID`, newest
last-end first. The running session, if any, is included and marked — the same
rule `sessionsToday` and `longestToday` already follow, so the count on one
surface can never disagree with another.

## Side apps

Derived at display time from `AppUsageArchive`, never stored on the record.
Storing them would duplicate a truth that already exists and would go stale when
grouping rules change; the day-slice machinery in `DashboardStats` already
computes app attendance per day, and this reuses it.

For a thread, over the union of its segments' time ranges:

- **Primary app** — the app with the most attended time whose purpose is a
  focused purpose. If none qualifies, the most attended app overall.
- **Side apps** — every other app with at least 60 seconds attended, ranked by
  attended time.

```swift
struct ThreadApps: Equatable {
    let primary: AppRank?
    let side: [AppRank]
}
```

The 60-second floor keeps a two-second Finder detour out of the list. It lives
in `FocusConstants`.

## Continue

`SessionStore.continueThread(_ threadID: UUID)` starts a session carrying the
thread's `threadID`, `name` and `workType`. It does not bring any app forward:
the existing per-app Continue does that because the user asked for an app; here
the user asked for a *thread*, and stealing focus to an editor they may have
deliberately closed would be presumptuous.

If a session is already running, the existing rule applies unchanged — it is
archived first, then the new one starts.

## Menu bar surface

A new **Continue today** section in the popover, above the app history, listing
the day's threads newest first:

```
CONTINUE TODAY
  Refactor the parser            3h 10m · 3 segments
  [icon] Xcode  + Terminal, Chrome           [Continue]

  Design review                  45m · 1 segment
  [icon] Figma  + Dia                        [Continue]
```

Each row shows the thread name, total worked, segment count, the primary app's
real icon and name, and side app names. The running thread shows `· running`
instead of a Continue button.

The section is capped by the existing "recent sessions" preference rather than a
new setting, and it renders a designed empty state — *"No sessions yet today."*
A section that draws nothing is treated as a defect, as everywhere else in this
app.

## Dashboard

The session log gains thread grouping: segments of one thread nest under a
thread header carrying the total and segment count. Threads with a single
segment render exactly as rows do today, so nothing regresses for existing data.

## Testing

Headless tests against the injected clock, in `SelfTest.swift`, following the
existing numbering:

1. `PurposeMap` resolves static apps; unmapped bundles fall to `utility`.
2. Ambiguous apps resolve to their active purpose under `active` density and
   their passive purpose under `passive`.
3. `InputDensity` classifies absent / passive / active from synthetic sample
   sequences, and the ring stays bounded past its capacity.
4. Density is discarded when the idle timer reports absence, even if counters
   advanced — the synthetic-event caveat, pinned.
5. `threads(on:)` groups segments, sums worked time, orders by last end, and
   includes the running session.
6. Legacy `SessionRecord` JSON without `threadID` decodes, each record becoming
   its own thread.
7. `ThreadApps` picks a focused-purpose primary, falls back to most-attended,
   and drops apps under the 60-second floor.
8. `continueThread` carries thread, name and work type, and archives a running
   session first.

Snapshots via `--snapshot` for the popover Continue section: populated,
single-segment, running-thread and empty states, both appearances.

## Non-goals for this slice

- Auto-start, auto-pause and auto-end (slice C).
- Learning from corrections (slice D).
- Any Accessibility, Automation, Screen Recording or Input Monitoring grant —
  permanently out of scope.
- Reading window titles or URLs. Not possible without a grant, and the
  behavioural signal is the accepted substitute.

## On the AgentDB plugins

They cannot ship inside Daybook. They are MCP servers running in the
assistant's tooling; the app is a self-contained `swiftc` binary with no SPM, no
network access and no third-party dependencies, and adding any of those would
break constraints the project is built on.

The transferable idea — store observed patterns, score them, learn from
corrections — is implemented natively in slice D as a counter-based learner in
`UserDefaults`. It is pattern storage plus scoring, not machine learning, and
will not be described as machine learning.
