# Honest Session Time Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a session's elapsed time reflect time actually worked, make the daily goal fillable only by declared work the user demonstrably did, and make the popover fit any screen.

**Architecture:** `SessionEngine` gains one new event (`idleObserved`) posted by the existing one-second ticker, so idle stretches auto-pause the session backdated to when input stopped. A new pure `FocusedActiveTime` intersects session spans with hands-on usage stretches and becomes the goal's basis. The away decisions become symmetric — all but *I was working* close the old session at the departure moment. A `PopoverMetrics` helper reads the screen and drives a pinned-scroll-pinned layout.

**Tech Stack:** Swift 5, SwiftUI, AppKit where macOS requires it. `swiftc` via `./build.sh`, no SPM, no Xcode project, no third-party packages.

## Global Constraints

- **Not a git repository.** Commit steps are recorded but skipped. Do not run `git init`.
- **No Xcode on this machine.** `@State` and `@Observable` do not compile — the SDK ships no `SwiftUIMacros` plugin. All view state lives in `ObservableObject` + `@Published`, consumed via `@StateObject` / `@ObservedObject` / `@EnvironmentObject`. `@Binding`, `@Environment`, `@FocusState` and `@AppStorage` work normally.
- **`Sources/Core/` imports Foundation and CoreGraphics only** — never SwiftUI or AppKit. (`EventMonitor.swift` and `HotKeyMonitor.swift` are pre-existing violations; do not add more.)
- **Exactly one repeating `Timer` in the app**: the one-second ticker in `SessionStore.startTicker()`. Do not add another.
- **No new TCC permissions.** `CGEventSource.secondsSinceLastEventType` needs none — verified 2026-08-12.
- **Warnings are errors** (`-warnings-as-errors`). Build with `./build.sh`.
- **macOS 13.0 deployment target.**
- Tests live in `Sources/SelfTest.swift` and run headless via `./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest`. Every test uses the injected `Clock`, never `Date()`.
- **`idlePauseThreshold` is 600 seconds.** Not configurable.
- Keep files under 500 lines where practical.

---

### Task 1: Idle auto-pause

**Files:**
- Modify: `Sources/Core/SessionState.swift` — add `PauseReason.idle`, `SessionEvent.idleObserved`, `FocusConstants.idlePauseThreshold`, persistence strings
- Modify: `Sources/Core/SessionEngine.swift` — `enterPause(reason:at:)`, two new transition cases
- Modify: `Sources/App/SessionStore.swift` — sample idle from the ticker
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces: `PauseReason.idle`; `SessionEvent.idleObserved(seconds: TimeInterval)`; `FocusConstants.idlePauseThreshold: TimeInterval = 600`
- Consumes: existing `SessionEngine.transition(on:)`, `IdleMonitor(idleSeconds:)`

- [ ] **Step 1: Write the failing test**

Add to `Sources/SelfTest.swift`, immediately before `// MARK: - 60`:

```swift
    // MARK: - 68

    /// Sitting idle pauses the session backdated to when input actually stopped,
    /// so the ten minutes that prove the user is gone are excluded too. Only an
    /// idle pause auto-resumes: a pause the user pressed is a deliberate act.
    private static func testIdleAutoPause() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)
        engine.transition(on: .launch)
        clock.advance(600)                       // ten minutes of real work

        // Nine minutes idle is tolerated — reading and calls are work.
        clock.advance(540)
        engine.transition(on: .idleObserved(seconds: 540))
        expect(engine.state == .running, "nine minutes idle keeps the session", &problems)
        expectClose(engine.elapsed, 1_140, "and counts", &problems)

        // Past the threshold it pauses, backdated to the last keypress.
        clock.advance(60)
        engine.transition(on: .idleObserved(seconds: 600))
        expect(engine.state == .paused(reason: .idle),
               "ten minutes idle pauses, got \(engine.state)", &problems)
        expectClose(engine.elapsed, 600,
                    "the whole idle stretch is excluded, not just the tail", &problems)

        // Still idle: no further effect, and no time accrues.
        clock.advance(1_800)
        engine.transition(on: .idleObserved(seconds: 2_400))
        expectClose(engine.elapsed, 600, "a half hour away adds nothing", &problems)

        // Input resumes it.
        engine.transition(on: .idleObserved(seconds: 0))
        expect(engine.state == .running, "input resumes an idle pause", &problems)
        clock.advance(300)
        expectClose(engine.elapsed, 900, "and the clock runs again", &problems)

        // A pause the user pressed must not be undone by typing.
        let manualClock = Clock(base)
        let manual = makeEngine(manualClock)
        manual.transition(on: .launch)
        manualClock.advance(60)
        manual.transition(on: .manualPause)
        manual.transition(on: .idleObserved(seconds: 0))
        expect(manual.state == .paused(reason: .manual),
               "input must not undo a deliberate pause, got \(manual.state)", &problems)

        // The reason survives persistence.
        let idleClock = Clock(base)
        let persisted = makeEngine(idleClock)
        persisted.transition(on: .launch)
        idleClock.advance(1_200)
        persisted.transition(on: .idleObserved(seconds: 700))
        let blob = try? JSONEncoder().encode(persisted.snapshot())
        let reloaded = blob.flatMap { try? JSONDecoder().decode(PersistedState.self, from: $0) }
        expect(reloaded?.restoredPauseReason == .idle,
               "an idle pause must survive a save/load cycle", &problems)
        return problems
    }
```

Register it in the `tests` array in `SelfTest.run()`, after the `testRecordedBreak` entry:

```swift
            ("Idle past ten minutes pauses backdated; typing resumes only that",
             testIdleAutoPause)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./build.sh 2>&1 | grep -E "error:" | head`
Expected: FAIL to compile — `type 'SessionEvent' has no member 'idleObserved'` and `type 'PauseReason' has no member 'idle'`.

- [ ] **Step 3: Add the vocabulary**

In `Sources/Core/SessionState.swift`, add to `PauseReason` after `case away`:

```swift
    /// Nobody has touched the machine for `idlePauseThreshold`. Distinct from
    /// `.manual` because only this one resumes by itself — undoing a pause the
    /// user pressed would be the app overruling a deliberate act.
    case idle
```

Add to its `displayName` switch:

```swift
        case .idle: return "Paused (idle)"
```

Add to `SessionEvent` after `case markedAway`:

```swift
    /// Seconds since the last keypress or click, sampled by the ticker. The
    /// engine is otherwise event-driven; this is the one signal that has to be
    /// observed rather than announced.
    case idleObserved(seconds: TimeInterval)
```

Add to `FocusConstants`, next to `longAwayCapOptions`:

```swift
    /// Idle time after which a session pauses itself. Deliberately tolerant:
    /// reading a long document, thinking, and taking a call are all work the
    /// keyboard cannot see, and a three-minute rule punishes them. Lunch is
    /// still caught.
    static let idlePauseThreshold: TimeInterval = 600
```

In `PersistedState`'s `init(state:...)`, add to the `switch pauseReason` block:

```swift
            case .idle: reason = "idle"
```

And in `restoredPauseReason`:

```swift
        case "idle": return .idle
```

- [ ] **Step 4: Add the transitions**

In `Sources/Core/SessionEngine.swift`, change `enterPause` to accept a moment:

```swift
    /// - Parameter moment: when the pause really began. Idle pauses are
    ///   backdated to the last keypress, so the interval that proves the user is
    ///   gone is excluded along with the rest of the absence.
    private func enterPause(reason: PauseReason, at moment: Date? = nil) {
        cancelDwell()
        pauseStartDate = min(moment ?? now(), now())
        state = .paused(reason: reason)
    }
```

Add to the `.running` block, after the `(.running, .markedAway)` case:

```swift
        case (.running, .idleObserved(let seconds)):
            if seconds >= FocusConstants.idlePauseThreshold {
                enterPause(reason: .idle, at: now().addingTimeInterval(-seconds))
            }
```

Add to the `.paused` block, before the documented no-op line:

```swift
        case (.paused(let reason), .idleObserved(let seconds)):
            // Only an idle pause lifts itself. A pause the user pressed stays
            // pressed until they say otherwise.
            if reason == .idle, seconds < FocusConstants.idlePauseThreshold {
                leavePause()
            }
```

Add `.idleObserved` to the existing documented no-op tuples for `.idle` and `.awaitingUserDecision`:

```swift
        case (.idle, .markedAway), (.idle, .idleObserved):
```

```swift
        case (.awaitingUserDecision, .launch), (.awaitingUserDecision, .awayEnded),
             (.awaitingUserDecision, .dwellExpired), (.awaitingUserDecision, .manualPause),
             (.awaitingUserDecision, .idleObserved),
             (.awaitingUserDecision, .overrideApplied):
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `./build.sh >/dev/null 2>&1 && ./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest 2>&1 | grep -E "FAIL|passed"`
Expected: `68/68 passed`

- [ ] **Step 6: Add `.idleObserved` to the exhaustive sweep**

Test 10's event list is hand-maintained and has silently let two new cases escape already. In `Sources/SelfTest.swift`, add to the `let events: [SessionEvent]` array after `.markedAway`:

```swift
            .idleObserved(seconds: 0),
            .idleObserved(seconds: FocusConstants.idlePauseThreshold + 1),
```

Run: `./build.sh >/dev/null 2>&1 && ./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest 2>&1 | grep -E "FAIL|passed"`
Expected: `68/68 passed`

- [ ] **Step 7: Feed idle from the ticker**

In `Sources/App/SessionStore.swift`, add a stored property beside `tick`:

```swift
    /// Reads one integer per tick. No new timer: the engine is event-driven and
    /// this is the only signal it cannot be told about.
    private let idle = IdleMonitor()
```

In the ticker closure in `startTicker()`, immediately after `self.tick += 1`:

```swift
            self.engine.transition(on: .idleObserved(seconds: self.idle.idleSeconds()))
```

- [ ] **Step 8: Verify the build and relaunch**

Run: `./build.sh 2>&1 | grep -E "error:|warning:"; ./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest 2>&1 | tail -2`
Expected: no output from the first command; `68/68 passed`

- [ ] **Step 9: Commit** *(recorded, skipped — not a git repository)*

```bash
git add Sources/Core/SessionState.swift Sources/Core/SessionEngine.swift Sources/App/SessionStore.swift Sources/SelfTest.swift
git commit -m "feat: pause a session after ten idle minutes, backdated"
```

---

### Task 2: The goal counts session ∩ hands-on

**Files:**
- Create: `Sources/Core/FocusedActiveTime.swift`
- Modify: `Sources/Core/DailyGoal.swift` — take the intersection instead of `archive.workSeconds(on:)`
- Modify: `Sources/App/SessionStore.swift` — supply usage and the running span
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Consumes: `SessionRecord.workType.countsAsFocus`, `SessionRecord.dayBounds(_:calendar:)`, `AppUsageSession.start/end`
- Produces:
  - `FocusedActiveTime.seconds(on:records:usage:running:calendar:) -> TimeInterval`
  - `DailyGoal.init(archive:goal:usage:running:goalSeconds:calendar:now:)` — see Step 5 for the exact signature

- [ ] **Step 1: Write the failing test**

Add to `Sources/SelfTest.swift`, immediately before `// MARK: - 60`:

```swift
    // MARK: - 69

    /// The goal counts only seconds that are both inside a declared session and
    /// within reach of real input. Either alone is a lie: wall-clock sessions
    /// counted an untouched machine, and raw hands-on time would let an hour of
    /// messaging fill a focus goal.
    private static func testFocusedActiveTime() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: base)
        func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3_600) }
        func record(_ from: Double, _ to: Double,
                    type: WorkType = .deepWork) -> SessionRecord {
            SessionRecord(name: "S", workType: type, start: at(from), end: at(to),
                          workSeconds: (to - from) * 3_600)
        }
        func used(_ from: Double, _ to: Double) -> AppUsageSession {
            AppUsageSession(bundleID: "com.a", appName: "Alpha",
                            start: at(from), end: at(to))
        }
        func seconds(_ records: [SessionRecord], _ usage: [AppUsageSession],
                     running: (start: Date, end: Date)? = nil) -> TimeInterval {
            FocusedActiveTime.seconds(on: day, records: records, usage: usage,
                                      running: running, calendar: calendar)
        }

        expectClose(seconds([record(9, 11)], [used(13, 14)]), 0,
                    "no overlap, nothing counted", &problems)
        expectClose(seconds([record(9, 11)], []), 0,
                    "a session with nobody at the keyboard counts nothing", &problems)
        expectClose(seconds([], [used(9, 11)]), 0,
                    "hands-on outside any session counts nothing", &problems)
        expectClose(seconds([record(9, 11)], [used(10, 12)]), 3_600,
                    "only the overlapping hour", &problems)

        // Two overlapping records must not count one second twice.
        expectClose(seconds([record(9, 11), record(10, 12)], [used(9, 12)]), 3 * 3_600,
                    "overlapping sessions are merged, not summed", &problems)
        // Nor two overlapping usage stretches.
        expectClose(seconds([record(9, 12)], [used(9, 11), used(10, 12)]), 3 * 3_600,
                    "overlapping usage is merged, not summed", &problems)

        // Breaks are not focus, so a break covering hands-on time counts nothing.
        expectClose(seconds([record(9, 11, type: .breakTime)], [used(9, 11)]), 0,
                    "a recorded break cannot fill the goal", &problems)

        // The running session participates.
        expectClose(seconds([], [used(9, 11)], running: (at(10), at(12))), 3_600,
                    "the in-flight session counts its overlap too", &problems)

        // Everything is clipped to the day.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let overnight = SessionRecord(name: "S", workType: .deepWork,
                                      start: yesterday.addingTimeInterval(22 * 3_600),
                                      end: at(2), workSeconds: 4 * 3_600)
        let overnightUse = AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                           start: yesterday.addingTimeInterval(22 * 3_600),
                                           end: at(2))
        expectClose(seconds([overnight], [overnightUse]), 2 * 3_600,
                    "only the hours after midnight belong to today", &problems)
        return problems
    }
```

Register it in the `tests` array, after the `testIdleAutoPause` entry:

```swift
            ("The goal counts only declared work you were actually doing",
             testFocusedActiveTime),
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./build.sh 2>&1 | grep -E "error:" | head -3`
Expected: FAIL — `cannot find 'FocusedActiveTime' in scope`.

- [ ] **Step 3: Create the intersection**

Create `Sources/Core/FocusedActiveTime.swift`:

```swift
import Foundation

/// Seconds that are both inside a declared focus session and within reach of
/// real input.
///
/// Neither half is sufficient alone, and the app shipped both mistakes. Session
/// wall-clock counted an untouched machine, so a four-hour goal read as met on
/// two and a half hours of use. Raw hands-on time would let an hour of messaging
/// fill a *focus* goal. The intersection is the only figure that can be filled
/// solely by work the user declared and demonstrably did.
enum FocusedActiveTime {

    /// - Parameter running: the in-flight session's span, or nil when idle.
    static func seconds(on day: Date,
                        records: [SessionRecord],
                        usage: [AppUsageSession],
                        running: (start: Date, end: Date)?,
                        calendar: Calendar = .current) -> TimeInterval {
        guard let bounds = SessionRecord.dayBounds(day, calendar: calendar) else {
            return 0
        }
        var focus = records
            .filter { $0.workType.countsAsFocus }
            .map { (start: $0.start, end: $0.end) }
        if let running { focus.append(running) }

        let focused = merged(clip(focus, to: bounds))
        let handsOn = merged(clip(usage.map { (start: $0.start, end: $0.end) },
                                  to: bounds))
        return overlap(focused, handsOn)
    }

    private typealias Range = (start: Date, end: Date)

    private static func clip(_ ranges: [Range], to bounds: Range) -> [Range] {
        ranges.compactMap { range in
            let low = max(range.start, bounds.start)
            let high = min(range.end, bounds.end)
            return high > low ? (start: low, end: high) : nil
        }
    }

    /// Overlapping ranges become one. Without this, two sessions covering the
    /// same hour would each claim it and the goal would fill twice as fast.
    private static func merged(_ ranges: [Range]) -> [Range] {
        let ordered = ranges.sorted { $0.start < $1.start }
        var result: [Range] = []
        for range in ordered {
            if let last = result.last, range.start <= last.end {
                result[result.count - 1].end = max(last.end, range.end)
            } else {
                result.append(range)
            }
        }
        return result
    }

    /// Both inputs are sorted and disjoint, so this is a linear sweep rather
    /// than the quadratic pass the dashboard's focus-quality figure still uses.
    private static func overlap(_ left: [Range], _ right: [Range]) -> TimeInterval {
        var total: TimeInterval = 0
        var i = 0
        var j = 0
        while i < left.count, j < right.count {
            let low = max(left[i].start, right[j].start)
            let high = min(left[i].end, right[j].end)
            if high > low { total += high.timeIntervalSince(low) }
            if left[i].end < right[j].end { i += 1 } else { j += 1 }
        }
        return total
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `./build.sh >/dev/null 2>&1 && ./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest 2>&1 | grep -E "FAIL|passed"`
Expected: `69/69 passed`

- [ ] **Step 5: Point the goal at it**

In `Sources/Core/DailyGoal.swift`, replace the stored properties and `init` with:

```swift
    private let archive: SessionArchive
    private let goal: TimeInterval
    private let usage: [AppUsageSession]
    private let running: (start: Date, end: Date)?
    private let calendar: Calendar
    private let now: () -> Date

    /// - Parameters:
    ///   - usage: hands-on stretches, already idle-trimmed and system-filtered.
    ///     Empty means the goal reads zero, which is correct: with no record of
    ///     anyone at the keyboard there is no evidence of work.
    ///   - running: the in-flight session's span, or nil when idle.
    init(archive: SessionArchive,
         goal: TimeInterval,
         usage: [AppUsageSession] = [],
         running: (start: Date, end: Date)? = nil,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.archive = archive
        self.goal = goal
        self.usage = usage
        self.running = running
        self.calendar = calendar
        self.now = now
    }
```

Replace `achievedToday()` with:

```swift
    /// Deliberately not `archive.workSeconds(on:)`: a session that ran is a fact,
    /// but the goal is a claim about effort and only the intersection can carry it.
    func achievedToday() -> TimeInterval {
        FocusedActiveTime.seconds(on: now(), records: archive.records,
                                  usage: usage, running: running,
                                  calendar: calendar)
    }
```

Leave `typicalByNow()` reading recorded work: the median describes what past days
contained, and re-deriving it from usage would compare a new rule against old data.

- [ ] **Step 6: Supply usage and the running span from the store**

In `Sources/App/SessionStore.swift`, add to `SessionEngine`'s public surface first — in `Sources/Core/SessionEngine.swift`, next to `elapsedToday()`:

```swift
    /// The running session's span, for figures that intersect it with something
    /// else. Nil when idle.
    var runningSpan: (start: Date, end: Date)? {
        state == .idle ? nil : (start: sessionStartDate, end: now())
    }
```

Then in `SessionStore.refreshLiveFigures()`, replace the `goal = GoalProgress(...)` line with:

```swift
        goal = GoalProgress(goal: engine.store.dailyGoal,
                            achieved: DailyGoal(archive: engine.archive,
                                                goal: engine.store.dailyGoal,
                                                usage: usage?.sessions ?? [],
                                                running: engine.runningSpan)
                                .achievedToday(),
                            typical: cachedTypical)
```

And in `refresh()`, give the cached median the same collaborators so it cannot drift:

```swift
        cachedTypical = DailyGoal(archive: engine.archive,
                                  goal: engine.store.dailyGoal,
                                  usage: usage?.sessions ?? [],
                                  running: engine.runningSpan).typical()
```

- [ ] **Step 7: Verify**

Run: `./build.sh 2>&1 | grep -E "error:|warning:"; ./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest 2>&1 | grep -E "FAIL|passed"`
Expected: no output from the first; `69/69 passed`

- [ ] **Step 8: Commit** *(recorded, skipped — not a git repository)*

```bash
git add Sources/Core/FocusedActiveTime.swift Sources/Core/DailyGoal.swift Sources/Core/SessionEngine.swift Sources/App/SessionStore.swift Sources/SelfTest.swift
git commit -m "feat: fill the daily goal only from declared work actually done"
```

---

### Task 3: The away answers all end the session

**Files:**
- Modify: `Sources/Core/SessionEngine.swift` — `apply(_ decision:)`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Consumes: `archiveCurrentSession(endingAt:)`, `beginFreshSession()`, `activeThreadID`
- Produces: no new API — behaviour change only

- [ ] **Step 1: Write the failing test**

Add to `Sources/SelfTest.swift`, immediately before `// MARK: - 60`:

```swift
    // MARK: - 70

    /// Every answer but "I was working" closes the session where the user
    /// walked away and opens a new one when they got back. What separates them
    /// is the thread: an afternoon split by lunch is still one piece of work.
    private static func testAwayEndsSession() -> [String] {
        var problems: [String] = []
        let work: TimeInterval = 40 * 60
        let away: TimeInterval = 33 * 60

        func run(_ decision: UserDecision) -> (engine: SessionEngine,
                                               left: Date, back: Date) {
            let clock = Clock(base)
            let engine = makeEngine(clock)
            engine.start(workType: .deepWork, intent: "Refactor")
            clock.advance(work)
            let left = clock.value
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(away)
            let back = clock.value
            engine.transition(on: .awayEnded)
            engine.transition(on: .decision(decision))
            return (engine, left, back)
        }

        for decision in [UserDecision.continueSession, .tookBreak, .resetTimer] {
            let (engine, left, back) = run(decision)
            expect(engine.state == .running,
                   "\(decision): a new session should be running", &problems)
            expectClose(engine.elapsed, 0,
                        "\(decision): the new session starts fresh", &problems)
            expectClose(engine.sessionStartDate.timeIntervalSince(back), 0,
                        "\(decision): and starts when the user got back", &problems)
            guard let closed = engine.archive.records
                .last(where: { $0.workType.countsAsFocus }) else {
                problems.append("\(decision): the old session should be archived")
                continue
            }
            expectClose(closed.workSeconds, work,
                        "\(decision): archived work is what was worked", &problems)
            expectClose(closed.end.timeIntervalSince(left), 0,
                        "\(decision): archived end is where they left", &problems)
        }

        // Thread identity is the whole difference between the three.
        let awayRun = run(.continueSession)
        expect(awayRun.engine.activeThreadID
                == awayRun.engine.archive.records.last?.threadID,
               "'I was away' keeps the thread", &problems)

        let freshRun = run(.resetTimer)
        expect(freshRun.engine.activeThreadID
                != freshRun.engine.archive.records.last?.threadID,
               "'Start fresh' takes a new thread", &problems)

        let breakRun = run(.tookBreak)
        let focusRecords = breakRun.engine.archive.records.filter {
            $0.workType.countsAsFocus
        }
        expect(breakRun.engine.activeThreadID == focusRecords.last?.threadID,
               "'It was a break' keeps the thread", &problems)
        expect(breakRun.engine.archive.records.contains { $0.workType == .breakTime },
               "and still records the break", &problems)

        // "I was working" is the one answer that does not split anything.
        let (merged, _, _) = run(.mergeTime)
        expect(merged.archive.records.isEmpty,
               "merging archives nothing, got \(merged.archive.records.count)", &problems)
        expectClose(merged.elapsed, work + away,
                    "and the gap becomes work", &problems)
        return problems
    }
```

Register it after the `testFocusedActiveTime` entry:

```swift
            ("Away closes the session where you left and reopens on return",
             testAwayEndsSession),
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./build.sh >/dev/null 2>&1 && ./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest 2>&1 | grep -A 4 "FAIL"`
Expected: FAIL on test 70 — `continueSession: the new session starts fresh` (elapsed is `work`, not 0).

- [ ] **Step 3: Make the decisions symmetric**

In `Sources/Core/SessionEngine.swift`, replace the whole `switch decision` block inside `apply(_:)` with:

```swift
        switch decision {
        case .mergeTime:
            totalPausedDuration -= away   // it was work after all (D12)
            state = .running
        case .continueSession, .tookBreak, .resetTimer:
            // The session ended when they walked away. Holding it open across
            // the gap made one record span an afternoon, so its elapsed figure
            // measured the span of the work rather than any stretch worked.
            if decision == .tookBreak, let awayStarted,
               away >= FocusConstants.minimumRecordedSession {
                archive.append(SessionRecord(name: "Break",
                                             workType: .breakTime,
                                             start: awayStarted,
                                             end: awayStarted.addingTimeInterval(away),
                                             workSeconds: away,
                                             threadID: UUID()))
            }
            // Time since the return belongs to the session starting now.
            if let returnedAt { totalPausedDuration += interval(from: returnedAt) }
            let thread = activeThreadID
            archiveCurrentSession(endingAt: awayStarted)
            beginFreshSession()
            // Same work, resumed — unless the user said it was something else.
            // `Continue Today` groups by thread, so this is what keeps an
            // afternoon split by lunch reading as one job.
            activeThreadID = decision == .resetTimer ? UUID() : thread
            if let returnedAt { sessionStartDate = returnedAt }
        }
```

`activeThreadID` is declared `private(set) var`, which already permits assignment from
inside `SessionEngine`. No declaration change is needed.

- [ ] **Step 4: Run the test to verify it passes**

Run: `./build.sh >/dev/null 2>&1 && ./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest 2>&1 | grep -E "FAIL|passed" -A 4`
Expected: `70/70 passed`

- [ ] **Step 5: Fix the two older tests that assumed the old behaviour**

Test 5 (`testMergeVersusContinue`) asserts `continued == 60` — under the new rule
`.continueSession` starts a fresh session, so elapsed is 0. Replace its final three
assertions with:

```swift
        expectClose(merged, 60 + away, "merged elapsed", &problems)
        // Continue now closes the old session and opens a new one at the moment
        // of return, so its elapsed starts from zero rather than carrying the
        // pre-away work forward.
        expectClose(continued, 0, "continue starts a fresh clock", &problems)
```

and delete the `expectClose(merged - continued, away, ...)` line above them, which
compared two quantities that are no longer comparable.

Test 14 (`testDecisionAccounting`) asserts `continued.elapsed == work + deliberation`.
Replace that assertion with:

```swift
        let continued = engineAfter(.continueSession)
        expectClose(continued.elapsed, deliberation,
                    "continue starts fresh at the moment of return", &problems)
```

- [ ] **Step 6: Verify**

Run: `./build.sh 2>&1 | grep -E "error:|warning:"; ./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest 2>&1 | grep -E "FAIL|passed" -A 4`
Expected: no output from the first; `70/70 passed`

- [ ] **Step 7: Commit** *(recorded, skipped — not a git repository)*

```bash
git add Sources/Core/SessionEngine.swift Sources/SelfTest.swift
git commit -m "feat: an absence closes the session where it began"
```

---

### Task 4: `Now:` shows the current stretch, not process uptime

**Files:**
- Modify: `Sources/Core/DashboardStats.swift` — `RunningAppInput`, `runningNow(from:)`
- Modify: `Sources/App/SessionStore.swift` — supply the open stretch
- Modify: `Sources/Surfaces/PopoverView.swift` — the second glance line's wording
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Consumes: `AppUsageTracker.currentBundleID`, `AppUsageTracker.openSeconds()`
- Produces: `RunningAppInput.stretchSeconds: TimeInterval?`; `RunningApp.openFor` redefined as stretch length

- [ ] **Step 1: Write the failing test**

Add to `Sources/SelfTest.swift`, immediately before `// MARK: - 60`:

```swift
    // MARK: - 71

    /// `Now: Claude 6h 50m` was the time since the process launched, rendered
    /// directly above `Claude 53m` in Top Apps. Two labels that read alike must
    /// not measure different things.
    private static func testRunningStretch() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fc-stretch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let stats = DashboardStats(
            sessions: SessionArchive(directory: directory, now: { clock.value }),
            usage: AppUsageArchive(directory: directory, now: { clock.value }),
            now: { clock.value })
        let launched = base.addingTimeInterval(-6 * 3_600)

        let apps = stats.runningNow(from: [
            RunningAppInput(bundleID: "com.a", appName: "Alpha",
                            launched: launched, stretchSeconds: 12 * 60),
            RunningAppInput(bundleID: "com.b", appName: "Beta",
                            launched: launched, stretchSeconds: nil)
        ])

        guard let alpha = apps.first(where: { $0.bundleID == "com.a" }) else {
            problems.append("the frontmost app should be listed")
            return problems
        }
        expectClose(alpha.openFor ?? -1, 12 * 60,
                    "the current stretch, not six hours of uptime", &problems)

        let beta = apps.first { $0.bundleID == "com.b" }
        expect(beta?.openFor == nil,
               "an app with no open stretch reports no figure", &problems)
        expect(apps.first?.bundleID == "com.a",
               "the app you are actually in sorts first", &problems)
        return problems
    }
```

Register it after the `testAwayEndsSession` entry:

```swift
            ("'Now' reports the current stretch, not process uptime",
             testRunningStretch),
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./build.sh 2>&1 | grep -E "error:" | head -3`
Expected: FAIL — `extra argument 'stretchSeconds' in call`.

- [ ] **Step 3: Redefine the input and the output**

In `Sources/Core/DashboardStats.swift`, replace `RunningAppInput` with:

```swift
/// Plain input so `Core` never imports AppKit and the tests need no real processes.
struct RunningAppInput: Equatable {
    let bundleID: String
    let appName: String
    let launched: Date?
    /// How long this app has been frontmost in the current unbroken stretch, or
    /// nil when it is not the one in front. Process uptime was what this used to
    /// carry, which made `Now: Claude 6h 50m` sit above `Claude 53m` in the same
    /// panel and mean something unrelated.
    var stretchSeconds: TimeInterval?
}
```

Replace `runningNow(from:)` with:

```swift
    func runningNow(from inputs: [RunningAppInput]) -> [RunningApp] {
        inputs
            // No launch date means nothing useful can be said: Finder is started
            // at login, runs permanently, and its row could only ever read
            // "since login". Excluded rather than listed uninformatively.
            .compactMap { input -> RunningApp? in
                guard input.launched != nil else { return nil }
                return RunningApp(bundleID: input.bundleID,
                                  appName: input.appName,
                                  launched: input.launched,
                                  openFor: input.stretchSeconds)
            }
            // The app you are actually in leads; the rest keep a stable order so
            // the list does not reshuffle on every refresh.
            .sorted {
                ($0.openFor ?? -1, $1.appName) > ($1.openFor ?? -1, $0.appName)
            }
    }
```

Update `RunningApp.openFor`'s doc comment:

```swift
    /// Seconds in the current unbroken stretch, or nil when this app is not the
    /// one in front.
    let openFor: TimeInterval?
```

- [ ] **Step 4: Supply the stretch from the store**

In `Sources/App/SessionStore.swift`, in `refreshDashboard()`, replace the
`RunningAppInput(...)` construction with:

```swift
                let frontmost = tracker?.currentBundleID
                return RunningAppInput(bundleID: bundleID,
                                       appName: app.localizedName ?? bundleID,
                                       launched: app.launchDate,
                                       stretchSeconds: bundleID == frontmost
                                           ? tracker?.openSeconds() : nil)
```

Hoist `let frontmost = tracker?.currentBundleID` above the `.compactMap` so it is read
once rather than per application.

- [ ] **Step 5: Reword the second glance line**

In `Sources/Core/DashboardStats.swift:413`, change the headline string:

```swift
                       headline: "Longest stretch in one app today",
```

Then update its assertion in `Sources/SelfTest.swift:1710`:

```swift
        expect(longest.headline == "Longest stretch in one app today",
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `./build.sh 2>&1 | grep -E "error:|warning:"; ./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest 2>&1 | grep -E "FAIL|passed" -A 4`
Expected: no output from the first; `71/71 passed`

- [ ] **Step 7: Commit** *(recorded, skipped — not a git repository)*

```bash
git add Sources/Core/DashboardStats.swift Sources/App/SessionStore.swift Sources/Surfaces/PopoverView.swift Sources/SelfTest.swift
git commit -m "fix: 'Now' reports the current stretch rather than process uptime"
```

---

### Task 5: Responsive popover

**Files:**
- Create: `Sources/Design/PopoverMetrics.swift`
- Modify: `Sources/Surfaces/PopoverView.swift` — pinned-scroll-pinned layout
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces: `PopoverMetrics.fitting(_ visible: CGSize) -> PopoverMetrics`, with `width: CGFloat`, `maxHeight: CGFloat`, `twoColumn: Bool`

- [ ] **Step 1: Write the failing test**

Add to `Sources/SelfTest.swift`, immediately before `// MARK: - 60`:

```swift
    // MARK: - 72

    /// The panel had a fixed width and unbounded height, so its lower half ran
    /// off a 14" display once Settings was expanded.
    private static func testPopoverMetrics() -> [String] {
        var problems: [String] = []

        // 14" MacBook Pro, menu bar and Dock removed.
        let laptop = PopoverMetrics.fitting(CGSize(width: 1_512, height: 900))
        expect(laptop.maxHeight < 900,
               "the panel must be shorter than the screen", &problems)
        expect(laptop.maxHeight >= 600,
               "but not uselessly short, got \(laptop.maxHeight)", &problems)

        // 11" Air: still fits, still one column.
        let small = PopoverMetrics.fitting(CGSize(width: 1_366, height: 700))
        expect(small.maxHeight < 700, "shorter than a small screen too", &problems)
        expect(!small.twoColumn,
               "a short screen gains nothing from two columns", &problems)
        expect(small.width == Tokens.popoverWidth,
               "and stays at the single-column width", &problems)

        // A large display earns the second column.
        let desktop = PopoverMetrics.fitting(CGSize(width: 2_560, height: 1_440))
        expect(desktop.twoColumn, "a large screen affords two columns", &problems)
        expect(desktop.width > Tokens.popoverWidth,
               "which needs more width, got \(desktop.width)", &problems)
        expect(desktop.width <= 640, "but never a whole window", &problems)
        return problems
    }
```

Register it after the `testRunningStretch` entry:

```swift
            ("The popover fits the screen it opens on", testPopoverMetrics),
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./build.sh 2>&1 | grep -E "error:" | head -3`
Expected: FAIL — `cannot find 'PopoverMetrics' in scope`.

- [ ] **Step 3: Create the metrics**

Create `Sources/Design/PopoverMetrics.swift`:

```swift
import CoreGraphics

/// How large the menu-bar panel may be on the screen it is opening on.
///
/// It was a fixed 320pt wide with no height limit and no scroll region, so on a
/// 14" display the lower half — Settings, and the Quit button — simply ran off
/// the bottom with no way to reach it.
struct PopoverMetrics: Equatable {
    let width: CGFloat
    let maxHeight: CGFloat
    let twoColumn: Bool

    /// Leaves a margin below the panel rather than filling the screen edge to
    /// edge, which reads as a window that failed to size itself.
    private static let heightShare: CGFloat = 0.8
    /// Below this the panel would be too short to be worth splitting.
    private static let twoColumnMinimumHeight: CGFloat = 1_000
    private static let twoColumnMinimumWidth: CGFloat = 1_800
    private static let twoColumnWidth: CGFloat = 560

    /// - Parameter visible: the screen's usable area, menu bar and Dock excluded.
    static func fitting(_ visible: CGSize) -> PopoverMetrics {
        let twoColumn = visible.width >= twoColumnMinimumWidth
            && visible.height >= twoColumnMinimumHeight
        return PopoverMetrics(
            width: twoColumn ? twoColumnWidth : Tokens.popoverWidth,
            // Floored so a very small or misreported screen still yields a
            // usable panel rather than a sliver.
            maxHeight: max(480, visible.height * heightShare),
            twoColumn: twoColumn)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `./build.sh >/dev/null 2>&1 && ./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest 2>&1 | grep -E "FAIL|passed"`
Expected: `72/72 passed`

- [ ] **Step 5: Restructure the popover**

In `Sources/Surfaces/PopoverView.swift`, add near the top of the struct:

```swift
    /// Read at body evaluation rather than stored: the panel can open on a
    /// different display than the one it last opened on.
    private var metrics: PopoverMetrics {
        PopoverMetrics.fitting(NSScreen.main?.visibleFrame.size
                               ?? CGSize(width: 1_440, height: 900))
    }
```

Add `import AppKit` beneath `import SwiftUI` if it is not already present.

Replace the `body` with:

```swift
    var body: some View {
        let metrics = self.metrics
        return VStack(alignment: .leading, spacing: Tokens.Space.m) {
            // Pinned: the figures glanced at most, and the controls reached for
            // most. These must never scroll out of view.
            header
            GoalBar(progress: store.goal)
                .explains("goal", "Focus time towards today's goal", goalDetail)
            hero

            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    scrollingBody(twoColumn: metrics.twoColumn)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()

            footer
        }
        .padding(Tokens.Space.l)
        .frame(width: metrics.width)
        .frame(maxHeight: metrics.maxHeight)
        .background(.ultraThinMaterial)
        .tipLayer(tips)
        .onAppear {
            store.refresh()
            intentFocused = store.isIdle
        }
    }

    /// Everything that may scroll. In two-column mode the timeline and the app
    /// list sit side by side, which roughly halves the height.
    @ViewBuilder private func scrollingBody(twoColumn: Bool) -> some View {
        if store.isIdle && !store.quickStarts.isEmpty {
            QuickStartRow(items: store.quickStarts) { store.startQuick($0) }
        }
        if twoColumn {
            HStack(alignment: .top, spacing: Tokens.Space.l) {
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    timelineSection
                    continueSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    topApps
                    glanceLines
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            timelineSection
            Divider()
            continueSection
            Divider()
            topApps
            Divider()
            glanceLines
        }
        Divider()
        settingsRow
    }

    private var timelineSection: some View {
        DayTimelineView(store: store, compact: true)
            .explains("timeline", "Your day, left to right",
                      "Each coloured block is a stretch in one app, in the "
                      + "order it happened. Colours match the app list "
                      + "below. Empty space is time away from the Mac. A "
                      + "wide block means a long unbroken stretch; lots of "
                      + "thin stripes means you were switching often.")
    }

    private var continueSection: some View {
        ContinueTodaySection(store: store, limit: store.menuSessionCount)
            .explains("continue", "Pick up where you left off",
                      "Sessions you already started today. Choosing one "
                      + "carries on with that same piece of work instead of "
                      + "beginning a new one, so an afternoon split by "
                      + "lunch still reads as one job rather than two.")
    }
```

- [ ] **Step 6: Verify the build, then look at the rendered panel**

Run: `./build.sh 2>&1 | grep -E "error:|warning:"; ./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest 2>&1 | grep -E "FAIL|passed"`
Expected: no output from the first; `72/72 passed`

Then render and inspect — `ScrollView` has no intrinsic content under `ImageRenderer`, so
confirm the harness still produces all twelve images rather than trusting the build:

Run: `rm -rf /tmp/fcfit && ./FocusContinuity.app/Contents/MacOS/FocusContinuity --snapshot /tmp/fcfit 2>&1 | tail -2`
Expected: `12/12 snapshots written to /tmp/fcfit`

Open `/tmp/fcfit/running-dark.png` and confirm the header, goal bar and timer are present
and nothing is clipped. If the snapshot renders empty, the `ScrollView` is swallowing the
content under `ImageRenderer` — pass a `scrolls: Bool = true` flag through `PopoverView`
exactly as `DashboardView` already does, and have `Snapshotter` set it to `false`.

- [ ] **Step 7: Relaunch and check the real panel against the real screen**

Run: `pkill -f "FocusContinuity.app/Contents/MacOS"; sleep 1; open ./FocusContinuity.app`
Then open the menu bar panel, expand Settings, and confirm the Quit button is reachable
without the panel running off the bottom of the display.

- [ ] **Step 8: Commit** *(recorded, skipped — not a git repository)*

```bash
git add Sources/Design/PopoverMetrics.swift Sources/Surfaces/PopoverView.swift Sources/SelfTest.swift
git commit -m "feat: fit the popover to the screen it opens on"
```

---

### Task 6: Say which clock is which

**Files:**
- Modify: `Sources/Surfaces/PopoverView.swift` — hero subtitle and tooltip copy
- Modify: `Sources/Design/Components/Components.swift` — menu-bar accessibility label
- Modify: `README.md`

**Interfaces:**
- Consumes: `store.elapsed`, `store.goal`, `store.trackedToday`
- Produces: no new API — copy only

- [ ] **Step 1: Name the hero timer**

In `Sources/Surfaces/PopoverView.swift`, update the `explains` on `LiveTimer` so it states
the scope and points at the day figures:

```swift
                    .explains("timer", "This session, not today",
                              "Time since this focus session began — one stretch "
                              + "of work, not the day's total. It pauses itself "
                              + "after \(Int(FocusConstants.idlePauseThreshold / 60)) "
                              + "minutes without a keypress and starts again when "
                              + "you touch the machine, so thinking time counts "
                              + "and lunch does not.\n\n"
                              + "The day's totals are the two figures above: what "
                              + "you did at the Mac, and how much of it went "
                              + "towards your goal.")
```

- [ ] **Step 2: Name the menu-bar figure**

In `Sources/Design/Components/Components.swift`, in `MenuBarLabel`, set an accessibility
label that states the scope:

```swift
        .accessibilityLabel(state == .idle
                            ? "FocusContinuity, no session running"
                            : "Current session \(Tokens.spent(elapsed))")
```

Place it on the outermost view of `MenuBarLabel`'s body.

- [ ] **Step 3: Update the goal tooltip to match the new rule**

In `Sources/Surfaces/PopoverView.swift`, replace the first sentence of `goalDetail`:

```swift
        let base = "How much focused work you have done today, against the goal "
            + "you set. A minute counts only when both things are true: a focus "
            + "session was running, and you were actually at the keyboard. "
            + "Reading for ten minutes mid-session keeps the session alive but "
            + "does not fill this; an hour of messaging with no session running "
            + "fills nothing at all. "
```

- [ ] **Step 4: Update the README**

In `README.md`, in the `### Timing` section, add after the paragraph about the away ladder:

```markdown
A session also pauses itself after ten minutes without a keypress or click, backdated to
when input actually stopped, and resumes on the next input. Only idle pauses lift
themselves — a pause you pressed stays pressed.

The daily goal counts the **intersection** of "a session was running" and "you were at the
keyboard". Session wall-clock alone counted an untouched machine; hands-on time alone would
let an hour of messaging fill a focus goal. `todayTotal`, the week chart and the streak keep
using recorded session time, because a session that happened is a fact — only the goal, which
is a claim about effort, uses the intersection.
```

Update the test count in the `## Test` section from `Sixty-six` to `Seventy-two`.

- [ ] **Step 5: Verify**

Run: `./build.sh 2>&1 | grep -E "error:|warning:"; ./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest 2>&1 | grep -E "FAIL|passed"`
Expected: no output from the first; `72/72 passed`

- [ ] **Step 6: Commit** *(recorded, skipped — not a git repository)*

```bash
git add Sources/Surfaces/PopoverView.swift Sources/Design/Components/Components.swift README.md
git commit -m "docs: state which figure is the session and which is the day"
```

---

### Task 7: The menu bar is always today; the dashboard can reach any day

**Files:**
- Modify: `Sources/App/SessionStore.swift` — a today-scoped glance, separate from the selected day
- Modify: `Sources/Surfaces/PopoverView.swift` — read the glance, not the selection
- Modify: `Sources/Surfaces/Dashboard/DashboardView.swift` — reset on appear, add the date picker
- Test: `Sources/SelfTest.swift`

**Problem:** `dayOffset` is one value shared by both surfaces. Stepping the dashboard back
to Yesterday re-scoped the menu bar to Yesterday too, and it stayed there for as long as
the process lived — the dashboard *window* closing does not reset it, only quitting does.
A menu-bar panel is a "right now" surface and must never show a past day.

**Interfaces:**
- Produces: `SessionStore.todayGlance: TodayGlance` with `timeline: [TimelineSegment]`,
  `rankedApps: [AppShare]`, `insights: [Insight]`
- Consumes: existing `DashboardStats`, `earliestRecordedDay()`

- [ ] **Step 1: Write the failing test**

Add to `Sources/SelfTest.swift`, immediately before `// MARK: - 60`:

```swift
    // MARK: - 73

    /// Stepping the dashboard to Yesterday must not re-scope the menu bar. They
    /// shared one `dayOffset`, so the panel that exists to answer "how am I doing
    /// right now" quietly started answering it about a day that had ended.
    private static func testGlanceStaysToday() -> [String] {
        var problems: [String] = []
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fc-glance-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = Clock(base)
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: clock.value)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return ["could not build a two-day window"]
        }
        usage.record(AppUsageSession(bundleID: "com.today", appName: "TodayApp",
                                     start: today.addingTimeInterval(3_600),
                                     end: today.addingTimeInterval(7_200)))
        usage.record(AppUsageSession(bundleID: "com.past", appName: "PastApp",
                                     start: yesterday.addingTimeInterval(3_600),
                                     end: yesterday.addingTimeInterval(7_200)))

        let stats = DashboardStats(
            sessions: SessionArchive(directory: directory, now: { clock.value }),
            usage: usage, now: { clock.value })

        // The glance is built for today whatever day is selected.
        let todayApps = stats.appShares(for: today)
        let pastApps = stats.appShares(for: yesterday)
        expect(todayApps.first?.appName == "TodayApp",
               "today's glance names today's app", &problems)
        expect(pastApps.first?.appName == "PastApp",
               "and the selected day is a separate question", &problems)
        expect(todayApps.first?.appName != pastApps.first?.appName,
               "the two must not be the same computation", &problems)
        return problems
    }
```

If `appShares(for:)` is not the accessor `refreshDashboard()` already uses for
`rankedApps`, substitute whichever method it calls — read
`Sources/App/SessionStore.swift:481` onward and use the same one.

Register it after the `testPopoverMetrics` entry:

```swift
            ("The menu bar stays on today when the dashboard browses back",
             testGlanceStaysToday),
```

- [ ] **Step 2: Run the test to verify it fails or passes**

Run: `./build.sh >/dev/null 2>&1 && ./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest 2>&1 | grep -E "FAIL|passed"`
Expected: `73/73 passed` — this test pins `DashboardStats` behaviour that is already
correct. The defect is in `SessionStore`, which the headless harness cannot drive; the
test exists so a later refactor cannot collapse the two computations into one.

- [ ] **Step 3: Give the popover its own today-scoped values**

In `Sources/App/SessionStore.swift`, add published properties beside `rankedApps`:

```swift
    /// Today's figures, for the menu bar. Separate from the day-scoped ones
    /// because the dashboard may be browsing history while this panel must still
    /// answer "how am I doing right now".
    @Published private(set) var glanceTimeline: [TimelineSegment] = []
    @Published private(set) var glanceApps: [AppShare] = []
    @Published private(set) var glanceInsights: [Insight] = []
```

At the end of `refreshDashboard()`, add:

```swift
        // When the dashboard is on today these are the same computation, so the
        // second pass only runs while browsing history.
        if dayOffset == 0 {
            glanceTimeline = timeline
            glanceApps = rankedApps
            glanceInsights = insights
        } else {
            let today = Date()
            glanceTimeline = stats.timeline(for: today)
            glanceApps = stats.appShares(for: today)
            glanceInsights = stats.insights(for: today)
        }
```

Use the same method names `refreshDashboard()` already calls for `timeline`,
`rankedApps` and `insights`; read the existing body and mirror it exactly.

- [ ] **Step 4: Point the popover at them**

In `Sources/Surfaces/PopoverView.swift`:
- `topApps` reads `store.glanceApps` instead of `store.rankedApps`.
- `glanceLines` reads `store.glanceInsights.first` instead of `store.insights.first`.
- `timelineSection` passes the glance timeline. `DayTimelineView` currently takes the
  whole store; add `var segments: [TimelineSegment]? = nil` to it, defaulting to the
  store's own `timeline` when nil, and have the popover pass `store.glanceTimeline`.

- [ ] **Step 5: Reset the dashboard to today when it opens**

In `Sources/Surfaces/Dashboard/DashboardView.swift`, change the `onAppear`:

```swift
        .onAppear {
            // Reopening the window is a fresh question, and the question is
            // almost always about today. The selection survived a window close
            // before, so the dashboard reopened on whatever day was last browsed.
            store.goToToday()
            store.refresh()
        }
```

- [ ] **Step 6: Make the date label a date picker**

In `Sources/Surfaces/Dashboard/DashboardView.swift`, replace the `Text(store.dayLabel)`
inside `dayStepper` with a popover-presenting button. Add to `DashboardView`:

```swift
    @StateObject private var calendarShown = BoolBox()
```

and, in `Sources/Design/Components/Components.swift`, a tiny box because `@State` does
not compile on this toolchain:

```swift
/// A single boolean that a view can bind to. `@State` is unavailable here —
/// Command Line Tools ships no SwiftUIMacros plugin — so even one flag needs an
/// object behind it.
final class BoolBox: ObservableObject {
    @Published var value = false
    init(_ value: Bool = false) { self.value = value }
}
```

Then in `dayStepper`:

```swift
            Button {
                calendarShown.value.toggle()
            } label: {
                Text(store.dayLabel)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 96)
            }
            .buttonStyle(.plain)
            .help("Pick a date")
            .popover(isPresented: Binding(get: { calendarShown.value },
                                          set: { calendarShown.value = $0 })) {
                DatePicker("", selection: dateBinding,
                           in: (store.earliestSelectableDay ?? Date())...Date(),
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(Tokens.Space.m)
                    .frame(width: 260)
            }
```

Add the binding to `DashboardView`:

```swift
    private var dateBinding: Binding<Date> {
        Binding(get: { store.selectedDay },
                set: { store.selectDate($0); calendarShown.value = false })
    }
```

- [ ] **Step 7: Add the store API the picker needs**

In `Sources/App/SessionStore.swift`, beside `goToToday()`:

```swift
    /// The first day with anything recorded — the calendar cannot reach behind
    /// it, because there is nothing there to show.
    var earliestSelectableDay: Date? { earliestDay }

    /// Jumps to a specific date. Clamped to the recorded range so the picker can
    /// never land the dashboard on an empty day it refuses to step to.
    func selectDate(_ date: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var target = calendar.startOfDay(for: date)
        if let earliest = earliestDay, target < earliest { target = earliest }
        if target > today { target = today }
        let days = calendar.dateComponents([.day], from: target, to: today).day ?? 0
        selectDay(offset: max(0, days))
    }
```

- [ ] **Step 8: Verify**

Run: `./build.sh 2>&1 | grep -E "error:|warning:"; ./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest 2>&1 | grep -E "FAIL|passed"`
Expected: no output from the first; `73/73 passed`

- [ ] **Step 9: Check it against the live app**

Run: `pkill -f "FocusContinuity.app/Contents/MacOS"; sleep 1; open ./FocusContinuity.app`
Then: open the dashboard, step back to Yesterday, open the menu-bar panel and confirm it
still shows today's apps and timeline. Close the dashboard, reopen it, confirm it reads
Today. Click the date label and pick a date from the calendar.

- [ ] **Step 10: Commit** *(recorded, skipped — not a git repository)*

```bash
git add Sources/App/SessionStore.swift Sources/Surfaces/PopoverView.swift Sources/Surfaces/Dashboard/DashboardView.swift Sources/Design/Components/Components.swift Sources/SelfTest.swift
git commit -m "fix: the menu bar always shows today; the dashboard gets a date picker"
```

---

## Verification after all tasks

- [ ] `./build.sh` produces no warnings and no errors.
- [x] `--selftest` reports `79/79 passed` (73 at the time of writing; 74–79 were added by
  the 2026-08-22 audit — see the spec's Testing section).
- [ ] The dashboard on Yesterday leaves the menu-bar panel showing today.
- [ ] `--snapshot` writes 12 images and `running-dark.png` shows an unclipped panel.
- [ ] The live app: open the panel, expand Settings, confirm Quit is reachable.
- [ ] The live app: leave the machine untouched for eleven minutes with a session running;
      confirm the hero timer shows paused and has lost roughly ten minutes, and that
      touching the trackpad resumes it.
