# Reporting Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` or `superpowers:executing-plans`.
> Execute every task test-first and commit after its acceptance checks pass.

**Goal:** Make goal pace, selected-day composition, period bars and live
dashboard data reconcile to one source of truth.

**Architecture:** Generalise focused-active intersection to arbitrary windows,
clip all day composition before grouping, and drive period bars only from exact
tracked seconds. Archive revision and change callbacks keep visible data fresh.

**Tech Stack:** Swift 5 language mode, SwiftUI, Charts, Foundation, macOS 13.

**Spec:** `docs/specs/2026-08-28-focuscontinuity-stabilisation-design.md`

## Global constraints

- Consume the v2 usage metadata from the honest-usage plan.
- Period bars show tracked time; the Work type donut remains separate.
- Historical pre-fix usage is preserved and visibly qualified.

---

### Task 1: Use one metric for current and historical goal pace

**Files:**
- Modify: `Sources/Core/FocusedActiveTime.swift`
- Modify: `Sources/Core/DailyGoal.swift`
- Modify: `Sources/App/SessionStore.swift`
- Modify: `Sources/App/AppCoordinator.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces `FocusedActiveTime.seconds(in:records:usage:running:runningWork:)`.
- `DailyGoal` consumes `usageAccurateFrom`.

- [ ] Add `testHistoricalPaceUsesFocusedActiveTime`: two session hours with one
  usage hour contribute one historical hour.
- [ ] Add pre/post-accuracy records; assert pre-epoch days are excluded and pace
  remains nil until three authoritative active days exist.
- [ ] Run the new tests and capture the incorrect raw-session median.
- [ ] Implement the DateInterval overload and delegate the day overload to it.
- [ ] Compute historical cutoffs through the same intersection algorithm used
  today and pass `metadata.accurateFrom` from every `DailyGoal` call site.
- [ ] Rebuild and run the full suite; commit as
  `fix: reconcile usual pace with goal progress`.

### Task 2: Clip day sessions and exclude rest from focus

**Files:**
- Modify: `Sources/Core/SessionDigest.swift`
- Modify: `Sources/Core/DashboardStats.swift`
- Modify: `Sources/App/SessionStore+History.swift`
- Modify: `Sources/App/SessionStore+Summary.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces `SessionDigest.entries(...day:...)`, `focusSpans(for:)`, and
  `runningThread(on:)`.

- [ ] Add a 23:30–00:30 regression: each day gets a clipped thirty-minute row
  and no bound outside that day.
- [ ] Add a break record and assert it creates rest but no focus span, bracket,
  session count or focus-quality work-type share.
- [ ] Run the tests and preserve the expected failures.
- [ ] Clip start, end, work credit and live spans to the requested calendar day
  before grouping.
- [ ] Filter focus-specific calculations with `countsAsFocus`; build brackets
  from clipped `focusSpans(for:)`.
- [ ] Rebuild and run the full suite; commit as
  `fix: keep day and focus figures within their scope`.

### Task 3: Make period bars and live dashboards reconcile

**Files:**
- Modify: `Sources/Core/PeriodStats.swift`
- Modify: `Sources/Core/AppUsage.swift`
- Modify: `Sources/Core/DashboardStats.swift`
- Modify: `Sources/App/SessionStore.swift`
- Modify: `Sources/App/SessionStore+History.swift`
- Modify: `Sources/App/SettingsModel.swift`
- Modify: `Sources/Surfaces/Settings/SettingsView.swift`
- Modify: `Sources/Surfaces/Dashboard/DashboardView.swift`
- Modify: `Sources/Surfaces/Dashboard/PeriodViews.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces `PeriodChartPoint`, `PeriodChartData.tracked(_:)`,
  `setDashboardVisible(_:)`, and `selectedDayIntegrityNote`.

- [ ] Add a two-hours-tracked/45-minutes-focus fixture and assert its period
  chart point and tracked average are exactly two hours.
- [ ] Replace a same-UUID checkpoint without changing count and assert the
  dashboard day slice rebuilds on archive revision.
- [ ] Assert each real archive mutation calls `onDidChange` once.
- [ ] Run the tests and capture the stale-cache and mixed-measure failures.
- [ ] Draw one tracked-time bar per day and label the card `Tracked by day`;
  retain the Work type donut unchanged.
- [ ] Invalidate day slices by archive revision. Refresh archive-derived
  dashboard data on changes only while the dashboard is visible.
- [ ] Show the pre-accuracy warning for affected days and add a read-only
  `Reveal data folder` action in Display settings.
- [ ] Run the full suite and temporary Day/Week/Month snapshots; commit as
  `fix: reconcile period charts and live usage`.
