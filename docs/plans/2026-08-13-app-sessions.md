# App Sessions and Drill-Down — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Group raw usage stretches into real working sessions with an attention-aware rule, expand app rows to hourly colour-matched detail, make `+N more` expandable, and stop the date stepper wrapping.

**Architecture:** Recording keeps full fidelity — the destructive record-time merge is removed and each stretch records why it ended. Grouping happens at display time in `Core/AppSessionGrouper.swift`, so changing the rule re-groups existing history.

**Tech Stack:** Swift 5, SwiftUI, `Canvas`, AppKit.

**Spec:** `docs/superpowers/specs/2026-08-13-app-sessions-design.md`

## Global Constraints

- **No `@State`, no `@Observable`** — view state lives on `SessionStore`.
- **`Core/` never imports SwiftUI.**
- **No new TCC permissions.**
- macOS 13.0, `swiftc` via `build.sh`, `-parse-as-library`, `-warnings-as-errors`.
- Retired files move to `_trash/`.
- `./build.sh --test` passes at the end of every task. Currently 32 tests.
- Not a git repository — commit steps recorded but skipped.
- **Old records must keep decoding.** `endReason` is optional on disk with a default.

---

## File Structure

| File | Change |
|---|---|
| `Sources/Core/AppUsage.swift` | `UsageEndReason`; `AppUsageSession.endReason`; record-time merge removed |
| `Sources/Core/AppUsageTracker.swift` | Records why each stretch ended |
| `Sources/Core/AppSessionGrouper.swift` | **New.** The grouping rule, pure and testable |
| `Sources/Core/DashboardStats.swift` | Serves grouped sessions and hourly buckets |
| `Sources/App/SessionStore.swift` | Expansion state for `+N more` |
| `Sources/Surfaces/Dashboard/DashboardSections.swift` | Hourly strip, expandable rows, stepper fix |
| `Sources/SelfTest.swift` | Grouping, migration and bucketing tests |

---

### Task 1: Record why each stretch ended

**Files:**
- Modify: `Sources/Core/AppUsage.swift`, `Sources/Core/AppUsageTracker.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces: `enum UsageEndReason: String, Codable { case appSwitch, idle, systemLock, stillOpen }`;
  `AppUsageSession.endReason: UsageEndReason` (decodes as `.appSwitch` when absent).

- [ ] **Step 1: Write the failing test**

```swift
private static func testEndReasonsAndMigration() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let dir = scratchDirectory()
    let usage = AppUsageArchive(directory: dir, now: { clock.value })
    var idle: TimeInterval = 0
    let tracker = AppUsageTracker(archive: usage,
                                  ownBundleID: FocusConstants.bundleIdentifier,
                                  idle: IdleMonitor(idleSeconds: { idle }),
                                  now: { clock.value })

    tracker.appActivated(bundleID: "com.a", name: "Alpha")
    clock.advance(600)
    tracker.appActivated(bundleID: "com.b", name: "Beta")     // switch
    clock.advance(600)
    idle = 600                                                 // then idle out
    tracker.flush()
    idle = 0
    clock.advance(60)
    tracker.suspend()                                          // then a lock

    let reasons = usage.sessions.map(\.endReason)
    expect(reasons.first == .appSwitch,
           "first stretch ended by a switch, got \(String(describing: reasons.first))",
           &problems)
    expect(reasons.contains(.idle), "an idle-trimmed stretch records .idle", &problems)

    // Records written before this field existed must still decode.
    let legacy = """
    [{"id":"\(UUID().uuidString)","bundleID":"com.legacy","appName":"Legacy",
      "start":\(base.timeIntervalSinceReferenceDate),
      "end":\(base.addingTimeInterval(600).timeIntervalSinceReferenceDate)}]
    """
    let migrationDir = scratchDirectory()
    try? FileManager.default.createDirectory(at: migrationDir, withIntermediateDirectories: true)
    try? Data(legacy.utf8).write(to: migrationDir.appendingPathComponent("app-usage.json"))
    let migrated = AppUsageArchive(directory: migrationDir, now: { clock.value })
    expect(migrated.sessions.count == 1,
           "a legacy record must still decode, got \(migrated.sessions.count)", &problems)
    expect(migrated.sessions.first?.endReason == .appSwitch,
           "a legacy record defaults to .appSwitch", &problems)

    try? FileManager.default.removeItem(at: dir)
    try? FileManager.default.removeItem(at: migrationDir)
    return problems
}
```

- [ ] **Step 2: Run to verify it fails** — `value of type 'AppUsageSession' has no member 'endReason'`.

- [ ] **Step 3: Add the type and the field**

```swift
/// Why a stretch stopped. Grouping needs this to tell a quick detour from a
/// real break, and it is a few bytes on a record we already write.
enum UsageEndReason: String, Codable {
    case appSwitch, idle, systemLock, stillOpen
}
```

`AppUsageSession` gains `var endReason: UsageEndReason`. Its `init` defaults to
`.appSwitch`, and a custom `init(from:)` decodes the field as optional so records written
before it existed still load:

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    bundleID = try container.decode(String.self, forKey: .bundleID)
    appName = try container.decode(String.self, forKey: .appName)
    start = try container.decode(Date.self, forKey: .start)
    end = try container.decode(Date.self, forKey: .end)
    endReason = try container.decodeIfPresent(UsageEndReason.self, forKey: .endReason)
        ?? .appSwitch
}
```

- [ ] **Step 4: Record the reason in the tracker**

`closeOpenSegment(reason:)` takes the reason. `appActivated` passes `.appSwitch`,
`suspend` passes `.systemLock`, `flush` passes `.stillOpen`, and any close where
`effectiveEnd()` trimmed idle time passes `.idle` instead.

- [ ] **Step 5: Remove the record-time merge**

Delete the merge branch in `AppUsageArchive.record`. Merging destroys the gap evidence
that grouping needs, and grouping now does the job non-destructively. The
`minimumSegment` noise floor stays.

- [ ] **Step 6: Run tests** — expected 33/33.

- [ ] **Step 7: Commit** *(skipped — not a git repository)*

---

### Task 2: The grouping rule

**Files:**
- Create: `Sources/Core/AppSessionGrouper.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces:
  `struct AppSession: Identifiable, Equatable { let bundleID, appName: String; let start, end: Date; let attended: TimeInterval; let visits: Int; var id: String }`
  and `enum AppSessionGrouper { static func group(_ stretches: [TimelineSegment], others: [TimelineSegment], sessionGap: TimeInterval, awayBridge: TimeInterval) -> [AppSession] }`.

- [ ] **Step 1: Write the failing test**

```swift
private static func testSessionGrouping() -> [String] {
    var problems: [String] = []
    let dayStart = Calendar.current.startOfDay(for: base)
    func seg(_ id: String, _ fromMin: Double, _ toMin: Double,
             _ reason: UsageEndReason = .appSwitch) -> TimelineSegment {
        TimelineSegment(id: UUID(), bundleID: id, appName: id,
                        start: dayStart.addingTimeInterval(fromMin * 60),
                        end: dayStart.addingTimeInterval(toMin * 60),
                        colorIndex: 0, endReason: reason)
    }
    let gap: TimeInterval = 300, bridge: TimeInterval = 900

    // A three-minute detour joins: one session, two visits.
    let detour = AppSessionGrouper.group([seg("com.a", 0, 20), seg("com.a", 23, 40)],
                                         others: [seg("com.b", 20, 23)],
                                         sessionGap: gap, awayBridge: bridge)
    expect(detour.count == 1, "a short detour joins, got \(detour.count) sessions", &problems)
    expect(detour.first?.visits == 2, "two visits", &problems)
    expectClose(detour.first?.attended ?? -1, 37 * 60,
                "attended excludes the gap", &problems)
    expectClose((detour.first?.end.timeIntervalSince(detour.first!.start)) ?? -1, 40 * 60,
                "the span includes the gap", &problems)

    // A lock between stretches splits, however short the gap.
    let locked = AppSessionGrouper.group([seg("com.a", 0, 20, .systemLock), seg("com.a", 21, 40)],
                                         others: [], sessionGap: gap, awayBridge: bridge)
    expect(locked.count == 2, "a lock splits, got \(locked.count)", &problems)

    // Real work elsewhere splits, even inside the gap window.
    let switched = AppSessionGrouper.group([seg("com.a", 0, 20), seg("com.a", 24, 40)],
                                           others: [seg("com.b", 20, 24)],
                                           sessionGap: 180, awayBridge: bridge)
    expect(switched.count == 2,
           "another app's real usage splits, got \(switched.count)", &problems)

    // Stepping away and returning to the same app joins, up to the bridge.
    let away = AppSessionGrouper.group([seg("com.a", 0, 20, .idle), seg("com.a", 32, 40)],
                                       others: [], sessionGap: gap, awayBridge: bridge)
    expect(away.count == 1, "an idle gap under the bridge joins, got \(away.count)", &problems)

    // Beyond the bridge it splits.
    let longAway = AppSessionGrouper.group([seg("com.a", 0, 20, .idle), seg("com.a", 60, 70)],
                                           others: [], sessionGap: gap, awayBridge: bridge)
    expect(longAway.count == 2, "beyond the bridge splits", &problems)
    return problems
}
```

- [ ] **Step 2: Run to verify it fails** — `cannot find 'AppSessionGrouper'`.

- [ ] **Step 3: Implement**

```swift
enum AppSessionGrouper {
    static func group(_ stretches: [TimelineSegment],
                      others: [TimelineSegment],
                      sessionGap: TimeInterval,
                      awayBridge: TimeInterval) -> [AppSession] {
        let ordered = stretches.sorted { $0.start < $1.start }
        guard !ordered.isEmpty else { return [] }

        var sessions: [AppSession] = []
        var current: [TimelineSegment] = [ordered[0]]

        for segment in ordered.dropFirst() {
            guard let previous = current.last else { continue }
            if joins(previous: previous, next: segment, others: others,
                     sessionGap: sessionGap, awayBridge: awayBridge) {
                current.append(segment)
            } else {
                sessions.append(make(current))
                current = [segment]
            }
        }
        sessions.append(make(current))
        return sessions
    }

    private static func joins(previous: TimelineSegment,
                              next: TimelineSegment,
                              others: [TimelineSegment],
                              sessionGap: TimeInterval,
                              awayBridge: TimeInterval) -> Bool {
        // A locked screen is an explicit boundary, however short the gap.
        if previous.endReason == .systemLock { return false }
        let gap = next.start.timeIntervalSince(previous.end)
        guard gap >= 0 else { return true }

        // Real work elsewhere is a context switch, not a detour.
        let elsewhere = others
            .filter { $0.start < next.start && $0.end > previous.end }
            .reduce(0.0) { total, other in
                let start = max(other.start, previous.end)
                let end = min(other.end, next.start)
                return total + max(0, end.timeIntervalSince(start))
            }
        if elsewhere >= sessionGap { return false }

        if previous.endReason == .idle { return gap < awayBridge }
        return gap < sessionGap
    }

    private static func make(_ stretches: [TimelineSegment]) -> AppSession {
        let first = stretches[0]
        return AppSession(
            bundleID: first.bundleID,
            appName: first.appName,
            start: first.start,
            end: stretches.map(\.end).max() ?? first.end,
            // Gap time is never usage: attended sums the stretches only.
            attended: stretches.reduce(0) { $0 + $1.seconds },
            visits: stretches.count)
    }
}
```

- [ ] **Step 4: Run tests** — expected 34/34.

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 3: Serve sessions and hourly buckets

**Files:**
- Modify: `Sources/Core/DashboardStats.swift`, `Sources/App/SessionStore.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces: `DashboardStats.sessions(for day: Date, bundleID: String) -> [AppSession]`
  and `DashboardStats.hourlyBuckets(for day: Date, bundleID: String) -> [HourBucket]`
  where `struct HourBucket: Identifiable { let hour: Date; let seconds: TimeInterval; var id: Date }`.

- [ ] **Step 1: Write the failing test**

```swift
private static func testHourlyBuckets() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
    let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
    let dayStart = Calendar.current.startOfDay(for: base)

    // 9:45 to 10:15 — fifteen minutes in each of two hours.
    usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                 start: dayStart.addingTimeInterval(9 * 3_600 + 2_700),
                                 end: dayStart.addingTimeInterval(10 * 3_600 + 900)))
    let stats = DashboardStats(sessions: SessionArchive(directory: sessionDir,
                                                        now: { clock.value }),
                               usage: usage, now: { clock.value })
    let buckets = stats.hourlyBuckets(for: base, bundleID: "com.a")
        .filter { $0.seconds > 0 }
    expect(buckets.count == 2,
           "a stretch across an hour boundary lands in two buckets, got \(buckets.count)",
           &problems)
    expectClose(buckets.first?.seconds ?? -1, 900, "fifteen minutes in the first hour",
                &problems)
    expectClose(buckets.last?.seconds ?? -1, 900, "fifteen minutes in the second", &problems)
    expectClose(buckets.reduce(0) { $0 + $1.seconds }, 1_800,
                "buckets sum to the stretch", &problems)

    try? FileManager.default.removeItem(at: usageDir)
    try? FileManager.default.removeItem(at: sessionDir)
    return problems
}
```

- [ ] **Step 2: Run to verify it fails** — `cannot find 'hourlyBuckets'`.

- [ ] **Step 3: Implement**

```swift
func hourlyBuckets(for day: Date, bundleID: String) -> [HourBucket] {
    let (dayStart, _) = bounds(of: day)
    var totals: [Date: TimeInterval] = [:]
    for stretch in stretches(for: day, bundleID: bundleID) {
        var cursor = stretch.start
        while cursor < stretch.end {
            let hour = calendar.date(bySetting: .minute, value: 0, of: cursor) ?? cursor
            let hourEnd = hour.addingTimeInterval(3_600)
            let slice = min(stretch.end, hourEnd).timeIntervalSince(cursor)
            totals[hour, default: 0] += max(0, slice)
            cursor = hourEnd
        }
    }
    // Every hour in the window, so the strip aligns with the timeline above it.
    guard let window = timelineWindow(for: day) else { return [] }
    var buckets: [HourBucket] = []
    var hour = window.start
    while hour < window.end {
        buckets.append(HourBucket(hour: hour, seconds: totals[hour] ?? 0))
        hour = hour.addingTimeInterval(3_600)
    }
    _ = dayStart
    return buckets
}
```

`sessions(for:bundleID:)` calls `AppSessionGrouper.group` with the app's stretches, every
other app's stretches as `others`, and the thresholds from `FocusConstants`.

- [ ] **Step 4: Publish through the store**

`SessionStore.sessions(for bundleID:)` and `hourlyBuckets(for bundleID:)` mirror the
existing `stretches(for:)` accessor, and `earlierToday` is rebuilt from sessions rather
than raw stretches.

- [ ] **Step 5: Run tests** — expected 35/35.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*

---

### Task 4: Drill-down UI and the two rough edges

**Files:**
- Modify: `Sources/Surfaces/Dashboard/DashboardSections.swift`,
  `Sources/Surfaces/Dashboard/DashboardView.swift`, `Sources/App/SessionStore.swift`

- [ ] **Step 1: Hourly strip in the expanded row**

One bar per hour, height proportional to that hour's minutes, filled in the app's own
timeline colour so the row and the band agree:

```swift
struct HourlyStrip: View {
    let buckets: [HourBucket]
    let colorIndex: Int

    var body: some View {
        let peak = max(1, buckets.map(\.seconds).max() ?? 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(buckets) { bucket in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(bucket.seconds > 0
                              ? AnyShapeStyle(TimelinePalette.color(colorIndex))
                              : AnyShapeStyle(.quaternary))
                        .frame(height: max(2, 28 * bucket.seconds / peak))
                    Text(DayTimelineView.hourLabel(bucket.hour).replacingOccurrences(
                            of: "m", with: ""))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .help("\(DayTimelineView.hourLabel(bucket.hour)): "
                      + Tokens.preciseDuration(bucket.seconds))
            }
        }
        .frame(height: 44, alignment: .bottom)
    }
}
```

- [ ] **Step 2: Expanded Top apps row shows the strip plus sessions**

Replace the raw stretch list in the expanded row with the strip, then the app's sessions:
`10:55 pm – 11:58 pm · 36m over 5 visits`. `visits` is omitted when it is 1.

- [ ] **Step 3: `+N more` expands**

```swift
if app.sessions.count > visibleCount {
    Button("+\(app.sessions.count - visibleCount) more") {
        store.toggleExpanded(app.bundleID)
    }
    .buttonStyle(.plain)
    .font(.caption2)
    .foregroundStyle(.tint)
}
```

`visibleCount` is 4 when collapsed and `app.sessions.count` when the bundle id is in
`store.expandedApps`. The same `Set<String>` already drives Top apps expansion, so both
stay in step.

- [ ] **Step 4: Stop "Today" wrapping**

The stepper's Today button gets `.fixedSize()` and the day label `.lineLimit(1)` with
`.fixedSize(horizontal: true, vertical: false)`, so neither can wrap in the narrow header.

- [ ] **Step 5: Verify** — `./build.sh --run`, expand a Top apps row and confirm the strip
matches the timeline's colour for that app; click `+N more` and confirm the remaining
sessions appear; narrow the window and confirm "Today" stays on one line.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*

---

### Task 5: Verification

- [ ] **Step 1: Tests** — `./build.sh --test`, all passing, zero warnings.

- [ ] **Step 2: Real-data check** — open the dashboard and confirm the fragmentation is
gone: an app you used across a few detours reads as one session with several visits, not
as four slivers.

- [ ] **Step 3: Snapshots** — `--snapshot`, confirm the expanded row and expanded `+N more`
render in both appearances.

- [ ] **Step 4: Memory** — `footprint`, confirm the grouping did not regress it.

- [ ] **Step 5: Update the README** — the session model, the grouping rule, and why
background media is excluded.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*
