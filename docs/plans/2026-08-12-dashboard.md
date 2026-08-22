# FocusContinuity Dashboard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the sparse Today window with a two-column dashboard that answers "where did my day go, and was it any good?" — a 24-hour Canvas timeline, icon-led app rankings, live running-apps, focus quality and gated insights — and fix the three computation defects visible in the current build.

**Architecture:** Every figure is computed in `Core/DashboardStats.swift`, a pure struct over `(SessionArchive, AppUsageArchive, now)`, so the headless self-test covers all of it. Views receive plain values and never touch an archive. The timeline draws in a single `Canvas` pass.

**Tech Stack:** Swift 5, SwiftUI, `Canvas`, Swift Charts (weekly bars only), AppKit for icons and running-app queries.

**Spec:** `docs/superpowers/specs/2026-08-12-dashboard-design.md`

## Global Constraints

- **No `@State`, no `@Observable`** — Command Line Tools ship no `SwiftUIMacros` plugin. View state lives in `ObservableObject` + `@Published`. `@Binding`, `@Environment`, `@FocusState`, `@AppStorage` are fine.
- **`Core/` never imports SwiftUI.** `DashboardStats` must stay headless-testable.
- **No new TCC permissions.** No Accessibility, Automation, Screen Recording or Input Monitoring. A feature that needs one is dropped, not the promise.
- **macOS 13.0 target**, host arch, ad-hoc signing, `swiftc` via `build.sh`, `-parse-as-library`, `-warnings-as-errors`.
- **Semantic colours only.** No hardcoded hex outside the one categorical timeline ramp, which is built from system colours.
- **No cards for list rows, no four-tile stat grid** — spec §4. Rows with hairline separators.
- **No file deletion.** Retired files move to `_trash/`.
- **`./build.sh --test` passes at the end of every task.** Currently 24 tests; the count only grows.
- **Not a git repository** — commit steps are recorded but skipped.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/Core/DashboardStats.swift` | All dashboard computation. Pure, injected clock |
| `Sources/Core/IdleMonitor.swift` | **New, conditional on Task 1.** System idle seconds |
| `Sources/Core/AppUsageTracker.swift` | Gains idle-aware closing |
| `Sources/Core/SessionArchive.swift` | Streak counts in-flight work (B-3) |
| `Sources/App/AppIconProvider.swift` | bundleID → `NSImage`, memoised, symbol fallback |
| `Sources/App/SessionStore.swift` | Publishes `DashboardStats`, timeframe selection |
| `Sources/Surfaces/Dashboard/DashboardView.swift` | Two-column shell |
| `Sources/Surfaces/Dashboard/ActiveSessionPanel.swift` | Hero |
| `Sources/Surfaces/Dashboard/DayTimelineView.swift` | `Canvas` timeline |
| `Sources/Surfaces/Dashboard/TopAppsList.swift` | Ranked rows |
| `Sources/Surfaces/Dashboard/RunningNowList.swift` | Live app rows |
| `Sources/Surfaces/Dashboard/InsightsList.swift` | Gated insight lines |
| `Sources/Surfaces/Dashboard/FocusQualityBar.swift` | Work-type split line |

`Sources/Surfaces/TodayView.swift` is replaced by `DashboardView` and moves to `_trash/`.

---

### Task 1: Spike — idle detection without a permission

Gates the honest-time fix. Do this first; the answer changes Task 6.

**Files:** `/tmp/spike/Idle.swift` (scratch only)

- [ ] **Step 1: Probe the API**

```swift
import CoreGraphics
import Foundation

for _ in 0..<3 {
    let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .null)
    print("idle seconds: \(idle)")
    Thread.sleep(forTimeInterval: 2)   // scratch spike only, never in the app
}
```

- [ ] **Step 2: Record the answer**

Run it, then leave the machine untouched for 10 seconds and run it again.
Expected on success: a small number when active, ≥10 when untouched, **no TCC prompt**, and no entry added by `tccutil`.
If it returns 0 always, or prompts for Input Monitoring, **Task 6 is dropped** and the README states that foreground time is counted whether or not you are at the keyboard.

- [ ] **Step 3: Commit** *(skipped — not a git repository)*

---

### Task 2: `DashboardStats` — timeline and rankings

**Files:**
- Create: `Sources/Core/DashboardStats.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Consumes: `SessionArchive`, `AppUsageArchive`, `AppUsageSession`, `SessionRecord`, `WorkType`.
- Produces: `TimelineSegment`, `AppRank`, `RunningApp`, `FocusQuality`, `Insight` (spec §5.1), and
  `struct DashboardStats { init(sessions:usage:now:calendar:); func timeline(for day: Date) -> [TimelineSegment]; func rankedApps(for day: Date) -> [AppRank]; func trackedTotal(for day: Date) -> TimeInterval }`.

- [ ] **Step 1: Write the failing tests**

```swift
private static func testDashboardTimeline() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let dir = scratchDirectory()
    let usage = AppUsageArchive(directory: dir, now: { clock.value })
    let sessions = SessionArchive(directory: scratchDirectory(), now: { clock.value })

    let calendar = Calendar.current
    let dayStart = calendar.startOfDay(for: base)
    func use(_ id: String, _ name: String, fromHour: Double, hours: Double) {
        let start = dayStart.addingTimeInterval(fromHour * 3_600)
        usage.record(AppUsageSession(bundleID: id, appName: name,
                                     start: start,
                                     end: start.addingTimeInterval(hours * 3_600)))
    }
    use("com.a", "Alpha", fromHour: 9, hours: 2)
    use("com.b", "Beta", fromHour: 11, hours: 1)
    use("com.a", "Alpha", fromHour: 14, hours: 1)

    let stats = DashboardStats(sessions: sessions, usage: usage, now: { clock.value })
    let segments = stats.timeline(for: base)
    expect(segments.count == 3, "three segments, got \(segments.count)", &problems)
    expect(segments.first?.start ?? .distantPast < (segments.last?.start ?? .distantPast),
           "segments must be ordered by start", &problems)

    // Busiest app owns colour index 0 so the ramp is stable for the day.
    let alpha = segments.filter { $0.bundleID == "com.a" }
    expect(alpha.allSatisfy { $0.colorIndex == 0 },
           "the busiest app takes index 0 for every one of its segments", &problems)

    let ranked = stats.rankedApps(for: base)
    expect(ranked.count == 2, "two apps, got \(ranked.count)", &problems)
    expect(ranked.first?.bundleID == "com.a", "busiest first", &problems)
    expectClose(ranked.first?.total ?? -1, 3 * 3_600, "Alpha total", &problems)
    expectClose(ranked.first?.longest ?? -1, 2 * 3_600, "Alpha longest", &problems)
    expectClose(ranked.reduce(0) { $0 + $1.share }, 1.0, "shares sum to 1", &problems)
    expectClose(stats.trackedTotal(for: base), 4 * 3_600, "tracked total", &problems)

    try? FileManager.default.removeItem(at: dir)
    return problems
}

private static func testTimelineClipsAcrossMidnight() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let dir = scratchDirectory()
    let usage = AppUsageArchive(directory: dir, now: { clock.value })
    let calendar = Calendar.current
    let dayStart = calendar.startOfDay(for: base)

    // 23:30 to 00:30 — half belongs to each day.
    let start = dayStart.addingTimeInterval(23.5 * 3_600)
    usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                 start: start, end: start.addingTimeInterval(3_600)))

    let stats = DashboardStats(sessions: SessionArchive(directory: scratchDirectory(),
                                                        now: { clock.value }),
                               usage: usage, now: { clock.value })
    let today = stats.timeline(for: base)
    expect(today.count == 1, "one clipped segment today", &problems)
    expectClose(today.first.map { $0.end.timeIntervalSince($0.start) } ?? -1, 1_800,
                "today keeps only the first half hour", &problems)

    let tomorrow = stats.timeline(for: base.addingTimeInterval(86_400))
    expectClose(tomorrow.first.map { $0.end.timeIntervalSince($0.start) } ?? -1, 1_800,
                "tomorrow keeps the second half hour", &problems)

    try? FileManager.default.removeItem(at: dir)
    return problems
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `./build.sh --test`
Expected: compile error — `cannot find 'DashboardStats' in scope`.

- [ ] **Step 3: Implement**

Clipping is the part that is easy to get wrong; a session spanning midnight must contribute
to both days and to neither twice:

```swift
func timeline(for day: Date) -> [TimelineSegment] {
    let dayStart = calendar.startOfDay(for: day)
    guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
    let ranks = rankedApps(for: day)
    let indexByBundle = Dictionary(uniqueKeysWithValues:
        ranks.enumerated().map { ($0.element.bundleID, min($0.offset, 6)) })

    return usage.sessions
        .compactMap { session -> TimelineSegment? in
            let start = max(session.start, dayStart)
            let end = min(session.end, dayEnd)
            guard end > start else { return nil }
            return TimelineSegment(id: session.id,
                                   bundleID: session.bundleID,
                                   appName: session.appName,
                                   start: start,
                                   end: end,
                                   colorIndex: indexByBundle[session.bundleID] ?? 6)
        }
        .sorted { $0.start < $1.start }
}
```

`rankedApps(for:)` uses the same clipping so totals and the timeline can never disagree.
`share` divides by `trackedTotal(for:)`, returning 0 when the total is 0 rather than NaN.

- [ ] **Step 4: Run tests**

Run: `./build.sh --test`
Expected: 26/26 passed.

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 3: `DashboardStats` — focus quality, running apps, insights

**Files:**
- Modify: `Sources/Core/DashboardStats.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces: `focusQuality(for:) -> FocusQuality`, `runningNow(from: [RunningAppInput]) -> [RunningApp]`,
  `insights(for:) -> [Insight]`.
- `RunningAppInput` is a plain struct (`bundleID`, `appName`, `launched: Date?`) so `Core`
  never imports AppKit and the tests need no real processes.

- [ ] **Step 1: Write the failing tests**

```swift
private static func testFocusQualityAndRunning() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let calendar = Calendar.current
    let dayStart = calendar.startOfDay(for: base)
    let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
    let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
    let sessions = SessionArchive(directory: sessionDir, now: { clock.value })

    // 4h tracked: 2h inside a focus session, 2h outside.
    func use(_ id: String, fromHour: Double, hours: Double) {
        let start = dayStart.addingTimeInterval(fromHour * 3_600)
        usage.record(AppUsageSession(bundleID: id, appName: id,
                                     start: start,
                                     end: start.addingTimeInterval(hours * 3_600)))
    }
    use("com.a", fromHour: 9, hours: 2)
    use("com.b", fromHour: 13, hours: 2)
    sessions.append(SessionRecord(name: "Deep", workType: .deepWork,
                                  start: dayStart.addingTimeInterval(9 * 3_600),
                                  end: dayStart.addingTimeInterval(11 * 3_600),
                                  workSeconds: 7_200))

    let stats = DashboardStats(sessions: sessions, usage: usage, now: { clock.value })
    let quality = stats.focusQuality(for: base)
    expectClose(quality.insideSessionShare, 0.5, "half of tracked time was in a session",
                &problems)

    // Running apps: a missing launch date must not fabricate a duration.
    clock.value = dayStart.addingTimeInterval(12 * 3_600)
    let running = stats.runningNow(from: [
        RunningAppInput(bundleID: "com.a", appName: "Alpha",
                        launched: dayStart.addingTimeInterval(9 * 3_600)),
        RunningAppInput(bundleID: "com.finder", appName: "Finder", launched: nil)
    ])
    expectClose(running.first?.openFor ?? -1, 3 * 3_600, "Alpha open three hours", &problems)
    expect(running.last?.openFor == nil, "no launch date means no duration", &problems)

    try? FileManager.default.removeItem(at: usageDir)
    try? FileManager.default.removeItem(at: sessionDir)
    return problems
}

private static func testInsightGating() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
    let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
    let sessions = SessionArchive(directory: sessionDir, now: { clock.value })
    let stats = DashboardStats(sessions: sessions, usage: usage, now: { clock.value })

    // Nothing recorded: no insights at all, rather than empty cards.
    expect(stats.insights(for: base).isEmpty, "no data means no insights", &problems)

    let dayStart = Calendar.current.startOfDay(for: base)
    usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                 start: dayStart.addingTimeInterval(9 * 3_600),
                                 end: dayStart.addingTimeInterval(11 * 3_600)))
    let withUsage = stats.insights(for: base)
    expect(withUsage.contains { $0.id == "longest-stretch" },
           "one usage session unlocks the longest-stretch insight", &problems)
    expect(!withUsage.contains { $0.id == "best-window" },
           "best focus window needs five days and must stay hidden", &problems)

    try? FileManager.default.removeItem(at: usageDir)
    try? FileManager.default.removeItem(at: sessionDir)
    return problems
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `./build.sh --test`
Expected: `cannot find 'RunningAppInput' in scope`.

- [ ] **Step 3: Implement**

`insideSessionShare` intersects each usage segment with each focus session and sums the
overlap, divided by tracked total. `switchesPerSession` counts distinct usage segments
that begin inside a focus session, divided by the number of sessions that day; 0 sessions
yields 0, never NaN.

Insight gates are exactly the table in spec §6.4. Each insight is emitted by a small
function returning `Insight?`, and `insights(for:)` is `[...].compactMap { $0 }` — so a
gate failing removes the line rather than emitting a placeholder.

- [ ] **Step 4: Run tests**

Run: `./build.sh --test`
Expected: 28/28 passed.

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 4: Fix the three defects

**Files:**
- Modify: `Sources/Core/SessionArchive.swift`, `Sources/App/SessionStore.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- `SessionArchive.currentStreak(includingToday inFlight: TimeInterval = 0) -> Int`.
- `SessionStore` publishes `sessionsToday` and `longestToday` counting the running session.

- [ ] **Step 1: Write the failing regression test**

```swift
private static func testRunningSessionCountsEverywhere() -> [String] {
    var problems: [String] = []
    let clock = Clock(base)
    let engine = makeEngine(clock)

    // The exact screenshot state: 42 minutes in, nothing completed yet.
    engine.start(workType: .deepWork, intent: "Refactor")
    clock.advance(42 * 60)

    expectClose(engine.todayTotal, 42 * 60, "today counts the running session", &problems)
    expect(engine.archive.currentStreak(includingToday: engine.elapsed) == 1,
           "42 minutes of live work should light the streak, got "
           + "\(engine.archive.currentStreak(includingToday: engine.elapsed))", &problems)
    expect(engine.sessionsToday == 1,
           "the running session counts as one, got \(engine.sessionsToday)", &problems)
    expectClose(engine.longestToday, 42 * 60,
                "longest today includes the running session", &problems)

    // Under the 25 minute bar the streak stays honest.
    let clock2 = Clock(base)
    let engine2 = makeEngine(clock2)
    engine2.start(workType: .deepWork, intent: "Short")
    clock2.advance(10 * 60)
    expect(engine2.archive.currentStreak(includingToday: engine2.elapsed) == 0,
           "10 minutes must not light the streak", &problems)
    return problems
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./build.sh --test`
Expected: FAIL — streak 0, sessionsToday 0, longestToday 0.

- [ ] **Step 3: Implement**

`currentStreak(includingToday:)` adds the in-flight seconds to today's total before
testing the threshold. `SessionEngine.sessionsToday` returns
`archive.sessionsToday() + (state == .idle ? 0 : 1)`, and `longestToday` returns
`max(archive.longestToday(), state == .idle ? 0 : elapsed)`.

- [ ] **Step 4: Fix the blank chart (B-1)**

In `WeekChart`, add a y-domain floor and an empty state:

```swift
private var hasData: Bool { bars.contains { $0.minutes > 0 } }

var body: some View {
    if hasData {
        Chart(bars) { /* unchanged */ }
            .chartYScale(domain: 0...max(60, bars.map(\.minutes).max() ?? 60))
    } else {
        Text("No sessions yet today")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(height: height, alignment: .leading)
    }
}
```

- [ ] **Step 5: Run tests**

Run: `./build.sh --test`
Expected: 29/29 passed.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*

---

### Task 5: `AppIconProvider`

**Files:**
- Create: `Sources/App/AppIconProvider.swift`

**Interfaces:**
- `final class AppIconProvider { static let shared: AppIconProvider; func icon(for bundleID: String) -> NSImage? }`

- [ ] **Step 1: Implement with memoisation and a fallback**

```swift
import AppKit

/// bundleID -> icon, resolved once and cached. Uninstalled apps still appear in
/// history, so a miss is normal and the view falls back to an SF Symbol.
final class AppIconProvider {
    static let shared = AppIconProvider()
    private var cache: [String: NSImage?] = [:]

    func icon(for bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        let resolved = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[bundleID] = resolved
        return resolved
    }
}
```

Verified on this machine: Safari, Terminal, Chrome, Spotify and Finder all resolve;
Xcode is not installed and returns nil, which is the fallback path.

- [ ] **Step 2: Add the row icon view**

```swift
struct AppIcon: View {
    let bundleID: String
    var size: CGFloat = 20

    var body: some View {
        if let icon = AppIconProvider.shared.icon(for: bundleID) {
            Image(nsImage: icon).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 3: Verify**

Run: `./build.sh --test` — expected: build succeeds, 29/29.

- [ ] **Step 4: Commit** *(skipped — not a git repository)*

---

### Task 6: Idle-aware tracking — **only if Task 1 succeeded**

**Files:**
- Create: `Sources/Core/IdleMonitor.swift`
- Modify: `Sources/Core/AppUsageTracker.swift`

- [ ] **Step 1: Implement `IdleMonitor`**

```swift
import CoreGraphics

/// System idle seconds. Reads a timestamp, not event content, so it needs no
/// Input Monitoring grant.
struct IdleMonitor {
    var idleSeconds: () -> TimeInterval = {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .null)
    }
}
```

- [ ] **Step 2: Close the open stretch when idle**

`AppUsageTracker` takes an `IdleMonitor` and, in `flush()`, ends the open stretch at
`now - idleSeconds` when idle exceeds 180s, then reopens on the next activation. The
injected closure makes this testable with no real input.

- [ ] **Step 3: Test it**

```swift
private static func testIdleTrimsUsage() -> [String] {
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
    clock.advance(3_600)          // an hour frontmost
    idle = 2_400                  // but the last 40 minutes had no input
    tracker.flush()

    expectClose(usage.sessions.first?.seconds ?? -1, 1_200,
                "idle time must not be counted as usage", &problems)
    try? FileManager.default.removeItem(at: dir)
    return problems
}
```

- [ ] **Step 4: Run tests** — expected: 30/30 passed.

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 7: Dashboard shell and the active-session panel

**Files:**
- Create: `Sources/Surfaces/Dashboard/DashboardView.swift`, `ActiveSessionPanel.swift`
- Modify: `Sources/App/FocusContinuityApp.swift`
- Move to `_trash/`: `Sources/Surfaces/TodayView.swift`

- [ ] **Step 1: Build the two-column shell**

Left column flexible, right column fixed at 240pt so opening an app never reflows the
narrative. Section spacing 24pt, within-section 8pt.

```swift
struct DashboardView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.xl) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                    ActiveSessionPanel(store: store)
                    Divider()
                    DaySection(store: store)
                    Divider()
                    TopAppsList(apps: store.rankedApps, sessionsToday: store.sessionsToday)
                    Divider()
                    FocusQualityBar(quality: store.focusQuality)
                }
                .padding(Tokens.Space.xl)
            }
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                RunningNowList(apps: store.runningApps)
                InsightsList(insights: store.insights)
            }
            .frame(width: 240)
            .padding(.vertical, Tokens.Space.xl)
            .padding(.trailing, Tokens.Space.xl)
        }
        .onAppear { store.refresh() }
    }
}
```

- [ ] **Step 2: Active-session panel**

Timer in `Tokens.heroTimerFont`; one secondary line reading `intent · work type · started
10:17 am`; Pause and Stop; streak on the trailing edge. Idle state swaps the timer for the
intent field and Start. No stat tiles anywhere.

- [ ] **Step 3: Point the window at it**

```swift
Window("Dashboard", id: "today") {
    DashboardView(store: coordinator.store)
}
.defaultSize(width: 1000, height: 680)
```

- [ ] **Step 4: Verify** — `./build.sh --run`, open the dashboard, confirm both columns
render and the right column keeps its width as apps open and close.

- [ ] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 8: The day timeline

**Files:**
- Create: `Sources/Surfaces/Dashboard/DayTimelineView.swift`

- [ ] **Step 1: Draw the band in one `Canvas` pass**

```swift
struct DayTimelineView: View {
    let segments: [TimelineSegment]
    let focusSessions: [(start: Date, end: Date)]
    let window: (start: Date, end: Date)     // adaptive, see spec 6.2

    var body: some View {
        Canvas { context, size in
            let span = max(1, window.end.timeIntervalSince(window.start))
            func x(_ date: Date) -> CGFloat {
                CGFloat(date.timeIntervalSince(window.start) / span) * size.width
            }
            for segment in segments {
                let rect = CGRect(x: x(segment.start), y: 0,
                                  width: max(1, x(segment.end) - x(segment.start)),
                                  height: size.height - 14)
                context.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .color(TimelinePalette.color(segment.colorIndex)))
            }
            for session in focusSessions {
                let y = size.height - 8
                var bracket = Path()
                bracket.move(to: CGPoint(x: x(session.start), y: y))
                bracket.addLine(to: CGPoint(x: x(session.end), y: y))
                context.stroke(bracket, with: .color(.accentColor), lineWidth: 2)
            }
        }
        .frame(height: 56)
        .accessibilityLabel(Text("Day timeline, \(segments.count) app segments"))
    }
}
```

`TimelinePalette.color(_:)` returns one of six system colours by index, with index 6
("Other") using `.secondary`. Focus sessions are strokes beneath the band, never fills,
so they read as annotation.

- [ ] **Step 2: Empty state**

When `segments.isEmpty`, render the text "Tracking starts when you switch apps." instead
of an empty frame — this is defect B-1's root cause and must not recur here.

- [ ] **Step 3: Verify with a heavy day**

Add a `--snapshot` fixture with 300 segments and confirm it renders and that the window
stays responsive.

- [ ] **Step 4: Commit** *(skipped — not a git repository)*

---

### Task 9: The three list sections

**Files:**
- Create: `TopAppsList.swift`, `RunningNowList.swift`, `InsightsList.swift`, `FocusQualityBar.swift`

- [ ] **Step 1: `TopAppsList` — rows, not cards**

Each row: `AppIcon` at 20pt, name, proportional bar (a `Capsule` at `share` of available
width, `.tint` for rank 0 and `.quaternary` below), absolute time, percentage. The top row
also shows the longest stretch. Hairline `Divider()` between rows, no per-row background.

- [ ] **Step 2: `RunningNowList`**

Icon, name, `Tokens.spent(openFor)` and the launch time beneath. When `launched` is nil,
show "since login" — Finder is the confirmed case and must not display a fabricated time.

- [ ] **Step 3: `InsightsList`**

Each insight is a leading SF Symbol, a headline in `.callout`, and a detail line in
`.caption` secondary. No cards, no fixed height. An empty array renders nothing at all.

- [ ] **Step 4: `FocusQualityBar`**

One line of work-type shares, then two figures: percentage of tracked time inside a
session, and switches per session. When there are no sessions, the line reads
"No sessions yet today" instead of showing 0%.

- [ ] **Step 5: Verify** — `./build.sh --test`, then `--snapshot` and inspect each state.

- [ ] **Step 6: Commit** *(skipped — not a git repository)*

---

### Task 10: Timeframe control and verification

**Files:**
- Modify: `DashboardView.swift`, `SessionStore.swift`, `Snapshotter.swift`, `README.md`

- [ ] **Step 1: Timeframe picker**

`Today / Yesterday / Last 7 days` in the day section header, bound to a `@Published var
selectedDay: Date` plus a `multiDay: Bool` on the store. On "Last 7 days" the timeline
becomes seven stacked bands, one per day, weekday leading each row — same grammar, no new
chart type.

- [ ] **Step 2: Dashboard fixtures**

Add to `Fixture`: `dashboardEmpty`, `dashboardTypical`, `dashboardHeavy` (300 segments),
`dashboardNoSessions`, `dashboardTrackingOff`. Each renders in light and dark via
`--snapshot`.

- [ ] **Step 3: Full verification**

```bash
./build.sh --test
./FocusContinuity.app/Contents/MacOS/FocusContinuity --snapshot ./snapshots
```

Expected: all tests pass; every dashboard fixture renders with no blank frames, no
clipped text, no card grids, and correct light/dark.

- [ ] **Step 4: Idle cost**

Leave the dashboard open 60s and measure. Expected: the timeline redraws no more than
once a second, CPU stays at 0.0% when no session is running, `phys_footprint` under 60 MB.

- [ ] **Step 5: Update the README**

Replace the Today-window description with the dashboard, document the timeframe control,
and state plainly whether idle trimming shipped (Task 1's answer).

- [ ] **Step 6: Commit** *(skipped — not a git repository)*
