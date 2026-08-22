# Timeline Refinement and Memory Budget — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the day timeline readable by the hour and inspectable to the minute, show when each app's stretches happened, fill the dead space under Insights with app history, scale date navigation past two days, and cut memory from 49 MB to ≤35 MB.

**Architecture:** All new computation goes in `DashboardStats`, which gains a day slice computed once in `init` and shared by every query. The Canvas gains an hour grid, hover hit-testing and a selection-driven detail row. Icon caching rasterises at display size.

**Tech Stack:** Swift 5, SwiftUI `Canvas`, `onContinuousHover`, AppKit for icon rasterisation.

**Spec:** `docs/superpowers/specs/2026-08-13-timeline-refinement-design.md`

## Global Constraints

- **No `@State`, no `@Observable`** — no `SwiftUIMacros` plugin on this machine. View state lives on `SessionStore`.
- **`Core/` never imports SwiftUI.**
- **No new TCC permissions.**
- macOS 13.0 target, `swiftc` via `build.sh`, `-parse-as-library`, `-warnings-as-errors`.
- Semantic colours only, outside the existing timeline ramp.
- No cards for list rows; hairline separators.
- Retired files move to `_trash/`, never deleted.
- `./build.sh --test` passes at the end of every task. Currently 30 tests.
- Not a git repository — commit steps recorded but skipped.

---

## File Structure

| File | Change |
|---|---|
| `Sources/Core/DashboardStats.swift` | Day slice computed once; hour window snapping; stretch grouping; hover hit-test |
| `Sources/Design/DesignTokens.swift` | `preciseDuration`, `dayLabel` |
| `Sources/Design/Components/AppIcon.swift` | Rasterise at display size |
| `Sources/App/SessionStore.swift` | `selectedDay`, hover/selection state, expanded rows, earlier-today data |
| `Sources/Surfaces/Dashboard/DayTimelineView.swift` | Hour grid, hover, detail row |
| `Sources/Surfaces/Dashboard/DashboardSections.swift` | Session ranges, disclosure, Earlier today, date stepper |
| `Sources/SelfTest.swift` | Tests for all of the above |

---

### Task 1: Precise durations and the consistency defect

**Files:**
- Modify: `Sources/Design/DesignTokens.swift`, `Sources/Core/DashboardStats.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces: `Tokens.preciseDuration(_ seconds: TimeInterval) -> String`;
  `DashboardStats.focusQuality(for:runningSeconds:)` where a non-nil running session
  counts toward `sessionCount`.

- [ ] **Step 1: Write the failing test**

```swift
private static func testPreciseDurationAndSessionConsistency() -> [String] {
    var problems: [String] = []

    // D-2: sub-minute stretches must not render as "0m".
    expect(Tokens.preciseDuration(0) == "0s", "zero, got \(Tokens.preciseDuration(0))", &problems)
    expect(Tokens.preciseDuration(45) == "45s", "45s, got \(Tokens.preciseDuration(45))", &problems)
    expect(Tokens.preciseDuration(59) == "59s", "boundary below a minute", &problems)
    expect(Tokens.preciseDuration(60) == "1m", "boundary at a minute", &problems)
    expect(Tokens.preciseDuration(3_599) == "59m", "boundary below an hour", &problems)
    expect(Tokens.preciseDuration(3_600) == "1h", "boundary at an hour", &problems)
    expect(Tokens.preciseDuration(7_980) == "2h 13m", "hours and minutes", &problems)

    // D-1: "1 session today" and "No sessions yet today" must never disagree.
    let clock = Clock(base)
    let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
    let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
    let sessions = SessionArchive(directory: sessionDir, now: { clock.value })
    let dayStart = Calendar.current.startOfDay(for: base)
    usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                 start: dayStart.addingTimeInterval(9 * 3_600),
                                 end: dayStart.addingTimeInterval(10 * 3_600)))

    let stats = DashboardStats(sessions: sessions, usage: usage, now: { clock.value })
    let running = stats.focusQuality(for: base, runningSeconds: 2_520)
    expect(running.sessionCount == 1,
           "a running session counts, got \(running.sessionCount)", &problems)
    let idle = stats.focusQuality(for: base, runningSeconds: nil)
    expect(idle.sessionCount == 0, "no running session, no count", &problems)

    try? FileManager.default.removeItem(at: usageDir)
    try? FileManager.default.removeItem(at: sessionDir)
    return problems
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.sh --test`
Expected: `cannot find 'preciseDuration'`.

- [ ] **Step 3: Implement**

```swift
/// Sub-minute stretches are common in app usage, where `duration` floors to "0m".
static func preciseDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    if total < 60 { return "\(total)s" }
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
    return "\(minutes)m"
}
```

`focusQuality(for:runningSeconds:)` adds 1 to `sessionCount` when `runningSeconds != nil`,
and includes those seconds in the work-type total for the active type.

- [ ] **Step 4: Swap the call sites**

`TopAppsList`, `RunningNowList`, `AppHistoryRow`, the timeline detail row and every
insight use `preciseDuration`. `Tokens.duration` stays only for session-length figures
(the hero, the streak, focus totals).

- [ ] **Step 5: Run tests** — expected 31/31.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*

---

### Task 2: One day slice, hour snapping, stretch grouping

**Files:**
- Modify: `Sources/Core/DashboardStats.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces: `DashboardStats.stretches(for day: Date, bundleID: String) -> [TimelineSegment]`,
  `DashboardStats.span(for day: Date, bundleID: String) -> (start: Date, end: Date)?`,
  `DashboardStats.segment(at date: Date, on day: Date) -> TimelineSegment?`,
  and a `timelineWindow` that snaps to hours with a four-hour minimum.

- [ ] **Step 1: Write the failing test**

```swift
private static func testWindowSnappingAndStretches() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
    let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
    let dayStart = Calendar.current.startOfDay(for: base)

    // D-3: four minutes of data must not produce a one-hour axis.
    usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                 start: dayStart.addingTimeInterval(9 * 3_600 + 120),
                                 end: dayStart.addingTimeInterval(9 * 3_600 + 360)))
    let stats = DashboardStats(sessions: SessionArchive(directory: sessionDir,
                                                        now: { clock.value }),
                               usage: usage, now: { clock.value })
    guard let window = stats.timelineWindow(for: base) else {
        problems.append("a day with data must have a window")
        return problems
    }
    let span = window.end.timeIntervalSince(window.start)
    expect(span >= 4 * 3_600, "minimum four-hour span, got \(span / 3_600)h", &problems)
    let calendar = Calendar.current
    expect(calendar.component(.minute, from: window.start) == 0,
           "window start snaps to the hour", &problems)
    expect(calendar.component(.minute, from: window.end) == 0,
           "window end snaps to the hour", &problems)

    // Stretch grouping and span.
    usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                 start: dayStart.addingTimeInterval(16 * 3_600),
                                 end: dayStart.addingTimeInterval(16 * 3_600 + 600)))
    let stretches = stats.stretches(for: base, bundleID: "com.a")
    expect(stretches.count == 2, "two stretches, got \(stretches.count)", &problems)
    expect(stretches.first!.start < stretches.last!.start, "ordered by start", &problems)
    guard let appSpan = stats.span(for: base, bundleID: "com.a") else {
        problems.append("an app with usage must have a span")
        return problems
    }
    expectClose(appSpan.end.timeIntervalSince(appSpan.start), 7 * 3_600 + 480,
                "span runs first start to last end", &problems)

    // Hover hit-testing: a time inside a stretch finds it, a gap finds nothing.
    let hit = stats.segment(at: dayStart.addingTimeInterval(9 * 3_600 + 180), on: base)
    expect(hit?.bundleID == "com.a", "hover inside a stretch finds it", &problems)
    expect(stats.segment(at: dayStart.addingTimeInterval(12 * 3_600), on: base) == nil,
           "hover over a gap finds nothing", &problems)

    try? FileManager.default.removeItem(at: usageDir)
    try? FileManager.default.removeItem(at: sessionDir)
    return problems
}
```

- [ ] **Step 2: Run to verify it fails** — `cannot find 'stretches'`.

- [ ] **Step 3: Compute the day slice once**

The current code recomputes `clippedUsage(for:)` inside `trackedTotal`, `rankedApps`,
`timeline` and `focusQuality` — four full scans per refresh. Replace with a memoised slice:

```swift
private final class DaySliceCache {
    var day: Date?
    var slice: [TimelineSegment] = []
}
private let cache = DaySliceCache()

/// Clipped, coloured and ordered once; every query reads this.
private func slice(for day: Date) -> [TimelineSegment] {
    if let cached = cache.day, calendar.isDate(cached, inSameDayAs: day) {
        return cache.slice
    }
    let computed = buildSlice(for: day)
    cache.day = day
    cache.slice = computed
    return computed
}
```

`buildSlice` does the clip, the ranking and the colour assignment in one pass.

- [ ] **Step 4: Snap the window**

```swift
func timelineWindow(for day: Date) -> (start: Date, end: Date)? {
    let segments = slice(for: day)
    guard let first = segments.map(\.start).min(),
          let last = segments.map(\.end).max() else { return nil }
    let (dayStart, dayEnd) = bounds(of: day)

    var start = calendar.date(bySetting: .minute, value: 0, of: first) ?? first
    if start > first { start = start.addingTimeInterval(-3_600) }
    var end = calendar.date(bySetting: .minute, value: 0, of: last) ?? last
    if end < last { end = end.addingTimeInterval(3_600) }

    // A four-minute day must not render as one block on a one-hour axis.
    let minimum: TimeInterval = 4 * 3_600
    if end.timeIntervalSince(start) < minimum {
        end = start.addingTimeInterval(minimum)
    }
    // Never run past the day.
    if end > dayEnd {
        end = dayEnd
        start = max(dayStart, end.addingTimeInterval(-minimum))
    }
    return (max(dayStart, start), end)
}
```

- [ ] **Step 5: Add grouping and hit-testing**

```swift
func stretches(for day: Date, bundleID: String) -> [TimelineSegment] {
    slice(for: day).filter { $0.bundleID == bundleID }
}

func span(for day: Date, bundleID: String) -> (start: Date, end: Date)? {
    let mine = stretches(for: day, bundleID: bundleID)
    guard let first = mine.map(\.start).min(), let last = mine.map(\.end).max() else {
        return nil
    }
    return (first, last)
}

func segment(at date: Date, on day: Date) -> TimelineSegment? {
    slice(for: day).first { $0.start <= date && date < $0.end }
}
```

- [ ] **Step 6: Run tests** — expected 32/32.

- [ ] **Step 7: Commit** *(skipped — not a git repository)*

---

### Task 3: Icons rasterised at display size

**Files:**
- Modify: `Sources/Design/Components/AppIcon.swift`
- Test: manual measurement, recorded in Task 7

**Interfaces:**
- Produces: `AppIconProvider.icon(for bundleID: String, size: CGFloat) -> NSImage?`

- [ ] **Step 1: Measure the current cost**

Run the dashboard, then `footprint -p <pid> | head -8`.
Record the total and the `Malloc Small` line. Measured before this change: 49 MB total,
25 MB `Malloc Small`.

- [ ] **Step 2: Rasterise once, discard the original**

`NSWorkspace.icon(forFile:)` returns 32 representations up to 2048×2048 — about 53 MB
fully decoded, per icon. Draw it once at the size actually displayed and keep only that:

```swift
final class AppIconProvider {
    static let shared = AppIconProvider()
    private var cache: [String: NSImage?] = [:]

    /// Cached at the drawn size. Holding the original multi-representation image
    /// costs megabytes per icon; a 40px bitmap costs about 6 KB.
    func icon(for bundleID: String, size: CGFloat = 20) -> NSImage? {
        let key = "\(bundleID)@\(Int(size))"
        if let cached = cache[key] { return cached }

        let rasterised: NSImage? = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleID)
            .map { url -> NSImage in
                let source = NSWorkspace.shared.icon(forFile: url.path)
                let target = NSSize(width: size, height: size)
                let image = NSImage(size: target)
                image.lockFocus()
                source.draw(in: NSRect(origin: .zero, size: target),
                            from: .zero,
                            operation: .sourceOver,
                            fraction: 1)
                image.unlockFocus()
                return image
            }
        cache[key] = rasterised
        return rasterised
    }
}
```

`AppIcon` passes its own `size` through.

- [ ] **Step 3: Re-measure**

Run the dashboard again, wait 60 s, `footprint -p <pid> | head -8`.
Expected: total below 35 MB. **If it is not, report the real number rather than the
target** and note what still dominates.

- [ ] **Step 4: Run tests** — expected 32/32, no regressions.

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 4: Hour grid, hover and the detail row

**Files:**
- Modify: `Sources/Surfaces/Dashboard/DayTimelineView.swift`, `Sources/App/SessionStore.swift`

**Interfaces:**
- Consumes: `DashboardStats.segment(at:on:)`, `stretches(for:bundleID:)`.
- Produces: `SessionStore.hoveredSegment: TimelineSegment?`,
  `SessionStore.selectedSegment: TimelineSegment?`,
  `SessionStore.hoverTimeline(at fraction: Double)`, `selectTimeline(at fraction: Double)`.

- [ ] **Step 1: Add hover and selection state to the store**

```swift
@Published private(set) var hoveredSegment: TimelineSegment?
@Published private(set) var selectedSegment: TimelineSegment?

/// `fraction` is the pointer's position across the band, 0...1.
func hoverTimeline(at fraction: Double?) {
    guard let fraction, let window = timelineWindow, let usage else {
        hoveredSegment = nil
        return
    }
    let span = window.end.timeIntervalSince(window.start)
    let date = window.start.addingTimeInterval(span * min(max(fraction, 0), 1))
    hoveredSegment = DashboardStats(sessions: engine.archive, usage: usage)
        .segment(at: date, on: selectedDay)
}

func selectTimeline(at fraction: Double) {
    hoverTimeline(at: fraction)
    // Clicking the same segment closes it: the detail row is a toggle.
    selectedSegment = (selectedSegment?.id == hoveredSegment?.id) ? nil : hoveredSegment
}

func clearTimelineSelection() { selectedSegment = nil }
```

- [ ] **Step 2: Draw the hour grid**

Inside the `Canvas` closure, before the segments:

```swift
for hour in DayTimelineView.hourTicks(from: window.start, to: window.end) {
    let hx = x(hour)
    var line = Path()
    line.move(to: CGPoint(x: hx, y: 0))
    line.addLine(to: CGPoint(x: hx, y: bandHeight))
    context.stroke(line, with: .color(.secondary.opacity(0.18)), lineWidth: 0.5)
}
```

`hourTicks` returns every whole hour in the window. The axis labels every hour, or every
second hour when there would be more than twelve.

- [ ] **Step 3: Wire hover**

```swift
.onContinuousHover { phase in
    switch phase {
    case .active(let point):
        store.hoverTimeline(at: Double(point.x / max(1, bandWidth)))
    case .ended:
        store.hoverTimeline(at: nil)
    }
}
```

`bandWidth` comes from a `GeometryReader` wrapping the Canvas. The floating label renders
in an overlay anchored to the pointer's x, clamped so it never leaves the band.

- [ ] **Step 4: The detail row**

Beneath the axis, when `store.selectedSegment` is non-nil, list that app's stretches within
the selected segment's hour:

```swift
if let selected = store.selectedSegment {
    VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: Tokens.Space.s) {
            AppIcon(bundleID: selected.bundleID, size: 16)
            Text(selected.appName).font(.callout.weight(.medium))
            Spacer()
            Button("Close") { store.clearTimelineSelection() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        ForEach(store.stretchesInSelectedHour) { stretch in
            Text("\(Tokens.timeRange(stretch.start, stretch.end))  ·  "
                 + Tokens.preciseDuration(stretch.seconds))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    .padding(Tokens.Space.s)
    .background(.quaternary.opacity(0.25),
                in: RoundedRectangle(cornerRadius: Tokens.cardCorner))
}
```

- [ ] **Step 5: Verify** — `./build.sh --run`, hover the band and confirm the label tracks
the pointer and names the right app; click a segment and confirm the stretches listed fall
inside that hour; press Escape and confirm it closes.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*

---

### Task 5: Session ranges, Earlier today, date stepper

**Files:**
- Modify: `Sources/Surfaces/Dashboard/DashboardSections.swift`,
  `Sources/Surfaces/Dashboard/DashboardView.swift`, `Sources/App/SessionStore.swift`

**Interfaces:**
- Produces: `SessionStore.selectedDay: Date`, `stepDay(by: Int)`, `goToToday()`,
  `canStepBack: Bool`, `canStepForward: Bool`, `earlierToday: [AppDayHistory]`,
  `toggleExpanded(_ bundleID: String)`, `expandedApps: Set<String>`;
  `struct AppDayHistory: Identifiable { let bundleID, appName: String;
  let total: TimeInterval; let stretches: [TimelineSegment]; var id: String { bundleID } }`.

- [ ] **Step 1: Top apps gains a span and a disclosure**

Each row shows `Tokens.timeRange(span.start, span.end)` beneath the name. A disclosure
triangle toggles `store.toggleExpanded(app.bundleID)`; when expanded the row lists each
stretch as `range · preciseDuration`.

- [ ] **Step 2: Earlier today**

New view in `DashboardSections.swift`, placed in the right column **above** `InsightsList`:

```swift
struct EarlierTodayList: View {
    let apps: [AppDayHistory]

    var body: some View {
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                SectionHeader(title: "Earlier today", trailing: "\(apps.count)")
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    if index > 0 { Divider() }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Tokens.Space.s) {
                            AppIcon(bundleID: app.bundleID, size: 16)
                            Text(app.appName).font(.callout).lineLimit(1)
                            Spacer()
                            Text(Tokens.preciseDuration(app.total))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        // One line per stretch: an app used three times shows three.
                        ForEach(app.stretches) { stretch in
                            Text("\(Tokens.timeRange(stretch.start, stretch.end))  ·  "
                                 + Tokens.preciseDuration(stretch.seconds))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, Tokens.Space.xs)
                }
            }
        }
    }
}
```

`earlierToday` excludes apps currently running (they are in Running Now) and caps at
`menuSessionCount` apps so the column cannot grow without bound.

- [ ] **Step 3: Date stepper**

Replaces the Today/Yesterday picker in the day-section header:

```swift
HStack(spacing: Tokens.Space.xs) {
    Button { store.stepDay(by: -1) } label: { Image(systemName: "chevron.left") }
        .disabled(!store.canStepBack)
    Text(Tokens.dayLabel(store.selectedDay))
        .font(.callout.weight(.medium))
        .frame(minWidth: 110)
    Button { store.stepDay(by: 1) } label: { Image(systemName: "chevron.right") }
        .disabled(!store.canStepForward)
    if !store.isToday {
        Button("Today") { store.goToToday() }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .font(.caption)
    }
}
.buttonStyle(.borderless)
```

`Tokens.dayLabel` returns "Today", "Yesterday", or `EEE d MMM`. `canStepBack` is false once
the selected day is at or before the earliest record in either archive; `canStepForward` is
false on today.

- [ ] **Step 4: Test the bounds**

```swift
private static func testDayStepperBounds() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
    let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
    let dayStart = Calendar.current.startOfDay(for: base)
    usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                 start: dayStart.addingTimeInterval(-2 * 86_400),
                                 end: dayStart.addingTimeInterval(-2 * 86_400 + 3_600)))

    let stats = DashboardStats(sessions: SessionArchive(directory: sessionDir,
                                                        now: { clock.value }),
                               usage: usage, now: { clock.value })
    guard let earliest = stats.earliestRecordedDay() else {
        problems.append("an archive with data must report an earliest day")
        return problems
    }
    expect(Calendar.current.isDate(earliest, inSameDayAs: base.addingTimeInterval(-2 * 86_400)),
           "earliest day is two days back", &problems)

    try? FileManager.default.removeItem(at: usageDir)
    try? FileManager.default.removeItem(at: sessionDir)
    return problems
}
```

- [ ] **Step 5: Run tests** — expected 33/33.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*

---

### Task 6: Snapshots and fixtures

**Files:**
- Modify: `Sources/Surfaces/GalleryView.swift`, `Sources/Surfaces/Snapshotter.swift`

- [ ] **Step 1: Add fixtures**

`dashboardShortDay` (four minutes total, to prove D-3's minimum span),
`dashboardDenseDay` (300 segments across twelve hours),
`dashboardYesterday` (navigated back one day).

- [ ] **Step 2: Render and inspect**

Run: `./build.sh && ./FocusContinuity.app/Contents/MacOS/FocusContinuity --snapshot ./shots`
Expected: the short day fills a four-hour axis rather than one block; the dense day draws
without visual mush; hour gridlines are visible in both appearances.

- [ ] **Step 3: Commit** *(skipped — not a git repository)*

---

### Task 7: Verification

- [ ] **Step 1: Tests** — `./build.sh --test`, all passing, zero warnings.

- [ ] **Step 2: Memory, before and after**

Dashboard open, 60 s idle, `footprint -p <pid> | head -8`.
Baseline: 49 MB total, 25 MB `Malloc Small`. Target: ≤35 MB.
**Report the measured number whether or not it meets the target.**

- [ ] **Step 3: Idle CPU** — 0.0% with no session running; the timeline must not redraw
except on hover or refresh.

- [ ] **Step 4: Manual pass** — hover names the right app; click expands the right hour;
Escape closes; the date stepper stops at the earliest record and at today; Earlier today
lists an app used twice as two lines.

- [ ] **Step 5: Update the README** — timeline interaction, date navigation, and the icon
rasterisation note.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*
