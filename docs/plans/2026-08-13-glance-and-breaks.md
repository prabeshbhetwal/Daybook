# Menu Bar at a Glance and Break Reminders — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the menu bar popover so it answers the whole day without opening the dashboard, and add a break reminder driven by continuous computer use.

**Architecture:** The break logic is a pure `Core/BreakReminder.swift` over the usage stretches, so the interval rules are covered headlessly. The popover reuses the dashboard's day band and ranked rows rather than growing its own widgets.

**Tech Stack:** Swift 5, SwiftUI, `Canvas`, `UNUserNotificationCenter`.

**Spec:** `docs/specs/2026-08-13-glance-and-breaks-design.md`

## Global Constraints

- **No `@State`, no `@Observable`** — view state lives on `SessionStore`.
- **`Core/` never imports SwiftUI.**
- **No new TCC permissions.**
- macOS 13.0, `swiftc` via `build.sh`, `-parse-as-library`, `-warnings-as-errors`.
- Retired files move to `_trash/`.
- `./build.sh --test` passes at the end of every task. Currently 35 tests.
- Not a git repository — commit steps recorded but skipped.
- **No blocking behaviour.** The reminder never pauses a session and never takes focus.

---

## File Structure

| File | Change |
|---|---|
| `Sources/Core/BreakReminder.swift` | **New.** Continuous-work maths and due/not-due |
| `Sources/Core/PersistenceStore.swift` | Reminders on/off, work interval, break length |
| `Sources/App/SessionStore.swift` | Publishes the countdown; posts the notification |
| `Sources/Design/Components/Components.swift` | `WeekChart` empty state (G-1) |
| `Sources/Surfaces/PopoverView.swift` | Rebuilt per spec §3 |
| `Sources/SelfTest.swift` | Break maths and the G-1 regression |

---

### Task 1: Fix G-1 — the chart that renders nothing

The dashboard plan specified this and execution skipped it. Do it first so it cannot be
skipped again.

**Files:**
- Modify: `Sources/Design/Components/Components.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces: `WeekChart.hasData: Bool` (private) and a designed empty state.

- [ ] **Step 1: Write the failing test**

`WeekChart` is a view, so the regression is asserted on the data rule it uses:

```swift
private static func testWeekChartEmptyRule() -> [String] {
    var problems: [String] = []
    let day = Calendar.current.startOfDay(for: base)
    let empty = (0..<7).map {
        DayBar(id: day.addingTimeInterval(Double($0) * 86_400),
               label: "D", minutes: 0, isToday: $0 == 6)
    }
    expect(!DayBar.hasData(empty),
           "all-zero bars must report no data, or the chart renders 150pt of nothing",
           &problems)

    var oneDay = empty
    oneDay[3] = DayBar(id: oneDay[3].id, label: "D", minutes: 42, isToday: false)
    expect(DayBar.hasData(oneDay), "one non-zero day is data", &problems)
    return problems
}
```

- [ ] **Step 2: Run to verify it fails** — `type 'DayBar' has no member 'hasData'`.

- [ ] **Step 3: Implement**

```swift
extension DayBar {
    /// All-zero bars draw nothing while the frame keeps its height — the
    /// "150pt of dead space" defect. The caller must show an empty state instead.
    static func hasData(_ bars: [DayBar]) -> Bool {
        bars.contains { $0.minutes > 0 }
    }
}
```

and in `WeekChart`:

```swift
var body: some View {
    if DayBar.hasData(bars) {
        Chart(bars) { bar in
            BarMark(x: .value("Day", bar.id, unit: .day),
                    y: .value("Minutes", bar.minutes))
                .foregroundStyle(bar.isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                .cornerRadius(3)
        }
        .chartYScale(domain: 0...max(60, bars.map(\.minutes).max() ?? 60))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: bars.map(\.id)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow)).font(.caption2)
            }
        }
        .frame(height: height)
    } else {
        Text("No sessions this week yet.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(height: height, alignment: .leading)
    }
}
```

- [ ] **Step 4: Run tests** — expected 36/36.

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 2: `BreakReminder`

**Files:**
- Create: `Sources/Core/BreakReminder.swift`
- Modify: `Sources/Core/PersistenceStore.swift`, `Sources/Core/SessionState.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces:
  `struct BreakReminder { init(workInterval: TimeInterval, breakLength: TimeInterval); func workedContinuously(_ stretches: [AppUsageSession], now: Date) -> TimeInterval; func isDue(_ stretches: [AppUsageSession], now: Date, lastNotified: Date?) -> Bool; func timeUntilBreak(_ stretches: [AppUsageSession], now: Date) -> TimeInterval }`
- `PersistenceStore.remindersEnabled: Bool`, `.workInterval: TimeInterval`, `.breakLength: TimeInterval`.
- `FocusConstants.defaultWorkInterval = 50 * 60`, `.defaultBreakLength = 10 * 60`,
  `workIntervalOptions = [1500, 3000, 5400]`, `breakLengthOptions = [300, 600, 900]`.

- [ ] **Step 1: Write the failing test**

```swift
private static func testBreakReminder() -> [String] {
    var problems: [String] = []
    let now = base.addingTimeInterval(4 * 3_600)
    func stretch(_ fromMinAgo: Double, _ toMinAgo: Double) -> AppUsageSession {
        AppUsageSession(bundleID: "com.a", appName: "Alpha",
                        start: now.addingTimeInterval(-fromMinAgo * 60),
                        end: now.addingTimeInterval(-toMinAgo * 60))
    }
    let reminder = BreakReminder(workInterval: 50 * 60, breakLength: 10 * 60)

    // 55 minutes of work broken only by a 2 minute gap: still continuous.
    let continuous = [stretch(55, 30), stretch(28, 0)]
    expectClose(reminder.workedContinuously(continuous, now: now), 53 * 60,
                "gaps under the break length do not reset, and are not counted",
                &problems)
    expect(reminder.isDue(continuous, now: now, lastNotified: nil),
           "53 minutes of continuous work is due a break", &problems)

    // A 12 minute gap counts as the break: only the recent stretch remains.
    let rested = [stretch(90, 40), stretch(28, 0)]
    expectClose(reminder.workedContinuously(rested, now: now), 28 * 60,
                "a gap at or over the break length resets the clock", &problems)
    expect(!reminder.isDue(rested, now: now, lastNotified: nil),
           "28 minutes is not yet due", &problems)

    // Having just notified, it stays quiet until another interval passes.
    expect(!reminder.isDue(continuous, now: now,
                           lastNotified: now.addingTimeInterval(-600)),
           "no second nudge ten minutes after the first", &problems)
    expect(reminder.isDue(continuous, now: now,
                          lastNotified: now.addingTimeInterval(-60 * 60)),
           "an hour later, due again", &problems)

    expectClose(reminder.timeUntilBreak([stretch(20, 0)], now: now), 30 * 60,
                "twenty minutes in, thirty to go", &problems)
    expect(reminder.workedContinuously([], now: now) == 0,
           "no usage, no work", &problems)
    return problems
}
```

- [ ] **Step 2: Run to verify it fails** — `cannot find 'BreakReminder'`.

- [ ] **Step 3: Implement**

```swift
/// How long you have worked without a real break, from the usage stretches.
/// Pure so the interval rules are covered headlessly.
struct BreakReminder {
    let workInterval: TimeInterval
    let breakLength: TimeInterval

    /// Walks backwards from now, summing attended time, and stops at the first
    /// gap long enough to count as a break. Gap time is never added.
    func workedContinuously(_ stretches: [AppUsageSession], now: Date) -> TimeInterval {
        let ordered = stretches.sorted { $0.end > $1.end }
        var worked: TimeInterval = 0
        var boundary = now
        for stretch in ordered {
            let gap = boundary.timeIntervalSince(stretch.end)
            if gap >= breakLength { break }
            worked += stretch.seconds
            boundary = stretch.start
        }
        return worked
    }

    func timeUntilBreak(_ stretches: [AppUsageSession], now: Date) -> TimeInterval {
        max(0, workInterval - workedContinuously(stretches, now: now))
    }

    /// Due once the interval is reached, then quiet until another interval has
    /// passed — a nudge per interval, never a stream.
    func isDue(_ stretches: [AppUsageSession], now: Date, lastNotified: Date?) -> Bool {
        guard workedContinuously(stretches, now: now) >= workInterval else { return false }
        guard let lastNotified else { return true }
        return now.timeIntervalSince(lastNotified) >= workInterval
    }
}
```

- [ ] **Step 4: Add the preferences**

`remindersEnabled` stored inverted so a missing key reads as on, matching
`isUsageTrackingEnabled`. `workInterval` and `breakLength` fall back to the defaults when
the stored value is zero, matching `breakThreshold`.

- [ ] **Step 5: Run tests** — expected 37/37.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*

---

### Task 3: Wire the reminder

**Files:**
- Modify: `Sources/App/SessionStore.swift`, `Sources/App/AppCoordinator.swift`

**Interfaces:**
- Produces: `SessionStore.breakCountdown: TimeInterval`, `.isBreakDue: Bool`,
  `.remindersEnabled`, `.workInterval`, `.breakLength`, and
  `SessionStore.onBreakDue: ((TimeInterval, TimeInterval) -> Void)?`.

- [ ] **Step 1: Compute the countdown on refresh**

```swift
private func refreshBreak() {
    guard let usage, engine.store.remindersEnabled else {
        breakCountdown = 0
        isBreakDue = false
        return
    }
    let reminder = BreakReminder(workInterval: engine.store.workInterval,
                                 breakLength: engine.store.breakLength)
    let now = Date()
    breakCountdown = reminder.timeUntilBreak(usage.sessions, now: now)
    isBreakDue = reminder.isDue(usage.sessions, now: now, lastNotified: lastBreakNotice)

    if isBreakDue {
        lastBreakNotice = now
        onBreakDue?(reminder.workedContinuously(usage.sessions, now: now),
                    engine.store.breakLength)
    }
}
```

`lastBreakNotice` persists in `UserDefaults` so quitting the app does not re-trigger the
nudge on next launch.

- [ ] **Step 2: Post the notification from the coordinator**

```swift
store.onBreakDue = { [weak self] worked, breakLength in
    self?.notifier.postAwayResolution(
        title: "Time to stretch",
        body: "You have been working \(Int(worked / 60))m. "
            + "Take a \(Int(breakLength / 60)) minute break.")
}
```

The reminder never pauses the session and never takes focus. If notification authorisation
was denied, the popover countdown and the menu bar still say `Break due`, so the feature
degrades to surfaces we control.

- [ ] **Step 3: Verify** — set the work interval to 25 minutes, work for 25, confirm one
notification arrives and a second does not follow immediately.

- [ ] **Step 4: Commit** *(skipped — not a git repository)*

---

### Task 4: Rebuild the popover

**Files:**
- Modify: `Sources/Surfaces/PopoverView.swift`, `Sources/Design/Components/Components.swift`

- [ ] **Step 1: Header line**

`2h 28m today` leading, streak and tracked-total trailing, all in one row:

```swift
HStack(spacing: Tokens.Space.s) {
    Text(Tokens.duration(store.todayTotal)).foregroundStyle(.secondary)
    Spacer()
    StreakBadge(days: store.streak)
    Label(Tokens.duration(store.trackedToday), systemImage: "clock")
        .foregroundStyle(.tertiary)
}
.font(.callout)
```

- [ ] **Step 2: Replace the weekly chart with the compact day band**

`DayTimelineView` already exists and already has a designed empty state. Give it a
`compact` flag that drops the detail row and shrinks the band to 28pt, and use it here.
This is what removes the dead space for good: the band never renders an empty frame.

- [ ] **Step 3: Top apps, four rows**

Reuse `TopAppsList` with `apps: Array(store.rankedApps.prefix(4))` and no store, so rows
are not expandable in the popover — expansion belongs to the dashboard.

- [ ] **Step 4: Running and insight, one line each**

```swift
if let first = store.runningApps.first {
    let others = store.runningApps.count - 1
    Text("Now: \(first.appName)"
         + (first.openFor.map { " " + Tokens.preciseDuration($0) } ?? "")
         + (others > 0 ? " · +\(others) more" : ""))
        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
}
if let insight = store.insights.first {
    Text("\(insight.headline) — \(insight.detail)")
        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
}
```

- [ ] **Step 5: Settings row with the break controls**

One line collapsed: `Break in 12m` (or `Break due`), the existing per-app count picker, and
the tracking toggle. A `Breaks` disclosure reveals reminders on/off, work interval and
break length pickers.

- [ ] **Step 6: Remove the nested scroll region**

Delete the `ScrollView { AppHistorySection }.frame(maxHeight: 260)`. A bounded list of four
rows needs no scroll view, and the nested scroller is why the section read as empty.
`AppHistorySection` stays in the file for now but is no longer used by the popover; if
nothing else uses it by the end of the task, move it to `_trash/`.

- [ ] **Step 7: Verify** — `./build.sh --run`, open the popover and confirm: no dead space,
the band renders, four app rows with icons, the running line, the insight line, and the
break countdown.

- [ ] **Step 8: Commit** *(skipped — not a git repository)*

---

### Task 5: Verification

- [ ] **Step 1: Tests** — `./build.sh --test`, all passing, zero warnings.
- [ ] **Step 2: Snapshots** — `--snapshot`; confirm the popover has no blank regions in any
fixture, including `firstRun` where there is no data at all.
- [ ] **Step 3: Memory** — `footprint`, no regression against 17 MB.
- [ ] **Step 4: Break test** — set the interval to 25 minutes and confirm the notification
text names the real worked minutes and the configured break length.
- [ ] **Step 5: README** — document the glance popover and the reminder rules.
- [ ] **Step 6: Commit** *(skipped — not a git repository)*
