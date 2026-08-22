# FocusContinuity — Dashboard Design Spec

**Date:** 2026-08-12
**Status:** Approved for planning
**Supersedes:** §6.3 of `2026-08-12-focuscontinuity-ui-design.md` (the four-stat-tile Today view)

---

## 1. Goal

Turn the Today window from a sparse focus timer into the surface that answers
**"where did my day actually go, and was it any good?"** — comprehensive, icon-led,
and honest. Every number on it must be defensible; nothing is shown that the data
does not support.

## 2. What is broken today

Observed in a real screenshot, all three are computation bugs rather than layout bugs.

| # | Defect | Cause | Fix |
|---|---|---|---|
| B-1 | Weekly chart is blank, occupying 120pt of dead space | Every bar is 0, so Charts draws nothing | Y-domain floor plus a designed empty state |
| B-2 | "Focused today 42m" beside "Sessions today 0" and "Longest 0m" | `todayTotal` counts the in-flight session; the others read completed records only | Every figure counts the running session, consistently |
| B-3 | "Current streak 0 days" after 42 minutes of work | The streak needs ≥25 min of *completed* work | Today qualifies on completed + in-flight work |

B-3 matters beyond correctness: a streak that reads 0 while you are working is
demoralising at the exact moment the number exists to motivate.

## 3. Research

- **Rize leads with a day calendar, not charts.** The only concrete UI element its
  page names is a "Time Entry Review Panel", *"a context panel docked to your day
  calendar"*. The timeline is the primary surface; totals are secondary.
- **Nobody credible leads with a pie chart.** Timeline for change over time, bars for
  comparison; proportional wedges are hard to judge against each other.
- **The accuracy criticism that indicts our own tracker:** Screen Time *"registers an
  app as 'in use' whenever it occupies the foreground — even if you've switched away
  mentally"*. `AppUsageTracker` has exactly this flaw: leave an editor frontmost and
  go to lunch and it records an hour of deep work. See §7.
- **Reddit could not be read** — it refuses our crawler. The above comes from vendor
  documentation, dashboard-practice writing, and platform convention.

Sources: rize.io/features/automatic-time-tracking, rize.io/blog/rize-vs-rescuetime,
timingapp.com/blog/mac-time-tracking-apps, uxpin.com/studio/blog/dashboard-design-principles,
thoughtspot.com/data-trends/dashboard-design-examples-best-practices,
lifetips.alibaba.com/tech-efficiency/apples-screen-time-report-is-not-accurate-for-tracking

## 4. Design laws adopted

From the `impeccable` skill, restricted to what does not conflict with macOS HIG.
Its CSS-specific guidance (OKLCH palettes, `background-clip`, `border-left`) is
deliberately not applied: HIG requires semantic system colours and system materials.

- **No identical card grid, no hero-metric template.** The four stat tiles are removed.
  Each number moves beside the evidence for it.
- **No nested cards.** Top Apps and Running Now are rows with hairline separators —
  the native list idiom, and it lets icon, bar and number align on a real grid.
- **Spacing carries rhythm:** 4–8pt within a section, 24pt between.
- **Hierarchy through scale and weight**, one dominant numeral per column.
- **Colour is Restrained:** semantic neutrals, accent reserved for the live session and
  today's bar. The timeline is the sole exception — categorical data needs distinct
  hues (§6.2).

## 5. Architecture

All computation lives in `Core`, so every figure on screen is covered by the headless
self-test. The three defects above are computation bugs; a view test would not catch them.

```
Core/DashboardStats.swift        pure, injected clock, no SwiftUI
  timeline(for:)      -> [TimelineSegment]  usage clipped to the day
  rankedApps(for:)    -> [AppRank]          bundleID, total, share, longest
  runningNow()        -> [RunningApp]       launch date, open duration
  focusQuality(for:)  -> FocusQuality       work-type split, in-session share,
                                            switches per session
  insights(for:)      -> [Insight]          only where data supports it
App/AppIconProvider.swift        bundleID -> NSImage, memoised, symbol fallback
Surfaces/Dashboard/
  DashboardView.swift            two-column shell
  ActiveSessionPanel.swift       hero, left column
  DayTimelineView.swift          Canvas, left column
  TopAppsList.swift              rows, left column
  FocusQualityBar.swift          left column footer
  RunningNowList.swift           rows, right column
  InsightsList.swift             right column
```

`DashboardStats` is a struct built from `(SessionArchive, AppUsageArchive, now)`. Views
receive plain values; none of them reach into an archive.

### 5.1 Types

```swift
struct TimelineSegment: Identifiable, Equatable {
    let id: UUID
    let bundleID: String
    let appName: String
    let start: Date
    let end: Date
    let colorIndex: Int          // stable per app within the day, see 6.2
}

struct AppRank: Identifiable, Equatable {
    let bundleID: String
    let appName: String
    let total: TimeInterval
    let share: Double            // 0...1 of tracked time that day
    let longest: TimeInterval
    var id: String { bundleID }
}

struct RunningApp: Identifiable, Equatable {
    let bundleID: String
    let appName: String
    let launched: Date?          // nil for Finder and other login processes
    let openFor: TimeInterval?   // nil when `launched` is nil
    var id: String { bundleID }
}

struct FocusQuality: Equatable {
    let byWorkType: [(WorkType, TimeInterval)]
    let insideSessionShare: Double   // tracked time that fell inside a focus session
    let switchesPerSession: Double
}

struct Insight: Identifiable, Equatable {
    let id: String
    let headline: String
    let detail: String
    let symbolName: String
}
```

## 6. The screen

Two columns. Active left, Running right, as requested. Left column takes the remaining
width; right column is fixed at 240pt and never pushes the narrative around when an app
opens or quits.

### 6.1 Left column

**Active session.** The live SF Mono timer, then intent, work type and start time on one
secondary line, then Pause and Stop. The streak sits on the trailing edge of this block —
it belongs to the session, not to a tile. When idle, the timer is replaced by the intent
field and Start, and the line reads "Ready when you are".

**Today.** Section label with the day's tracked total as the one dominant numeral, and the
timeframe control (Today / Yesterday / Last 7 days) trailing. Below it the 24-hour
timeline (§6.2).

**Top apps.** Rows, hairline separators, no cards. Each row: 20pt app icon, name,
proportional bar, absolute time, share, and for the top row the longest unbroken stretch.
The section header carries "N sessions today" — the count next to its evidence.

**Focus quality.** A single line of work-type shares, then two figures: what percentage of
tracked time fell inside a focus session, and app switches per session. This is the
research's "reward quality, not volume" signal.

### 6.2 The day timeline

A SwiftUI `Canvas`, chosen over Swift Charts because a busy day is several hundred
segments and Canvas draws them in one immediate-mode pass. Charts would need a
`RectangleMark` per segment plus a fiddly time-of-day axis.

- The band spans an **adaptive window**, not a fixed 24 hours: from one hour before the
  first segment to one hour after the last, rounded outward to the hour, so an eight-hour
  day fills the width instead of sitting in a mostly empty 24-hour frame. The axis labels
  state the real hours, so the window is never ambiguous. A day with no data shows the
  empty state instead of an empty frame.
- Each segment is filled from a **fixed six-colour categorical ramp** assigned by rank
  (busiest app gets index 0), with everything beyond sixth place drawn in a neutral
  "Other". The ramp is built from system colours so it survives light, dark and Increase
  Contrast. Colour index is stable for the day being displayed.
- Focus sessions are drawn as brackets **beneath** the band, not as fills, so they read as
  annotation rather than as another category.
- Segments at least 28pt wide carry their app icon inline; narrower ones are colour only.
- Hover shows app name, clock range and duration. Reduce Motion disables the hover
  transition, not the hover itself.
- On "Last 7 days" the same band repeats once per day, stacked, with the weekday leading
  each row. Same visual grammar, no second chart type to learn.

### 6.3 Right column

**Running now.** Every app with `activationPolicy == .regular`, ordered by launch time,
each row: icon, name, how long it has been open, and the launch time beneath. Apps
without a launch date — Finder is the confirmed case — read "since login" rather than a
fabricated time.

**Insights.** Plain lines with a leading SF Symbol, no cards. Each insight is computed and
gated (§6.4).

### 6.4 Insight rules

An insight appears only when its data exists. Day one shows two, not six empty cards.

| Insight | Requires |
|---|---|
| Longest unbroken stretch | ≥1 usage session that day |
| Share of tracked time inside a focus session | ≥1 focus session and ≥1 usage session |
| App that most often ends a focus session | ≥3 focus sessions with a break-app pause |
| Deep-work share versus yesterday | usage on both days |
| Best focus window | ≥5 days with completed sessions |

No insight is prescriptive. They describe, they do not instruct.

## 7. Honest time — the idle problem

The research criticism applies to us directly. `AppUsageTracker` counts an app as in use
whenever it is frontmost, so an untouched machine still accrues time.

`CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .null)` reports
system idle seconds and requires **no** TCC permission. Verified 2026-08-12: `.hidSystemState`
returns true seconds-since-last-input and advances 1:1 with real time, while
`.combinedSessionState` returned 44221s on an actively used machine and is unusable — it reads a timestamp, not event
content. The tracker closes the open stretch after 3 minutes of no input and reopens on
the next input or activation, so an idle machine stops accruing time.

**This must be spiked before it is planned in.** If the API turns out to require Input
Monitoring on this OS version, the feature is dropped and the tracker keeps its current
behaviour, with the limitation stated in the README. The privacy promise outranks the
accuracy gain.

## 8. Empty and error states

| Situation | Behaviour |
|---|---|
| No usage recorded yet | "Tracking starts when you switch apps." Timeline hidden, not blank |
| No focus sessions today | Timeline shows usage without brackets; focus-quality line reads "No sessions yet today" |
| Weekly / timeline data all zero | Y-domain floor plus the empty message — never an empty frame (B-1) |
| App uninstalled since it was recorded | Generic SF Symbol icon, name retained from history |
| App with no launch date | "since login" |
| Tracking disabled | Timeline and Top Apps replaced by one line explaining tracking is off, with a control to enable it |

## 9. Verification

- `DashboardStats` is pure and gets headless tests: timeline clipping across midnight,
  ranked shares summing to 1, running-app duration with and without a launch date,
  work-type split, switches per session, and each insight's gate.
- Regression tests for B-2 and B-3 specifically: with a running session and no completed
  ones, today's total, session count, longest and streak must agree.
- `--snapshot` gains dashboard fixtures: empty day, typical day, heavy day (300+
  segments), tracking-disabled, and a day with no focus sessions — light and dark.
- Idle cost is re-measured; the timeline must not redraw more than once a second.

## 10. Out of scope

Per-app detail pages, editing or deleting usage records, week-over-week trend charts,
project and client attribution, and export. The dashboard reads; it does not edit.
