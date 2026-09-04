# Elided Timeline and Clearer Insights — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop spending the timeline on empty time, make insights state what they measure, and drop permanently-running processes from Running Now.

**Architecture:** A new pure `Core/TimelineLayout.swift` owns clustering, width allocation and the two coordinate mappings. The view asks it where things go and computes no positions itself, so the band, the axis and the pointer cannot drift apart.

**Tech Stack:** Swift 5, SwiftUI `Canvas`.

**Spec:** `docs/specs/2026-08-13-elided-timeline-design.md`

## Global Constraints

- **No `@State`, no `@Observable`** — view state lives on `SessionStore`.
- **`Core/` never imports SwiftUI.**
- **No new TCC permissions.**
- macOS 13.0, `swiftc` via `build.sh`, `-parse-as-library`, `-warnings-as-errors`.
- Retired files move to `_trash/`.
- `./build.sh --test` passes at the end of every task. Currently 37 tests.
- Not a git repository — commit steps recorded but skipped.

---

## File Structure

| File | Change |
|---|---|
| `Sources/Core/TimelineLayout.swift` | **New.** Clusters, widths, `fraction(for:)`, `date(at:)` |
| `Sources/Core/DashboardStats.swift` | Serves the layout; insight copy rewritten |
| `Sources/App/SessionStore.swift` | Publishes the layout; hover goes through it |
| `Sources/Surfaces/Dashboard/DayTimelineView.swift` | Draws clusters and separators |
| `Sources/Surfaces/Dashboard/DashboardSections.swift` | Running Now filter |
| `Sources/SelfTest.swift` | Clustering, mapping, copy and filter tests |

---

### Task 1: `TimelineLayout`

**Files:**
- Create: `Sources/Core/TimelineLayout.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces:
  `struct TimelineCluster: Identifiable, Equatable { let start, end: Date; let xStart, xEnd: Double; var id: Date { start }; var duration: TimeInterval }`
  `struct TimelineGap: Identifiable, Equatable { let start, end: Date; let xStart, xEnd: Double; var id: Date { start }; var duration: TimeInterval }`
  `struct TimelineLayout { init(segments: [TimelineSegment], gapThreshold: TimeInterval, separatorShare: Double, minimumClusterShare: Double); let clusters: [TimelineCluster]; let gaps: [TimelineGap]; func fraction(for date: Date) -> Double?; func date(at fraction: Double) -> Date?; func hourTicks() -> [Date] }`

- [ ] **Step 1: Write the failing test**

```swift
private static func testTimelineLayout() -> [String] {
    var problems: [String] = []
    let dayStart = Calendar.current.startOfDay(for: base)
    func seg(_ fromMin: Double, _ toMin: Double) -> TimelineSegment {
        TimelineSegment(id: UUID(), bundleID: "com.a", appName: "Alpha",
                        start: dayStart.addingTimeInterval(fromMin * 60),
                        end: dayStart.addingTimeInterval(toMin * 60),
                        colorIndex: 0)
    }

    // 0–30 min, then nothing for three hours, then 210–240 min.
    let layout = TimelineLayout(segments: [seg(0, 30), seg(210, 240)],
                                gapThreshold: 20 * 60)
    expect(layout.clusters.count == 2, "two clusters, got \(layout.clusters.count)", &problems)
    expect(layout.gaps.count == 1, "one elided gap, got \(layout.gaps.count)", &problems)
    expectClose(layout.gaps.first?.duration ?? -1, 180 * 60,
                "the gap is three hours", &problems)

    // Equal-duration clusters get equal width, and the whole band is used.
    let first = layout.clusters[0], second = layout.clusters[1]
    expectClose(first.xEnd - first.xStart, second.xEnd - second.xStart,
                "equal durations, equal widths", &problems)
    expectClose(layout.clusters.last?.xEnd ?? -1, 1.0, "the band is fully used", &problems)
    expect(first.xEnd < (layout.gaps.first?.xStart ?? -1),
           "the gap sits between the clusters", &problems)

    // A 15 minute gap is not elided.
    let tight = TimelineLayout(segments: [seg(0, 30), seg(45, 60)], gapThreshold: 20 * 60)
    expect(tight.clusters.count == 1, "a 15 minute gap stays inside one cluster", &problems)
    expect(tight.gaps.isEmpty, "and produces no separator", &problems)

    // Mapping round-trips inside a cluster and refuses inside a gap.
    let inside = dayStart.addingTimeInterval(15 * 60)
    guard let f = layout.fraction(for: inside) else {
        problems.append("an instant inside a cluster must map to a fraction")
        return problems
    }
    expectClose(layout.date(at: f)?.timeIntervalSince(inside) ?? 999, 0,
                "fraction and date round-trip", &problems)
    expect(layout.fraction(for: dayStart.addingTimeInterval(120 * 60)) == nil,
           "an instant inside an elided gap has no position", &problems)

    // A tiny cluster beside a huge one stays visible.
    let lopsided = TimelineLayout(segments: [seg(0, 2), seg(120, 360)],
                                  gapThreshold: 20 * 60)
    let tiny = lopsided.clusters[0]
    expect(tiny.xEnd - tiny.xStart >= 0.04,
           "a two-minute cluster keeps a readable minimum width, got \(tiny.xEnd - tiny.xStart)",
           &problems)

    expect(TimelineLayout(segments: [], gapThreshold: 20 * 60).clusters.isEmpty,
           "no segments, no clusters", &problems)
    return problems
}
```

- [ ] **Step 2: Run to verify it fails** — `cannot find 'TimelineLayout'`.

- [ ] **Step 3: Implement**

```swift
struct TimelineLayout {
    let clusters: [TimelineCluster]
    let gaps: [TimelineGap]

    init(segments: [TimelineSegment],
         gapThreshold: TimeInterval = FocusConstants.timelineGapThreshold,
         separatorShare: Double = 0.035,
         minimumClusterShare: Double = 0.04) {
        // 1. Cluster: a gap at or over the threshold ends the run.
        let ordered = segments.sorted { $0.start < $1.start }
        var ranges: [(start: Date, end: Date)] = []
        for segment in ordered {
            if var last = ranges.last,
               segment.start.timeIntervalSince(last.end) < gapThreshold {
                last.end = max(last.end, segment.end)
                ranges[ranges.count - 1] = last
            } else {
                ranges.append((segment.start, max(segment.end, segment.start)))
            }
        }
        guard !ranges.isEmpty else {
            clusters = []; gaps = []; return
        }

        // 2. Allocate: separators take a fixed share, clusters split the rest in
        //    proportion to duration, with a floor so a short burst stays visible.
        let separatorTotal = separatorShare * Double(max(0, ranges.count - 1))
        let available = max(0.1, 1 - separatorTotal)
        let durations = ranges.map { max(1, $0.end.timeIntervalSince($0.start)) }
        let totalDuration = durations.reduce(0, +)

        var shares = durations.map { available * ($0 / totalDuration) }
        // Lift anything under the floor, then renormalise the rest so the sum holds.
        let floor = minimumClusterShare
        let lifted = shares.map { Swift.max($0, floor) }
        let liftedTotal = lifted.reduce(0, +)
        shares = lifted.map { $0 * available / liftedTotal }

        var builtClusters: [TimelineCluster] = []
        var builtGaps: [TimelineGap] = []
        var cursor = 0.0
        for (index, range) in ranges.enumerated() {
            if index > 0 {
                let previous = ranges[index - 1]
                builtGaps.append(TimelineGap(start: previous.end, end: range.start,
                                             xStart: cursor,
                                             xEnd: cursor + separatorShare))
                cursor += separatorShare
            }
            builtClusters.append(TimelineCluster(start: range.start, end: range.end,
                                                 xStart: cursor,
                                                 xEnd: cursor + shares[index]))
            cursor += shares[index]
        }
        clusters = builtClusters
        gaps = builtGaps
    }

    /// nil when the instant falls inside an elided gap: it has no position.
    func fraction(for date: Date) -> Double? {
        for cluster in clusters where date >= cluster.start && date <= cluster.end {
            let span = max(1, cluster.end.timeIntervalSince(cluster.start))
            let progress = date.timeIntervalSince(cluster.start) / span
            return cluster.xStart + progress * (cluster.xEnd - cluster.xStart)
        }
        return nil
    }

    func date(at fraction: Double) -> Date? {
        for cluster in clusters where fraction >= cluster.xStart && fraction <= cluster.xEnd {
            let width = max(0.0001, cluster.xEnd - cluster.xStart)
            let progress = (fraction - cluster.xStart) / width
            let span = cluster.end.timeIntervalSince(cluster.start)
            return cluster.start.addingTimeInterval(progress * span)
        }
        return nil
    }

    /// Whole hours inside clusters only — an elided gap has no hours to draw.
    func hourTicks() -> [Date] {
        let calendar = Calendar.current
        var ticks: [Date] = []
        for cluster in clusters {
            guard var cursor = calendar.dateInterval(of: .hour, for: cluster.start)?.start
            else { continue }
            if cursor < cluster.start { cursor = cursor.addingTimeInterval(3_600) }
            while cursor <= cluster.end && ticks.count < 48 {
                ticks.append(cursor)
                cursor = cursor.addingTimeInterval(3_600)
            }
        }
        return ticks
    }
}
```

Add `FocusConstants.timelineGapThreshold: TimeInterval = 20 * 60`.

- [ ] **Step 4: Run tests** — expected 38/38.

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 2: Draw through the layout

**Files:**
- Modify: `Sources/Surfaces/Dashboard/DayTimelineView.swift`, `Sources/App/SessionStore.swift`

- [ ] **Step 1: Publish the layout**

`SessionStore.timelineLayout: TimelineLayout?`, rebuilt in `refreshDashboard`. Hover now
goes through it, so the pointer and the band cannot disagree:

```swift
func hoverTimeline(at fraction: Double?) {
    guard let fraction, let layout = timelineLayout, let usage else {
        if hoveredSegment != nil { hoveredSegment = nil }
        return
    }
    guard let date = layout.date(at: fraction) else {
        // The pointer is over an elided gap: nothing to name.
        if hoveredSegment != nil { hoveredSegment = nil }
        return
    }
    let found = DashboardStats(sessions: engine.archive, usage: usage)
        .segment(at: date, on: selectedDay)
    if found?.id != hoveredSegment?.id { hoveredSegment = found }
}
```

- [ ] **Step 2: Draw segments through `fraction(for:)`**

Every x in the `Canvas` comes from the layout. A segment whose start has no fraction is
skipped rather than drawn at 0, which is what would smear it across the band:

```swift
for segment in store.timelineSegments {
    guard let startX = layout.fraction(for: segment.start),
          let endX = layout.fraction(for: segment.end) else { continue }
    let left = startX * size.width
    let width = max(1.5, endX * size.width - left)
    ...
}
```

- [ ] **Step 3: Draw the gap separators**

A hatched band at the separator's x range, with the duration beneath:

```swift
for gap in layout.gaps {
    let rect = CGRect(x: gap.xStart * size.width, y: 0,
                      width: (gap.xEnd - gap.xStart) * size.width, height: bandHeight)
    context.fill(Path(rect), with: .color(.secondary.opacity(0.08)))
    var hatch = Path()
    var x = rect.minX - bandHeight
    while x < rect.maxX {
        hatch.move(to: CGPoint(x: x, y: bandHeight))
        hatch.addLine(to: CGPoint(x: x + bandHeight, y: 0))
        x += 6
    }
    context.clip(to: Path(rect))
    context.stroke(hatch, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
}
```

Labels for the gaps render as an overlay, not in the `Canvas`, so they use real text:
`No activity · 8h 12m`, centred on the separator, hidden when the separator is under 40pt.

- [ ] **Step 4: Axis through the layout**

`layout.hourTicks()` positioned by `fraction(for:)`. Ticks inside gaps do not exist, so
the axis automatically skips empty time.

- [ ] **Step 5: Verify** — `./build.sh --run`, select Yesterday, confirm the 8pm–11pm
emptiness is a single labelled separator and the 11pm–12am activity fills the band.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*

---

### Task 3: Insight copy and the Running Now filter

**Files:**
- Modify: `Sources/Core/DashboardStats.swift`, `Sources/App/SessionStore.swift`
- Test: `Sources/SelfTest.swift`

- [ ] **Step 1: Write the failing test**

```swift
private static func testInsightCopyAndRunningFilter() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
    let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
    let sessions = SessionArchive(directory: sessionDir, now: { clock.value })
    let dayStart = Calendar.current.startOfDay(for: base)

    usage.record(AppUsageSession(bundleID: "com.a", appName: "Claude",
                                 start: dayStart.addingTimeInterval(9 * 3_600),
                                 end: dayStart.addingTimeInterval(9 * 3_600 + 600)))
    let stats = DashboardStats(sessions: sessions, usage: usage, now: { clock.value })

    guard let longest = stats.insights(for: base).first(where: { $0.id == "longest-stretch" })
    else {
        problems.append("the longest-stretch insight must be present")
        return problems
    }
    expect(longest.headline.contains("Longest unbroken stretch"),
           "the headline names the measure, got '\(longest.headline)'", &problems)
    expect(longest.detail.contains("Claude") && longest.detail.contains("10m"),
           "the detail names the app and the duration, got '\(longest.detail)'", &problems)
    expect(longest.detail.contains("–"),
           "the detail carries the clock range as evidence, got '\(longest.detail)'",
           &problems)

    // A process with no launch date tells us nothing, so it is not listed.
    let running = stats.runningNow(from: [
        RunningAppInput(bundleID: "com.a", appName: "Claude",
                        launched: dayStart.addingTimeInterval(8 * 3_600)),
        RunningAppInput(bundleID: "com.apple.finder", appName: "Finder", launched: nil)
    ])
    expect(running.count == 1, "apps without a launch date are excluded, got \(running.count)",
           &problems)
    expect(running.first?.bundleID == "com.a", "the real app survives", &problems)

    try? FileManager.default.removeItem(at: usageDir)
    try? FileManager.default.removeItem(at: sessionDir)
    return problems
}
```

- [ ] **Step 2: Run to verify it fails** — the headline is still `Longest stretch` and
Finder is still listed.

- [ ] **Step 3: Rewrite the copy**

```swift
private func longestStretch(_ day: Date) -> Insight? {
    let all = timeline(for: day)
    guard let top = all.max(by: { $0.seconds < $1.seconds }), top.seconds > 0 else {
        return nil
    }
    return Insight(id: "longest-stretch",
                   headline: "Longest unbroken stretch",
                   detail: "\(durationPhrase(top.seconds)) in \(top.appName), "
                         + "\(clockRange(top.start, top.end))",
                   symbolName: "arrow.up.right")
}
```

`inside-session` becomes headline `62% of tracked time was in a focus session`, detail
`1h 18m of 2h 6m tracked`. `vs-yesterday` becomes headline `50m less than yesterday`,
detail `1h 15m today, 2h 5m yesterday` — a delta without its baseline is not an insight.

`clockRange` is a private formatter on `DashboardStats`; `Core` cannot import `Design`.

- [ ] **Step 4: Filter Running Now**

```swift
func runningNow(from inputs: [RunningAppInput]) -> [RunningApp] {
    let reference = now()
    return inputs
        // No launch date means we can say nothing useful: Finder is started at
        // login, runs permanently, and its row could only ever read "since login".
        .compactMap { input -> RunningApp? in
            guard let launched = input.launched else { return nil }
            return RunningApp(bundleID: input.bundleID,
                              appName: input.appName,
                              launched: launched,
                              openFor: max(0, reference.timeIntervalSince(launched)))
        }
        .sorted { ($0.openFor ?? 0) > ($1.openFor ?? 0) }
}
```

The "since login" branch in `RunningNowList` becomes unreachable and is removed.

- [ ] **Step 5: Run tests** — expected 39/39. Test 27 asserts the old nil-launch-date
behaviour and must be updated to the new contract: it now expects one row, not two.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*

---

### Task 4: Verification

- [ ] **Step 1: Tests** — `./build.sh --test`, all passing, zero warnings.
- [ ] **Step 2: Snapshots** — `--snapshot`; confirm a fixture with a long gap shows one
labelled separator rather than empty columns.
- [ ] **Step 3: Live check** — select Yesterday and confirm the activity is readable.
- [ ] **Step 4: Memory** — `footprint`, no regression against 20 MB.
- [ ] **Step 5: README** — the elision rule and the Running Now filter.
- [ ] **Step 6: Commit** *(skipped — not a git repository)*
