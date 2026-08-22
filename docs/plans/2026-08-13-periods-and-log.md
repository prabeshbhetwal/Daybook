# Day / Week / Month and the Session Log — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the dashboard answer "how was my week and month", and give sessions a chronological log with time ranges, apps and durations.

**Architecture:** A new pure `Core/PeriodStats.swift` composes the existing `DashboardStats` once per day in the period, so a day's numbers have one definition used everywhere. Three new view files keep each surface focused.

**Tech Stack:** Swift 5, SwiftUI, Swift Charts for the period bars, `Canvas` for the day timeline.

**Spec:** `docs/superpowers/specs/2026-08-13-periods-and-log-design.md`

## Global Constraints

- **No `@State`, no `@Observable`** — view state lives on `SessionStore`.
- **`Core/` never imports SwiftUI.**
- **No new TCC permissions.**
- macOS 13.0, `swiftc` via `build.sh`, `-parse-as-library`, `-warnings-as-errors`.
- Semantic colours plus the existing timeline ramp only.
- **No identical card grids.** The stat row is one row of varying-width figures.
- Retired files move to `_trash/`.
- `./build.sh --test` passes at the end of every task. Currently 40 tests.
- Not a git repository — commit steps recorded but skipped.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/Core/PeriodStats.swift` | **New.** Period bounds, per-day rollups, averages, flattened log |
| `Sources/Core/PersistenceStore.swift` | Remembers the selected period |
| `Sources/App/SessionStore.swift` | Publishes `period`, `periodBars`, `periodLog`, `periodSummary` |
| `Sources/Surfaces/Dashboard/PeriodChart.swift` | **New.** Stacked bars, average line, legend |
| `Sources/Surfaces/Dashboard/SessionLogList.swift` | **New.** Grouped chronological rows |
| `Sources/Surfaces/Dashboard/StatRow.swift` | **New.** Varying-width figure row |
| `Sources/Surfaces/Dashboard/DashboardView.swift` | New left-column order |
| `Sources/SelfTest.swift` | Period, average, log and grouping tests |

---

### Task 1: `PeriodStats`

**Files:**
- Create: `Sources/Core/PeriodStats.swift`
- Modify: `Sources/Core/SessionState.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces:
  `enum TrackingPeriod: String, Codable, CaseIterable { case day, week, month; var displayName: String }`
  `struct PeriodDay: Identifiable, Equatable { let date: Date; let tracked: TimeInterval; let byWorkType: [WorkTypeShare]; var id: Date { date } }`
  `struct PeriodSummary: Equatable { let tracked: TimeInterval; let activeDays: Int; let totalDays: Int; let averagePerActiveDay: TimeInterval; let longest: AppSession? }`
  `struct LogEntry: Identifiable, Equatable { let session: AppSession; let day: Date; var id: String { session.id } }`
  `struct PeriodStats { init(sessions: SessionArchive, usage: AppUsageArchive, calendar: Calendar, now: @escaping () -> Date); func bounds(for period: TrackingPeriod, containing day: Date) -> (start: Date, end: Date); func days(for period: TrackingPeriod, containing day: Date) -> [PeriodDay]; func summary(for period: TrackingPeriod, containing day: Date) -> PeriodSummary; func log(for period: TrackingPeriod, containing day: Date) -> [LogEntry] }`

- [ ] **Step 1: Write the failing test**

```swift
private static func testPeriodStats() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
    let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
    let sessions = SessionArchive(directory: sessionDir, now: { clock.value })
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: base)

    // Two active days in the week: 2h and 1h. The rest idle.
    func use(_ daysAgo: Int, hours: Double) {
        guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { return }
        let start = day.addingTimeInterval(10 * 3_600)
        usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                     start: start,
                                     end: start.addingTimeInterval(hours * 3_600)))
    }
    use(0, hours: 2)
    use(1, hours: 1)

    let stats = PeriodStats(sessions: sessions, usage: usage, now: { clock.value })

    let week = stats.days(for: .week, containing: base)
    expect(week.count == 7, "a week has seven days, got \(week.count)", &problems)
    expectClose(week.reduce(0) { $0 + $1.tracked }, 3 * 3_600,
                "the week's bars sum to the tracked total", &problems)

    let summary = stats.summary(for: .week, containing: base)
    expect(summary.activeDays == 2, "two active days, got \(summary.activeDays)", &problems)
    // The average must divide by ACTIVE days, not calendar days, or it is
    // meaningless in any week containing a weekend.
    expectClose(summary.averagePerActiveDay, 1.5 * 3_600,
                "average is over active days", &problems)
    expectClose(summary.tracked, 3 * 3_600, "period total", &problems)

    let month = stats.days(for: .month, containing: base)
    expect(month.count >= 28 && month.count <= 31,
           "a month has 28 to 31 days, got \(month.count)", &problems)

    // Day period is a single day.
    expect(stats.days(for: .day, containing: base).count == 1, "day is one day", &problems)

    // An empty period is empty, not crashing or NaN.
    let emptyStats = PeriodStats(sessions: SessionArchive(directory: scratchDirectory(),
                                                          now: { clock.value }),
                                 usage: AppUsageArchive(directory: scratchDirectory(),
                                                        now: { clock.value }),
                                 now: { clock.value })
    let emptySummary = emptyStats.summary(for: .week, containing: base)
    expect(emptySummary.activeDays == 0, "no active days", &problems)
    expectClose(emptySummary.averagePerActiveDay, 0, "average is 0, never NaN", &problems)

    try? FileManager.default.removeItem(at: usageDir)
    try? FileManager.default.removeItem(at: sessionDir)
    return problems
}

private static func testPeriodLog() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
    let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: base)

    // Today: two visits to one app, four minutes apart — one session, two visits.
    let morning = today.addingTimeInterval(10 * 3_600)
    usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                 start: morning, end: morning.addingTimeInterval(1_200)))
    usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                 start: morning.addingTimeInterval(1_440),
                                 end: morning.addingTimeInterval(2_400)))
    // Yesterday: one session.
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
        let start = yesterday.addingTimeInterval(9 * 3_600)
        usage.record(AppUsageSession(bundleID: "com.b", appName: "Beta",
                                     start: start, end: start.addingTimeInterval(1_800)))
    }

    let stats = PeriodStats(sessions: SessionArchive(directory: sessionDir,
                                                     now: { clock.value }),
                            usage: usage, now: { clock.value })
    let log = stats.log(for: .week, containing: base)
    expect(log.count == 2, "two grouped sessions across the week, got \(log.count)",
           &problems)
    expect(log.first?.day ?? .distantPast > (log.last?.day ?? .distantFuture),
           "the log is reverse chronological", &problems)
    expect(log.first?.session.visits == 2,
           "the two visits group into one session, got \(log.first?.session.visits ?? -1)",
           &problems)
    expectClose(log.first?.session.attended ?? -1, 2_160,
                "attended excludes the four-minute gap", &problems)

    // Day period sees only today.
    expect(stats.log(for: .day, containing: base).count == 1, "day sees one session",
           &problems)

    try? FileManager.default.removeItem(at: usageDir)
    try? FileManager.default.removeItem(at: sessionDir)
    return problems
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `./build.sh --test`
Expected: `cannot find 'PeriodStats' in scope`.

- [ ] **Step 3: Implement**

```swift
enum TrackingPeriod: String, Codable, CaseIterable {
    case day, week, month
    var displayName: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }
}

struct PeriodStats {
    private let sessions: SessionArchive
    private let usage: AppUsageArchive
    private let calendar: Calendar
    private let now: () -> Date

    func bounds(for period: TrackingPeriod, containing day: Date) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: day)
        switch period {
        case .day:
            return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: start)
            return (interval?.start ?? start, interval?.end ?? start)
        case .month:
            let interval = calendar.dateInterval(of: .month, for: start)
            return (interval?.start ?? start, interval?.end ?? start)
        }
    }

    /// One entry per calendar day in the period, so a bar chart has a bar for
    /// every day including the idle ones.
    func days(for period: TrackingPeriod, containing day: Date) -> [PeriodDay] {
        let (start, end) = bounds(for: period, containing: day)
        var result: [PeriodDay] = []
        var cursor = start
        while cursor < end && result.count < 40 {
            // Composed, not reimplemented: a day's numbers have one definition.
            let stats = DashboardStats(sessions: sessions, usage: usage,
                                       calendar: calendar, now: now)
            result.append(PeriodDay(date: cursor,
                                    tracked: stats.trackedTotal(for: cursor),
                                    byWorkType: stats.focusQuality(for: cursor).byWorkType))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end
        }
        return result
    }

    func summary(for period: TrackingPeriod, containing day: Date) -> PeriodSummary {
        let days = self.days(for: period, containing: day)
        let active = days.filter { $0.tracked > 0 }
        let tracked = days.reduce(0) { $0 + $1.tracked }
        let entries = log(for: period, containing: day)
        return PeriodSummary(
            tracked: tracked,
            activeDays: active.count,
            totalDays: days.count,
            // Divide by ACTIVE days: averaging a five-day week over seven
            // understates every working day by nearly a third.
            averagePerActiveDay: active.isEmpty ? 0 : tracked / Double(active.count),
            longest: entries.map(\.session).max { $0.attended < $1.attended })
    }

    func log(for period: TrackingPeriod, containing day: Date) -> [LogEntry] {
        let (start, end) = bounds(for: period, containing: day)
        var entries: [LogEntry] = []
        var cursor = start
        while cursor < end && entries.count < 500 {
            let stats = DashboardStats(sessions: sessions, usage: usage,
                                       calendar: calendar, now: now)
            for rank in stats.rankedApps(for: cursor) {
                for session in stats.sessions(for: cursor, bundleID: rank.bundleID) {
                    entries.append(LogEntry(session: session, day: cursor))
                }
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end
        }
        return entries.sorted { $0.session.start > $1.session.start }
    }
}
```

- [ ] **Step 4: Persist the period**

`PersistenceStore.trackingPeriod: TrackingPeriod` backed by a string key, defaulting to
`.day` when absent or unrecognised.

- [ ] **Step 5: Run tests** — expected 42/42.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*

---

### Task 2: Publish through the store

**Files:**
- Modify: `Sources/App/SessionStore.swift`

**Interfaces:**
- Produces: `SessionStore.period: TrackingPeriod` (settable), `.periodDays: [PeriodDay]`,
  `.periodSummary: PeriodSummary`, `.periodLog: [LogEntry]`.

- [ ] **Step 1: Add the published values and the setter**

```swift
@Published private(set) var periodDays: [PeriodDay] = []
@Published private(set) var periodLog: [LogEntry] = []
@Published private(set) var periodSummary = PeriodSummary(tracked: 0, activeDays: 0,
                                                          totalDays: 0,
                                                          averagePerActiveDay: 0,
                                                          longest: nil)

var period: TrackingPeriod {
    get { engine.store.trackingPeriod }
    set {
        engine.store.trackingPeriod = newValue
        refreshDashboard()
    }
}
```

- [ ] **Step 2: Compute once per refresh**

In `refreshDashboard`, after the day figures:

```swift
// A month is 31 day-slices, each one pass over the usage array. That runs on
// selection and on archive change, never per frame.
let periodStats = PeriodStats(sessions: engine.archive, usage: usage)
periodDays = periodStats.days(for: period, containing: day)
periodLog = periodStats.log(for: period, containing: day)
periodSummary = periodStats.summary(for: period, containing: day)
```

- [ ] **Step 3: Verify** — `./build.sh --test`, expected 42/42.

- [ ] **Step 4: Commit** *(skipped — not a git repository)*

---

### Task 3: `StatRow`

**Files:**
- Create: `Sources/Surfaces/Dashboard/StatRow.swift`

- [ ] **Step 1: Build the varying-width row**

Not four equal cards — that was the identical-card-grid failure. One row, each figure sized
to its content, label small and secondary above:

```swift
struct StatFigure: Identifiable, Equatable {
    let label: String
    let value: String
    var detail: String?
    var id: String { label }
}

struct StatRow: View {
    let figures: [StatFigure]

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.xl) {
            ForEach(figures) { figure in
                VStack(alignment: .leading, spacing: 2) {
                    Text(figure.label.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(0.5)
                        .foregroundStyle(.tertiary)
                    Text(figure.value)
                        .font(.title3.weight(.semibold).monospacedDigit())
                    if let detail = figure.detail {
                        Text(detail).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 0)
        }
    }
}
```

- [ ] **Step 2: Verify** — build succeeds, zero warnings.

- [ ] **Step 3: Commit** *(skipped — not a git repository)*

---

### Task 4: `PeriodChart`

**Files:**
- Create: `Sources/Surfaces/Dashboard/PeriodChart.swift`

- [ ] **Step 1: Stacked bars with an average line**

The average line is what turns bars into a judgement; without it they are just bars.

```swift
struct PeriodChart: View {
    let days: [PeriodDay]
    let average: TimeInterval
    var height: CGFloat = 140

    var body: some View {
        if days.allSatisfy({ $0.tracked == 0 }) {
            Text("Nothing tracked in this period yet.")
                .font(.callout).foregroundStyle(.secondary)
                .frame(height: height, alignment: .leading)
        } else {
            Chart {
                ForEach(days) { day in
                    ForEach(day.byWorkType) { share in
                        BarMark(x: .value("Day", day.date, unit: .day),
                                y: .value("Minutes", share.seconds / 60))
                            .foregroundStyle(by: .value("Type", share.workType.displayName))
                            .cornerRadius(2)
                    }
                    // A day with usage but no session still needs a bar.
                    if day.byWorkType.isEmpty && day.tracked > 0 {
                        BarMark(x: .value("Day", day.date, unit: .day),
                                y: .value("Minutes", day.tracked / 60))
                            .foregroundStyle(.quaternary)
                            .cornerRadius(2)
                    }
                }
                if average > 0 {
                    RuleMark(y: .value("Average", average / 60))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .trailing, alignment: .leading) {
                            Text("avg").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
            .frame(height: height)
        }
    }
}
```

Swift Charts supplies the legend from the `foregroundStyle(by:)` series, which is the
colour-with-totals legend the references use.

- [ ] **Step 2: Verify** — build, then `--snapshot` and confirm bars, the dashed average
and the legend all render in both appearances.

- [ ] **Step 3: Commit** *(skipped — not a git repository)*

---

### Task 5: `SessionLogList`

**Files:**
- Create: `Sources/Surfaces/Dashboard/SessionLogList.swift`

- [ ] **Step 1: Grouped chronological rows**

```swift
struct SessionLogList: View {
    let entries: [LogEntry]
    let dayTotals: [Date: TimeInterval]

    var body: some View {
        if entries.isEmpty {
            Text("No sessions in this period yet.")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                SectionHeader(title: "Session log", trailing: "\(entries.count)")
                ForEach(groupedDays, id: \.self) { day in
                    HStack {
                        Text(Tokens.dayLabel(day)).font(.callout.weight(.medium))
                        Spacer()
                        Text(Tokens.preciseDuration(dayTotals[day] ?? 0))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, Tokens.Space.xs)
                    ForEach(entries.filter { $0.day == day }) { entry in
                        Divider()
                        row(entry)
                    }
                }
            }
        }
    }

    private var groupedDays: [Date] {
        var seen: [Date] = []
        for entry in entries where !seen.contains(entry.day) { seen.append(entry.day) }
        return seen
    }

    private func row(_ entry: LogEntry) -> some View {
        HStack(spacing: Tokens.Space.m) {
            Text(Tokens.timeRange(entry.session.start, entry.session.end))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            AppIcon(bundleID: entry.session.bundleID, size: 16)
            Text(entry.session.appName).font(.callout).lineLimit(1)
            if entry.session.visits > 1 {
                // Where the grouping work becomes visible to the reader.
                Text("· \(entry.session.visits) visits")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Text(Tokens.preciseDuration(entry.session.attended))
                .font(.callout.monospacedDigit())
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 2: Verify** — build, snapshot, confirm day headers carry totals and `visits`
appears only above one.

- [ ] **Step 3: Commit** *(skipped — not a git repository)*

---

### Task 6: Wire the dashboard

**Files:**
- Modify: `Sources/Surfaces/Dashboard/DashboardView.swift`

- [ ] **Step 1: New left-column order**

active session → stat row → period switch → chart → session log → top apps → focus quality.
Top apps and focus quality move below the log: the log is the evidence, the rankings are
the summary.

- [ ] **Step 2: Period switch**

```swift
Picker("Period", selection: periodBinding) {
    ForEach(TrackingPeriod.allCases, id: \.self) { Text($0.displayName).tag($0) }
}
.pickerStyle(.segmented)
.labelsHidden()
.frame(width: 200)
```

The date stepper stays beside it and moves within the selected period.

- [ ] **Step 3: Chart switches on period**

`.day` renders `DayTimelineView`; `.week` and `.month` render `PeriodChart` with
`store.periodDays` and `store.periodSummary.averagePerActiveDay`.

- [ ] **Step 4: Stat row content**

Day: tracked, sessions, average session, longest.
Week and Month: tracked, `N of M` active days, average per active day, longest session with
its app name.

- [ ] **Step 5: Verify** — `./build.sh --run`; switch Day / Week / Month and confirm the
chart, stat row and log all change together.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*

---

### Task 7: Verification

- [x] **Step 1: Tests** — `./build.sh --test`, all passing, zero warnings.
- [x] **Step 2: Snapshots** — `--snapshot`; a week and a month fixture in both appearances,
plus an empty period.
- [x] **Step 3: Memory** — `footprint` after switching to Month and back. A month is 31
day-slices; confirm no regression against 20 MB.
- [x] **Step 4: README** — periods, the average-over-active-days rule, and the log.
- [x] **Step 5: Commit** *(skipped — not a git repository)*

**Result.** 42/42 pass, zero warnings. Snapshots rendered for week and month with history
and for an empty week, both appearances. Three defects found and fixed in verification:
work-type colours reshuffled between periods (Swift Charts assigns by first-seen order —
now a fixed scale); the chart's x-axis spanned only days with data, so a month showed 7
slots instead of 31 (now an explicit domain over the period bounds); and `Longest session`
read `0s` for an empty period (now `—`). Memory: Month settled at **33 MB** against 17 MB
for Day, over the 20 MB target — `days`/`log`/`dayTotals`/`summary` each re-walked the
period and the single-slot day cache thrashed, 93 passes over the usage array per refresh.
`PeriodStats.rollup` now produces all four from one walk; Month and Day both idle at
**17 MB**. Test 42 pins the rollup against the piecewise accessors.
