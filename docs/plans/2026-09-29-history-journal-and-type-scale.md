# History Journal and Type Scale Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Step the whole app's type scale down to Mac-standard sizes, and rebuild History as one scrolling journal with a rail that describes only the selected month, day or session.

**Architecture:** A pure builder (`HistoryJournalBuilder`) turns the store's existing day index (`historyDays`) and search hits into journal entries (month / day / quiet run). The store caches them per evidence revision. `MainWindowModel` holds a `HistorySelection` in place of the old range, span and paging state. Two new views render it: `HistoryJournal` for the column and `HistoryJournalRail` for the rail. The old Insights-based History is retired to `_trash/`.

**Tech Stack:** Swift 5, SwiftUI + AppKit, macOS 13 target, built by `swiftc` through `build.sh`. There is no Xcode project and no SPM. Self-tests live in `Sources/Verification/*Checks.swift` and are registered in `Sources/SelfTest.swift`.

**Spec:** `docs/specs/2026-09-29-history-journal-and-type-scale-design.md`

## Global Constraints

- Target `arm64-apple-macos13.0`, Swift 5. No new dependencies. No macOS 14-only API (`onKeyPress`, `focusEffectDisabled`, `ContentUnavailableView` are out).
- Type scale exactly `[9, 10, 11, 12, 13, 14, 15, 19, 22, 24, 36]` (micro, smallLabel, ring, metadata, control, row, section, headline, page, metric, timer). Story headline 20pt. `StoryLayout.railWidth` 300.
- Colour values from the accessibility branch stay untouched. The type-scale change touches sizes only.
- Keep the accessibility branch's edits in `StoryChromeBar`, `MainWindowView`, `WelcomeCoach`, `FirstRun`, `DesignTokens`, `StoryStyle` and `docs/usage.md`:
  - the session pill's spoken label and the "Toolbar" row label
  - the modal report and the VoiceOver order
  - ⌘] / ⌘[ in the tour
- Each fact is shown once. Logged focus, recorded app use and goal credit stay separate measures and are never merged.
- Duration figures in History use `Text(durations:)`. Labels built from strings that contain compact durations go through `DurationText.spoken(in:)`.
- Motion goes through `Tokens.Motion.animation(_:reduceMotion:)` or `MainWindowModel.animated`, so Reduce Motion is honoured.
- Never delete a file: retired files move to `/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/_trash/2026-09-29-history-journal/` (the main checkout's `_trash/`, which is gitignored; the worktree's copy would vanish with the worktree).
- Commit messages follow the repo's style: one plain sentence naming what now works, no `feat:` prefix. Every message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- The self-test count never drops below the baseline recorded in Task 0.
- Build and test with the sandbox disabled: `./build.sh --check` (the `sips` icon step fails inside the sandbox). The quick compile check runs in the sandbox: `swiftc -typecheck -module-cache-path $TMPDIR/mc -swift-version 5 -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 $(find Sources -name '*.swift')`.

## Review Focus

1. **Midnight or month rollover while History is open.** Today's row and the new month's header must appear; the old "today" becomes a normal day. This is pinned in Task 2 (`monthBoundary`).
2. **Daylight-saving days** (Sydney, 4 Oct 2026). Month bars keep 31 slots, days step without skipping or doubling, and quiet runs stay correct. Pinned in Task 2 (`daylightSaving`).
3. **A day holding only a recorded break**, with no focus, no app use and no session. It must still get its own row, not vanish into a quiet run. Pinned in Task 2 (`breakOnlyDay`).
4. **A selected session that is removed, or hidden by a search.** The rail must fall back to its month and must not show an empty or stale session. Pinned in Task 4 (`railFallsBackToMonth`).
5. **Keyboard stepping across a day with no sessions, a quiet run, and a month boundary.** ↑/↓ must never land on a quiet line or get stuck. Pinned in Task 2 (`keyboardSteps`).

---

### Task 0: Baseline

**Files:** none changed.

- [ ] **Step 1: Confirm the branch base**

Run: `git log --oneline -3 && git status --short`
Expected: HEAD is the spec commit on `claude/app-size-history-redesign-2628b9`, working tree clean.

- [ ] **Step 2: Record the self-test baseline (sandbox disabled)**

Run: `./build.sh --check 2>&1 | grep -E "\[FAIL\]|passed$"`
Expected: one line `N/N passed`, where N is about 484. Write N down: every later task must end with at least N passing.

- [ ] **Step 3: Render the "before" Day page (sandbox disabled)**

```bash
./build.sh
mkdir -p "$TMPDIR/fc-before"
FC_SNAPSHOT_ONLY=storyDay ./FocusContinuity.app/Contents/MacOS/FocusContinuity --snapshot "$TMPDIR/fc-before"
FC_SNAPSHOT_ONLY=insightsEnough ./FocusContinuity.app/Contents/MacOS/FocusContinuity --snapshot "$TMPDIR/fc-before"
ls "$TMPDIR/fc-before"
```
Expected: PNGs for `storyDay` and `insightsEnough` in light, dark and system. Keep them for the Task 7 before/after comparison.

- [ ] **Step 4: Tell the Manager session that `Sources/Surfaces/Story/StoryColumns.swift` gains five render-evidence cases in Task 4**

Send via SendMessage to `local_346045dc-bea7-4062-82e0-a89dea4ac39c`: "History session will add five cases to `StoryRenderEvidence` in `Surfaces/Story/StoryColumns.swift` (enum only). Say if you have edits there."

---

### Task 1: The type scale steps down

**Files:**
- Modify: `Sources/Design/DesignTokens.swift:112-123` (`Tokens.Typography.Size`)
- Modify: `Sources/Design/StoryStyle.swift:22` (`headline`)
- Modify: `Sources/Surfaces/Story/StoryView.swift:5` (`railWidth`)
- Test: `Sources/Verification/CompactControlsChecks.swift` (`typeScaleHoldsItsShape`)

**Interfaces:**
- Produces: `StoryStyle.headlineSize: CGFloat` (= 20). `Tokens.Typography.Size.all` is unchanged in shape.

- [ ] **Step 1: Pin the approved scale in the existing check**

In `CompactControlsChecks.typeScaleHoldsItsShape()`, directly after the `if steps.count > 12 { … }` block, add:

```swift
        // The Mac-sized scale approved on 2026-09-29: rows at 14, not 15;
        // a 19pt headline, not 23. Text had run a step above native apps.
        if steps != [9, 10, 11, 12, 13, 14, 15, 19, 22, 24, 36] {
            failures.append("The type scale is not the approved Mac-sized scale: \(steps)")
        }
        if StoryStyle.headlineSize != 20 {
            failures.append("The story headline is \(StoryStyle.headlineSize)pt, not 20pt")
        }
        if StoryLayout.railWidth != 300 {
            failures.append("The rail is \(StoryLayout.railWidth)pt wide, not 300pt")
        }
```

- [ ] **Step 2: Confirm it fails to compile**

Run the typecheck command from Global Constraints.
Expected: error `type 'StoryStyle' has no member 'headlineSize'`.

- [ ] **Step 3: Change the three constants**

In `DesignTokens.swift`, the `Size` enum becomes:

```swift
        enum Size {
            static let micro: CGFloat = 9
            static let smallLabel: CGFloat = 10
            static let ring: CGFloat = 11
            static let metadata: CGFloat = 12
            static let control: CGFloat = 13
            static let row: CGFloat = 14
            static let section: CGFloat = 15
            static let headline: CGFloat = 19
            static let page: CGFloat = 22
            static let metric: CGFloat = 24
            static let timer: CGFloat = 36
```
Leave the `all` array and the doc comment as they are.

In `StoryStyle.swift`, replace
```swift
    static let headline = Font.system(size: 25, weight: .semibold)
```
with
```swift
    /// The story's sentence. 20pt since 2026-09-29: at 25 it wrapped to three
    /// lines on History and read a step larger than the Mac around it.
    static let headlineSize: CGFloat = 20
    static let headline = Font.system(size: headlineSize, weight: .semibold)
```

In `StoryView.swift`, change `static let railWidth: CGFloat = 336` to `static let railWidth: CGFloat = 300`.

- [ ] **Step 4: Run the self-tests (sandbox disabled)**

Run: `./build.sh --check 2>&1 | grep -E "\[FAIL\]|^         - |passed$"`
Expected: no `[FAIL]`, and `N/N passed` with N at least the baseline. If a layout check fails because text now fits differently, read its message. Fix the check's expectation only when it pinned the old size. Never re-grow a size.

- [ ] **Step 5: Commit**

```bash
git add Sources/Design/DesignTokens.swift Sources/Design/StoryStyle.swift Sources/Surfaces/Story/StoryView.swift Sources/Verification/CompactControlsChecks.swift
git commit -m "Text and cards are a step smaller, the size of the Mac around them

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The journal read model

**Files:**
- Create: `Sources/App/SessionStore+Journal.swift`
- Modify: `Sources/App/SessionStore.swift` (two stored properties beside `insightReadingCache`, around line 467)
- Create: `Sources/Verification/HistoryJournalChecks.swift`
- Modify: `Sources/SelfTest.swift:448` (register `HistoryJournalChecks.tests`)

**Interfaces:**
- Consumes: `HistoryDay` (`date, tracked, focused, sessions, appBundleIDs, workTypes`), `HistorySearchHit` (`id, threadID, name, workType, start, end, worked, day, noteSnippet, matchedApps`), `SessionStore.historyDays` (newest first), `historyFilter.isActive`, `historySearchHits(limit:)`, `evidenceRevision`, `storyDayProjection(on:)`, `metadataArchive.metadata(for:)?.note`.
- Produces:
  - `struct JournalMonth { start, focused, tracked, focusedDays, dailyFocus: [TimeInterval]; averagePerFocusedDay }`
  - `struct JournalDay { date, focused, tracked, sessions, threads: Set<UUID>?; isAppUseOnly }`
  - `struct JournalQuiet { first, last; isSingleDay }`
  - `struct JournalMonthTotal { start, focused }`
  - `enum JournalEntry { month, day, quiet; id: String; static monthID(_:), dayID(_:) }`
  - `enum HistorySelection: Hashable { month(Date), day(Date), session(thread: UUID, day: Date); day: Date?; monthStart(calendar:) }`
  - `enum HistoryJournalBuilder`:
    - `entries(days:today:calendar:)`, `entries(matching:calendar:)`, `patching(_:today:calendar:)`
    - `step(from:by:entries:threads:)`, `selection(forJump:in:calendar:)`, `anchorID(for:in:calendar:)`
    - `month(starting:days:calendar:)`, `recentMonths(endingAt:focusByDay:firstDay:count:calendar:)`, `rows(_:only:)`
  - On `SessionStore`: `historyJournal() -> [JournalEntry]`, `journalRows(on:only:) -> [DayEntry]`, `journalThreads(on:only:) -> [UUID]`, `journalSession(thread:on:) -> DaySession?`, `journalNote(for:) -> String?`, `journalComputeCount: Int`

- [ ] **Step 1: Write the failing checks**

Create `Sources/Verification/HistoryJournalChecks.swift`:

```swift
import Foundation

/// History is one journal, newest first, back to the first recorded day.
/// These pin its shape: what gets a row, what collapses into a quiet line,
/// what the headers total, and how ↑/↓ walk it.
enum HistoryJournalChecks {
    static let tests: [(String, () -> [String])] = [
        ("The journal runs newest first to the first recorded day and no further", newestFirst),
        ("Month headers total their own days once", monthTotals),
        ("A day at the Mac with no session reads as app use only", appUseOnly),
        ("A day with only a recorded break keeps its own row", breakOnlyDay),
        ("With nothing recorded the journal is this month and today", emptyArchive),
        ("A new month opens with its own header at midnight on the 1st", monthBoundary),
        ("A daylight-saving month keeps every day once", daylightSaving),
        ("Search narrows the journal to matching sessions and totals them", searchNarrows),
        ("Today's live figures reach the cached journal and its month", liveToday),
        ("Arrow keys step through months, days and sessions in reading order", keyboardSteps),
        ("Jump to date selects a listed day, or the month of a quiet one", jumpSelects),
        ("The twelve-month chart stops at the first recorded month", recentMonthsFloor),
        ("A ticking clock does not rebuild the journal", journalIsCached)
    ]

    // MARK: - Fixtures

    /// Sydney, so the daylight-saving check meets a real transition.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        calendar.locale = Locale(identifier: "en_AU")
        return calendar
    }()

    static func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func row(_ month: Int, _ day: Int, focused: TimeInterval = 0, tracked: TimeInterval = 0,
                    sessions: Int = 0, types: Set<WorkType> = []) -> HistoryDay {
        HistoryDay(date: date(month, day), tracked: tracked, focused: focused, sessions: sessions,
                   appBundleIDs: [], workTypes: types)
    }

    /// Two September days and two August ones, with gaps between.
    static let archive: [HistoryDay] = [
        row(9, 28, focused: 3_600, tracked: 4_000, sessions: 2, types: [.deepWork]),
        row(9, 22, focused: 1_800, tracked: 2_000, sessions: 1, types: [.admin]),
        row(8, 30, tracked: 600),
        row(8, 29, focused: 900, tracked: 900, sessions: 1, types: [.learning])
    ]

    static func describe(_ entry: JournalEntry) -> String {
        switch entry {
        case .month(let month): return "month \(calendar.component(.month, from: month.start))"
        case .day(let day):
            return "day \(calendar.component(.month, from: day.date))/\(calendar.component(.day, from: day.date))"
        case .quiet(let quiet):
            return "quiet \(calendar.component(.day, from: quiet.first))-\(calendar.component(.day, from: quiet.last))"
        }
    }

    static func months(_ entries: [JournalEntry]) -> [JournalMonth] {
        entries.compactMap { if case .month(let month) = $0 { return month }; return nil }
    }

    static func days(_ entries: [JournalEntry]) -> [JournalDay] {
        entries.compactMap { if case .day(let day) = $0 { return day }; return nil }
    }

    // MARK: - Shape

    private static func newestFirst() -> [String] {
        let entries = HistoryJournalBuilder.entries(days: archive, today: date(9, 29), calendar: calendar)
        let expected = ["month 9", "day 9/29", "day 9/28", "quiet 23-27", "day 9/22", "quiet 1-21",
                        "month 8", "quiet 31-31", "day 8/30", "day 8/29"]
        let got = entries.map(describe)
        return got == expected ? [] : ["journal read \(got), expected \(expected)"]
    }

    private static func monthTotals() -> [String] {
        let entries = HistoryJournalBuilder.entries(days: archive, today: date(9, 29), calendar: calendar)
        var failures: [String] = []
        let found = months(entries)
        guard found.count == 2 else { return ["expected two months, found \(found.count)"] }
        let september = found[0], august = found[1]
        if september.focused != 5_400 || september.focusedDays != 2 || september.averagePerFocusedDay != 2_700 {
            failures.append("September totalled \(september.focused)s on \(september.focusedDays) days")
        }
        if september.tracked != 6_000 { failures.append("September app use was \(september.tracked)s") }
        if september.dailyFocus.count != 30 || september.dailyFocus[27] != 3_600 {
            failures.append("September's bars lost the 28th or a day: \(september.dailyFocus.count) slots")
        }
        if august.focused != 900 || august.tracked != 1_500 || august.focusedDays != 1 {
            failures.append("August totalled \(august.focused)s focus and \(august.tracked)s app use")
        }
        return failures
    }

    private static func appUseOnly() -> [String] {
        let entries = HistoryJournalBuilder.entries(days: archive, today: date(9, 29), calendar: calendar)
        let byDay = Dictionary(uniqueKeysWithValues: days(entries).map { ($0.date, $0) })
        var failures: [String] = []
        if byDay[date(8, 30)]?.isAppUseOnly != true { failures.append("30 Aug did not read as app use only") }
        if byDay[date(9, 28)]?.isAppUseOnly != false { failures.append("28 Sep read as app use only") }
        return failures
    }

    private static func breakOnlyDay() -> [String] {
        let rest = row(9, 25, types: [.breakTime])
        let entries = HistoryJournalBuilder.entries(days: archive + [rest], today: date(9, 29), calendar: calendar)
        let got = entries.map(describe)
        return got.contains("day 9/25") && got.contains("quiet 26-27") && got.contains("quiet 23-24")
            ? [] : ["a break-only day vanished into a quiet run: \(got)"]
    }

    private static func emptyArchive() -> [String] {
        let got = HistoryJournalBuilder.entries(days: [], today: date(9, 29), calendar: calendar).map(describe)
        return got == ["month 9", "day 9/29"] ? [] : ["an empty archive read \(got)"]
    }

    private static func monthBoundary() -> [String] {
        let got = HistoryJournalBuilder.entries(days: [row(9, 30, focused: 600, sessions: 1)],
                                                today: date(10, 1), calendar: calendar).map(describe)
        let expected = ["month 10", "day 10/1", "month 9", "day 9/30"]
        return got == expected ? [] : ["the 1st read \(got), expected \(expected)"]
    }

    private static func daylightSaving() -> [String] {
        // Sydney moves its clocks forward at 2 am on Sunday 4 October 2026.
        let rows = [row(10, 5, focused: 600, sessions: 1), row(10, 3, focused: 600, sessions: 1)]
        let entries = HistoryJournalBuilder.entries(days: rows, today: date(10, 6), calendar: calendar)
        var failures: [String] = []
        let expected = ["month 10", "day 10/6", "day 10/5", "quiet 4-4", "day 10/3"]
        if entries.map(describe) != expected {
            failures.append("October read \(entries.map(describe)), expected \(expected)")
        }
        if let october = months(entries).first {
            if october.dailyFocus.count != 31 { failures.append("October has \(october.dailyFocus.count) bars") }
            if october.dailyFocus[2] != 600 || october.dailyFocus[4] != 600 {
                failures.append("October's bars lost the 3rd or the 5th across the clock change")
            }
        }
        return failures
    }

    private static func searchNarrows() -> [String] {
        let a = UUID(), b = UUID(), c = UUID()
        func hit(_ thread: UUID, _ month: Int, _ day: Int, _ worked: TimeInterval) -> HistorySearchHit {
            let start = date(month, day).addingTimeInterval(9 * 3_600)
            return HistorySearchHit(id: UUID(), threadID: thread, name: "Parser", workType: .deepWork,
                                    start: start, end: start.addingTimeInterval(worked), worked: worked,
                                    day: date(month, day), noteSnippet: nil, matchedApps: [])
        }
        let hits = [hit(a, 9, 28, 1_200), hit(b, 9, 28, 600), hit(c, 8, 29, 900)]
        let entries = HistoryJournalBuilder.entries(matching: hits, calendar: calendar)
        var failures: [String] = []
        let expected = ["month 9", "day 9/28", "month 8", "day 8/29"]
        if entries.map(describe) != expected {
            failures.append("search read \(entries.map(describe)), expected \(expected)")
        }
        if let september = months(entries).first, september.focused != 1_800 || september.focusedDays != 1 {
            failures.append("September's header totalled \(september.focused)s, not the 1800s matched")
        }
        if let day = days(entries).first, day.threads != [a, b] || day.sessions != 2 || day.focused != 1_800 {
            failures.append("28 Sep was not narrowed to its two matches")
        }
        return failures
    }

    private static func liveToday() -> [String] {
        let cached = HistoryJournalBuilder.entries(days: archive, today: date(9, 29), calendar: calendar)
        let live = row(9, 29, focused: 1_200, tracked: 300, sessions: 1)
        let patched = HistoryJournalBuilder.patching(cached, today: live, calendar: calendar)
        var failures: [String] = []
        if let today = days(patched).first, today.focused != 1_200 || today.sessions != 1 {
            failures.append("today's row kept its cached figures")
        }
        if let september = months(patched).first,
           september.focused != 6_600 || september.tracked != 6_300 || september.focusedDays != 3 {
            failures.append("September did not take today's live figures: \(september.focused)s")
        }
        if patched.map(describe) != cached.map(describe) { failures.append("patching changed the rows") }
        return failures
    }

    private static func keyboardSteps() -> [String] {
        let entries = HistoryJournalBuilder.entries(days: archive, today: date(9, 29), calendar: calendar)
        let a = UUID(), b = UUID()
        let threads: (Date) -> [UUID] = { $0 == date(9, 28) ? [a, b] : [] }
        let down: [HistorySelection] = [
            .day(date(9, 29)), .day(date(9, 28)), .session(thread: a, day: date(9, 28)),
            .session(thread: b, day: date(9, 28)), .day(date(9, 22)), .month(date(8, 1)),
            .day(date(8, 30)), .day(date(8, 29)), .day(date(8, 29))
        ]
        var failures: [String] = []
        var current = HistorySelection.month(date(9, 1))
        for expected in down {
            current = HistoryJournalBuilder.step(from: current, by: 1, entries: entries, threads: threads)
            if current != expected { failures.append("↓ reached \(current), expected \(expected)"); break }
        }
        let up: [HistorySelection] = [
            .session(thread: b, day: date(9, 28)), .session(thread: a, day: date(9, 28)),
            .day(date(9, 28)), .day(date(9, 29)), .month(date(9, 1)), .month(date(9, 1))
        ]
        current = .day(date(9, 22))
        for expected in up {
            current = HistoryJournalBuilder.step(from: current, by: -1, entries: entries, threads: threads)
            if current != expected { failures.append("↑ reached \(current), expected \(expected)"); break }
        }
        return failures
    }

    private static func jumpSelects() -> [String] {
        let entries = HistoryJournalBuilder.entries(days: archive, today: date(9, 29), calendar: calendar)
        var failures: [String] = []
        if HistoryJournalBuilder.selection(forJump: date(9, 28), in: entries, calendar: calendar) != .day(date(9, 28)) {
            failures.append("jumping to a listed day did not select it")
        }
        if HistoryJournalBuilder.selection(forJump: date(9, 25), in: entries, calendar: calendar) != .month(date(9, 1)) {
            failures.append("jumping to a quiet day did not select its month")
        }
        let session = HistorySelection.session(thread: UUID(), day: date(9, 28))
        if HistoryJournalBuilder.anchorID(for: session, in: entries, calendar: calendar)
            != JournalEntry.dayID(date(9, 28)) {
            failures.append("a session did not scroll to its day's header")
        }
        if HistoryJournalBuilder.anchorID(for: .month(date(8, 1)), in: entries, calendar: calendar)
            != JournalEntry.monthID(date(8, 1)) {
            failures.append("a month did not scroll to its header")
        }
        if HistoryJournalBuilder.anchorID(for: .day(date(9, 25)), in: entries, calendar: calendar) != nil {
            failures.append("a quiet day claimed a row of its own")
        }
        return failures
    }

    private static func recentMonthsFloor() -> [String] {
        let focus = [date(8, 29): 900.0, date(9, 28): 3_600.0]
        var failures: [String] = []
        let short = HistoryJournalBuilder.recentMonths(endingAt: date(9, 15), focusByDay: focus,
                                                       firstDay: date(8, 29), calendar: calendar)
        if short.map(\.start) != [date(8, 1), date(9, 1)] || short.map(\.focused) != [900, 3_600] {
            failures.append("a two-month record drew \(short.map(\.start))")
        }
        let long = HistoryJournalBuilder.recentMonths(endingAt: date(9, 15), focusByDay: focus,
                                                      firstDay: date(1, 1, year: 2025), calendar: calendar)
        if long.count != 12 || long.first?.start != date(10, 1, year: 2025) || long.last?.start != date(9, 1) {
            failures.append("a long record drew \(long.count) months from \(String(describing: long.first?.start))")
        }
        return failures
    }

    // MARK: - Store

    private static func journalIsCached() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            store.refreshReview()
            var failures: [String] = []
            let first = store.historyJournal()
            guard case .month = first.first else { return ["the journal did not open on a month"] }
            let before = store.journalComputeCount
            for _ in 0..<5 { _ = store.historyJournal() }
            if store.journalComputeCount != before {
                failures.append("five reads of an unchanged archive rebuilt the journal "
                                + "\(store.journalComputeCount - before) times")
            }
            guard let record = store.engine.archive.records.first else {
                return failures + ["the fixture has no session to annotate"]
            }
            store.setNoteDraft("journal cache check", for: record.id)
            _ = store.saveNote(for: record.id)
            _ = store.historyJournal()
            if store.journalComputeCount != before + 1 {
                failures.append("a saved note did not rebuild the journal once")
            }
            return failures
        }
    }
}
```

Register it in `Sources/SelfTest.swift`: change `+ RedundancyChecks.tests` to `+ RedundancyChecks.tests + HistoryJournalChecks.tests`.

- [ ] **Step 2: Confirm it fails to compile**

Run the typecheck command.
Expected: errors such as `cannot find 'HistoryJournalBuilder' in scope`.

- [ ] **Step 3: Write the read model**

Create `Sources/App/SessionStore+Journal.swift`:

```swift
import Foundation

/// A month in History's journal: its figures, and one focus total for each
/// of its calendar days, for the thin bars under its name.
struct JournalMonth: Identifiable, Equatable {
    let start: Date
    let focused: TimeInterval
    let tracked: TimeInterval
    let focusedDays: Int
    /// Focused seconds per calendar day, the 1st first.
    let dailyFocus: [TimeInterval]

    var id: Date { start }
    var averagePerFocusedDay: TimeInterval { focusedDays > 0 ? focused / Double(focusedDays) : 0 }
}

/// A day the journal lists under its own header. While History is searched,
/// `threads` holds the sessions that matched; nil lists every session.
struct JournalDay: Identifiable, Equatable {
    let date: Date
    let focused: TimeInterval
    let tracked: TimeInterval
    let sessions: Int
    var threads: Set<UUID>? = nil

    var id: Date { date }
    /// At the Mac, but no session and no break: the journal says so in one line.
    var isAppUseOnly: Bool { sessions == 0 && focused == 0 && tracked > 0 }
}

/// Days in a row with nothing recorded, inside one month, read as one line.
struct JournalQuiet: Identifiable, Equatable {
    let first: Date
    let last: Date

    var id: Date { last }
    var isSingleDay: Bool { first == last }
}

/// One month's focus, for the rail's twelve-month chart.
struct JournalMonthTotal: Identifiable, Equatable {
    let start: Date
    let focused: TimeInterval
    var id: Date { start }
}

enum JournalEntry: Identifiable, Equatable {
    case month(JournalMonth)
    case day(JournalDay)
    case quiet(JournalQuiet)

    var id: String {
        switch self {
        case .month(let month): return Self.monthID(month.start)
        case .day(let day): return Self.dayID(day.date)
        case .quiet(let quiet): return "quiet-\(Int(quiet.last.timeIntervalSince1970))"
        }
    }

    static func monthID(_ start: Date) -> String { "month-\(Int(start.timeIntervalSince1970))" }
    static func dayID(_ date: Date) -> String { "day-\(Int(date.timeIntervalSince1970))" }
}

/// What History's rail describes: a month, a day, or one session on a day.
/// A session is its thread on that day, as it is one card in the story.
enum HistorySelection: Hashable {
    case month(Date)
    case day(Date)
    case session(thread: UUID, day: Date)

    /// The day a day or a session belongs to; nil for a month.
    var day: Date? {
        switch self {
        case .month: return nil
        case .day(let day), .session(_, let day): return day
        }
    }

    func monthStart(calendar: Calendar = .current) -> Date {
        let date: Date
        switch self {
        case .month(let start): date = start
        case .day(let day), .session(_, let day): date = day
        }
        return calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}

/// Builds the journal from History's day index. Pure, with no store and no
/// clock, so the checks can hand it any archive and any today.
enum HistoryJournalBuilder {
    /// Newest first, from today back to the first recorded day and no further.
    /// Today always has its own row; any other day without focus, app use, a
    /// session or a recorded break joins the quiet run it sits in.
    static func entries(days: [HistoryDay], today: Date,
                        calendar: Calendar = .current) -> [JournalEntry] {
        let today = calendar.startOfDay(for: today)
        let byDate = index(days, calendar: calendar)
        let oldest = min(byDate.keys.min() ?? today, today)
        var result: [JournalEntry] = []
        var quiet: (newest: Date, oldest: Date)?
        func flushQuiet() {
            if let run = quiet { result.append(.quiet(JournalQuiet(first: run.oldest, last: run.newest))) }
            quiet = nil
        }
        var openMonth: Date?
        var cursor = today
        while cursor >= oldest {
            let monthStart = calendar.dateInterval(of: .month, for: cursor)?.start ?? cursor
            if monthStart != openMonth {
                flushQuiet()
                result.append(.month(month(starting: monthStart, byDate: byDate, calendar: calendar)))
                openMonth = monthStart
            }
            let row = byDate[cursor]
            if cursor == today || row.map(hasEvidence) == true {
                flushQuiet()
                result.append(.day(JournalDay(date: cursor, focused: row?.focused ?? 0,
                                              tracked: row?.tracked ?? 0, sessions: row?.sessions ?? 0)))
            } else {
                quiet = (quiet?.newest ?? cursor, cursor)
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        flushQuiet()
        return result
    }

    /// Search results as a journal: only the months and days holding a match,
    /// each totalling its matches, each day narrowed to the sessions that
    /// matched. `hits` arrive newest first, as `historySearchHits` lists them.
    static func entries(matching hits: [HistorySearchHit],
                        calendar: Calendar = .current) -> [JournalEntry] {
        var result: [JournalEntry] = []
        var openMonth: Date?
        var monthHits: [HistorySearchHit] = []
        func flushMonth() {
            guard let start = openMonth, !monthHits.isEmpty else { return }
            var worked: [Date: TimeInterval] = [:]
            var threads: [Date: Set<UUID>] = [:]
            var order: [Date] = []
            for hit in monthHits {
                let day = calendar.startOfDay(for: hit.day)
                if worked[day] == nil { order.append(day) }
                worked[day, default: 0] += hit.worked
                threads[day, default: []].insert(hit.threadID)
            }
            let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 31
            let daily = (0..<count).map { offset -> TimeInterval in
                guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return 0 }
                return worked[date] ?? 0
            }
            result.append(.month(JournalMonth(start: start, focused: daily.reduce(0, +), tracked: 0,
                                              focusedDays: order.count, dailyFocus: daily)))
            for day in order {
                result.append(.day(JournalDay(date: day, focused: worked[day] ?? 0, tracked: 0,
                                              sessions: threads[day]?.count ?? 0,
                                              threads: threads[day] ?? [])))
            }
        }
        for hit in hits {
            let start = calendar.dateInterval(of: .month, for: hit.day)?.start ?? hit.day
            if start != openMonth {
                flushMonth()
                openMonth = start
                monthHits = []
            }
            monthHits.append(hit)
        }
        flushMonth()
        return result
    }

    /// Today's row and its month, brought up to the live figures. The rest of
    /// the journal stays cached; only today moves while a session runs.
    static func patching(_ entries: [JournalEntry], today live: HistoryDay?,
                         calendar: Calendar = .current) -> [JournalEntry] {
        guard let live else { return entries }
        let day = calendar.startOfDay(for: live.date)
        guard let dayIndex = entries.firstIndex(where: {
            if case .day(let row) = $0 { return row.date == day }
            return false
        }), case .day(let old) = entries[dayIndex] else { return entries }
        var patched = entries
        patched[dayIndex] = .day(JournalDay(date: day, focused: live.focused,
                                            tracked: live.tracked, sessions: live.sessions))
        // A day's month is the nearest header above it.
        if let monthIndex = entries[..<dayIndex].lastIndex(where: {
            if case .month = $0 { return true }
            return false
        }), case .month(let month) = entries[monthIndex] {
            var daily = month.dailyFocus
            let offset = calendar.dateComponents([.day], from: month.start, to: day).day ?? 0
            if daily.indices.contains(offset) { daily[offset] = live.focused }
            patched[monthIndex] = .month(JournalMonth(
                start: month.start, focused: daily.reduce(0, +),
                tracked: month.tracked - old.tracked + live.tracked,
                focusedDays: daily.filter { $0 > 0 }.count, dailyFocus: daily))
        }
        return patched
    }

    /// The row ↑ or ↓ lands on. Months, days and sessions are stops in
    /// reading order; quiet lines and breaks are not. `threads` lists a day's
    /// sessions in the order its rows show them. It is only asked about the
    /// day being left and the day being entered, never the whole journal.
    static func step(from current: HistorySelection, by delta: Int,
                     entries: [JournalEntry], threads: (Date) -> [UUID]) -> HistorySelection {
        guard delta != 0 else { return current }
        let stops: [HistorySelection] = entries.compactMap {
            switch $0 {
            case .month(let month): return .month(month.start)
            case .day(let day): return .day(day.date)
            case .quiet: return nil
            }
        }
        if case .session(let thread, let day) = current {
            let list = threads(day)
            if let index = list.firstIndex(of: thread) {
                let next = index + delta
                if list.indices.contains(next) { return .session(thread: list[next], day: day) }
                if next < 0 { return .day(day) }
            }
            return neighbour(of: .day(day), in: stops, forward: true, threads: threads) ?? current
        }
        if delta > 0, case .day(let day) = current, let first = threads(day).first {
            return .session(thread: first, day: day)
        }
        return neighbour(of: current, in: stops, forward: delta > 0, threads: threads) ?? current
    }

    private static func neighbour(of stop: HistorySelection, in stops: [HistorySelection],
                                  forward: Bool, threads: (Date) -> [UUID]) -> HistorySelection? {
        guard let index = stops.firstIndex(of: stop) else { return stops.first }
        let next = index + (forward ? 1 : -1)
        guard stops.indices.contains(next) else { return nil }
        // Moving up onto a day lands on its last session: the row just above.
        if !forward, case .day(let day) = stops[next], let last = threads(day).last {
            return .session(thread: last, day: day)
        }
        return stops[next]
    }

    /// Jump to date: a day with its own row is selected; a quiet day selects
    /// its month, since it has no row to select.
    static func selection(forJump date: Date, in entries: [JournalEntry],
                          calendar: Calendar = .current) -> HistorySelection {
        let day = calendar.startOfDay(for: date)
        let listed = entries.contains { $0.id == JournalEntry.dayID(day) }
        return listed ? .day(day) : .month(calendar.dateInterval(of: .month, for: day)?.start ?? day)
    }

    /// The row to scroll to for a selection: its day's header, or its month's.
    static func anchorID(for selection: HistorySelection, in entries: [JournalEntry],
                         calendar: Calendar = .current) -> String? {
        let wanted = selection.day.map { JournalEntry.dayID(calendar.startOfDay(for: $0)) }
            ?? JournalEntry.monthID(selection.monthStart(calendar: calendar))
        return entries.contains { $0.id == wanted } ? wanted : nil
    }

    /// One month's figures from the day index, whether or not it is listed.
    static func month(starting start: Date, days: [HistoryDay],
                      calendar: Calendar = .current) -> JournalMonth {
        month(starting: start, byDate: index(days, calendar: calendar), calendar: calendar)
    }

    /// Up to `count` months ending with the one holding `end`, oldest first,
    /// never reaching before the month the record began in.
    static func recentMonths(endingAt end: Date, focusByDay: [Date: TimeInterval],
                             firstDay: Date?, count: Int = 12,
                             calendar: Calendar = .current) -> [JournalMonthTotal] {
        let last = calendar.dateInterval(of: .month, for: end)?.start ?? end
        let floor = firstDay.flatMap { calendar.dateInterval(of: .month, for: $0)?.start } ?? last
        var totals: [Date: TimeInterval] = [:]
        for (day, seconds) in focusByDay {
            if let start = calendar.dateInterval(of: .month, for: day)?.start { totals[start, default: 0] += seconds }
        }
        var result: [JournalMonthTotal] = []
        var cursor = last
        while result.count < count, cursor >= floor {
            result.append(JournalMonthTotal(start: cursor, focused: totals[cursor] ?? 0))
            guard let previous = calendar.date(byAdding: .month, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return Array(result.reversed())
    }

    /// A journal day's rows from its projection, newest first, narrowed to
    /// `only` while History is searched. Breaks never match a search.
    static func rows(_ projection: StoryDayProjection, only: Set<UUID>?) -> [DayEntry] {
        projection.sessions
            .filter { entry in
                guard let only else { return true }
                if case .session(let session) = entry { return only.contains(session.threadID) }
                return false
            }
            .sorted { $0.start > $1.start }
    }

    private static func month(starting start: Date, byDate: [Date: HistoryDay],
                              calendar: Calendar) -> JournalMonth {
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 31
        var daily: [TimeInterval] = []
        var tracked: TimeInterval = 0
        for offset in 0..<count {
            let row = calendar.date(byAdding: .day, value: offset, to: start).flatMap { byDate[$0] }
            daily.append(row?.focused ?? 0)
            tracked += row?.tracked ?? 0
        }
        return JournalMonth(start: start, focused: daily.reduce(0, +), tracked: tracked,
                            focusedDays: daily.filter { $0 > 0 }.count, dailyFocus: daily)
    }

    private static func index(_ days: [HistoryDay], calendar: Calendar) -> [Date: HistoryDay] {
        var byDate: [Date: HistoryDay] = [:]
        for day in days { byDate[calendar.startOfDay(for: day.date)] = day }
        return byDate
    }

    /// Break records add a work type but never focus or a session, so a day
    /// holding only a recorded break still has something to show.
    private static func hasEvidence(_ day: HistoryDay) -> Bool {
        day.focused > 0 || day.tracked > 0 || day.sessions > 0 || !day.workTypes.isEmpty
    }
}

struct JournalKey: Equatable {
    let evidence: SessionStore.EvidenceRevision
    let dayCount: Int
    let oldest: Date?
}

extension SessionStore {
    /// The journal History lists. Cached until the archive behind it changes;
    /// while a session runs, only today's row and its month are brought up
    /// to date. A search builds its own narrowed journal from the matches.
    func historyJournal() -> [JournalEntry] {
        let calendar = Calendar.current
        if historyFilter.isActive {
            return HistoryJournalBuilder.entries(matching: historySearchHits(limit: .max), calendar: calendar)
        }
        let key = JournalKey(evidence: evidenceRevision, dayCount: historyDays.count,
                             oldest: historyDays.last?.date)
        let entries: [JournalEntry]
        if let cached = journalCache, cached.key == key {
            entries = cached.entries
        } else {
            journalComputeCount &+= 1
            entries = HistoryJournalBuilder.entries(days: historyDays, today: now(), calendar: calendar)
            journalCache = (key, entries)
        }
        return HistoryJournalBuilder.patching(entries, today: historyDays.first, calendar: calendar)
    }

    /// A journal day's rows, in the order the journal shows them.
    func journalRows(on day: Date, only: Set<UUID>?) -> [DayEntry] {
        HistoryJournalBuilder.rows(storyDayProjection(on: day), only: only)
    }

    /// The sessions a journal day lists, as ↑/↓ walk them.
    func journalThreads(on day: Date, only: Set<UUID>?) -> [UUID] {
        journalRows(on: day, only: only).compactMap { entry in
            if case .session(let session) = entry { return session.threadID }
            return nil
        }
    }

    /// The session a selection names, if that day still has it.
    func journalSession(thread: UUID, on day: Date) -> DaySession? {
        for entry in storyDayProjection(on: day).sessions {
            if case .session(let session) = entry, session.threadID == thread { return session }
        }
        return nil
    }

    /// The first note saved against any stretch of the session, trimmed.
    func journalNote(for session: DaySession) -> String? {
        for id in session.recordIDs {
            let note = (metadataArchive.metadata(for: id)?.note ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { return note }
        }
        return nil
    }
}
```

In `Sources/App/SessionStore.swift`, directly under the line `var insightReadingComputeCount = 0`, add:

```swift
    /// History's journal, kept until the archive behind it changes.
    var journalCache: (key: JournalKey, entries: [JournalEntry])?
    /// How many times the journal was built. A check proves the clock alone
    /// never rebuilds it.
    var journalComputeCount = 0
```

- [ ] **Step 4: Typecheck, then run the self-tests (sandbox disabled)**

Run the typecheck command, then `./build.sh --check 2>&1 | grep -E "\[FAIL\]|^         - |passed$"`.
Expected: all 13 new checks PASS; total = baseline + 13.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/SessionStore+Journal.swift Sources/App/SessionStore.swift Sources/Verification/HistoryJournalChecks.swift Sources/SelfTest.swift
git commit -m "History's days can be read as one journal, newest first

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: History remembers a selection

**Files:**
- Modify: `Sources/App/MainWindowModel.swift` (the History members, around lines 211-226 and 312-321)
- Test: `Sources/Verification/StoryNavigationChecks.swift` (add two tests)

**Interfaces:**
- Consumes: `HistorySelection`, `HistoryJournalBuilder.selection(forJump:in:calendar:)`, `.step(from:by:entries:threads:)`, `SessionStore.historyJournal()`, `journalThreads(on:only:)`.
- Produces on `MainWindowModel`:
  - `historySelection: HistorySelection?` (published, private(set))
  - `historyScrollRequest: Int`
  - `historySelectionOrDefault(calendar:) -> HistorySelection`
  - `selectHistory(_:scrolling:)`, `jumpToHistoryDay(_:calendar:)`, `stepHistorySelection(by:)`
  - `reviewSelectedDate` becomes computed (`historySelection?.day`)
  - `selectReviewDay(_:calendar:)` sets `.day`
  - `clearReviewDay()` clears to the default month

- [ ] **Step 1: Write the failing checks**

In `StoryNavigationChecks.tests`, add after the `findInHistory` entry:

```swift
        ("Picking in History changes what the rail reads, never the story's day", historyPicks),
        ("Jump to date and the arrow keys move History's selection and its scroll", historyJumpAndSteps)
```

and add these functions to the enum:

```swift
    private static func historyPicks() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            let calendar = Calendar.current
            let navigation = MainWindowModel(store: store)
            navigation.open(tab: .review)
            store.refreshReview()
            let storyDay = store.selectedDay
            var failures: [String] = []
            let month = calendar.dateInterval(of: .month, for: store.now())!.start
            if navigation.historySelectionOrDefault() != .month(month) {
                failures.append("History did not open on the current month")
            }
            let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: store.now()))!
            navigation.selectHistory(.day(yesterday))
            if navigation.reviewSelectedDate != yesterday {
                failures.append("a picked day was not the day History reads")
            }
            if let thread = store.journalThreads(on: yesterday, only: nil).first {
                navigation.selectHistory(.session(thread: thread, day: yesterday))
                if navigation.reviewSelectedDate != yesterday {
                    failures.append("a picked session did not belong to its day")
                }
            } else {
                failures.append("the fixture's yesterday has no session to pick")
            }
            if store.selectedDay != storyDay { failures.append("picking in History moved the story's day") }
            navigation.clearReviewDay()
            if navigation.historySelectionOrDefault() != .month(month) {
                failures.append("clearing the pick did not return to the month")
            }
            return failures
        }
    }

    private static func historyJumpAndSteps() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            let calendar = Calendar.current
            let navigation = MainWindowModel(store: store)
            navigation.open(tab: .review)
            store.refreshReview()
            var failures: [String] = []
            let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: store.now()))!
            let scroll = navigation.historyScrollRequest
            navigation.jumpToHistoryDay(twoDaysAgo)
            if navigation.historySelection != .day(twoDaysAgo) {
                failures.append("Jump to date did not select the day: \(String(describing: navigation.historySelection))")
            }
            if navigation.historyScrollRequest == scroll {
                failures.append("Jump to date did not ask the journal to scroll")
            }
            navigation.stepHistorySelection(by: 1)
            guard case .session(_, let day) = navigation.historySelection ?? .month(twoDaysAgo),
                  day == twoDaysAgo else {
                return failures + ["↓ from a day with a session did not reach that session"]
            }
            navigation.stepHistorySelection(by: -1)
            if navigation.historySelection != .day(twoDaysAgo) {
                failures.append("↑ from the day's first session did not return to its header")
            }
            return failures
        }
    }
```

- [ ] **Step 2: Confirm it fails to compile**

Run the typecheck command.
Expected: `value of type 'MainWindowModel' has no member 'historySelectionOrDefault'`.

- [ ] **Step 3: Add the selection to the model**

In `MainWindowModel.swift`, replace

```swift
    /// The day Review is inspecting, or nil when nothing is selected. It is
    /// deliberately separate from `requestedDate`: selecting evidence in Review
    /// explains a day in place, while `requestedDate` moves the user to Today.
    @Published private(set) var reviewSelectedDate: Date?
```

with

```swift
    /// What History's rail describes; nil reads as the current month. It is
    /// deliberately separate from `requestedDate`: picking in History explains
    /// a month, day or session in place, while `requestedDate` moves the story.
    @Published private(set) var historySelection: HistorySelection?
    /// Bumped when the journal should bring the selection into view.
    @Published private(set) var historyScrollRequest = 0

    /// The day History is inspecting: a picked day, or a picked session's day.
    var reviewSelectedDate: Date? { historySelection?.day }
```

Replace the bodies of `selectReviewDay` and `clearReviewDay`:

```swift
    func selectReviewDay(_ date: Date, calendar: Calendar = .current) {
        historySelection = .day(calendar.startOfDay(for: date))
    }

    func clearReviewDay() {
        historySelection = nil
    }
```

Add, directly after `clearReviewDay()`:

```swift
    func historySelectionOrDefault(calendar: Calendar = .current) -> HistorySelection {
        if let historySelection { return historySelection }
        let now = store?.now() ?? Date()
        return .month(calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now))
    }

    func selectHistory(_ selection: HistorySelection, scrolling: Bool = false) {
        animated(Tokens.Motion.selection) { historySelection = selection }
        if scrolling { historyScrollRequest &+= 1 }
    }

    /// The calendar picked a day: History selects it and scrolls to it. A day
    /// with nothing recorded has no row, so its month is selected instead.
    func jumpToHistoryDay(_ date: Date, calendar: Calendar = .current) {
        let entries = store?.historyJournal() ?? []
        selectHistory(HistoryJournalBuilder.selection(forJump: date, in: entries, calendar: calendar),
                      scrolling: true)
    }

    /// ↑ and ↓ in the journal: one row at a time, the list following.
    func stepHistorySelection(by delta: Int) {
        guard let store else { return }
        let entries = store.historyJournal()
        var only: [Date: Set<UUID>] = [:]
        for case .day(let day) in entries { if let threads = day.threads { only[day.date] = threads } }
        let next = HistoryJournalBuilder.step(from: historySelectionOrDefault(), by: delta, entries: entries,
                                              threads: { store.journalThreads(on: $0, only: only[$0]) })
        selectHistory(next, scrolling: true)
    }
```

Leave every other member alone. `InsightsView`, `HistoryFind` and the Snapshotter still read `reviewSelectedDate` and call `selectReviewDay` / `clearReviewDay`, and still compile.

- [ ] **Step 4: Run the self-tests (sandbox disabled)**

Run: `./build.sh --check 2>&1 | grep -E "\[FAIL\]|^         - |passed$"`
Expected: both new checks PASS. The existing Review-selection tests in `SelfTest.swift` (around lines 7537, 7718, 7962) also pass, because `selectReviewDay` and `clearReviewDay` keep their meaning.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/MainWindowModel.swift Sources/Verification/StoryNavigationChecks.swift
git commit -m "History remembers a picked month, day or session, and can step through them

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The journal and its rail are drawn

**Files:**
- Create: `Sources/Surfaces/History/HistoryJournal.swift` (`HistoryWorkspace`, `HistoryJournal`, `HistoryMonthHeader`, `HistoryMonthBars`, `HistoryDayGroup`, `HistoryDayHeader`, `HistorySessionRow`, `HistoryBreakRow`, `HistoryQuietRow`)
- Create: `Sources/Surfaces/History/HistoryJournalRail.swift` (`HistoryHours`, `HistoryRailScope`, `HistoryJournalRail`, `HistoryRailHeading`, `HistoryMonthRail`, `HistoryDayRail`, `HistorySessionRail`)
- Modify: `Sources/Surfaces/Story/StoryColumns.swift:3-22` (five `StoryRenderEvidence` cases)
- Modify: `Sources/Core/FirstRun.swift:77-93` (`CoachAnchor.journal`)
- Modify: `Sources/Verification/StoryWorkspaceChecks.swift` (make `renderFrame` and `StoryRenderedFrame` internal)
- Test: `Sources/Verification/HistoryJournalChecks.swift` (six more tests)

**Interfaces:**
- Consumes:
  - from Tasks 2–3: everything listed there
  - existing views and helpers: `HistoryFindBar(store:focusRequest:)`, `HistoryDayStrip(date:entries:height:)`, `HistoryStripAxis(leading:trailing:)`, `HistoryRowLayout.inset`, `StoryTile(title:trailing:content:)`, `StoryAppRow(app:rank:)`, `CategoryShareBar(shares:)`, `InsightSection(title:insight:)`, `WorkTypeChip(workType:)`, `EmptyState(_:detail:icon:)`, `StartButton(title:fills:action:)`, `StoryPressStyle(hovers:cornerRadius:)`, `StoryLinkStyle()`, `RestEntryRow.label(_:)`
  - store reads: `store.insightReading(scope:anchoredAt:limit:).facts`, `store.insightSurface(for:)`, `store.historyArchiveFacts()`
- Produces:
  - `HistoryWorkspace(store:navigation:scrolls:)`, the view Task 5 hosts
  - `StoryRenderEvidence.historyJournal / .historyEmpty / .historyMonthRail / .historyDayRail / .historySessionRail`
  - `CoachAnchor.journal`
  - static text helpers that later tasks test:
    - `HistoryMonthHeader.title(_:)`, `.facts(_:)`
    - `HistoryQuietRow.text(_:)`
    - `HistorySessionRow.spokenLabel(_:)`, `.detail(apps:note:)`
    - `HistoryJournal.matchSummary(_:)`, `.footerText(_:since:)`
    - `HistoryHours.label(_:)`, `.span(from:)`, `.note(seconds:phrase:)`
    - `HistoryMonthRail.appUseLine(tracked:)`
    - `HistoryRailScope.resolve(_:session:calendar:)`

- [ ] **Step 1: Write the failing checks**

Add to `HistoryJournalChecks.tests`:

```swift
        ("Journal headers and lines say each figure once, in words for VoiceOver", journalWording),
        ("A session row speaks its time, name, category and length as one element", sessionSpeech),
        ("The rail falls back to the month when its session is gone", railFallsBackToMonth),
        ("The best two hours are said once, with where they fell", bestHoursSaidOnce),
        ("The month rail carries recorded app use in one line", monthRailAppUse),
        ("The journal and each rail scope render with their evidence", journalRenders)
```

and the functions:

```swift
    // MARK: - Wording

    private static func journalWording() -> [String] {
        var failures: [String] = []
        let month = JournalMonth(start: date(9, 1), focused: 5_400, tracked: 6_000, focusedDays: 2,
                                 dailyFocus: Array(repeating: 0, count: 30))
        let facts = HistoryMonthHeader.facts(month)
        let expected = "\(Tokens.duration(5_400)) focused · 2 days · \(Tokens.duration(2_700)) per focused day"
        if facts != expected { failures.append("month header read \"\(facts)\", expected \"\(expected)\"") }
        if facts.contains("app use") { failures.append("the month header repeated app use from the rail") }
        // The quiet line formats in the Mac's own time zone, as the app does.
        let here = Calendar.current
        func local(_ day: Int) -> Date { here.date(from: DateComponents(year: 2026, month: 9, day: day))! }
        let single = HistoryQuietRow.text(JournalQuiet(first: local(22), last: local(22)))
        if single != "Tue 22 Sep · nothing recorded" { failures.append("a single quiet day read \"\(single)\"") }
        let run = HistoryQuietRow.text(JournalQuiet(first: local(23), last: local(27)))
        if run != "23 – 27 Sep · nothing recorded" { failures.append("a quiet run read \"\(run)\"") }
        let entries: [JournalEntry] = [
            .month(month),
            .day(JournalDay(date: date(9, 28), focused: 1_800, tracked: 0, sessions: 2, threads: [])),
            .day(JournalDay(date: date(9, 22), focused: 600, tracked: 0, sessions: 1, threads: []))
        ]
        let summary = HistoryJournal.matchSummary(entries)
        if summary != "3 sessions match · \(Tokens.duration(2_400)) of focus" {
            failures.append("the search summary read \"\(summary)\"")
        }
        return failures
    }

    private static func sessionSpeech() -> [String] {
        let start = date(9, 28).addingTimeInterval(8.5 * 3_600)
        let named = DaySession(id: UUID(), threadID: UUID(), name: "Refactor", workType: .deepWork,
                               start: start, end: start.addingTimeInterval(11_100), worked: 7_500,
                               stretches: 1, spans: [], isRunning: false)
        var failures: [String] = []
        let label = HistorySessionRow.spokenLabel(named)
        for part in [Tokens.timeRange(named.start, named.end), "Refactor",
                     WorkType.deepWork.displayName, Tokens.spent(7_500)] where !label.contains(part) {
            failures.append("the row did not say \"\(part)\": \(label)")
        }
        if label.contains(Tokens.duration(7_500)) { failures.append("the row spoke a compact duration: \(label)") }
        let unnamed = DaySession(id: UUID(), threadID: UUID(), name: "", workType: .deepWork,
                                 start: start, end: start.addingTimeInterval(600), worked: 600,
                                 stretches: 1, spans: [], isRunning: true)
        let quiet = HistorySessionRow.spokenLabel(unnamed)
        if quiet.components(separatedBy: WorkType.deepWork.displayName).count != 2 {
            failures.append("an unnamed session said its category twice: \(quiet)")
        }
        if !quiet.contains("in progress") { failures.append("a running session did not say so: \(quiet)") }
        if HistorySessionRow.detail(apps: ["Xcode", "Terminal", "Safari", "Notes"], note: "fixed it")
            != "Xcode, Terminal, Safari · “fixed it”" {
            failures.append("the second line lost its three apps or the note")
        }
        return failures
    }

    private static func railFallsBackToMonth() -> [String] {
        let day = date(9, 28)
        let gone = HistoryRailScope.resolve(.session(thread: UUID(), day: day), session: nil, calendar: calendar)
        return gone == .month(date(9, 1)) ? [] : ["a vanished session left the rail on \(gone)"]
    }

    private static func bestHoursSaidOnce() -> [String] {
        let note = HistoryHours.note(seconds: 12_000, phrase: "on Tuesdays")
        var failures: [String] = []
        if note != "\(Tokens.duration(12_000)) of focus fell here, most of it on Tuesdays." {
            failures.append("the best-hours note read \"\(note)\"")
        }
        if HistoryHours.span(from: 9) != "9 am – 11 am" || HistoryHours.label(0) != "12 am"
            || HistoryHours.label(13) != "1 pm" {
            failures.append("clock hours were not said as 9 am, 12 am and 1 pm")
        }
        return failures
    }

    private static func monthRailAppUse() -> [String] {
        let line = HistoryMonthRail.appUseLine(tracked: 59_100)
        return line == "\(Tokens.duration(59_100)) recorded app use"
            ? [] : ["the month rail's app use read \"\(line)\""]
    }

    // MARK: - Render

    private static func journalRenders() -> [String] {
        MainActor.assumeIsolated {
            var failures: [String] = []
            func require(_ label: String, _ frame: StoryRenderedFrame, _ evidence: StoryRenderEvidence) {
                if !frame.evidence.contains(evidence) {
                    failures.append("\(label) did not render \(evidence.rawValue): \(frame.evidence.map(\.rawValue).sorted())")
                }
            }
            let dense = FixtureFactory.insightsStore(withEvidence: true)
            dense.refreshReview()
            let navigation = MainWindowModel(store: dense)
            navigation.open(tab: .review)
            let monthFrame = StoryWorkspaceChecks.renderFrame(
                HistoryWorkspace(store: dense, navigation: navigation, scrolls: false), width: 1_160, height: 1_000)
            require("History on its month", monthFrame, .historyJournal)
            require("History on its month", monthFrame, .historyMonthRail)
            let yesterday = Calendar.current.date(byAdding: .day, value: -1,
                                                  to: Calendar.current.startOfDay(for: dense.now()))!
            navigation.selectHistory(.day(yesterday))
            require("History on a day", StoryWorkspaceChecks.renderFrame(
                HistoryWorkspace(store: dense, navigation: navigation, scrolls: false), width: 1_160, height: 1_000),
                .historyDayRail)
            if let thread = dense.journalThreads(on: yesterday, only: nil).first {
                navigation.selectHistory(.session(thread: thread, day: yesterday))
                require("History on a session", StoryWorkspaceChecks.renderFrame(
                    HistoryWorkspace(store: dense, navigation: navigation, scrolls: false), width: 1_160, height: 1_000),
                    .historySessionRail)
            } else {
                failures.append("the dense fixture's yesterday has no session")
            }
            FixtureFactory.cleanUp()
            let sparse = FixtureFactory.store(for: .firstRun, accurateUsage: true)
            sparse.refreshReview()
            let fresh = MainWindowModel(store: sparse)
            fresh.open(tab: .review)
            require("An empty History", StoryWorkspaceChecks.renderFrame(
                HistoryWorkspace(store: sparse, navigation: fresh, scrolls: false), width: 1_160, height: 800),
                .historyEmpty)
            FixtureFactory.cleanUp()
            return failures
        }
    }
```

- [ ] **Step 2: Confirm it fails to compile**

Run the typecheck command.
Expected: `cannot find 'HistoryMonthHeader' in scope`, and similar errors.

- [ ] **Step 3: Open the seams**

1. In `StoryColumns.swift`, add to `enum StoryRenderEvidence` after `case insightEmptyPeriod`:
```swift
    case historyJournal
    case historyEmpty
    case historyMonthRail
    case historyDayRail
    case historySessionRail
```
2. In `FirstRun.swift` `enum CoachAnchor`, add `case journal` directly after `case search`.
3. In `StoryWorkspaceChecks.swift`:
   - change `private struct StoryRenderedFrame {` to `struct StoryRenderedFrame {`
   - change `private static func renderFrame<V: View>(_ view: V,` to `static func renderFrame<V: View>(_ view: V,`

- [ ] **Step 4: Write the journal view**

Create `Sources/Surfaces/History/HistoryJournal.swift`:

```swift
import SwiftUI
import AppKit

/// History below the chrome: the journal, and beside it the rail for what
/// the journal has selected.
struct HistoryWorkspace: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    var scrolls = true

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HistoryJournal(store: store, navigation: navigation, scrolls: scrolls)
            Divider()
            Group {
                if scrolls {
                    ScrollView { HistoryJournalRail(store: store, navigation: navigation) }
                } else {
                    HistoryJournalRail(store: store, navigation: navigation)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(width: StoryLayout.railWidth)
            .background(StoryStyle.rail)
        }
        .background(Tokens.Colour.ground)
    }
}

/// History as one list, newest first, back to the first recorded day: each
/// month under its figures, each day under its total, every session on its
/// own row. The search stays above it; a search narrows the same list.
struct HistoryJournal: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @Environment(\.focusInterfaceDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scrolls = true

    private var isEmptyArchive: Bool { !store.historyFilter.isActive && store.historyDays.isEmpty }

    var body: some View {
        let entries = store.historyJournal()
        let selection = navigation.historySelectionOrDefault()
        let summary = store.historyFilter.isActive && !entries.isEmpty ? Self.matchSummary(entries) : nil
        let insets = StoryStyle.columnInsets(for: density)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                HistoryFindBar(store: store, focusRequest: navigation.historySearchFocusRequest)
                    .coachAnchor(.search)
                if let summary {
                    Text(durations: summary)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(EdgeInsets(top: insets.top, leading: insets.leading,
                                bottom: Tokens.Space.m, trailing: insets.trailing))
            Divider()
            ScrollViewReader { proxy in
                pane { content(entries, selection, insets: insets) }
                    .onChange(of: navigation.historyScrollRequest) { _ in
                        guard let id = HistoryJournalBuilder.anchorID(
                            for: navigation.historySelectionOrDefault(), in: store.historyJournal()) else { return }
                        withAnimation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion)) {
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StoryStyle.canvas)
        .announcesChanges(to: summary.map(DurationText.spoken(in:)))
        .onAppear { store.setInsightsVisible(true) }
        .onDisappear { store.setInsightsVisible(false) }
        .storyRenderEvidence(isEmptyArchive ? .historyEmpty : .historyJournal)
    }

    @ViewBuilder private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if scrolls {
            ScrollView { content() }
        } else {
            content().frame(maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func content(_ entries: [JournalEntry], _ selection: HistorySelection,
                         insets: EdgeInsets) -> some View {
        if store.historyFilter.isActive && entries.isEmpty {
            EmptyState("No matching sessions",
                       detail: "Try a session name, a word from a note, an app, a category or a date.",
                       icon: "magnifyingglass")
                .padding(insets)
        } else if isEmptyArchive {
            emptyArchive.padding(insets)
        } else {
            list(entries, selection)
                .padding(EdgeInsets(top: Tokens.Space.s, leading: insets.leading - HistoryRowLayout.inset,
                                    bottom: insets.bottom, trailing: insets.trailing - HistoryRowLayout.inset))
        }
    }

    private func list(_ entries: [JournalEntry], _ selection: HistorySelection) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                switch entry {
                case .month(let month):
                    HistoryMonthHeader(month: month, isSelected: selection == .month(month.start)) {
                        navigation.selectHistory(.month(month.start))
                    }
                    .padding(.top, Tokens.Space.m)
                    .id(entry.id)
                case .day(let day):
                    HistoryDayGroup(store: store, navigation: navigation, day: day, selection: selection)
                        .id(entry.id)
                case .quiet(let quiet):
                    HistoryQuietRow(quiet: quiet)
                        .id(entry.id)
                }
            }
            if !store.historyFilter.isActive, let first = store.historyArchiveFacts().firstDay {
                Text(durations: Self.footerText(store.historyArchiveFacts(), since: first))
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, HistoryRowLayout.inset)
                    .padding(.top, Tokens.Space.xl)
            }
        }
        .coachAnchor(.journal)
        // ↑ and ↓ move the selection; Return opens the selected day's story,
        // the keyboard twin of a double-click.
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .up: navigation.stepHistorySelection(by: -1)
            case .down: navigation.stepHistorySelection(by: 1)
            default: break
            }
        }
        .onCommand(#selector(NSStandardKeyBindingResponding.insertNewline(_:))) {
            if let day = navigation.historySelectionOrDefault().day { navigation.openDay(day) }
        }
        .accessibilityHint("Up and down arrows move through the list; Return opens the selected day")
    }

    private var emptyArchive: some View {
        StoryTile(title: "Nothing recorded yet", trailing: nil) {
            Text("History fills in as you work. Each day you record appears here, newest first, "
                 + "with its sessions one click away.")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            StartButton(title: "Start focus", fills: false) {
                navigation.performSessionControlsAction(.commandOrMenu)
            }
            .fixedSize()
            .accessibilityLabel("Start a focus session")
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    /// `12 sessions match · 8h 20m of focus`.
    static func matchSummary(_ entries: [JournalEntry]) -> String {
        var sessions = 0
        var worked: TimeInterval = 0
        for case .day(let day) in entries {
            sessions += day.sessions
            worked += day.focused
        }
        let noun = sessions == 1 ? "session matches" : "sessions match"
        return "\(sessions) \(noun) · \(Tokens.duration(worked)) of focus"
    }

    /// Where the journal ends: the whole record, said once.
    static func footerText(_ facts: HistoryArchiveFacts, since first: Date) -> String {
        var parts = ["On record since \(DateFormats.australian("d MMM yyyy").string(from: first))",
                     "\(Tokens.duration(facts.focused)) focused",
                     facts.dayCount == 1 ? "1 day" : "\(facts.dayCount) days",
                     facts.sessionCount == 1 ? "1 session" : "\(facts.sessionCount) sessions"]
        if facts.longestStreak > 1 { parts.append("longest streak \(facts.longestStreak) days") }
        return parts.joined(separator: " · ")
    }
}

/// A month's name, its figures, and a thin bar for each of its days.
struct HistoryMonthHeader: View {
    let month: JournalMonth
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                    Text(Self.title(month.start))
                        .font(Tokens.Typography.sectionTitle)
                    Spacer(minLength: Tokens.Space.s)
                    Text(durations: Self.facts(month))
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HistoryMonthBars(daily: month.dailyFocus)
            }
            .padding(.vertical, Tokens.Space.s)
            .padding(.horizontal, HistoryRowLayout.inset)
            .background(isSelected ? Tokens.Colour.focus.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.nested))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DurationText.spoken(in: "\(Self.title(month.start)), \(Self.facts(month))"))
        .accessibilityAddTraits(isSelected ? [.isHeader, .isButton, .isSelected] : [.isHeader, .isButton])
        .accessibilityHint("Shows this month beside the list")
    }

    static func title(_ start: Date) -> String {
        DateFormats.australian("MMMM yyyy").string(from: start)
    }

    /// `14h 20m focused · 7 days · 2h 2m per focused day`.
    static func facts(_ month: JournalMonth) -> String {
        guard month.focused > 0 else { return "no focus recorded" }
        let days = month.focusedDays == 1 ? "1 day" : "\(month.focusedDays) days"
        return "\(Tokens.duration(month.focused)) focused · \(days) · "
            + "\(Tokens.duration(month.averagePerFocusedDay)) per focused day"
    }
}

/// One bar per calendar day, height by focus. The dates are in the rows
/// below, so the bars carry no labels.
struct HistoryMonthBars: View {
    let daily: [TimeInterval]

    var body: some View {
        let peak = max(daily.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(daily.enumerated()), id: \.offset) { _, seconds in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(seconds > 0 ? AnyShapeStyle(Tokens.Colour.focus) : AnyShapeStyle(StoryStyle.line))
                    .frame(maxWidth: .infinity)
                    .frame(height: seconds > 0 ? max(3, 18 * seconds / peak) : 2)
            }
        }
        .frame(height: 18, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// A day's header and its rows: sessions newest first, breaks between them.
struct HistoryDayGroup: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    let day: JournalDay
    let selection: HistorySelection

    var body: some View {
        let isToday = Calendar.current.isDate(day.date, inSameDayAs: store.now())
        let projection = store.storyDayProjection(on: day.date)
        let rows = HistoryJournalBuilder.rows(projection, only: day.threads)
        return VStack(alignment: .leading, spacing: 0) {
            HistoryDayHeader(day: day, isToday: isToday, isSelected: selection == .day(day.date),
                             onSelect: { navigation.selectHistory(.day(day.date)) },
                             onOpen: { navigation.openDay(day.date) })
            if rows.isEmpty {
                Text(durations: day.isAppUseOnly
                     ? "Recorded app use only · \(Tokens.duration(day.tracked))"
                     : isToday ? "Nothing recorded yet today" : "Nothing recorded")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, HistoryRowLayout.inset)
                    .padding(.bottom, Tokens.Space.xs)
            }
            ForEach(rows) { entry in
                switch entry {
                case .session(let session):
                    let picked = HistorySelection.session(thread: session.threadID, day: day.date)
                    HistorySessionRow(session: session,
                                      apps: (projection.sessionDetails[session.id]?.apps ?? []).map(\.appName),
                                      note: store.journalNote(for: session)
                                          .flatMap { $0.split(whereSeparator: \.isNewline).first.map(String.init) },
                                      isSelected: selection == picked,
                                      onSelect: { navigation.selectHistory(picked) },
                                      onOpen: { navigation.openDay(day.date) })
                case .rest(let rest):
                    HistoryBreakRow(rest: rest)
                }
            }
        }
    }
}

/// `Mon 28 Sep` and the day's focus: a heading, and the way into the day.
struct HistoryDayHeader: View {
    let day: JournalDay
    let isToday: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                Text(Self.title(day.date, isToday: isToday))
                    .font(Tokens.Typography.metadata.weight(.bold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Tokens.Colour.focus) : AnyShapeStyle(.primary))
                Spacer(minLength: Tokens.Space.s)
                if day.focused > 0 {
                    Text(durations: Tokens.duration(day.focused))
                        .font(Tokens.Typography.metadata.weight(.semibold).monospacedDigit())
                }
            }
            .padding(.top, Tokens.Space.m)
            .padding(.bottom, Tokens.Space.xs)
            .padding(.horizontal, HistoryRowLayout.inset)
            .background(isSelected ? Tokens.Colour.focus.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.nested))
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DurationText.spoken(in: day.focused > 0
            ? "\(Self.title(day.date, isToday: isToday)), \(Tokens.duration(day.focused)) focused"
            : Self.title(day.date, isToday: isToday)))
        .accessibilityAddTraits(isSelected ? [.isHeader, .isButton, .isSelected] : [.isHeader, .isButton])
        .accessibilityAction(named: "Open as a story", onOpen)
    }

    static func title(_ date: Date, isToday: Bool) -> String {
        isToday ? "Today" : DateFormats.australian("EEE d MMM").string(from: date)
    }
}

/// One session: when, what, which category, how long; then the apps it used
/// and the first line of its note.
struct HistorySessionRow: View {
    let session: DaySession
    let apps: [String]
    let note: String?
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                Circle()
                    .fill(Tokens.Palette.workType(session.workType))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                        Text(Tokens.timeRange(session.start, session.end))
                            .font(Tokens.Typography.metadata.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(session.workType.sessionTitle(named: session.name))
                            .font(Tokens.Typography.rowTitle.weight(.medium))
                            .lineLimit(1)
                        // An unnamed session's title is its category already.
                        if !session.name.isEmpty { WorkTypeChip(workType: session.workType) }
                        Spacer(minLength: Tokens.Space.s)
                        Text(durations: session.isRunning ? "in progress" : Tokens.duration(session.worked))
                            .font(Tokens.Typography.metadata.weight(.semibold).monospacedDigit())
                    }
                    if let detail = Self.detail(apps: apps, note: note) {
                        Text(detail)
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, Tokens.Space.xs)
            .padding(.horizontal, HistoryRowLayout.inset)
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .background(isSelected ? Tokens.Colour.focus.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.nested))
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(session))
        .accessibilityValue(Self.detail(apps: apps, note: note) ?? "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Open its day's story", onOpen)
    }

    /// `8:30 am – 11:35 am, Refactor, Deep work, 2 hours 5 minutes`.
    static func spokenLabel(_ session: DaySession) -> String {
        var parts = [Tokens.timeRange(session.start, session.end)]
        if !session.name.isEmpty { parts.append(session.name) }
        parts.append(session.workType.displayName)
        parts.append(session.isRunning ? "in progress" : Tokens.spent(session.worked))
        return parts.joined(separator: ", ")
    }

    /// `Xcode, Terminal, Safari · “fixed the parser”`.
    static func detail(apps: [String], note: String?) -> String? {
        var parts: [String] = []
        if !apps.isEmpty { parts.append(apps.prefix(3).joined(separator: ", ")) }
        if let note, !note.isEmpty { parts.append("“\(note)”") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A recorded break between sessions, named when it was named.
struct HistoryBreakRow: View {
    let rest: RestEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Circle()
                .fill(Tokens.Palette.warmGrey.opacity(0.55))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(Tokens.timeRange(rest.start, rest.end))
                .font(Tokens.Typography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(rest.name.isEmpty ? "Break" : rest.name)
                .font(Tokens.Typography.metadata)
            Spacer(minLength: Tokens.Space.s)
            Text(durations: Tokens.duration(rest.length))
                .font(Tokens.Typography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, HistoryRowLayout.inset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Tokens.timeRange(rest.start, rest.end)), \(RestEntryRow.label(rest.name)), "
                            + Tokens.spent(rest.length))
    }
}

/// Days with nothing recorded, as one line.
struct HistoryQuietRow: View {
    let quiet: JournalQuiet

    var body: some View {
        Text(Self.text(quiet))
            .font(Tokens.Typography.metadata)
            .foregroundStyle(.tertiary)
            .padding(.vertical, Tokens.Space.s)
            .padding(.horizontal, HistoryRowLayout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `Tue 22 Sep · nothing recorded`, or `23 – 27 Sep · nothing recorded`.
    /// `DateFormats` formatters are shared and cached: read them, never set them.
    static func text(_ quiet: JournalQuiet) -> String {
        if quiet.isSingleDay {
            return "\(DateFormats.australian("EEE d MMM").string(from: quiet.last)) · nothing recorded"
        }
        return "\(DateFormats.australian("d").string(from: quiet.first)) – "
            + "\(DateFormats.australian("d MMM").string(from: quiet.last)) · nothing recorded"
    }
}
```

- [ ] **Step 5: Write the rail**

Create `Sources/Surfaces/History/HistoryJournalRail.swift`:

```swift
import SwiftUI

/// Clock hours as History says them: "9 am", "9 am – 11 am".
enum HistoryHours {
    static func label(_ hour: Int) -> String {
        let wrapped = ((hour % 24) + 24) % 24
        let twelve = wrapped % 12 == 0 ? 12 : wrapped % 12
        return "\(twelve) \(wrapped < 12 ? "am" : "pm")"
    }

    static func span(from startHour: Int) -> String {
        "\(label(startHour)) – \(label(startHour + 2))"
    }

    /// The best two hours' figure, and where it mostly fell, said once.
    static func note(seconds: TimeInterval, phrase: String?) -> String {
        var note = "\(Tokens.duration(seconds)) of focus fell here"
        if let phrase { note += ", most of it \(phrase)" }
        return note + "."
    }
}

/// What the rail describes once the selection meets the archive: a session
/// that is gone, or hidden by a search, reads as the month it was in.
enum HistoryRailScope: Equatable {
    case month(Date)
    case day(Date)
    case session(DaySession, day: Date)

    static func resolve(_ selection: HistorySelection, session: DaySession?,
                        calendar: Calendar = .current) -> HistoryRailScope {
        switch selection {
        case .month(let start): return .month(start)
        case .day(let day): return .day(day)
        case .session(_, let day):
            if let session { return .session(session, day: day) }
            return .month(selection.monthStart(calendar: calendar))
        }
    }
}

/// History's rail: the month, day or session picked in the journal, and
/// nothing from any other time frame.
struct HistoryJournalRail: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @Environment(\.focusInterfaceDensity) private var density

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            switch scope {
            case .month(let start):
                HistoryMonthRail(store: store, navigation: navigation, monthStart: start)
                    .storyRenderEvidence(.historyMonthRail)
            case .day(let day):
                HistoryDayRail(store: store, projection: store.storyDayProjection(on: day)) {
                    navigation.openDay(day)
                }
                .storyRenderEvidence(.historyDayRail)
            case .session(let session, let day):
                HistorySessionRail(store: store, session: session, day: day,
                                   apps: store.storyDayProjection(on: day).sessionDetails[session.id]?.apps ?? []) {
                    navigation.openDay(day)
                }
                .storyRenderEvidence(.historySessionRail)
            }
        }
        .padding(StoryStyle.railInsets(for: density))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scope: HistoryRailScope {
        let selection = navigation.historySelectionOrDefault()
        var session: DaySession?
        if case .session(let thread, let day) = selection {
            session = store.journalSession(thread: thread, on: day)
            // A search that hides the session, or its whole day, hides it
            // from the rail too.
            if store.historyFilter.isActive {
                let listed = store.historyJournal().contains { entry in
                    if case .day(let row) = entry { return row.date == day && (row.threads?.contains(thread) ?? true) }
                    return false
                }
                if !listed { session = nil }
            }
        }
        return HistoryRailScope.resolve(selection, session: session)
    }
}

/// The rail's title: which month, day or session it describes.
struct HistoryRailHeading: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Tokens.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(durations: detail)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A month: where its focus went, when, which goals it met, which apps, how
/// it compares with the months before, and for this month, how it is going.
struct HistoryMonthRail: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    let monthStart: Date

    var body: some View {
        let calendar = Calendar.current
        let now = store.now()
        let isCurrent = calendar.isDate(monthStart, equalTo: now, toGranularity: .month)
        let anchor = isCurrent ? now
            : (calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? monthStart)
        let facts = store.insightReading(scope: .month, anchoredAt: anchor, limit: 1).facts
        let month = HistoryJournalBuilder.month(starting: monthStart, days: store.historyDays, calendar: calendar)
        let archive = store.historyArchiveFacts()
        let recent = HistoryJournalBuilder.recentMonths(endingAt: monthStart, focusByDay: archive.focusByDay,
                                                        firstDay: archive.firstDay, calendar: calendar)
        let surface = store.insightSurface(for: .month)
        return VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HistoryRailHeading(title: HistoryMonthHeader.title(monthStart))
            if !facts.categories.isEmpty {
                StoryTile(title: "Focus by category", trailing: nil) {
                    CategoryShareBar(shares: facts.categories)
                    if isCurrent, let placed = surface.categories {
                        Text("Where each lands in the day: \(placed.headline).")
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let window = facts.bestWindow {
                StoryTile(title: "Best two hours", trailing: nil) {
                    Text(HistoryHours.span(from: window.startHour))
                        .font(Tokens.Typography.sectionTitle)
                    Text(durations: HistoryHours.note(seconds: window.seconds, phrase: facts.bestWindowPhrase))
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !facts.goalRates.isEmpty { goalsTile(facts.goalRates) }
            if !facts.apps.isEmpty { appsTile(facts.apps, tracked: month.tracked) }
            if recent.count > 1 { recentTile(recent) }
            if isCurrent { soFar(surface) }
        }
    }

    /// `16h 25m recorded app use`: the month's app use, said once, here.
    static func appUseLine(tracked: TimeInterval) -> String {
        "\(Tokens.duration(tracked)) recorded app use"
    }

    private func goalsTile(_ rates: [InsightGoalRate]) -> some View {
        StoryTile(title: "Category goals", trailing: "days met") {
            ForEach(rates) { rate in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Tokens.Space.xs) {
                        Image(systemName: rate.workType.symbolName)
                            .font(Tokens.Typography.microLabel)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Tokens.Palette.workType(rate.workType))
                            .frame(width: 14)
                            .accessibilityHidden(true)
                        Text(rate.workType.displayName)
                            .font(Tokens.Typography.metadata)
                        Spacer(minLength: Tokens.Space.s)
                        Text("\(rate.metDays) of \(rate.focusedDays)")
                            .font(Tokens.Typography.metadata.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geometry in
                        Capsule().fill(StoryStyle.line)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Tokens.Palette.workType(rate.workType))
                                    .frame(width: geometry.size.width * rate.share)
                            }
                    }
                    .frame(height: 3)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(rate.workType.displayName): \(Tokens.spent(rate.goal)) goal met on "
                                    + "\(rate.metDays) of \(rate.focusedDays) focused days")
            }
        }
    }

    private func appsTile(_ apps: [AppRank], tracked: TimeInterval) -> some View {
        let limit = store.engine.store.menuAppCount
        return StoryTile(title: apps.count > limit ? "Top \(limit) apps" : "Apps",
                         trailing: apps.count == 1 ? "1 recorded" : "\(apps.count) recorded") {
            if tracked > 0 {
                Text(durations: Self.appUseLine(tracked: tracked))
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(apps.prefix(limit).enumerated()), id: \.element.id) { index, app in
                StoryAppRow(app: app, rank: index)
            }
        }
    }

    private func recentTile(_ recent: [JournalMonthTotal]) -> some View {
        let peak = max(recent.map(\.focused).max() ?? 0, 1)
        return StoryTile(title: recent.count >= 12 ? "Last 12 months" : "Months on record", trailing: nil) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(recent) { total in
                    let isShown = total.start == monthStart
                    Button { navigation.selectHistory(.month(total.start), scrolling: true) } label: {
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Tokens.Colour.focus.opacity(isShown ? 1 : 0.35))
                                .frame(height: max(2, 44 * total.focused / peak))
                            Text(DateFormats.australian("MMMMM").string(from: total.start))
                                .font(Tokens.Typography.micro)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 60, alignment: .bottom)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DurationText.spoken(in:
                        "\(HistoryMonthHeader.title(total.start)), \(Tokens.duration(total.focused)) focused"))
                    .accessibilityAddTraits(isShown ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder private func soFar(_ surface: InsightSurface) -> some View {
        Text("This month so far")
            .font(Tokens.Typography.metadata.weight(.bold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, Tokens.Space.s)
        if surface.hasEvidence {
            if let pace = surface.pace { InsightSection(title: "Pace", insight: pace) }
            if let quality = surface.quality { InsightSection(title: "Focus quality", insight: quality) }
            if let continuity = surface.continuity { InsightSection(title: "Continuity", insight: continuity) }
        } else {
            Text(InsightSurface.insufficientEvidenceCopy)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A day: its focus and shape, its apps, its notes in full, and the way into
/// its story. Its sessions are in the journal already.
struct HistoryDayRail: View {
    @ObservedObject var store: SessionStore
    let projection: StoryDayProjection
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HistoryRailHeading(title: Tokens.longDate(projection.date))
            StoryTile(title: "Focus", trailing: nil) {
                Text(durations: Tokens.preciseDuration(projection.focused))
                    .font(Tokens.Typography.metricValue.monospacedDigit())
                    .foregroundStyle(projection.focused > 0 ? AnyShapeStyle(Tokens.Colour.focus)
                                                            : AnyShapeStyle(.secondary))
                if let note = summaryNote {
                    Text(durations: note)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 3) {
                    HistoryDayStrip(date: projection.date, entries: projection.sessions, height: 10)
                    HistoryStripAxis(leading: 0, trailing: 0)
                }
                .padding(.top, Tokens.Space.xs)
                Button("Open as a story ›", action: onOpen)
                    .buttonStyle(StoryLinkStyle())
                    .accessibilityLabel("Open \(Tokens.longDate(projection.date)) as a story")
            }
            if !projection.apps.isEmpty {
                let limit = store.engine.store.menuAppCount
                StoryTile(title: projection.apps.count > limit ? "Top \(limit) apps" : "Apps",
                          trailing: projection.apps.count == 1 ? "1 recorded" : "\(projection.apps.count) recorded") {
                    ForEach(Array(projection.apps.prefix(limit).enumerated()), id: \.element.id) { index, app in
                        StoryAppRow(app: app, rank: index)
                    }
                }
            }
            if !notes.isEmpty {
                StoryTile(title: "Notes", trailing: nil) {
                    ForEach(notes, id: \.id) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title).font(Tokens.Typography.metadata.weight(.semibold))
                            Text(note.text)
                                .font(Tokens.Typography.metadata)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var summaryNote: String? {
        var parts: [String] = []
        if projection.tracked > 0 { parts.append("\(Tokens.duration(projection.tracked)) recorded app use") }
        if projection.longestFocusStretch > 0 {
            parts.append("longest stretch \(Tokens.preciseDuration(projection.longestFocusStretch))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Notes saved against any stretch of the day's sessions, oldest first.
    private var notes: [(id: UUID, title: String, text: String)] {
        var result: [(id: UUID, title: String, text: String)] = []
        for entry in projection.sessions {
            guard case .session(let session) = entry else { continue }
            for recordID in session.recordIDs {
                let text = (store.metadataArchive.metadata(for: recordID)?.note ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    result.append((recordID, session.workType.sessionTitle(named: session.name), text))
                }
            }
        }
        return result
    }
}

/// A session: its length and time, each stretch when there were several,
/// its apps, its note in full, and the way into its day.
struct HistorySessionRail: View {
    @ObservedObject var store: SessionStore
    let session: DaySession
    let day: Date
    let apps: [AppRank]
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HistoryRailHeading(title: session.workType.sessionTitle(named: session.name),
                               detail: Tokens.longDate(day))
            StoryTile(title: session.workType.displayName, trailing: nil) {
                Text(durations: session.isRunning ? "In progress" : Tokens.preciseDuration(session.worked))
                    .font(Tokens.Typography.metricValue.monospacedDigit())
                Text(Tokens.timeRange(session.start, session.end))
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                if session.spans.count > 1 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(session.spans.count) stretches")
                            .font(Tokens.Typography.metadata.weight(.semibold))
                        ForEach(Array(session.spans.enumerated()), id: \.offset) { _, span in
                            Text(Tokens.timeRange(span.start, span.end))
                                .font(Tokens.Typography.metadata.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Open its day ›", action: onOpen)
                    .buttonStyle(StoryLinkStyle())
                    .accessibilityLabel("Open \(Tokens.longDate(day)) as a story")
            }
            if !apps.isEmpty {
                let limit = store.engine.store.menuAppCount
                StoryTile(title: apps.count > limit ? "Top \(limit) apps" : "Apps",
                          trailing: apps.count == 1 ? "1 recorded" : "\(apps.count) recorded") {
                    ForEach(Array(apps.prefix(limit).enumerated()), id: \.element.id) { index, app in
                        StoryAppRow(app: app, rank: index)
                    }
                }
            }
            if !notes.isEmpty {
                StoryTile(title: notes.count == 1 ? "Note" : "Notes", trailing: nil) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, text in
                        Text(text)
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var notes: [String] {
        session.recordIDs.compactMap { id in
            let text = (store.metadataArchive.metadata(for: id)?.note ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }
}
```

- [ ] **Step 6: Typecheck, then run the self-tests (sandbox disabled)**

Run the typecheck command. Fix only real compile errors:
- `let` inside a `ForEach` builder is supported from Swift 5.4. If the toolchain rejects it, hoist the value into a small helper function.
- If `NSStandardKeyBindingResponding.insertNewline(_:)` fails to resolve, use `#selector(NSResponder.insertNewline(_:))`.

Then run `./build.sh --check 2>&1 | grep -E "\[FAIL\]|^         - |passed$"`.
Expected: all six new checks PASS; nothing else regresses.

- [ ] **Step 7: Commit**

```bash
git add Sources/Surfaces/History Sources/Surfaces/Story/StoryColumns.swift Sources/Core/FirstRun.swift Sources/Verification/StoryWorkspaceChecks.swift Sources/Verification/HistoryJournalChecks.swift
git commit -m "History's journal and rail are drawn, spoken and walkable with the arrow keys

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: History opens as the journal

**Files:**
- Modify: `Sources/Surfaces/Main/MainWindowView.swift:150-157` (host `HistoryWorkspace`)
- Modify: `Sources/Surfaces/Main/StoryChromeBar.swift:131-212` (History bar: title + Jump to date)
- Modify: `Sources/Core/FirstRun.swift:392-411` (the "Looking back" cards)
- Modify: `Sources/Surfaces/Snapshotter.swift` (two scenarios; History routes)
- Modify: `Sources/SelfTest.swift:7195` (scenario order)
- Test: `Sources/Verification/CompactControlsChecks.swift:470-515` (`scopeRowsShareOneKeyboardTarget`)

**Interfaces:**
- Consumes: `HistoryWorkspace`, `navigation.jumpToHistoryDay`, `navigation.selectHistory`, `navigation.historySelectionOrDefault`, `CoachAnchor.journal`.
- Produces: `SnapshotScenario.historySession`, `.historySearch`.

- [ ] **Step 1: Update the check to the new chrome (it fails first)**

In `scopeRowsShareOneKeyboardTarget`:
- Change `for (tab, expected) in [(AppTab.story, 0), (.insights, 1), (.review, 1)]` to `for (tab, expected) in [(AppTab.story, 0), (.insights, 0), (.review, 0)]`.
- Change the comment above it to `// Neither the story nor History has a scope row: the story is a day, and History is one list.`
- Replace `InsightsView(store: store, navigation: insightsNavigation, scrolls: false)` with `HistoryWorkspace(store: store, navigation: insightsNavigation, scrolls: false)`.
- Replace the failure text `"The Insights page duplicated the chrome's scope control "` with `"The History page carried a scope control "`.

In `Sources/SelfTest.swift` `testSnapshotMatrixCoversEveryMaterialSurface`, change `.reviewHistorySelection,` to `.reviewHistorySelection, .historySession, .historySearch,`.

Run: `./build.sh --check 2>&1 | grep -E "\[FAIL\]|^         - |passed$"` (sandbox disabled). It should not compile yet, because `.historySession` does not exist. Adding the cases in Step 4 makes the matrix check pass; the scope-row check keeps failing until the chrome changes in Step 2.

- [ ] **Step 2: The History bar names the page and offers the calendar**

In `StoryChromeBar.swift`, replace the whole `case .history:` branch of `workspaceControls` with:

```swift
        case .history:
            // History is one list, newest first: the bar names it and offers
            // the calendar. Scrolling replaces paging, so there are no arrows.
            Text("History")
                .font(Tokens.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Tokens.Space.s)
            jumpToDate
                .coachAnchor(.periodNav)
            Spacer(minLength: Tokens.Space.s)
```

Delete the `insightNavigation` property and the `shownHistorySpan` property together with their doc comments. Keep `@StateObject private var historyCalendarShown = BoolBox()`. Add:

```swift
    /// History's calendar: pick a day and the journal selects it and scrolls
    /// there. Each date shows its focus, so the calendar is also a map.
    private var jumpToDate: some View {
        Button { historyCalendarShown.value.toggle() } label: {
            Label("Jump to date", systemImage: "calendar")
                .font(Tokens.Typography.metadata.weight(.semibold))
                .padding(.horizontal, Tokens.Space.m)
                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.well))
        .help("Pick a day to read in History")
        .accessibilityHint("Opens the calendar; the day you pick is selected in the list")
        .popover(isPresented: Binding(get: { historyCalendarShown.value },
                                      set: { historyCalendarShown.value = $0 }),
                 arrowEdge: .bottom) {
            DayPickerCalendar(
                selected: navigation.historySelectionOrDefault().day ?? store.now(),
                earliest: store.earliestSelectableDay,
                goal: store.goal.goal,
                facts: { store.dayFacts(inMonthOf: $0) }) { day in
                    navigation.jumpToHistoryDay(day)
                    historyCalendarShown.value = false
                }
        }
    }
```

- [ ] **Step 3: The window hosts the journal**

In `MainWindowView.swift` `readingWorkspace`, replace

```swift
                InsightsView(store: store, navigation: navigation,
                             scrolls: insightsScrolls)
```

with

```swift
                HistoryWorkspace(store: store, navigation: navigation,
                                 scrolls: insightsScrolls)
```

Keep the `.onAppear` and `.onDisappear` exactly as they are.

- [ ] **Step 4: The tour and the snapshots describe the journal**

In `FirstRun.swift`, replace the three `Card`s of `Chapter(id: .lookingBack, …)` with:

```swift
            Card(sentence: "The story is a day. History is the longer view.",
                 body: "History lists every day you recorded, newest first: each month "
                     + "with its total, each day with its sessions. Click a month, a day "
                     + "or a session to read it beside the list. ↑ and ↓ move through it; "
                     + "Return opens a day's story.",
                 anchor: .journal,
                 effect: .showHistory),
            Card(sentence: "History goes back to the day you installed the app.",
                 body: "Scroll to go further back, or use Jump to date to pick a day on "
                     + "the calendar. There is nothing from before the app was here, "
                     + "because nothing was recorded.",
                 anchor: .periodNav,
                 effect: .showHistory),
            Card(sentence: "Find any session by name.",
                 body: "The search at the top of History finds sessions by what you "
                     + "called them, what you noted, the app, the category or the date. "
                     + "⌘F takes you there from anywhere in the window.",
                 anchor: .search,
                 effect: .showHistory)
```

In `Snapshotter.swift`:
1. Change `case reviewHistorySelection` to `case reviewHistorySelection, historySession, historySearch`.
2. In `title`, add after the `.reviewHistorySelection` line:
```swift
        case .historySession: return "History — a session selected"
        case .historySearch: return "History — searching"
```
3. In `tab`, change `case .reviewHistorySelection:` to `case .reviewHistorySelection, .historySession, .historySearch:`.
4. In `store(for:)`, add after the `.reviewHistorySelection` case:
```swift
        case .historySession:
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            store.refreshReview()
            return store
        case .historySearch:
            let store = FixtureFactory.insightsStore(withEvidence: true)
            store.refreshReview()
            store.setHistoryQuery("Build")
            return store
```
5. In `navigation(for:store:)`, replace the `.reviewHistorySelection` and `.insightsEnough, .insightsEmpty` cases with:
```swift
        case .reviewHistorySelection:
            navigation.open(tab: .review)
            if let day = store.historyDays.first(where: { $0.sessions > 0 })?.date {
                navigation.selectReviewDay(day)
            }
        case .historySession:
            navigation.open(tab: .review)
            if let day = store.historyDays.first(where: { $0.sessions > 0 })?.date,
               let thread = store.journalThreads(on: day, only: nil).first {
                navigation.selectHistory(.session(thread: thread, day: day))
            }
        case .insightsEnough, .insightsEmpty, .historySearch:
            navigation.open(tab: .review)
```
6. The typecheck lists any other exhaustive `switch` over `SnapshotScenario` (for example in `GalleryView.swift`). Give `.historySession` and `.historySearch` the same handling as `.reviewHistorySelection` there.

- [ ] **Step 5: Run the self-tests (sandbox disabled)**

Run: `./build.sh --check 2>&1 | grep -E "\[FAIL\]|^         - |passed$"`
Expected: no `[FAIL]`. If a FirstRun check pins the old card text or anchors, update it to the new text above (the cards describe a changed feature). Never weaken a check that guards a still-true rule.

- [ ] **Step 6: Look at it (sandbox disabled)**

```bash
./build.sh
mkdir -p "$TMPDIR/fc-after"
for s in insightsEnough reviewHistorySelection historySession historySearch insightsEmpty storyDay; do
  FC_SNAPSHOT_ONLY=$s ./FocusContinuity.app/Contents/MacOS/FocusContinuity --snapshot "$TMPDIR/fc-after"
done
ls "$TMPDIR/fc-after"
```
Open the light and dark PNGs of each with the Read tool and check:
- the journal reads newest first
- each total appears once
- the rail shows one scope
- nothing clips at the minimum width

Fix layout problems in the History views, not in the checks.

- [ ] **Step 7: Commit**

```bash
git add Sources/Surfaces/Main/MainWindowView.swift Sources/Surfaces/Main/StoryChromeBar.swift Sources/Core/FirstRun.swift Sources/Surfaces/Snapshotter.swift Sources/SelfTest.swift Sources/Verification/CompactControlsChecks.swift
git commit -m "History opens as one journal with a calendar to jump by, and the tour says so

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The old History is retired

**Files:**
- Move to `…/FocusContinuity/_trash/2026-09-29-history-journal/`: `Sources/Surfaces/Insights/InsightsView.swift`, `Sources/Surfaces/Insights/InsightCharts.swift`
- Modify: `Sources/Surfaces/Review/HistoryFind.swift` (keep only `HistoryFindBar`)
- Modify: `Sources/Surfaces/Review/HistoryDayList.swift` (keep `HistoryRowLayout`, `HistoryDayStrip`, `HistoryStripAxis`)
- Modify: `Sources/App/MainWindowModel.swift` (remove range, span and paging state)
- Modify: `Sources/Surfaces/Dashboard/DayPickerCalendar.swift` (remove the unused range mode)
- Modify: `Sources/Surfaces/Story/StoryColumns.swift` (remove the four unused evidence cases)
- Modify checks: `StoryNavigationChecks.swift`, `StoryWorkspaceChecks.swift`, `StoryIntegrationChecks.swift`, `RedundancyChecks.swift`

**Interfaces:**
- Consumes: `HistoryHours.label(_:)`, `.note(seconds:phrase:)`, `HistoryMonthRail.appUseLine(tracked:)`, `HistoryJournalBuilder.entries(days:today:calendar:)`, `navigation.selectHistory`.
- Produces: nothing new. Removes:
  - `HistoryRange`, `HistorySpan`
  - `MainWindowModel.historyRange`, `historySpan`, `insightEnd`, `selectHistoryRange`, `setCustomHistoryRange`, `insightRange`, `insightRequestedCount`, `insightAnchor`, `stepInsightPeriod`, `insightShownCount`, `pageInsights`, `insightCanPageForward`, `insightCanPageBack`, `insightWindow`, `jumpInsights`, `insightWindowLabel`, `insightAnchorLabel`
  - `DayPickerCalendar.init(range:…)`
  - `StoryRenderEvidence.historyDetail`, `.insightPeriod`, `.insightStrongestDay`, `.insightEmptyPeriod`

- [ ] **Step 1: Rewrite the checks that describe retired behaviour**

1. `StoryNavigationChecks`: delete the `("History ranges read a fixed span at the grouping that suits it", historyRanges),` entry and the `historyRanges()` function. The ranges no longer exist; `historyPicks` and `historyJumpAndSteps` cover History's navigation now.

2. `StoryWorkspaceChecks`:
   - Replace the test entry `("History never shows a period from before the record began", insightRecordFloor),` with `("History's journal never lists a day from before the record began", journalRecordFloor),`.
   - Replace the `insightRecordFloor()` function with:
```swift
    private static func journalRecordFloor() -> [String] {
        MainActor.assumeIsolated {
            var failures: [String] = []
            let calendar = Calendar.current
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            store.refreshReview()
            guard let earliest = store.earliestSelectableDay else {
                return ["The evidence fixture has no first recorded day to stop at"]
            }
            let entries = store.historyJournal()
            let listed = entries.compactMap { entry -> Date? in
                switch entry {
                case .day(let day): return day.date
                case .quiet(let quiet): return quiet.first
                case .month: return nil
                }
            }
            if let oldest = listed.min(), oldest < calendar.startOfDay(for: earliest) {
                failures.append("the journal reached \(oldest), before the record began on \(earliest)")
            }
            if listed.min().map({ $0 > calendar.startOfDay(for: earliest) }) ?? true {
                failures.append("the journal stopped short of the first recorded day \(earliest)")
            }
            let bare = FixtureFactory.store(for: .firstRun)
            bare.refreshReview()
            if bare.historyJournal().count != 2 {
                failures.append("with nothing recorded the journal listed \(bare.historyJournal().count) rows, "
                                + "not this month and today")
            }
            return failures
        }
    }
```
   - In `offscreenWorkspaceRenders()`, delete everything from `navigation.open(tab: .review)` through the `FixtureFactory.cleanUp()` that ends the `HistoryRange` loop. The Day story render and its checks stay; History's renders are pinned by `HistoryJournalChecks.journalRenders`. Delete `let navigation = MainWindowModel(store: dense)` too, since it is then unused, and keep one `FixtureFactory.cleanUp()` before `return failures`.

3. `StoryIntegrationChecks.insightsLeaveStory()`: replace the `for range in HistoryRange.allCases { … }` loop with:
```swift
            store.refreshReview()
            navigation.open(tab: .review)
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: store.now())!
            var picks: [HistorySelection] = [.month(yesterday), .day(Calendar.current.startOfDay(for: yesterday))]
            if let thread = store.journalThreads(on: yesterday, only: nil).first {
                picks.append(.session(thread: thread, day: Calendar.current.startOfDay(for: yesterday)))
            }
            for pick in picks {
                navigation.selectHistory(pick)
                if store.selectedDay != shown {
                    failures.append("picking \(pick) in History changed the story's day")
                }
            }
```

4. `RedundancyChecks`:
   - Replace `("The hour grid's caption carries the best two hours in full", gridCarriesBestHours),` with `("The best two hours are said once, with where they fell", bestHoursSaidOnce),`.
   - Replace `("History's headline carries recorded app use once its total card is gone", historyHeadlineAppUse),` with `("History's month carries recorded app use in its rail, not its header", monthAppUseOnce),`.
   - Replace the two functions with:
```swift
    private static func bestHoursSaidOnce() -> [String] {
        let note = HistoryHours.note(seconds: 12_000, phrase: "on Tuesdays")
        return note == "\(Tokens.duration(12_000)) of focus fell here, most of it on Tuesdays."
            ? [] : ["the best-hours note lost its figure or place: \(note)"]
    }

    private static func monthAppUseOnce() -> [String] {
        let month = JournalMonth(start: Date(timeIntervalSince1970: 1_800_000_000), focused: 3_600,
                                 tracked: 7_200, focusedDays: 1, dailyFocus: [3_600])
        var failures: [String] = []
        if HistoryMonthHeader.facts(month).contains("app use") {
            failures.append("the month header repeated recorded app use")
        }
        if HistoryMonthRail.appUseLine(tracked: month.tracked) != "\(Tokens.duration(7_200)) recorded app use" {
            failures.append("the month rail lost recorded app use")
        }
        return failures
    }
```

- [ ] **Step 2: Move the retired views out**

```bash
TRASH=/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/_trash/2026-09-29-history-journal
mkdir -p "$TRASH"
ls "$TRASH"
mv Sources/Surfaces/Insights/InsightsView.swift "$TRASH/InsightsView.swift"
mv Sources/Surfaces/Insights/InsightCharts.swift "$TRASH/InsightCharts.swift"
```
If `ls` shows a file with the same name already there, stop and ask the user before overwriting.

Before moving, run `grep -n "^struct \|^enum \|^extension \|^final class " Sources/Surfaces/Insights/InsightCharts.swift`. If it declares any type besides `InsightTrendChart`, `InsightHourGrid`, `InsightMonthCalendars` and `InsightDayStrips`, grep for that type; if something outside the moved files uses it, cut that type into `HistoryJournalRail.swift` first.

- [ ] **Step 3: Trim the Review files**

- `HistoryFind.swift`: delete `HistoryFindResults`, `HistoryArchiveTiles`, `HistoryHitMonth` and `HistoryHitRow`, each with its doc comment. Keep `HistoryFindBar` unchanged.
- `HistoryDayList.swift`: delete `HistoryDayRow` and `HistoryDayPreview`, each with its doc comment. In `HistoryStripAxis`, change `Text(InsightHourGrid.hourLabel(hour))` to `Text(HistoryHours.label(hour))`.

- [ ] **Step 4: Remove the range state from the window model**

In `MainWindowModel.swift`, delete:
- `enum HistoryRange` (with its doc comment) and `struct HistorySpan` (with its doc comment)
- the properties `historyRange`, `historySpan` and `insightEnd` (with their comments)
- the line `self.insightEnd = Calendar.current.startOfDay(for: store?.now() ?? Date())` in `init`
- every member from `func selectHistoryRange` to the end of `var insightAnchorLabel`: `selectHistoryRange`, `setCustomHistoryRange`, `insightRange`, `insightRequestedCount`, `insightAnchor`, `stepInsightPeriod`, `insightShownCount`, `pageInsights`, `insightCanPageForward`, `insightCanPageBack`, `insightWindow`, `jumpInsights`, `insightWindowLabel`, `insightAnchorLabel`

Keep `enum InsightRange`: `InsightSurface` and the period projections still group by it.

- [ ] **Step 5: The calendar keeps only its single-day mode**

In `DayPickerCalendar.swift`:
- Delete `RangeAnchorBox` (lines 23-26), the `hovered` property of `MonthBox` with its comment (lines 18-19), the `range` and `onPickRange` properties with their comment (lines 40-43), `@StateObject private var anchor = RangeAnchorBox()`, the two lines `self.range = nil` and `self.onPickRange = nil`, the whole `init(range:…)`, and `paintedRange`.
- Replace `pick(_:)` with:
```swift
    private func pick(_ day: Date) { onPick(day) }
```
- In `dayCell`, replace
```swift
        let painted = paintedRange
        let isSelected = painted.map { key == $0.lowerBound || key == $0.upperBound }
            ?? calendar.isDate(day, inSameDayAs: selected)
        let inRange = painted.map { $0.contains(key) } ?? false
```
with
```swift
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
```
- Change the cell background to
```swift
            .background(isSelected ? AnyShapeStyle(Tokens.Colour.focus) : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
```
- In `.onHover`, delete the line `if range != nil { shown.hovered = … }`.
- `legend` keeps only its `else` branch's `Text(...)` and modifiers, with the `if range != nil` branch removed.
- Update the type's doc comment: "A month grid for picking a day, readable at a glance: …" (drop "or in History a span").

- [ ] **Step 6: Drop the unused evidence cases**

Run: `grep -rn "\.historyDetail\|\.insightPeriod\|\.insightStrongestDay\|\.insightEmptyPeriod" Sources`
Expected: no hits. Then delete those four cases from `StoryRenderEvidence`. If anything still uses them, fix that user first.

- [ ] **Step 7: Nothing references the old History**

Run: `grep -rn "InsightsView\|InsightTrendChart\|InsightHourGrid\|InsightMonthCalendars\|InsightDayStrips\|HistoryFindResults\|HistoryHitRow\|HistoryArchiveTiles\|HistoryDayRow\|HistoryDayPreview\|HistoryRange\|HistorySpan\|insightAnchor\|insightWindow\|selectHistoryRange\|setCustomHistoryRange\|onPickRange" Sources`
Expected: no hits except words inside comments. Rewrite any stale comment so it describes the journal.

- [ ] **Step 8: Run the self-tests (sandbox disabled)**

Run: `./build.sh --check 2>&1 | grep -E "\[FAIL\]|^         - |passed$"`
Expected: no `[FAIL]`. The total is at least the Task 0 baseline: +13 +2 +6 new, −1 retired (`historyRanges`), with the rest replaced one for one.

- [ ] **Step 9: Commit**

```bash
git add -A Sources
git commit -m "The range-and-chart History is retired; the calendar picks one day

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Docs, screenshots and landing

**Files:**
- Modify: `README.md`, `docs/usage.md`, `DESIGN.md` (their History passages)
- Replace: `docs/screenshots/day-story.png`, `docs/screenshots/history-dark.png`. Add `docs/screenshots/history.png`. Move `docs/screenshots/history-year.png` to `_trash/2026-09-29-history-journal/`.
- Memory: `/Users/prabeshbhetwal/.claude/projects/-Users-prabeshbhetwal-Desktop-Files-Development-Project-FocusContinuity/memory/redundancy-pass-2026-09-28.md` and `MEMORY.md`

- [ ] **Step 1: Find every stale History sentence**

Run: `grep -n "7 days\|30 days\|3 months\|12 months\|range\|span\|History" README.md docs/usage.md DESIGN.md`
Rewrite each passage about History so it says, in the doc's own voice:

> History is one list, newest first, back to the day the app was installed. Each month shows its focus, focused days and daily average over a thin bar per day; each day shows its focus; each session its time, name, category, length, apps and the first line of its note. Days with nothing recorded fold into one line. Click a month, a day or a session and the column beside the list describes just that; ↑ and ↓ move through the list and Return opens a day's story. Jump to date opens the calendar, where each date shows its focus. The search at the top narrows the same list; ⌘F reaches it from anywhere.

Keep the accessibility session's shortcut table and Keyboard panel in `docs/usage.md`, adding only the two History keys: ↑/↓ move through History, Return opens the selected day.

- [ ] **Step 2: Refresh the screenshots (sandbox disabled)**

```bash
./build.sh
rm -rf "$TMPDIR/fc-docs"; mkdir -p "$TMPDIR/fc-docs"
for s in storyDay insightsEnough historySession; do
  FC_SNAPSHOT_ONLY=$s ./FocusContinuity.app/Contents/MacOS/FocusContinuity --snapshot "$TMPDIR/fc-docs"
done
ls "$TMPDIR/fc-docs"
```
Copy the comfortable-width PNGs into the docs:
- `storyDay` light → `docs/screenshots/day-story.png`
- `insightsEnough` light → `docs/screenshots/history.png`
- `historySession` dark → `docs/screenshots/history-dark.png`

Move `docs/screenshots/history-year.png` into the `_trash` folder, then change every `history-year.png` link in `README.md` to `history.png`. Read each new PNG before committing it.

- [ ] **Step 3: Before and after**

Open `$TMPDIR/fc-before` and the new PNGs side by side with the Read tool: the Day page and History. Confirm the text is visibly smaller, nothing is clipped, and the rail fits at 300pt. Send the pair with SendUserFile (caption: "Before / after: Day page and History").

- [ ] **Step 4: Final full run (sandbox disabled)**

Run: `./build.sh --check 2>&1 | grep -E "\[FAIL\]|^         - |passed$"`
Expected: `N/N passed`, N ≥ the Task 0 baseline + 20.

- [ ] **Step 5: Commit**

```bash
git add -A README.md DESIGN.md docs
git commit -m "The docs and screenshots show History as one journal and the smaller text

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Update memory**

In `redundancy-pass-2026-09-28.md`, replace the Option A bullets about History (rolling ranges, "calendar is a picker only") with one line:

> Superseded 2026-09-29: History is one scrolling journal with a month/day/session rail ([[history-journal-2026-09-29]]); the calendar shows each day's focus again at the user's request.

Create `history-journal-2026-09-29.md` (type: project) recording:
- the journal replaced the rolling ranges
- the type scale is now `[9…36]` with rows at 14, and the rail is 300pt
- the Manager session owns the accessibility pass on History

Add its one-line pointer to `MEMORY.md`.

- [ ] **Step 7: Hand over**

Send to Manager (`local_346045dc-bea7-4062-82e0-a89dea4ac39c`):

> History journal landed on `claude/app-size-history-redesign-2628b9` at \<sha\>. It adds headers, spoken rows, ↑/↓/Return and Reduce Motion. Your accessibility pass on `Surfaces/History/*` is clear to start. `StoryTile`'s trailing text is plain `Text`, so a duration there is spoken as metres; that component is yours.

Then invoke superpowers:finishing-a-development-branch to choose how it lands on main.
