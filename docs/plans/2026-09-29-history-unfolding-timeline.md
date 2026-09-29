# History Unfolding Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace History's flat journal with one timeline that unfolds in place — years › months › weeks › days › sessions, each level indented under its parent — clipped to the recorded span, with a rail that follows the deepest open row, and make the dashboard show today only.

**Architecture:** A pure builder (`HistoryTreeBuilder`, `Sources/Core/HistoryTree.swift`) turns the store's day index (`historyDays`) into rows for any parent place, clipped to `[first recorded day, today]`. The store caches rows per evidence revision and patches only rows holding today. `MainWindowModel` holds the open path (`historyOpen: [HistoryPlace]`), the selected session and the keyboard focus. `HistoryTree` renders the column; `HistoryJournalRail` gains a period scope. The journal's month headers, quiet runs and `HistorySelection` are retired; its session and break rows are kept as the deepest level. The dashboard's ‹ › and calendar are removed.

**Tech Stack:** Swift 5, SwiftUI + AppKit, macOS 13 target, built by `swiftc` through `build.sh`. No Xcode project, no SPM. Self-tests live in `Sources/Verification/*Checks.swift` and are registered in `Sources/SelfTest.swift`.

**Spec:** `docs/specs/2026-09-29-history-unfolding-timeline-design.md`

## Global Constraints

- Target `arm64-apple-macos13.0`, Swift 5. No new dependencies. No macOS 14-only API (`onKeyPress`, `focusEffectDisabled`, `ContentUnavailableView` are out).
- Every level is clipped to `[SessionStore.earliestDay, today]`. No row, bar or figure is drawn for a day before the first recorded day or after today.
- Weeks are Monday to Sunday. `HistoryTreeBuilder.calendar(_:)` forces `firstWeekday = 2` and every date arithmetic in the tree goes through it.
- One open row per level. `historyOpen` is a path: index 0 is a root row, index n is a child of index n−1.
- Each fact is shown once: the headline gives the top period's totals; a row gives its own; a day of one finished session shows the figure on the session row, not the day row (kept from the journal, `HistoryDayHeader.showsTotal`).
- Duration figures use `Text(durations:)`. Spoken labels built from strings with compact durations go through `DurationText.spoken(in:)`.
- Motion goes through `Tokens.Motion.animation(_:reduceMotion:)` / `Tokens.Motion.transition(_:reduceMotion:)` or `MainWindowModel.animated`, so Reduce Motion is honoured.
- Never delete a file: retired files go to `/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/_trash/2026-09-29-history-tree/` (the main checkout's gitignored `_trash/`; the worktree's copy would vanish with the worktree).
- Commit messages follow the repo's style: one plain sentence naming what now works, no `feat:` prefix. Every message ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- The self-test count never drops below the Task 0 baseline minus the checks this plan retires by name (listed in Task 6, Step 1).
- Build and test with the sandbox disabled: `./build.sh --check` (the `sips` icon step fails inside the sandbox). The quick compile check runs in the sandbox: `swiftc -typecheck -module-cache-path $TMPDIR/mc -swift-version 5 -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 $(find Sources -name '*.swift')`.
- Work on branch `claude/activity-rule-sessions-9bc6da` in this worktree. It carries uncommitted activity-rule edits in `ActivityRuleDetector.swift`, `AppCoordinator.swift`, `SettingsGroups.swift`, `ActivityRuleChecks.swift`, `docs/usage.md`; never `git add -A`. Stage only the files each task names.

## Review Focus

1. **Midnight while History is open.** Today's row must appear under this week, the old today becomes `Tue 29 Sep`, and on a Monday the new week row appears with one day. Pinned in Task 1 (`dayRollover`).
2. **A record that begins mid-week and mid-month** (installed Wednesday 17 September). The first week row is `17 – 20 Sep` with four bars and opens to four days; September has fourteen bars. Pinned in Task 1 (`clippedToRecord`).
3. **A week across a month boundary** (28 Sep – 4 Oct). It appears under both months, clipped, and each month's rows sum to the month's total. Pinned in Task 1 (`weekAcrossMonths`).
4. **A running session while a year is open.** Today's figures must move up through the day, week, month and year rows without rebuilding the whole tree every second. Pinned in Task 2 (`liveTodayReachesRows`, `treeIsCached`).
5. **A searched-away or removed session that the rail describes.** The rail must fall back to the deepest open row, never show a stale session. Pinned in Task 5 (`railFollowsDeepestOpen`).

---

### Task 0: Baseline

**Files:** none changed.

- [ ] **Step 1: Confirm the branch and the uncommitted activity-rule edits**

```bash
cd /Users/prabeshbhetwal/Documents/FocusContinuity/app-size-history-redesign-2628b9
git status --short
git log --oneline -3
```

Expected: branch `claude/activity-rule-sessions-9bc6da`; five modified files (the activity-rule change); top commit `5ef8d82 Spec: History is one unfolding timeline…`. Leave those five files alone throughout.

- [ ] **Step 2: Record the self-test baseline**

```bash
./build.sh --test 2>&1 | tail -3
```

Expected: `514/514 passed` (or the current count). Write the number down; Task 8 compares against it.

- [ ] **Step 3: Make the trash folder**

```bash
mkdir -p "/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/_trash/2026-09-29-history-tree"
```

---

### Task 1: The tree's types and pure builder

**Files:**
- Modify: `Sources/Core/HistoryStats.swift:7-16` (add `focusByWorkType` to `HistoryDay`), `:94-100` (accumulator), `:177-182` (construction)
- Modify: `Sources/App/SessionStore+Story.swift:219-228` (today's running patch carries the category)
- Create: `Sources/Core/HistoryTree.swift`
- Create: `Sources/Verification/HistoryTreeChecks.swift`
- Modify: `Sources/SelfTest.swift:470` (register)

**Interfaces:**
- Consumes: `HistoryDay` (date, tracked, focused, sessions, appBundleIDs, workTypes), `WorkType.countsAsFocus`, `WorkTypeShare.shares(from:)`.
- Produces:
  - `enum HistoryLevel: Int, Comparable, CaseIterable { case year = 0, month, week, day }` with `var child: HistoryLevel?`, `var component: Calendar.Component`, `var spokenName: String`.
  - `struct HistoryPlace: Hashable { let level: HistoryLevel; let span: DateInterval }` with `var start: Date`, `var id: String`.
  - `struct HistoryBar: Equatable { let start: Date; let focused: TimeInterval }`.
  - `struct HistoryRow: Identifiable, Equatable { let place: HistoryPlace; let focused, tracked: TimeInterval; let focusedDays, sessions: Int; let mainWorkType: WorkType?; let hasEvidence: Bool; let bars: [HistoryBar] }` with `var isEmpty: Bool { !hasEvidence }`, `var id: String { place.id }`.
  - `struct HistoryTop: Equatable { let place: HistoryPlace?; let firstDay: Date; let today: Date }` with `var span: DateInterval`, `var rootLevel: HistoryLevel`.
  - `struct HistorySummary: Equatable { let focused, tracked: TimeInterval; let focusedDays, sessions: Int; let best: (place: HistoryPlace, focused: TimeInterval)? }` (custom `==`).
  - `enum HistoryTreeBuilder` with `calendar(_:)`, `top(days:today:calendar:)`, `period(_:containing:calendar:)`, `rows(under:top:days:calendar:)`, `summary(top:days:calendar:)`, `pathToToday(top:calendar:)`, `path(to:top:calendar:)`, `patching(_:top:live:days:calendar:)`.

- [ ] **Step 1: Give `HistoryDay` its per-category focus**

In `Sources/Core/HistoryStats.swift` replace the struct at lines 7–16 with:

```swift
struct HistoryDay: Identifiable, Equatable {
    let date: Date
    let tracked: TimeInterval
    let focused: TimeInterval
    let sessions: Int
    let appBundleIDs: Set<String>
    let workTypes: Set<WorkType>
    /// Focused seconds by category, so a period can name the category it
    /// spent most of its focus in. Sums to `focused`.
    var focusByWorkType: [WorkType: TimeInterval] = [:]

    var id: Date { date }
}
```

Add to `DayAccumulator` (line 94):

```swift
        var focusByWorkType: [WorkType: TimeInterval] = [:]
```

In the session loop (line 166) after `bucket.focused += worked` add:

```swift
                        bucket.focusByWorkType[record.workType, default: 0] += worked
```

In the construction (line 178) pass it:

```swift
            HistoryDay(date: date, tracked: bucket.tracked,
                       focused: bucket.focused, sessions: bucket.threadIDs.count,
                       appBundleIDs: bucket.appBundleIDs,
                       workTypes: bucket.workTypes,
                       focusByWorkType: bucket.focusByWorkType)
```

In `Sources/App/SessionStore+Story.swift` the running-session patch (line 219) becomes:

```swift
                    result[index] = HistoryDay(date: existing.date,
                                               tracked: existing.tracked,
                                               focused: existing.focused + contributed,
                                               sessions: storySessionCount(on: day),
                                               appBundleIDs: existing.appBundleIDs,
                                               workTypes: workTypes,
                                               focusByWorkType: existing.focusByWorkType
                                                   .merging([engine.activeWorkType: contributed], uniquingKeysWith: +))
```

and the `else` branch (line 226):

```swift
                    result.append(HistoryDay(date: day, tracked: 0, focused: contributed,
                                             sessions: storySessionCount(on: day),
                                             appBundleIDs: [], workTypes: [engine.activeWorkType],
                                             focusByWorkType: [engine.activeWorkType: contributed]))
```

The other `HistoryDay(` call sites (`SessionStore+Story.swift:39`, the checks' fixtures) compile unchanged because the new field has a default.

- [ ] **Step 2: Write the failing checks**

Create `Sources/Verification/HistoryTreeChecks.swift`:

```swift
import Foundation
import SwiftUI

/// Behavioural checks for History's tree: the top rule, clipping to the
/// record, week and month boundaries, and the pure helpers the model and
/// keyboard rely on. Fixtures are invented days; no archive is read.
enum HistoryTreeChecks {
    static let tests: [(String, () -> [String])] = [
        ("History opens on the smallest period that holds the whole record", topRule),
        ("Nothing is drawn before the first recorded day or after today", clippedToRecord),
        ("A week across a month boundary appears under both months, clipped, and the months still sum", weekAcrossMonths),
        ("Rows carry their category, hollow when only the Mac was seen, empty when nothing was", dots),
        ("Midnight adds today's row and, on a Monday, a new week", dayRollover),
        ("The opening path unfolds to this week and no further", pathToToday),
        ("Jump to date builds the path down to the day", pathToDay),
        ("A daylight-saving week keeps seven days", daylightSaving),
        ("The tree's summary names the best month for a year and the best day for a month", summaryBest)
    ]

    // MARK: - Fixtures

    /// Sydney, so the daylight-saving check meets a real transition.
    static let calendar: Calendar = HistoryTreeBuilder.calendar({
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        calendar.locale = Locale(identifier: "en_AU")
        return calendar
    }())

    static func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func row(_ month: Int, _ day: Int, year: Int = 2026, focused: TimeInterval = 0,
                    tracked: TimeInterval = 0, sessions: Int = 0,
                    types: [WorkType: TimeInterval] = [:]) -> HistoryDay {
        HistoryDay(date: date(month, day, year: year), tracked: tracked, focused: focused, sessions: sessions,
                   appBundleIDs: [], workTypes: Set(types.keys), focusByWorkType: types)
    }

    /// Installed Wednesday 17 September 2026; today is Tuesday 29 September.
    static let september: [HistoryDay] = [
        row(9, 28, focused: 3_600, tracked: 4_000, sessions: 2, types: [.deepWork: 3_000, .admin: 600]),
        row(9, 22, focused: 1_800, tracked: 2_000, sessions: 1, types: [.admin: 1_800]),
        row(9, 19, tracked: 600),
        row(9, 17, focused: 900, tracked: 900, sessions: 1, types: [.learning: 900])
    ]
    static let today = date(9, 29)

    static func names(_ rows: [HistoryRow]) -> [String] {
        rows.map { row in
            let f = DateFormatter()
            f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = calendar.locale
            f.dateFormat = "d/M"
            let end = calendar.date(byAdding: .day, value: -1, to: row.place.span.end)!
            return "\(row.place.level) \(f.string(from: row.place.start))–\(f.string(from: end))"
        }
    }

    // MARK: - Top

    private static func topRule() -> [String] {
        var failures: [String] = []
        // Three days, all this week (Mon 28 – Tue 29 with a day before).
        let threeDays = [row(9, 28, focused: 60, sessions: 1), row(9, 27, focused: 60, sessions: 1)]
        // 27 Sep is a Sunday: the record leaves this week, so the top is the month.
        let leaves = HistoryTreeBuilder.top(days: threeDays, today: today, calendar: calendar)
        if leaves.place?.level != .month { failures.append("a record from last Sunday opened on \(String(describing: leaves.place?.level)), not the month") }
        let thisWeek = HistoryTreeBuilder.top(days: [row(9, 28, focused: 60, sessions: 1)], today: today, calendar: calendar)
        if thisWeek.place?.level != .week || thisWeek.rootLevel != .day {
            failures.append("a record inside this week did not open on the week with day rows")
        }
        let month = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        if month.place?.level != .month || month.rootLevel != .week || month.firstDay != date(9, 17) {
            failures.append("a record from the 17th did not open on the month with week rows from the 17th")
        }
        let year = HistoryTreeBuilder.top(days: september + [row(6, 3, focused: 60, sessions: 1)], today: today, calendar: calendar)
        if year.place?.level != .year || year.rootLevel != .month { failures.append("a record from June did not open on the year") }
        let record = HistoryTreeBuilder.top(days: september + [row(7, 3, year: 2025, focused: 60, sessions: 1)], today: today, calendar: calendar)
        if record.place != nil || record.rootLevel != .year || record.firstDay != date(7, 3, year: 2025) {
            failures.append("a record from last year did not open on the record with year rows")
        }
        let empty = HistoryTreeBuilder.top(days: [], today: today, calendar: calendar)
        if empty.place?.level != .week || empty.firstDay != today { failures.append("an empty archive did not open on this week from today") }
        return failures
    }

    // MARK: - Clipping

    private static func clippedToRecord() -> [String] {
        let top = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        var failures: [String] = []
        let weeks = HistoryTreeBuilder.rows(under: nil, top: top, days: september, calendar: calendar)
        let expected = ["week 28/9–29/9", "week 21/9–27/9", "week 14/9–20/9"]
        if names(weeks) != expected { failures.append("September's weeks read \(names(weeks)), expected \(expected)") }
        guard weeks.count == 3 else { return failures }
        // The first week is Monday 14 – Sunday 20 on the calendar, but the
        // record began on Wednesday 17: the row spans 17 – 20 and has four bars.
        let first = weeks[2]
        if first.place.span.start != date(9, 17) || first.bars.count != 4 {
            failures.append("the first week began \(first.place.span.start) with \(first.bars.count) bars, not the 17th with four")
        }
        let firstDays = HistoryTreeBuilder.rows(under: first.place, top: top, days: september, calendar: calendar)
        if names(firstDays) != ["day 20/9–20/9", "day 19/9–19/9", "day 18/9–18/9", "day 17/9–17/9"] {
            failures.append("the first week opened to \(names(firstDays))")
        }
        // This week ends today, not Sunday.
        let thisWeek = weeks[0]
        if thisWeek.bars.count != 2 { failures.append("this week drew \(thisWeek.bars.count) bars, not two") }
        // A year top: September's row has fourteen bars, 17th to 30th... but
        // today is the 29th, so thirteen.
        let yearTop = HistoryTreeBuilder.top(days: september + [row(6, 3, focused: 60, sessions: 1)], today: today, calendar: calendar)
        let months = HistoryTreeBuilder.rows(under: nil, top: yearTop, days: september + [row(6, 3, focused: 60, sessions: 1)], calendar: calendar)
        if names(months) != ["month 1/9–29/9", "month 1/8–31/8", "month 1/7–31/7", "month 3/6–30/6"] {
            failures.append("the year's months read \(names(months))")
        }
        if let sep = months.first, sep.bars.count != 29 { failures.append("September's row has \(months.first!.bars.count) bars, not 29") }
        if months.contains(where: { $0.place.span.end > calendar.date(byAdding: .day, value: 1, to: today)! }) {
            failures.append("a month row reached past today")
        }
        return failures
    }

    private static func weekAcrossMonths() -> [String] {
        // Record from 1 September, today Tuesday 6 October. The week of
        // Mon 28 Sep – Sun 4 Oct straddles the boundary.
        let days = [row(10, 5, focused: 600, sessions: 1), row(10, 2, focused: 1_200, sessions: 1),
                    row(9, 29, focused: 1_800, sessions: 1), row(9, 1, focused: 300, sessions: 1)]
        let today = date(10, 6)
        let top = HistoryTreeBuilder.top(days: days, today: today, calendar: calendar)
        var failures: [String] = []
        guard top.place?.level == .year else { return ["two months did not open on the year"] }
        let months = HistoryTreeBuilder.rows(under: nil, top: top, days: days, calendar: calendar)
        guard months.count == 2 else { return ["expected October and September, got \(names(months))"] }
        let october = HistoryTreeBuilder.rows(under: months[0].place, top: top, days: days, calendar: calendar)
        let septemberWeeks = HistoryTreeBuilder.rows(under: months[1].place, top: top, days: days, calendar: calendar)
        if names(october) != ["week 5/10–6/10", "week 1/10–4/10"] { failures.append("October's weeks read \(names(october))") }
        if names(septemberWeeks).first != "week 28/9–30/9" { failures.append("September's newest week read \(names(septemberWeeks).first ?? "nothing")") }
        if october.map(\.focused).reduce(0, +) != months[0].focused { failures.append("October's weeks do not sum to October") }
        if septemberWeeks.map(\.focused).reduce(0, +) != months[1].focused { failures.append("September's weeks do not sum to September") }
        // The straddling week opened under October shows only October's days.
        let octoberPart = HistoryTreeBuilder.rows(under: october[1].place, top: top, days: days, calendar: calendar)
        if octoberPart.count != 4 || octoberPart.last?.place.start != date(10, 1) {
            failures.append("the straddling week under October opened to \(names(octoberPart))")
        }
        return failures
    }

    // MARK: - Dots

    private static func dots() -> [String] {
        let top = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let weeks = HistoryTreeBuilder.rows(under: nil, top: top, days: september, calendar: calendar)
        guard weeks.count == 3 else { return ["expected three weeks"] }
        var failures: [String] = []
        if weeks[0].mainWorkType != .deepWork { failures.append("this week's category was \(String(describing: weeks[0].mainWorkType)), not Deep work") }
        let days = HistoryTreeBuilder.rows(under: weeks[2].place, top: top, days: september, calendar: calendar)
        let byDay = Dictionary(uniqueKeysWithValues: days.map { ($0.place.start, $0) })
        if byDay[date(9, 19)]?.mainWorkType != nil || byDay[date(9, 19)]?.isEmpty != false || byDay[date(9, 19)]?.tracked != 600 {
            failures.append("19 Sep, at the Mac with no session, did not read as app use only")
        }
        if byDay[date(9, 18)]?.isEmpty != true { failures.append("18 Sep, with nothing, did not read as empty") }
        if byDay[date(9, 17)]?.mainWorkType != .learning { failures.append("17 Sep did not carry Learning") }
        let breakOnly = row(9, 25, types: [.breakTime: 0])
        let withBreak = HistoryTreeBuilder.rows(under: weeks[1].place, top: top, days: september + [breakOnly], calendar: calendar)
        if withBreak.first(where: { $0.place.start == date(9, 25) })?.isEmpty != false {
            failures.append("a day holding only a recorded break read as empty")
        }
        return failures
    }

    // MARK: - Time passing

    private static func dayRollover() -> [String] {
        var failures: [String] = []
        let before = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let thisWeek = HistoryTreeBuilder.rows(under: nil, top: before, days: september, calendar: calendar)[0]
        let daysBefore = HistoryTreeBuilder.rows(under: thisWeek.place, top: before, days: september, calendar: calendar)
        if daysBefore.first?.place.start != today { failures.append("today had no row before midnight") }
        // Wednesday 30 September: today's row appears, the 29th stays.
        let wednesday = date(9, 30)
        let after = HistoryTreeBuilder.top(days: september, today: wednesday, calendar: calendar)
        let week = HistoryTreeBuilder.rows(under: nil, top: after, days: september, calendar: calendar)[0]
        let daysAfter = HistoryTreeBuilder.rows(under: week.place, top: after, days: september, calendar: calendar)
        if daysAfter.map(\.place.start).prefix(2) != [wednesday, today] { failures.append("midnight did not add the 30th above the 29th") }
        // Monday 5 October: a new week and a new month appear; the top steps up to the year.
        let monday = date(10, 5)
        let mondayTop = HistoryTreeBuilder.top(days: september, today: monday, calendar: calendar)
        if mondayTop.place?.level != .year { failures.append("October did not step the top up to the year") }
        let months = HistoryTreeBuilder.rows(under: nil, top: mondayTop, days: september, calendar: calendar)
        let octoberWeeks = HistoryTreeBuilder.rows(under: months[0].place, top: mondayTop, days: september, calendar: calendar)
        if names(octoberWeeks) != ["week 5/10–5/10", "week 1/10–4/10"] { failures.append("Monday's October read \(names(octoberWeeks))") }
        return failures
    }

    private static func pathToToday() -> [String] {
        var failures: [String] = []
        let month = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let monthPath = HistoryTreeBuilder.pathToToday(top: month, calendar: calendar)
        if monthPath.map(\.level) != [.week] || monthPath.first?.span.start != date(9, 28) {
            failures.append("a month top opened to \(monthPath.map(\.level)), not this week")
        }
        let record = HistoryTreeBuilder.top(days: september + [row(7, 3, year: 2025, focused: 60, sessions: 1)], today: today, calendar: calendar)
        let recordPath = HistoryTreeBuilder.pathToToday(top: record, calendar: calendar)
        if recordPath.map(\.level) != [.year, .month, .week] { failures.append("the record opened to \(recordPath.map(\.level))") }
        if recordPath[0].span.start != date(1, 1) || recordPath[1].span.start != date(9, 1) || recordPath[2].span.start != date(9, 28) {
            failures.append("the record's path did not land on 2026 › September › this week")
        }
        let week = HistoryTreeBuilder.top(days: [row(9, 28, focused: 60, sessions: 1)], today: today, calendar: calendar)
        if !HistoryTreeBuilder.pathToToday(top: week, calendar: calendar).isEmpty { failures.append("a week top opened something") }
        return failures
    }

    private static func pathToDay() -> [String] {
        let record = HistoryTreeBuilder.top(days: september + [row(7, 3, year: 2025, focused: 60, sessions: 1)], today: today, calendar: calendar)
        let path = HistoryTreeBuilder.path(to: date(9, 17), top: record, calendar: calendar)
        var failures: [String] = []
        if path.map(\.level) != [.year, .month, .week, .day] { failures.append("the path to a day read \(path.map(\.level))") }
        // The week place is clipped to the record: it begins on the 17th.
        if path.count == 4, path[2].span.start != date(9, 17) || path[3].span.start != date(9, 17) {
            failures.append("the path's week or day was not clipped to the record")
        }
        // Each place is the row the tree would draw, so toggling by equality works.
        let months = HistoryTreeBuilder.rows(under: path[0], top: record, days: september, calendar: calendar)
        if !months.contains(where: { $0.place == path[1] }) { failures.append("the path's month is not a drawn row") }
        return failures
    }

    private static func daylightSaving() -> [String] {
        // Sydney moves its clocks forward at 2 am on Sunday 4 October 2026.
        let days = [row(10, 5, focused: 600, sessions: 1), row(10, 3, focused: 600, sessions: 1), row(9, 1, focused: 60, sessions: 1)]
        let today = date(10, 6)
        let top = HistoryTreeBuilder.top(days: days, today: today, calendar: calendar)
        let months = HistoryTreeBuilder.rows(under: nil, top: top, days: days, calendar: calendar)
        guard let october = months.first else { return ["no October"] }
        let weeks = HistoryTreeBuilder.rows(under: october.place, top: top, days: days, calendar: calendar)
        guard let straddle = weeks.last else { return ["no straddling week"] }
        let octoberDays = HistoryTreeBuilder.rows(under: straddle.place, top: top, days: days, calendar: calendar)
        var failures: [String] = []
        if octoberDays.count != 4 { failures.append("1 – 4 October drew \(octoberDays.count) days") }
        if Set(octoberDays.map(\.place.start)).count != 4 { failures.append("a daylight-saving day was doubled") }
        if octoberDays.first(where: { $0.place.start == date(10, 3) })?.focused != 600 { failures.append("3 October lost its focus across the clock change") }
        return failures
    }

    private static func summaryBest() -> [String] {
        var failures: [String] = []
        let days = september + [row(6, 3, focused: 7_200, sessions: 1, types: [.deepWork: 7_200])]
        let year = HistoryTreeBuilder.top(days: days, today: today, calendar: calendar)
        let yearSummary = HistoryTreeBuilder.summary(top: year, days: days, calendar: calendar)
        if yearSummary.focused != 13_500 || yearSummary.focusedDays != 4 || yearSummary.best?.place.level != .month
            || yearSummary.best?.place.start != date(6, 1) {
            failures.append("the year's summary read \(yearSummary.focused)s on \(yearSummary.focusedDays) days, best \(String(describing: yearSummary.best))")
        }
        let month = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let monthSummary = HistoryTreeBuilder.summary(top: month, days: september, calendar: calendar)
        if monthSummary.best?.place.level != .day || monthSummary.best?.place.start != date(9, 28) {
            failures.append("the month's best day was \(String(describing: monthSummary.best))")
        }
        return failures
    }
}
```

- [ ] **Step 3: Register and run to see them fail**

In `Sources/SelfTest.swift` line 470 change

```swift
            + RedundancyChecks.tests + HistoryJournalChecks.tests
```
to
```swift
            + RedundancyChecks.tests + HistoryJournalChecks.tests + HistoryTreeChecks.tests
```

Run the typecheck (sandboxed):

```bash
swiftc -typecheck -module-cache-path $TMPDIR/mc -swift-version 5 -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 $(find Sources -name '*.swift') 2>&1 | head -5
```

Expected: errors naming `HistoryTreeBuilder`, `HistoryRow` etc. as undefined.

- [ ] **Step 4: Write the builder**

Create `Sources/Core/HistoryTree.swift`:

```swift
import Foundation

/// The levels History unfolds through. Sessions sit under a day and come
/// from the day's projection, not from this index.
enum HistoryLevel: Int, Comparable, CaseIterable {
    case year = 0, month, week, day

    static func < (lhs: HistoryLevel, rhs: HistoryLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var child: HistoryLevel? { HistoryLevel(rawValue: rawValue + 1) }

    var component: Calendar.Component {
        switch self {
        case .year: return .year
        case .month: return .month
        case .week: return .weekOfYear
        case .day: return .day
        }
    }

    var spokenName: String {
        switch self {
        case .year: return "year"
        case .month: return "month"
        case .week: return "week"
        case .day: return "day"
        }
    }
}

/// One period on the spine: its level and the days it covers, already
/// clipped to its parent and to the record. A week that straddles a month
/// is two places, one under each month, so they never read as the same row.
struct HistoryPlace: Hashable {
    let level: HistoryLevel
    let span: DateInterval

    var start: Date { span.start }
    var id: String {
        "row-\(level.rawValue)-\(Int(span.start.timeIntervalSince1970))-\(Int(span.end.timeIntervalSince1970))"
    }
}

/// One thin bar inside a folded row: a month of a year, or a day of a month
/// or week.
struct HistoryBar: Equatable {
    let start: Date
    let focused: TimeInterval
}

/// A row as drawn. Figures cover the place's span and nothing outside it.
struct HistoryRow: Identifiable, Equatable {
    let place: HistoryPlace
    let focused: TimeInterval
    let tracked: TimeInterval
    let focusedDays: Int
    let sessions: Int
    /// The category most of the focus went to; nil without focus.
    let mainWorkType: WorkType?
    /// Anything at all: focus, app use, a session or a recorded break.
    let hasEvidence: Bool
    let bars: [HistoryBar]

    var isEmpty: Bool { !hasEvidence }
    var id: String { place.id }
    /// At the Mac, but no session.
    var isAppUseOnly: Bool { sessions == 0 && focused == 0 && tracked > 0 }
}

/// The top of the tree: the smallest period holding the whole record, or
/// nil for the record itself, whose rows are years.
struct HistoryTop: Equatable {
    let place: HistoryPlace?
    let firstDay: Date
    let today: Date

    /// The days the root rows divide between them.
    var span: DateInterval { place?.span ?? DateInterval(start: firstDay, end: HistoryTreeBuilder.dayAfter(today)) }
    var rootLevel: HistoryLevel { place?.level.child ?? .year }
}

/// The headline's figures for the top period.
struct HistorySummary: Equatable {
    let focused: TimeInterval
    let tracked: TimeInterval
    let focusedDays: Int
    let sessions: Int
    /// The best month of a year or the record; the best day of a month or week.
    let best: (place: HistoryPlace, focused: TimeInterval)?

    static func == (lhs: HistorySummary, rhs: HistorySummary) -> Bool {
        lhs.focused == rhs.focused && lhs.tracked == rhs.tracked && lhs.focusedDays == rhs.focusedDays
            && lhs.sessions == rhs.sessions && lhs.best?.place == rhs.best?.place && lhs.best?.focused == rhs.best?.focused
    }
}

/// Builds History's rows from the day index. Pure: no store, no clock, so
/// the checks hand it any archive and any today.
enum HistoryTreeBuilder {
    /// Weeks run Monday to Sunday whatever the locale says.
    static func calendar(_ base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = 2
        return calendar
    }

    static func dayAfter(_ day: Date, calendar: Calendar = calendar()) -> Date {
        calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
    }

    /// The calendar period of `level` holding `date`.
    static func period(_ level: HistoryLevel, containing date: Date, calendar: Calendar = calendar()) -> DateInterval {
        calendar.dateInterval(of: level.component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), end: dayAfter(date, calendar: calendar))
    }

    /// The smallest period holding every recorded day and today.
    static func top(days: [HistoryDay], today: Date, calendar: Calendar = calendar()) -> HistoryTop {
        let today = calendar.startOfDay(for: today)
        let firstDay = min(days.map { calendar.startOfDay(for: $0.date) }.min() ?? today, today)
        let record = DateInterval(start: firstDay, end: dayAfter(today, calendar: calendar))
        for level in [HistoryLevel.week, .month, .year] {
            let candidate = period(level, containing: today, calendar: calendar)
            if candidate.start <= firstDay {
                return HistoryTop(place: HistoryPlace(level: level, span: candidate.intersection(with: record) ?? record),
                                  firstDay: firstDay, today: today)
            }
        }
        return HistoryTop(place: nil, firstDay: firstDay, today: today)
    }

    /// The rows under `parent`, newest first; nil gives the root rows. Each
    /// child period is clipped to the parent's span, which is itself clipped
    /// to the record, so nothing reaches before the first day or past today.
    static func rows(under parent: HistoryPlace?, top: HistoryTop, days: [HistoryDay],
                     calendar: Calendar = calendar()) -> [HistoryRow] {
        rows(under: parent, top: top, byDate: index(days, calendar: calendar), calendar: calendar)
    }

    static func rows(under parent: HistoryPlace?, top: HistoryTop, byDate: [Date: HistoryDay],
                     calendar: Calendar) -> [HistoryRow] {
        guard let level = parent?.level.child ?? Optional(top.rootLevel) else { return [] }
        let bounds = parent?.span ?? top.span
        var result: [HistoryRow] = []
        var cursor = period(level, containing: bounds.start, calendar: calendar).start
        while cursor < bounds.end {
            let whole = period(level, containing: cursor, calendar: calendar)
            if let span = whole.intersection(with: bounds), span.duration > 0 {
                result.append(row(HistoryPlace(level: level, span: span), byDate: byDate, calendar: calendar))
            }
            cursor = whole.end
        }
        return result.reversed()
    }

    /// One row's figures from the days in its span.
    static func row(_ place: HistoryPlace, byDate: [Date: HistoryDay], calendar: Calendar) -> HistoryRow {
        var focused: TimeInterval = 0, tracked: TimeInterval = 0
        var focusedDays = 0, sessions = 0
        var byType: [WorkType: TimeInterval] = [:]
        var evidence = false
        forEachDay(in: place.span, calendar: calendar) { day in
            guard let row = byDate[day] else { return }
            focused += row.focused
            tracked += row.tracked
            sessions += row.sessions
            if row.focused > 0 { focusedDays += 1 }
            for (type, seconds) in row.focusByWorkType where type.countsAsFocus { byType[type, default: 0] += seconds }
            if row.focused > 0 || row.tracked > 0 || row.sessions > 0 || !row.workTypes.isEmpty { evidence = true }
        }
        return HistoryRow(place: place, focused: focused, tracked: tracked, focusedDays: focusedDays,
                          sessions: sessions, mainWorkType: WorkTypeShare.shares(from: byType).first?.workType,
                          hasEvidence: evidence, bars: bars(for: place, byDate: byDate, calendar: calendar))
    }

    /// A year's bars are its months; a month's or week's are its days; a
    /// day has none (its strip is drawn from the day's sessions).
    private static func bars(for place: HistoryPlace, byDate: [Date: HistoryDay], calendar: Calendar) -> [HistoryBar] {
        switch place.level {
        case .day: return []
        case .year:
            var result: [HistoryBar] = []
            var cursor = place.span.start
            while cursor < place.span.end {
                let month = period(.month, containing: cursor, calendar: calendar)
                let span = month.intersection(with: place.span) ?? month
                var total: TimeInterval = 0
                forEachDay(in: span, calendar: calendar) { total += byDate[$0]?.focused ?? 0 }
                result.append(HistoryBar(start: span.start, focused: total))
                cursor = month.end
            }
            return result
        case .month, .week:
            var result: [HistoryBar] = []
            forEachDay(in: place.span, calendar: calendar) { result.append(HistoryBar(start: $0, focused: byDate[$0]?.focused ?? 0)) }
            return result
        }
    }

    /// The headline's figures and its best child.
    static func summary(top: HistoryTop, days: [HistoryDay], calendar: Calendar = calendar()) -> HistorySummary {
        let byDate = index(days, calendar: calendar)
        let whole = row(HistoryPlace(level: top.place?.level ?? .year, span: top.span), byDate: byDate, calendar: calendar)
        let bestLevel: HistoryLevel = (top.place?.level ?? .year) <= .year ? .month : .day
        var best: (place: HistoryPlace, focused: TimeInterval)?
        var cursor = period(bestLevel, containing: top.span.start, calendar: calendar).start
        while cursor < top.span.end {
            let whole = period(bestLevel, containing: cursor, calendar: calendar)
            if let span = whole.intersection(with: top.span), span.duration > 0 {
                let candidate = row(HistoryPlace(level: bestLevel, span: span), byDate: byDate, calendar: calendar)
                if candidate.focused > (best?.focused ?? 0) { best = (candidate.place, candidate.focused) }
            }
            cursor = whole.end
        }
        return HistorySummary(focused: whole.focused, tracked: whole.tracked, focusedDays: whole.focusedDays,
                              sessions: whole.sessions, best: best)
    }

    /// What History opens with: the path from the root down to this week,
    /// each place clipped exactly as its row is drawn. Nothing when the top
    /// is the week itself.
    static func pathToToday(top: HistoryTop, calendar: Calendar = calendar()) -> [HistoryPlace] {
        var result: [HistoryPlace] = []
        var bounds = top.span
        var level: HistoryLevel? = top.rootLevel
        while let current = level, current <= .week {
            let whole = period(current, containing: top.today, calendar: calendar)
            guard let span = whole.intersection(with: bounds) else { break }
            result.append(HistoryPlace(level: current, span: span))
            bounds = span
            level = current.child
        }
        return result
    }

    /// The path from the root down to `day`, for Jump to date and search.
    static func path(to day: Date, top: HistoryTop, calendar: Calendar = calendar()) -> [HistoryPlace] {
        let day = calendar.startOfDay(for: day)
        var result: [HistoryPlace] = []
        var bounds = top.span
        var level: HistoryLevel? = top.rootLevel
        while let current = level {
            let whole = period(current, containing: day, calendar: calendar)
            guard let span = whole.intersection(with: bounds) else { break }
            result.append(HistoryPlace(level: current, span: span))
            bounds = span
            level = current.child
        }
        return result
    }

    /// Rows holding today, rebuilt from the live day; the rest untouched.
    static func patching(_ rows: [HistoryRow], top: HistoryTop, live: HistoryDay?, days: [HistoryDay],
                         calendar: Calendar = calendar()) -> [HistoryRow] {
        guard let live else { return rows }
        let today = calendar.startOfDay(for: live.date)
        guard rows.contains(where: { $0.place.span.contains(today) }) else { return rows }
        var byDate = index(days, calendar: calendar)
        byDate[today] = live
        return rows.map { $0.place.span.contains(today) ? row($0.place, byDate: byDate, calendar: calendar) : $0 }
    }

    static func index(_ days: [HistoryDay], calendar: Calendar) -> [Date: HistoryDay] {
        var byDate: [Date: HistoryDay] = [:]
        for day in days { byDate[calendar.startOfDay(for: day.date)] = day }
        return byDate
    }

    private static func forEachDay(in span: DateInterval, calendar: Calendar, _ body: (Date) -> Void) {
        var cursor = calendar.startOfDay(for: span.start)
        while cursor < span.end {
            body(cursor)
            cursor = dayAfter(cursor, calendar: calendar)
        }
    }
}
```

Note `HistoryLevel` is `Comparable` with `<` defined on `rawValue`; `Optional(top.rootLevel)` in `rows(under:)` keeps the `guard let` shape for the `nil` parent.

- [ ] **Step 5: Run the checks**

```bash
./build.sh --test 2>&1 | grep -E "History opens on|Nothing is drawn before|across a month boundary|Rows carry their category|Midnight adds|opening path unfolds|Jump to date builds|daylight-saving week|tree's summary|passed"
```

Expected: nine `[PASS]` lines and the total up by nine.

If `weekAcrossMonths` reports October's weeks as `["week 5/10–6/10", "week 28/9–4/10"]`, the intersection is not being applied: `whole.intersection(with: bounds)` must clip the straddling week to `1/10–4/10`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/HistoryStats.swift Sources/App/SessionStore+Story.swift Sources/Core/HistoryTree.swift Sources/Verification/HistoryTreeChecks.swift Sources/SelfTest.swift
git commit -m "History's tree is built from the day index, clipped to the record

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: The store caches the tree

**Files:**
- Create: `Sources/App/SessionStore+HistoryTree.swift`
- Modify: `Sources/App/SessionStore.swift:472-478` (cache storage beside `journalCache`)
- Modify: `Sources/Verification/HistoryTreeChecks.swift` (two checks)

**Interfaces:**
- Consumes: `HistoryTreeBuilder`, `JournalKey` (`Sources/App/SessionStore+Journal.swift`), `historyDays`, `evidenceRevision`, `historyIndexGeneration`, `now()`.
- Produces on `SessionStore`:
  - `func historyTop() -> HistoryTop`
  - `func historyRows(under parent: HistoryPlace?) -> [HistoryRow]`
  - `func historySummary() -> HistorySummary`
  - `var historyTreeComputeCount: Int` (for the caching check)
  - `static let historyCalendar: Calendar` (the Monday calendar every History view uses)

- [ ] **Step 1: Write the failing checks**

Append to `HistoryTreeChecks.tests`:

```swift
        ("A ticking clock does not rebuild the tree, and today's live figures reach its rows", treeIsCached)
```

and the check:

```swift
    private static func treeIsCached() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .running, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            store.refreshReview()
            var failures: [String] = []
            let top = store.historyTop()
            _ = store.historyRows(under: nil)
            let path = HistoryTreeBuilder.pathToToday(top: top, calendar: SessionStore.historyCalendar)
            for place in path { _ = store.historyRows(under: place) }
            let built = store.historyTreeComputeCount
            for _ in 0..<5 {
                _ = store.historyRows(under: nil)
                for place in path { _ = store.historyRows(under: place) }
            }
            if store.historyTreeComputeCount != built {
                failures.append("re-reading the tree rebuilt it \(store.historyTreeComputeCount - built) times")
            }
            // The running session's live focus reaches today's row and every
            // row above it, without a rebuild.
            let today = SessionStore.historyCalendar.startOfDay(for: store.now())
            let live = store.historyDays.first { SessionStore.historyCalendar.isDate($0.date, inSameDayAs: today) }
            guard let liveFocus = live?.focused, liveFocus > 0 else { return ["the running fixture has no live focus today"] }
            var parent: HistoryPlace? = nil
            var chain: [HistoryPlace] = path
            if let week = path.last { chain = path } else { chain = [] }
            for place in chain {
                let rows = store.historyRows(under: parent)
                guard let row = rows.first(where: { $0.place == place }) else { failures.append("\(place.level) row missing"); break }
                if row.focused < liveFocus { failures.append("the \(place.level) row shows \(row.focused)s, less than today's \(liveFocus)s") }
                parent = place
            }
            if let week = chain.last {
                let days = store.historyRows(under: week)
                if days.first(where: { $0.place.span.contains(today) })?.focused != liveFocus {
                    failures.append("today's row does not carry the live figure")
                }
            }
            if store.historyTreeComputeCount != built { failures.append("reading live rows rebuilt the tree") }
            return failures
        }
    }
```

(`chain` is `path` when the top is above the week, otherwise empty; the `if let week` line only makes that explicit.)

- [ ] **Step 2: Add the cache and the store methods**

In `Sources/App/SessionStore.swift`, after line 478 (`searchJournalCache`), add:

```swift
    /// History's tree, per parent place, held until the archive changes.
    var historyTreeCache: (key: JournalKey, top: HistoryTop, rows: [String: [HistoryRow]])?
    var historyTreeComputeCount = 0
```

Create `Sources/App/SessionStore+HistoryTree.swift`:

```swift
import Foundation

extension SessionStore {
    /// Monday-first, so weeks in History are Monday to Sunday.
    static let historyCalendar = HistoryTreeBuilder.calendar(.current)

    /// The top of History's tree for the current record and today.
    func historyTop() -> HistoryTop {
        tree().top
    }

    /// The rows under a place, or the root rows for nil. Cached until the
    /// archive changes; rows holding today are brought up to the live
    /// figures on every read, the rest are returned as cached.
    func historyRows(under parent: HistoryPlace?) -> [HistoryRow] {
        let calendar = Self.historyCalendar
        var state = tree()
        let key = parent?.id ?? "root"
        let rows: [HistoryRow]
        if let cached = state.rows[key] {
            rows = cached
        } else {
            historyTreeComputeCount &+= 1
            rows = HistoryTreeBuilder.rows(under: parent, top: state.top, days: historyDays, calendar: calendar)
            state.rows[key] = rows
            historyTreeCache = state
        }
        return HistoryTreeBuilder.patching(rows, top: state.top, live: liveToday(calendar), days: historyDays,
                                           calendar: calendar)
    }

    /// The headline's figures for the top period, live for today.
    func historySummary() -> HistorySummary {
        HistoryTreeBuilder.summary(top: historyTop(), days: historyDays, calendar: Self.historyCalendar)
    }

    private func liveToday(_ calendar: Calendar) -> HistoryDay? {
        let today = calendar.startOfDay(for: now())
        return historyDays.first { calendar.isDate($0.date, inSameDayAs: today) }
    }

    private func tree() -> (key: JournalKey, top: HistoryTop, rows: [String: [HistoryRow]]) {
        let key = JournalKey(evidence: evidenceRevision, indexGeneration: historyIndexGeneration,
                             dayCount: historyDays.count, oldest: historyDays.last?.date)
        let today = Self.historyCalendar.startOfDay(for: now())
        if let cached = historyTreeCache, cached.key == key, cached.top.today == today { return cached }
        historyTreeComputeCount &+= 1
        let top = HistoryTreeBuilder.top(days: historyDays, today: now(), calendar: Self.historyCalendar)
        let fresh = (key, top, [String: [HistoryRow]]())
        historyTreeCache = fresh
        return fresh
    }
}
```

`historySummary()` walks the whole record's days once per read; the headline reads it from `body`. If Task 4's render check shows it costly, cache it beside the rows keyed the same way — but measure first.

- [ ] **Step 3: Run the checks**

```bash
./build.sh --test 2>&1 | grep -E "ticking clock does not rebuild the tree|passed"
```

Expected: `[PASS]` and the total up by one.

- [ ] **Step 4: Commit**

```bash
git add Sources/App/SessionStore.swift Sources/App/SessionStore+HistoryTree.swift Sources/Verification/HistoryTreeChecks.swift
git commit -m "The store keeps History's tree until the archive changes

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: The model holds the open path

**Files:**
- Modify: `Sources/App/MainWindowModel.swift:150-170` (state), `:251-290` (selection API), `:200-225` (`open(tab:)`)
- Modify: `Sources/Core/HistoryTree.swift` (append `HistoryFocus` and `visible(...)`)
- Modify: `Sources/Verification/HistoryTreeChecks.swift` (two checks)

The old `HistorySelection` API stays for now so the journal views keep compiling; Task 6 removes it.

**Interfaces:**
- Produces on `MainWindowModel`:
  - `@Published private(set) var historyOpen: [HistoryPlace]`
  - `@Published private(set) var historySession: HistorySessionPick?` where `struct HistorySessionPick: Hashable { let thread: UUID; let day: Date }`
  - `@Published private(set) var historyFocus: HistoryFocus?`
  - `@Published private(set) var historyScrollTarget: String?` (a row id; bumps `historyScrollRequest`)
  - `var historyDeepestOpen: HistoryPlace? { historyOpen.last }`
  - `func prepareHistory()` — first opening: `pathToToday`
  - `func toggleHistory(_ place: HistoryPlace)`
  - `@discardableResult func foldDeepestHistory() -> Bool`
  - `func openHistory(day: Date)`
  - `func selectHistory(session thread: UUID, on day: Date)`
  - `func stepHistoryFocus(by delta: Int)`, `func activateHistoryFocus()`, `func moveHistoryFocus(open: Bool)`
- Produces in `HistoryTree.swift`:
  - `enum HistoryFocus: Hashable { case row(HistoryPlace), session(thread: UUID, day: Date) }`
  - `HistoryTreeBuilder.visible(open:rows:threads:) -> [HistoryFocus]`

- [ ] **Step 1: Write the failing checks**

Append to `HistoryTreeChecks.tests`:

```swift
        ("Opening a row folds its sibling; folding a row folds everything under it; an empty row cannot open", openAndFold),
        ("Arrow keys walk the visible rows in reading order, Return toggles, left and right fold and open", keyboardWalk)
```

and the checks:

```swift
    private static func openAndFold() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            store.refreshReview()
            let navigation = MainWindowModel(store: store)
            navigation.open(tab: .review)
            var failures: [String] = []
            let top = store.historyTop()
            let expected = HistoryTreeBuilder.pathToToday(top: top, calendar: SessionStore.historyCalendar)
            if navigation.historyOpen != expected { failures.append("History did not open to this week: \(navigation.historyOpen.map(\.place.level))") }
            let roots = store.historyRows(under: nil)
            guard roots.count >= 2 else { return ["the dense fixture has fewer than two root rows"] }
            let newest = roots[0], older = roots[1]
            navigation.toggleHistory(older.place)
            if navigation.historyOpen != [older.place] { failures.append("opening a sibling did not fold the open root: \(navigation.historyOpen.map(\.place.level))") }
            navigation.toggleHistory(newest.place)
            let children = store.historyRows(under: newest.place)
            if let child = children.first(where: { !$0.isEmpty }) {
                navigation.toggleHistory(child.place)
                if navigation.historyOpen != [newest.place, child.place] { failures.append("a child did not open under its parent") }
                navigation.toggleHistory(newest.place)
                if !navigation.historyOpen.isEmpty { failures.append("folding the root left \(navigation.historyOpen.count) open") }
            }
            navigation.toggleHistory(newest.place)
            if let empty = children.first(where: \.isEmpty) {
                navigation.toggleHistory(empty.place)
                if navigation.historyOpen.contains(empty.place) { failures.append("an empty row opened") }
            }
            // A child of a folded parent cannot be opened out of order.
            navigation.foldDeepestHistory()
            if let child = children.first {
                navigation.toggleHistory(child.place)
                if navigation.historyOpen.contains(child.place) { failures.append("a child opened under a folded parent") }
            }
            // Escape folds one level at a time.
            navigation.toggleHistory(newest.place)
            if let child = children.first(where: { !$0.isEmpty }) { navigation.toggleHistory(child.place) }
            let depth = navigation.historyOpen.count
            navigation.foldDeepestHistory()
            if navigation.historyOpen.count != depth - 1 { failures.append("Escape folded \(depth - navigation.historyOpen.count) levels") }
            return failures
        }
    }

    private static func keyboardWalk() -> [String] {
        let top = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let weeks = HistoryTreeBuilder.rows(under: nil, top: top, days: september, calendar: calendar)
        let thisWeek = weeks[0]
        let days = HistoryTreeBuilder.rows(under: thisWeek.place, top: top, days: september, calendar: calendar)
        let a = UUID(), b = UUID()
        let rows: (HistoryPlace?) -> [HistoryRow] = { parent in
            HistoryTreeBuilder.rows(under: parent, top: top, days: september, calendar: calendar)
        }
        let threads: (Date) -> [UUID] = { $0 == date(9, 28) ? [a, b] : [] }
        // This week open, and Monday 28 open: its two sessions are stops.
        let open = [thisWeek.place, days[1].place]
        let visible = HistoryTreeBuilder.visible(open: open, rows: rows, threads: threads)
        let expected: [HistoryFocus] = [
            .row(thisWeek.place), .row(days[0].place), .row(days[1].place),
            .session(thread: a, day: date(9, 28)), .session(thread: b, day: date(9, 28)),
            .row(weeks[1].place), .row(weeks[2].place)
        ]
        return visible == expected ? [] : ["visible rows read \(visible), expected \(expected)"]
    }
```

- [ ] **Step 2: Add `HistoryFocus` and `visible` to the builder**

Append to `Sources/Core/HistoryTree.swift`:

```swift
/// What the keyboard stands on in History: a row, or a session under an
/// open day.
enum HistoryFocus: Hashable {
    case row(HistoryPlace)
    case session(thread: UUID, day: Date)
}

extension HistoryTreeBuilder {
    /// Every stop ↑ and ↓ can land on, in reading order: each root row,
    /// then, under the one that is open, its rows, and so on down; under an
    /// open day, its sessions. Breaks are not stops.
    static func visible(open: [HistoryPlace], rows: (HistoryPlace?) -> [HistoryRow],
                        threads: (Date) -> [UUID]) -> [HistoryFocus] {
        var result: [HistoryFocus] = []
        func walk(_ parent: HistoryPlace?, depth: Int) {
            for row in rows(parent) {
                result.append(.row(row.place))
                guard open.indices.contains(depth), open[depth] == row.place else { continue }
                if row.place.level == .day {
                    for thread in threads(row.place.start) { result.append(.session(thread: thread, day: row.place.start)) }
                } else {
                    walk(row.place, depth: depth + 1)
                }
            }
        }
        walk(nil, depth: 0)
        return result
    }
}
```

- [ ] **Step 3: Add the state and API to `MainWindowModel`**

After line 157 (`historyScrollRequest`) add:

```swift
    /// The rows open in History, root first. One row per level; opening a
    /// sibling folds the row that was open there.
    @Published private(set) var historyOpen: [HistoryPlace] = []
    /// The session the rail describes, under an open day.
    @Published private(set) var historySession: HistorySessionPick?
    /// The row the keyboard stands on.
    @Published private(set) var historyFocus: HistoryFocus?
    /// The row to bring into view when `historyScrollRequest` bumps.
    @Published private(set) var historyScrollTarget: String?
    private var historyPrepared = false

    var historyDeepestOpen: HistoryPlace? { historyOpen.last }
```

Add the struct above the class (after `StorySheetKind`):

```swift
/// A session picked in History: its thread on that day.
struct HistorySessionPick: Hashable {
    let thread: UUID
    let day: Date
}
```

Change `reviewSelectedDate` (line 160) to read the new state alongside the old:

```swift
    var reviewSelectedDate: Date? {
        historySession?.day ?? historyOpen.last(where: { $0.level == .day })?.start ?? historySelection?.day
    }
```

In `open(tab:)`, the `.review` and `.insights` cases both gain `prepareHistory()` after `sheet = nil`.

Add the API after `stepHistorySelection`:

```swift
    // MARK: - History's tree

    /// The first time History shows: unfold to this week. Later openings
    /// keep whatever the reader left open.
    func prepareHistory() {
        guard !historyPrepared, let store else { return }
        historyPrepared = true
        historyOpen = HistoryTreeBuilder.pathToToday(top: store.historyTop(), calendar: SessionStore.historyCalendar)
    }

    private func historyDepth(of place: HistoryPlace) -> Int? {
        guard let store else { return nil }
        let depth = place.level.rawValue - store.historyTop().rootLevel.rawValue
        // A row is only on screen when every level above it is open.
        return depth >= 0 && depth <= historyOpen.count ? depth : nil
    }

    /// Click or Return on a row: open it, folding the sibling that was open
    /// at its level; or fold it and everything under it.
    func toggleHistory(_ place: HistoryPlace) {
        guard let store, let depth = historyDepth(of: place) else { return }
        let parent = depth == 0 ? nil : historyOpen[depth - 1]
        guard let row = store.historyRows(under: parent).first(where: { $0.place == place }), !row.isEmpty else { return }
        animated(Tokens.Motion.reveal) {
            historySession = nil
            if historyOpen.indices.contains(depth), historyOpen[depth] == place {
                historyOpen = Array(historyOpen.prefix(depth))
            } else {
                historyOpen = Array(historyOpen.prefix(depth)) + [place]
                historyScrollTarget = place.id
                historyScrollRequest &+= 1
            }
            historyFocus = .row(place)
        }
    }

    /// Escape: fold the deepest open row. False when nothing was open.
    @discardableResult
    func foldDeepestHistory() -> Bool {
        guard let last = historyOpen.last else { return false }
        animated(Tokens.Motion.dismiss) {
            historySession = nil
            historyOpen.removeLast()
            historyFocus = .row(last)
        }
        return true
    }

    /// Jump to date and search: unfold down to the day and open it.
    func openHistory(day: Date) {
        guard let store else { return }
        let path = HistoryTreeBuilder.path(to: day, top: store.historyTop(), calendar: SessionStore.historyCalendar)
        animated(Tokens.Motion.reveal) {
            historySession = nil
            historyOpen = path
            if let last = path.last {
                historyFocus = .row(last)
                historyScrollTarget = last.id
                historyScrollRequest &+= 1
            }
        }
    }

    /// A session row clicked: the rail describes it. Its day is opened if
    /// it was not, so the row is on screen.
    func selectHistory(session thread: UUID, on day: Date) {
        let day = SessionStore.historyCalendar.startOfDay(for: day)
        if historyOpen.last?.level != .day || historyOpen.last?.start != day { openHistory(day: day) }
        animated(Tokens.Motion.selection) {
            historySession = HistorySessionPick(thread: thread, day: day)
            historyFocus = .session(thread: thread, day: day)
        }
    }

    private func historyVisible() -> [HistoryFocus] {
        guard let store else { return [] }
        return HistoryTreeBuilder.visible(open: historyOpen, rows: { store.historyRows(under: $0) },
                                          threads: { store.journalThreads(on: $0, only: nil) })
    }

    /// ↑ and ↓: one visible row at a time. With no focus, ↓ lands on the
    /// first row and ↑ on the last.
    func stepHistoryFocus(by delta: Int) {
        let stops = historyVisible()
        guard !stops.isEmpty else { return }
        let next: HistoryFocus
        if let current = historyFocus, let index = stops.firstIndex(of: current) {
            next = stops[max(0, min(stops.count - 1, index + delta))]
        } else {
            next = delta > 0 ? stops[0] : stops[stops.count - 1]
        }
        animated(Tokens.Motion.selection) {
            historyFocus = next
            if case .session(let thread, let day) = next { historySession = HistorySessionPick(thread: thread, day: day) }
            switch next {
            case .row(let place): historyScrollTarget = place.id
            case .session(let thread, _): historyScrollTarget = "session-\(thread.uuidString)"
            }
            historyScrollRequest &+= 1
        }
    }

    /// Return: open or fold the focused row; select the focused session.
    func activateHistoryFocus() {
        switch historyFocus {
        case .row(let place): toggleHistory(place)
        case .session(let thread, let day): selectHistory(session: thread, on: day)
        case nil: stepHistoryFocus(by: 1)
        }
    }

    /// → opens a folded row; ← folds an open one, or moves to its parent.
    func moveHistoryFocus(open: Bool) {
        guard case .row(let place) = historyFocus, let depth = historyDepth(of: place) else {
            if !open, case .session(_, let day) = historyFocus,
               let dayPlace = historyOpen.last, dayPlace.level == .day, dayPlace.start == day {
                animated(Tokens.Motion.selection) { historyFocus = .row(dayPlace) }
            }
            return
        }
        let isOpen = historyOpen.indices.contains(depth) && historyOpen[depth] == place
        if open, !isOpen { toggleHistory(place) }
        if !open {
            if isOpen { toggleHistory(place) } else if depth > 0 {
                animated(Tokens.Motion.selection) { historyFocus = .row(historyOpen[depth - 1]) }
            }
        }
    }
```

- [ ] **Step 4: Run the checks**

```bash
./build.sh --test 2>&1 | grep -E "Opening a row folds|Arrow keys walk the visible|passed"
```

Expected: two `[PASS]` lines.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/MainWindowModel.swift Sources/Core/HistoryTree.swift Sources/Verification/HistoryTreeChecks.swift
git commit -m "History remembers which year, month, week and day are open

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: The column draws the tree

**Files:**
- Create: `Sources/Surfaces/History/HistoryTree.swift`
- Create: `Sources/Surfaces/History/HistoryTreeRow.swift`
- Modify: `Sources/Surfaces/History/HistoryJournal.swift` (`HistoryWorkspace` uses `HistoryTree`; `HistorySessionRow` and `HistoryDayHeader` lose `onOpen`; `HistoryMonthBars` takes bars)
- Modify: `Sources/Surfaces/Story/StoryColumns.swift:3-6` (`historyTree` evidence)
- Modify: `Sources/Verification/HistoryTreeChecks.swift` (wording + render checks)

**Interfaces:**
- Consumes: Task 2's store methods, Task 3's model API, `HistoryFindBar`, `HistoryDayStrip`, `HistorySessionRow`, `HistoryBreakRow`, `HistoryDayHeader.showsTotal`, `StoryHeadline`, `HistoryJournalBuilder.rows(_:only:)`, `HistoryJournalBuilder.entries(matching:)`.
- Produces:
  - `struct HistoryTree: View` (the column), `static let keyboardHint`.
  - `struct HistoryTreeRow: View`.
  - `enum HistoryRowText` with `title(_:today:calendar:)`, `facts(_:today:)`, `spoken(_:today:isOpen:depth:calendar:)`, `headline(top:summary:calendar:) -> (eyebrow: String, sentence: String, facts: [String])`.
  - `StoryRenderEvidence.historyTree`.

- [ ] **Step 1: Write the failing wording checks**

Append to `HistoryTreeChecks.tests`:

```swift
        ("Rows say their period, figures and state once, in words for VoiceOver", rowWording),
        ("The headline names the top period and its totals", headlineWording)
```

and:

```swift
    private static func rowWording() -> [String] {
        let top = HistoryTreeBuilder.top(days: september + [row(7, 3, year: 2025, focused: 60, sessions: 1)], today: today, calendar: calendar)
        let years = HistoryTreeBuilder.rows(under: nil, top: top, days: september, calendar: calendar)
        var failures: [String] = []
        guard let year = years.first else { return ["no year row"] }
        if HistoryRowText.title(year.place, today: today, calendar: calendar) != "2026" { failures.append("the year row was titled \(HistoryRowText.title(year.place, today: today, calendar: calendar))") }
        let months = HistoryTreeBuilder.rows(under: year.place, top: top, days: september, calendar: calendar)
        guard let sep = months.first else { return ["no September"] }
        if HistoryRowText.title(sep.place, today: today, calendar: calendar) != "September" { failures.append("September was titled \(HistoryRowText.title(sep.place, today: today, calendar: calendar))") }
        if HistoryRowText.facts(sep, today: today) != "\(Tokens.duration(6_300)) · 3 days" { failures.append("September's facts read \(HistoryRowText.facts(sep, today: today))") }
        let weeks = HistoryTreeBuilder.rows(under: sep.place, top: top, days: september, calendar: calendar)
        if HistoryRowText.title(weeks[2].place, today: today, calendar: calendar) != "17 – 20 Sep" { failures.append("the first week was titled \(HistoryRowText.title(weeks[2].place, today: today, calendar: calendar))") }
        if HistoryRowText.title(weeks[0].place, today: today, calendar: calendar) != "28 – 29 Sep" { failures.append("this week was titled \(HistoryRowText.title(weeks[0].place, today: today, calendar: calendar))") }
        let days = HistoryTreeBuilder.rows(under: weeks[0].place, top: top, days: september, calendar: calendar)
        if HistoryRowText.title(days[0].place, today: today, calendar: calendar) != "Today" { failures.append("today was titled \(HistoryRowText.title(days[0].place, today: today, calendar: calendar))") }
        if HistoryRowText.title(days[1].place, today: today, calendar: calendar) != "Mon 28 Sep" { failures.append("Monday was titled \(HistoryRowText.title(days[1].place, today: today, calendar: calendar))") }
        if HistoryRowText.facts(days[1], today: today) != "\(Tokens.duration(3_600)) · 2 sessions" { failures.append("Monday's facts read \(HistoryRowText.facts(days[1], today: today))") }
        if HistoryRowText.facts(days[0], today: today) != "nothing recorded yet today" { failures.append("an empty today read \(HistoryRowText.facts(days[0], today: today))") }
        let older = HistoryTreeBuilder.rows(under: weeks[2].place, top: top, days: september, calendar: calendar)
        let empty = older.first { $0.place.start == date(9, 18) }!
        let appOnly = older.first { $0.place.start == date(9, 19) }!
        if HistoryRowText.facts(empty, today: today) != "nothing recorded" { failures.append("an empty day read \(HistoryRowText.facts(empty, today: today))") }
        if HistoryRowText.facts(appOnly, today: today) != "Recorded app use only · \(Tokens.duration(600))" { failures.append("an app-use day read \(HistoryRowText.facts(appOnly, today: today))") }
        let spoken = HistoryRowText.spoken(sep, today: today, isOpen: false, depth: 1, calendar: calendar)
        let wanted = "September 2026, \(Tokens.spent(6_300)) across 3 days, month, level 2, collapsed"
        if spoken != wanted { failures.append("September was spoken as \"\(spoken)\", wanted \"\(wanted)\"") }
        if spoken.contains("h ") { failures.append("a compact duration reached VoiceOver") }
        return failures
    }

    private static func headlineWording() -> [String] {
        var failures: [String] = []
        let month = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let monthLine = HistoryRowText.headline(top: month, summary: HistoryTreeBuilder.summary(top: month, days: september, calendar: calendar), calendar: calendar)
        if monthLine.eyebrow != "September 2026" || monthLine.sentence != "You focused \(Tokens.duration(6_300)) across 3 days." {
            failures.append("the month headline read \(monthLine.eyebrow) / \(monthLine.sentence)")
        }
        if !monthLine.facts.contains("best day Mon 28 Sep · \(Tokens.duration(3_600))") { failures.append("the month's facts were \(monthLine.facts)") }
        let recordDays = september + [row(7, 3, year: 2025, focused: 60, sessions: 1)]
        let record = HistoryTreeBuilder.top(days: recordDays, today: today, calendar: calendar)
        let recordLine = HistoryRowText.headline(top: record, summary: HistoryTreeBuilder.summary(top: record, days: recordDays, calendar: calendar), calendar: calendar)
        if recordLine.eyebrow != "On record since 3 July 2025" { failures.append("the record's eyebrow read \(recordLine.eyebrow)") }
        if !recordLine.facts.contains("best month September 2026 · \(Tokens.duration(6_300))") { failures.append("the record's facts were \(recordLine.facts)") }
        let oneDay = HistoryTreeBuilder.top(days: [row(9, 28, focused: 60, sessions: 1)], today: today, calendar: calendar)
        let weekLine = HistoryRowText.headline(top: oneDay, summary: HistoryTreeBuilder.summary(top: oneDay, days: [row(9, 28, focused: 60, sessions: 1)], calendar: calendar), calendar: calendar)
        if weekLine.sentence != "You focused \(Tokens.duration(60)) across 1 day." { failures.append("one focused day read \(weekLine.sentence)") }
        return failures
    }
```

- [ ] **Step 2: Add the render evidence**

In `Sources/Surfaces/Story/StoryColumns.swift` add after `case historyJournal`:

```swift
    case historyTree
```

- [ ] **Step 3: Write the row text and the row view**

Create `Sources/Surfaces/History/HistoryTreeRow.swift`:

```swift
import SwiftUI

/// The words on and about a row. Kept apart from the view so the checks can
/// read them without rendering.
enum HistoryRowText {
    static func title(_ place: HistoryPlace, today: Date, calendar: Calendar) -> String {
        switch place.level {
        case .year:
            return DateFormats.australian("yyyy").string(from: place.start)
        case .month:
            return DateFormats.australian("MMMM").string(from: place.start)
        case .week:
            let last = calendar.date(byAdding: .day, value: -1, to: place.span.end) ?? place.start
            if calendar.isDate(place.start, inSameDayAs: last) {
                return DateFormats.australian("EEE d MMM").string(from: place.start)
            }
            let sameMonth = calendar.isDate(place.start, equalTo: last, toGranularity: .month)
            let first = DateFormats.australian(sameMonth ? "d" : "d MMM").string(from: place.start)
            return "\(first) – \(DateFormats.australian("d MMM").string(from: last))"
        case .day:
            return calendar.isDate(place.start, inSameDayAs: today) ? "Today"
                : DateFormats.australian("EEE d MMM").string(from: place.start)
        }
    }

    /// `20h 40m · 14 days`, `2h 10m · 3 sessions`, or why there is no figure.
    static func facts(_ row: HistoryRow, today: Date) -> String {
        if row.isAppUseOnly { return "Recorded app use only · \(Tokens.duration(row.tracked))" }
        if row.isEmpty {
            return row.place.level == .day && Calendar.current.isDate(row.place.start, inSameDayAs: today)
                ? "nothing recorded yet today" : "nothing recorded"
        }
        if row.place.level == .day {
            let noun = row.sessions == 1 ? "1 session" : "\(row.sessions) sessions"
            return row.focused > 0 ? "\(Tokens.duration(row.focused)) · \(noun)" : noun
        }
        let days = row.focusedDays == 1 ? "1 day" : "\(row.focusedDays) days"
        return row.focused > 0 ? "\(Tokens.duration(row.focused)) · \(days)" : "no focus recorded"
    }

    /// `September 2026, 1 hour 45 minutes across 3 days, month, level 2, collapsed`.
    static func spoken(_ row: HistoryRow, today: Date, isOpen: Bool, depth: Int, calendar: Calendar) -> String {
        var name = title(row.place, today: today, calendar: calendar)
        if row.place.level == .month { name += " " + DateFormats.australian("yyyy").string(from: row.place.start) }
        let figure: String
        if row.isAppUseOnly {
            figure = "recorded app use only, \(Tokens.spent(row.tracked))"
        } else if row.isEmpty {
            figure = facts(row, today: today)
        } else if row.place.level == .day {
            let noun = row.sessions == 1 ? "1 session" : "\(row.sessions) sessions"
            figure = row.focused > 0 ? "\(Tokens.spent(row.focused)), \(noun)" : noun
        } else {
            let days = row.focusedDays == 1 ? "1 day" : "\(row.focusedDays) days"
            figure = row.focused > 0 ? "\(Tokens.spent(row.focused)) across \(days)" : "no focus recorded"
        }
        var parts = [name, figure, row.place.level.spokenName, "level \(depth + 1)"]
        if !row.isEmpty { parts.append(isOpen ? "expanded" : "collapsed") }
        return parts.joined(separator: ", ")
    }

    static func headline(top: HistoryTop, summary: HistorySummary, calendar: Calendar)
        -> (eyebrow: String, sentence: String, facts: [String]) {
        let eyebrow: String
        switch top.place?.level {
        case .year: eyebrow = DateFormats.australian("yyyy").string(from: top.span.start)
        case .month: eyebrow = DateFormats.australian("MMMM yyyy").string(from: top.span.start)
        case .week:
            let last = calendar.date(byAdding: .day, value: -1, to: top.span.end) ?? top.span.start
            eyebrow = "\(DateFormats.australian("d").string(from: top.span.start)) – "
                + DateFormats.australian("d MMMM").string(from: last)
        case .day, .none:
            eyebrow = "On record since \(DateFormats.australian("d MMMM yyyy").string(from: top.firstDay))"
        }
        let days = summary.focusedDays == 1 ? "1 day" : "\(summary.focusedDays) days"
        let sentence = summary.focused > 0
            ? "You focused \(Tokens.duration(summary.focused)) across \(days)."
            : "Nothing focused here yet."
        var facts: [String] = []
        if summary.focusedDays > 1 {
            facts.append("\(Tokens.duration(summary.focused / Double(summary.focusedDays))) per focused day")
        }
        if let best = summary.best {
            let name = best.place.level == .month
                ? DateFormats.australian("MMMM yyyy").string(from: best.place.start)
                : DateFormats.australian("EEE d MMM").string(from: best.place.start)
            facts.append("best \(best.place.level.spokenName) \(name) · \(Tokens.duration(best.focused))")
        }
        return (eyebrow, sentence, facts)
    }
}

/// One row on the spine, and under it, when open, its children one step in.
struct HistoryTreeRow: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    let row: HistoryRow
    let depth: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let indent: CGFloat = Tokens.Space.l
    static let dotSize: CGFloat = 8

    private var isOpen: Bool { navigation.historyOpen.indices.contains(depth) && navigation.historyOpen[depth] == row.place }
    private var isFocused: Bool { navigation.historyFocus == .row(row.place) }
    private var today: Date { store.now() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isOpen {
                children
                    .padding(.leading, Self.indent)
                    .overlay(alignment: .leading) { spine }
                    .transition(Tokens.Motion.transition(Tokens.Motion.unfold, reduceMotion: reduceMotion))
            }
        }
        .id(row.id)
    }

    private var header: some View {
        Button { navigation.toggleHistory(row.place) } label: {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                dot
                Text(HistoryRowText.title(row.place, today: today, calendar: SessionStore.historyCalendar))
                    .font(row.place.level == .day ? Tokens.Typography.metadata.weight(.bold)
                                                  : Tokens.Typography.rowTitle.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: Tokens.Space.s)
                if showsFacts {
                    Text(durations: HistoryRowText.facts(row, today: today))
                        .font(Tokens.Typography.metadata.monospacedDigit())
                        .foregroundStyle(row.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
                bars
            }
            .padding(.vertical, Tokens.Space.xs)
            .padding(.horizontal, HistoryRowLayout.inset)
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .background(isFocused ? Tokens.Colour.focus.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: !row.isEmpty, cornerRadius: Tokens.Radius.nested))
        .disabled(row.isEmpty)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HistoryRowText.spoken(row, today: today, isOpen: isOpen, depth: depth,
                                                  calendar: SessionStore.historyCalendar))
        .accessibilityAddTraits(isFocused ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(row.isEmpty ? "" : HistoryTree.keyboardHint)
    }

    /// A day of one finished session shows its figure on the session row.
    private var showsFacts: Bool {
        guard row.place.level == .day, isOpen, row.focused > 0 else { return true }
        let rows = HistoryJournalBuilder.rows(store.storyDayProjection(on: row.place.start), only: nil)
        return HistoryDayHeader.showsTotal(day: JournalDay(date: row.place.start, focused: row.focused,
                                                           tracked: row.tracked, sessions: row.sessions), rows: rows)
    }

    private var dot: some View {
        Circle()
            .strokeBorder(dotColour, lineWidth: row.focused > 0 ? 0 : 1.5)
            .background(Circle().fill(row.focused > 0 ? dotColour : Color.clear))
            .frame(width: Self.dotSize, height: Self.dotSize)
            .accessibilityHidden(true)
    }

    private var dotColour: Color {
        if let type = row.mainWorkType { return Tokens.Palette.workType(type) }
        return row.isEmpty ? StoryStyle.line : Tokens.Palette.warmGrey.opacity(0.7)
    }

    @ViewBuilder private var bars: some View {
        if row.place.level == .day {
            HistoryDayStrip(date: row.place.start, entries: store.storyDayProjection(on: row.place.start).sessions, height: 6)
                .frame(width: 120)
        } else if !row.bars.isEmpty {
            HistoryMonthBars(daily: row.bars.map(\.focused))
                .frame(width: 120)
        }
    }

    /// The line the children hang from, under this row's dot.
    private var spine: some View {
        Rectangle()
            .fill(StoryStyle.line)
            .frame(width: 1)
            .padding(.leading, HistoryRowLayout.inset + Self.dotSize / 2)
            .padding(.vertical, Tokens.Space.xs)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var children: some View {
        if row.place.level == .day {
            HistoryDaySessions(store: store, navigation: navigation, day: row.place.start, only: nil)
        } else {
            let rows = store.historyRows(under: row.place)
            // AnyView breaks the recursion in the opaque type; the tree is at
            // most four rows deep, so it costs nothing worth measuring.
            AnyView(ForEach(rows) { child in
                HistoryTreeRow(store: store, navigation: navigation, row: child, depth: depth + 1)
            })
        }
    }
}

/// A day's sessions and breaks, newest first, as the journal drew them.
struct HistoryDaySessions: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    let day: Date
    /// Narrowed to matching threads while History is searched.
    let only: Set<UUID>?

    var body: some View {
        let projection = store.storyDayProjection(on: day)
        let rows = HistoryJournalBuilder.rows(projection, only: only)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { entry in
                switch entry {
                case .session(let session):
                    HistorySessionRow(session: session,
                                      apps: (projection.sessionDetails[session.id]?.apps ?? []).map(\.appName),
                                      note: store.journalNote(for: session)
                                          .flatMap { $0.split(whereSeparator: \.isNewline).first.map(String.init) },
                                      isSelected: navigation.historySession == HistorySessionPick(thread: session.threadID, day: day)
                                          || navigation.historyFocus == .session(thread: session.threadID, day: day),
                                      onSelect: { navigation.selectHistory(session: session.threadID, on: day) })
                        .id("session-\(session.threadID.uuidString)")
                case .rest(let rest):
                    HistoryBreakRow(rest: rest)
                }
            }
        }
    }
}
```

In `HistoryJournal.swift` change `HistorySessionRow`: remove `let onOpen: () -> Void`, the `.simultaneousGesture(TapGesture(count: 2)…)` line and the `.accessibilityAction(named: "Open its day's story", onOpen)` line; change its `.accessibilityHint(HistoryJournal.keyboardHint)` to `.accessibilityHint(HistoryTree.keyboardHint)`. `HistoryDayGroup` (which still passes `onOpen:`) is retired in Task 6; until then make its call site pass nothing by removing the `onOpen:` argument there too. Also change `HistoryMonthBars` to leave `daily` as `[TimeInterval]` (it already is) — no change needed.

- [ ] **Step 4: Write the column**

Create `Sources/Surfaces/History/HistoryTree.swift`:

```swift
import SwiftUI
import AppKit

/// History's column: the top period's headline, the search, and the tree
/// of rows that unfolds in place. A search replaces the tree with the days
/// that matched, each open to its matching sessions.
struct HistoryTree: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @Environment(\.focusInterfaceDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Rows are buttons, and a clicked button never takes focus on macOS,
    /// so a click hands focus to the tree itself: ↑, ↓, ←, →, Return and
    /// Escape then reach it. The search field keeps its own cursor.
    @FocusState private var treeFocused: Bool
    var scrolls = true

    static let keyboardHint = "Up and down arrows move through the rows; Return opens or folds one; "
        + "left and right fold and open; Escape folds the deepest open row"

    private var isEmptyArchive: Bool { !store.historyFilter.isActive && store.historyDays.isEmpty }

    var body: some View {
        let insets = StoryStyle.columnInsets(for: density)
        let searched = store.historyFilter.isActive ? store.historyJournal() : nil
        let summary = searched.map { $0.isEmpty ? nil : HistoryJournal.matchSummary($0) } ?? nil
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
                pane { content(searched: searched, insets: insets) }
                    .onChange(of: navigation.historyScrollRequest) { _ in
                        treeFocused = true
                        guard let target = navigation.historyScrollTarget else { return }
                        withAnimation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StoryStyle.canvas)
        .announcesChanges(to: summary.map(DurationText.spoken(in:)))
        .onAppear { store.setInsightsVisible(true); navigation.prepareHistory() }
        .onDisappear { store.setInsightsVisible(false) }
        .storyRenderEvidence(isEmptyArchive ? .historyEmpty : .historyTree)
    }

    @ViewBuilder private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if scrolls {
            ScrollView { content() }
        } else {
            content().frame(maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func content(searched: [JournalEntry]?, insets: EdgeInsets) -> some View {
        if let searched, searched.isEmpty {
            EmptyState("No matching sessions",
                       detail: "Try a session name, a word from a note, an app, a category or a date.",
                       icon: "magnifyingglass")
                .padding(insets)
        } else if isEmptyArchive {
            emptyArchive.padding(insets)
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                headline
                if let searched {
                    HistorySearchResults(store: store, navigation: navigation, entries: searched)
                } else {
                    tree
                }
            }
            .padding(EdgeInsets(top: insets.top, leading: insets.leading - HistoryRowLayout.inset,
                                bottom: insets.bottom, trailing: insets.trailing - HistoryRowLayout.inset))
        }
    }

    private var headline: some View {
        let line = HistoryRowText.headline(top: store.historyTop(), summary: store.historySummary(),
                                           calendar: SessionStore.historyCalendar)
        return StoryHeadline(eyebrow: line.eyebrow, sentence: line.sentence, facts: line.facts,
                             highlight: Tokens.duration(store.historySummary().focused))
            .padding(.horizontal, HistoryRowLayout.inset)
    }

    private var tree: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(store.historyRows(under: nil)) { row in
                HistoryTreeRow(store: store, navigation: navigation, row: row, depth: 0)
            }
        }
        .coachAnchor(.journal)
        .focusable()
        .focused($treeFocused)
        .onMoveCommand { direction in
            switch direction {
            case .up: navigation.stepHistoryFocus(by: -1)
            case .down: navigation.stepHistoryFocus(by: 1)
            case .left: navigation.moveHistoryFocus(open: false)
            case .right: navigation.moveHistoryFocus(open: true)
            @unknown default: return
            }
            if let spoken = Self.spoken(navigation.historyFocus, store: store) { Announcement.post(spoken) }
        }
        .onCommand(#selector(NSStandardKeyBindingResponding.insertNewline(_:))) {
            navigation.activateHistoryFocus()
        }
        .onExitCommand { navigation.foldDeepestHistory() }
    }

    /// What a row says when the keyboard lands on it: its VoiceOver label.
    static func spoken(_ focus: HistoryFocus?, store: SessionStore) -> String? {
        switch focus {
        case .row(let place):
            let top = store.historyTop()
            let depth = place.level.rawValue - top.rootLevel.rawValue
            let parent = depth == 0 ? nil : HistoryTreeBuilder.path(to: place.start, top: top,
                                                                    calendar: SessionStore.historyCalendar)[depth - 1]
            guard let row = store.historyRows(under: parent).first(where: { $0.place == place }) else { return nil }
            return DurationText.spoken(in: HistoryRowText.spoken(row, today: store.now(), isOpen: false, depth: depth,
                                                                calendar: SessionStore.historyCalendar))
        case .session(let thread, let day):
            return store.journalSession(thread: thread, on: day).map(HistorySessionRow.spokenLabel)
        case nil:
            return nil
        }
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
            .accessibilityHint("Opens the session controls to choose an activity")
        }
        .frame(maxWidth: 520, alignment: .leading)
    }
}

/// The days a search matched, newest first, each open to its matching
/// sessions, with the month named between months.
struct HistorySearchResults: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    let entries: [JournalEntry]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                switch entry {
                case .month(let month):
                    Text(HistoryMonthHeader.title(month.start))
                        .font(Tokens.Typography.metadata.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, HistoryRowLayout.inset)
                        .padding(.top, Tokens.Space.m)
                        .accessibilityAddTraits(.isHeader)
                case .day(let day):
                    Text(HistoryDayHeader.title(day.date, isToday: Calendar.current.isDate(day.date, inSameDayAs: store.now())))
                        .font(Tokens.Typography.metadata.weight(.semibold))
                        .padding(.horizontal, HistoryRowLayout.inset)
                        .padding(.top, Tokens.Space.s)
                        .accessibilityAddTraits(.isHeader)
                    HistoryDaySessions(store: store, navigation: navigation, day: day.date, only: day.threads)
                case .quiet:
                    EmptyView()
                }
            }
        }
    }
}
```

In `HistoryJournal.swift` change `HistoryWorkspace` to use the tree:

```swift
            HistoryTree(store: store, navigation: navigation, scrolls: scrolls)
```

- [ ] **Step 5: Typecheck, then run the checks**

```bash
swiftc -typecheck -module-cache-path $TMPDIR/mc -swift-version 5 -parse-as-library -warnings-as-errors -target arm64-apple-macos13.0 $(find Sources -name '*.swift') 2>&1 | head -20
```

Fix what it names; the usual ones: `onExitCommand` needs `import SwiftUI` (present); `@unknown default` in `onMoveCommand` — if the compiler says the switch is already exhaustive, use `default: return`. Then:

```bash
./build.sh --test 2>&1 | grep -E "Rows say their period|headline names the top|FAIL|passed"
```

Expected: both `[PASS]`, no `[FAIL]`. The old `journalRenders` check still passes because `HistoryWorkspace` still renders a rail; its `.historyJournal` evidence is now `.historyTree`, so update that check's two `require(…, .historyJournal)` lines to `.historyTree`.

- [ ] **Step 6: Look at it**

```bash
./build.sh --run
```

Open History (⌘2). Expected: headline, search, the tree unfolded to this week. Click a week: it folds/opens; click a day: its sessions appear indented; the rail still shows the month (Task 5 fixes the rail). Quit.

- [ ] **Step 7: Commit**

```bash
git add Sources/Surfaces/History/HistoryTree.swift Sources/Surfaces/History/HistoryTreeRow.swift Sources/Surfaces/History/HistoryJournal.swift Sources/Surfaces/Story/StoryColumns.swift Sources/Verification/HistoryTreeChecks.swift Sources/Verification/HistoryJournalChecks.swift
git commit -m "History unfolds in place: years, months, weeks, days and sessions on one spine

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: The rail follows the deepest open row

**Files:**
- Modify: `Sources/Surfaces/History/HistoryJournalRail.swift` (scope, `HistoryPeriodRail` replaces `HistoryMonthRail`, `HistoryDayRail`/`HistorySessionRail` lose their open buttons)
- Modify: `Sources/App/StoryDayProjection.swift:153` (month limit)
- Modify: `Sources/Surfaces/Story/StoryColumns.swift` (`historyPeriodRail` evidence replaces `historyMonthRail`)
- Modify: `Sources/Verification/HistoryTreeChecks.swift`, `Sources/Verification/RedundancyChecks.swift:150-153`

**Interfaces:**
- Produces:
  - `enum HistoryRailScope: Equatable { case period(HistoryPlace?), day(Date), session(DaySession, day: Date) }` with `static func resolve(open:session:pick:) -> HistoryRailScope`.
  - `struct HistoryPeriodRail: View` with `static func appUseLine(tracked:) -> String` and `static func reading(for place: HistoryPlace?, top: HistoryTop) -> (scope: InsightRange, anchor: Date, limit: Int)`.
  - `StoryRenderEvidence.historyPeriodRail`.

- [ ] **Step 1: Write the failing checks**

Append to `HistoryTreeChecks.tests`:

```swift
        ("The rail follows the deepest open row and the picked session, and drops a session that is gone", railFollowsDeepestOpen),
        ("A period's reading covers exactly its span: one week, one month, a year's months, the record's months", periodReading)
```

and:

```swift
    private static func railFollowsDeepestOpen() -> [String] {
        let top = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let week = HistoryTreeBuilder.rows(under: nil, top: top, days: september, calendar: calendar)[0]
        let day = HistoryTreeBuilder.rows(under: week.place, top: top, days: september, calendar: calendar)[1]
        var failures: [String] = []
        if HistoryRailScope.resolve(open: [], session: nil, pick: nil) != .period(nil) { failures.append("nothing open did not describe the top") }
        if HistoryRailScope.resolve(open: [week.place], session: nil, pick: nil) != .period(week.place) { failures.append("an open week was not described") }
        if HistoryRailScope.resolve(open: [week.place, day.place], session: nil, pick: nil) != .day(day.place.start) { failures.append("an open day was not described") }
        let pick = HistorySessionPick(thread: UUID(), day: day.place.start)
        if HistoryRailScope.resolve(open: [week.place, day.place], session: nil, pick: pick) != .day(day.place.start) {
            failures.append("a picked session that is gone did not fall back to its day")
        }
        return failures
    }

    private static func periodReading() -> [String] {
        var failures: [String] = []
        let top = HistoryTreeBuilder.top(days: september + [row(7, 3, year: 2025, focused: 60, sessions: 1)], today: today, calendar: calendar)
        let record = HistoryPeriodRail.reading(for: nil, top: top)
        if record.scope != .month || record.limit != 15 || !calendar.isDate(record.anchor, inSameDayAs: today) {
            failures.append("the record read \(record.scope) × \(record.limit) anchored \(record.anchor)")
        }
        let years = HistoryTreeBuilder.rows(under: nil, top: top, days: september, calendar: calendar)
        let thisYear = HistoryPeriodRail.reading(for: years[0].place, top: top)
        if thisYear.scope != .month || thisYear.limit != 9 { failures.append("2026 read \(thisYear.scope) × \(thisYear.limit)") }
        let lastYear = HistoryPeriodRail.reading(for: years[1].place, top: top)
        if lastYear.limit != 6 || !calendar.isDate(lastYear.anchor, inSameDayAs: date(12, 31, year: 2025)) {
            failures.append("2025 read × \(lastYear.limit) anchored \(lastYear.anchor)")
        }
        let months = HistoryTreeBuilder.rows(under: years[0].place, top: top, days: september, calendar: calendar)
        let sep = HistoryPeriodRail.reading(for: months[0].place, top: top)
        if sep.scope != .month || sep.limit != 1 { failures.append("September read \(sep.scope) × \(sep.limit)") }
        let weeks = HistoryTreeBuilder.rows(under: months[0].place, top: top, days: september, calendar: calendar)
        let week = HistoryPeriodRail.reading(for: weeks[0].place, top: top)
        if week.scope != .week || week.limit != 1 { failures.append("a week read \(week.scope) × \(week.limit)") }
        return failures
    }
```

- [ ] **Step 2: Let a reading cover more than twelve months**

In `Sources/App/StoryDayProjection.swift` line 153 change `12` to `240`:

```swift
        case .month: limit = min(max(1, requestedLimit), 240)
```

(Twenty years; the record rail asks for as many months as are on record.)

- [ ] **Step 3: Rewrite the rail's scope and the period rail**

In `Sources/Surfaces/History/HistoryJournalRail.swift` replace `HistoryRailScope` (lines 26–55) with:

```swift
/// What the rail describes: the deepest open row, or the picked session.
enum HistoryRailScope: Equatable {
    /// A year, month or week; nil is the top period itself.
    case period(HistoryPlace?)
    case day(Date)
    case session(DaySession, day: Date)

    /// `session` is the picked session if its day still has it; a pick
    /// whose session is gone, or hidden by a search, reads as its day.
    static func resolve(open: [HistoryPlace], session: DaySession?, pick: HistorySessionPick?) -> HistoryRailScope {
        if let pick, let session, open.last?.level == .day, open.last?.start == pick.day {
            return .session(session, day: pick.day)
        }
        guard let deepest = open.last else { return .period(nil) }
        return deepest.level == .day ? .day(deepest.start) : .period(deepest)
    }
}
```

Replace `HistoryJournalRail.body` and `scope`:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            switch scope {
            case .period(let place):
                HistoryPeriodRail(store: store, place: place)
                    .storyRenderEvidence(.historyPeriodRail)
            case .day(let day):
                HistoryDayRail(store: store, projection: store.storyDayProjection(on: day))
                    .storyRenderEvidence(.historyDayRail)
            case .session(let session, let day):
                HistorySessionRail(store: store, session: session, day: day,
                                   apps: store.storyDayProjection(on: day).sessionDetails[session.id]?.apps ?? [])
                    .storyRenderEvidence(.historySessionRail)
            }
        }
        .padding(StoryStyle.railInsets(for: density))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scope: HistoryRailScope {
        var session: DaySession?
        if let pick = navigation.historySession {
            session = store.journalSession(thread: pick.thread, on: pick.day)
            // A search that hides the session hides it from the rail too.
            if store.historyFilter.isActive, let found = session,
               !store.historyJournal().contains(where: { entry in
                   if case .day(let row) = entry, row.date == pick.day { return row.threads?.contains(found.threadID) ?? true }
                   return false
               }) { session = nil }
        }
        return HistoryRailScope.resolve(open: navigation.historyOpen, session: session, pick: navigation.historySession)
    }
```

Replace `HistoryMonthRail` (lines 120–268) with `HistoryPeriodRail`. Keep `goalsTile` and `appsTile` as they are; drop `recentTile` and `recentMonths` (the year row's bars show the months now):

```swift
/// A year, month, week or the whole record: where its focus went, when,
/// which goals it met, which apps; for this month, how it is going; for a
/// year or the record, its best month; for a month or week, its best day.
struct HistoryPeriodRail: View {
    @ObservedObject var store: SessionStore
    /// nil: the top period.
    let place: HistoryPlace?

    /// Which reading covers a place: a week is one week, a month one
    /// month, a year its months on record, the record all its months.
    static func reading(for place: HistoryPlace?, top: HistoryTop) -> (scope: InsightRange, anchor: Date, limit: Int) {
        let calendar = SessionStore.historyCalendar
        let span = place?.span ?? top.span
        let last = calendar.date(byAdding: .day, value: -1, to: span.end) ?? span.start
        let anchor = min(last, top.today)
        switch place?.level ?? top.place?.level {
        case .week: return (.week, anchor, 1)
        case .month: return (.month, anchor, 1)
        case .year, .day, .none:
            let first = calendar.dateInterval(of: .month, for: span.start)?.start ?? span.start
            let months = (calendar.dateComponents([.month], from: first, to: anchor).month ?? 0) + 1
            return (.month, anchor, max(1, months))
        }
    }

    var body: some View {
        let calendar = SessionStore.historyCalendar
        let top = store.historyTop()
        let span = place?.span ?? top.span
        let read = Self.reading(for: place, top: top)
        let facts = store.insightReading(scope: read.scope, anchoredAt: read.anchor, limit: read.limit).facts
        let summary = place.map { HistoryTreeBuilder.row($0, byDate: HistoryTreeBuilder.index(store.historyDays, calendar: calendar), calendar: calendar) }
        let tracked = summary?.tracked ?? store.historySummary().tracked
        let isCurrentMonth = (place?.level ?? top.place?.level) == .month && span.contains(top.today)
        let surface = store.insightSurface(for: .month)
        return VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HistoryRailHeading(title: place.map { HistoryRowText.title($0, today: top.today, calendar: calendar) }
                                    ?? HistoryRowText.headline(top: top, summary: store.historySummary(), calendar: calendar).eyebrow)
            if !facts.categories.isEmpty {
                StoryTile(title: "Focus by category", trailing: nil) {
                    CategoryShareBar(shares: facts.categories)
                    if isCurrentMonth, let placed = surface.categories {
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
            bestTile(span: span, level: place?.level ?? top.place?.level ?? .year)
            if !facts.goalRates.isEmpty { goalsTile(facts.goalRates) }
            if !facts.apps.isEmpty { appsTile(facts.apps, tracked: tracked) }
            if isCurrentMonth { soFar(surface) }
        }
    }

    /// The best month of a year or the record; the best day of a month or week.
    @ViewBuilder private func bestTile(span: DateInterval, level: HistoryLevel) -> some View {
        let calendar = SessionStore.historyCalendar
        let top = HistoryTop(place: HistoryPlace(level: level, span: span), firstDay: span.start,
                             today: store.historyTop().today)
        let summary = HistoryTreeBuilder.summary(top: top, days: store.historyDays, calendar: calendar)
        if let best = summary.best, summary.focusedDays > 1 {
            let isMonth = best.place.level == .month
            StoryTile(title: isMonth ? "Best month" : "Best day", trailing: nil) {
                Text(isMonth ? DateFormats.australian("MMMM yyyy").string(from: best.place.start)
                             : Tokens.longDate(best.place.start))
                    .font(Tokens.Typography.sectionTitle)
                Text(durations: "\(Tokens.duration(best.focused)) focused")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// `16h 25m recorded app use`: the period's app use, said once, here.
    static func appUseLine(tracked: TimeInterval) -> String {
        "\(Tokens.duration(tracked)) recorded app use"
    }

    // goalsTile, appsTile and soFar exactly as HistoryMonthRail had them.
}
```

Copy `goalsTile`, `appsTile` and `soFar` from the old `HistoryMonthRail` verbatim into the new struct. Delete `recentTile`.

In `HistoryDayRail` remove `let onOpen: () -> Void` and the `Button("Open as a story ›", action: onOpen)…` three lines. In `HistorySessionRail` remove `let onOpen` and the `Button("Open its day ›", action: onOpen)…` three lines.

In `StoryColumns.swift` rename `case historyMonthRail` to `case historyPeriodRail`; in `HistoryJournalChecks.journalRenders` change `.historyMonthRail` to `.historyPeriodRail`. In `RedundancyChecks.swift` lines 150–153 replace `HistoryMonthHeader.facts(month)` with `HistoryRowText.facts(HistoryTreeBuilder.row(HistoryPlace(level: .month, span: DateInterval(start: month.start, duration: 86_400 * 30)), byDate: [:], calendar: SessionStore.historyCalendar), today: Date())` only if the check still compiles against `month`; simpler: replace that assertion with one that `HistoryRowText.facts` for a month row never contains "app use":

```swift
        let monthRow = HistoryRow(place: HistoryPlace(level: .month, span: DateInterval(start: month.start, duration: 86_400 * 30)),
                                  focused: month.focused, tracked: month.tracked, focusedDays: month.focusedDays,
                                  sessions: 3, mainWorkType: .deepWork, hasEvidence: true, bars: [])
        if HistoryRowText.facts(monthRow, today: Date()).contains("app use") {
            failures.append("a month row said its app use, which the rail says")
        }
        if HistoryPeriodRail.appUseLine(tracked: month.tracked) != "\(Tokens.duration(7_200)) recorded app use" {
```

Remove `recentMonthsFloor` from `HistoryJournalChecks.tests` and its function (its tile is gone); keep `HistoryJournalBuilder.recentMonths` only if something else calls it — nothing does, so delete it from `SessionStore+Journal.swift` and `JournalMonthTotal` with it.

- [ ] **Step 4: Run the checks and look**

```bash
./build.sh --test 2>&1 | grep -E "rail follows the deepest|period's reading covers|FAIL|passed"
./build.sh --run
```

Expected: both `[PASS]`, no `[FAIL]`. In the app: History's rail says "28 – 29 September" (this week) on opening; click a day, the rail describes it; click a session, the session; press Escape twice, the rail returns to the month.

- [ ] **Step 5: Commit**

```bash
git add Sources/Surfaces/History/HistoryJournalRail.swift Sources/App/StoryDayProjection.swift Sources/App/SessionStore+Journal.swift Sources/Surfaces/Story/StoryColumns.swift Sources/Verification/HistoryTreeChecks.swift Sources/Verification/HistoryJournalChecks.swift Sources/Verification/RedundancyChecks.swift
git commit -m "History's rail describes whichever year, month, week, day or session is open

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Retire the journal's selection, wire Jump to date and search

**Files:**
- Modify: `Sources/App/MainWindowModel.swift` (remove `historySelection`, `historySelectionOrDefault`, `selectHistory(_:scrolling:)`, `jumpToHistoryDay`, `stepHistorySelection`, `selectReviewDay`, `clearReviewDay`)
- Modify: `Sources/Surfaces/Main/StoryChromeBar.swift:160-180` (Jump to date)
- Modify: `Sources/App/SessionStore+Journal.swift` (remove `HistorySelection`, `JournalQuiet`, `.quiet`, `entries(days:today:)`, `step`, `neighbour`, `selection(forJump:)`, `anchorID`; keep `JournalMonth`, `JournalDay`, `JournalEntry` `.month`/`.day`, `entries(matching:)`, `patching`, `month(starting:)`, `rows(_:only:)`)
- Modify: `Sources/Surfaces/History/HistoryJournal.swift` (remove `HistoryJournal`, `HistoryMonthHeader`'s body → keep only its `title`/`facts` statics, `HistoryDayGroup`, `HistoryQuietRow`; keep `HistoryWorkspace`, `HistoryMonthBars`, `HistoryDayHeader` statics, `HistorySessionRow`, `HistoryBreakRow`)
- Modify: `Sources/Surfaces/Snapshotter.swift:433-447`, `Sources/Verification/StoryNavigationChecks.swift:20-75`, `Sources/Verification/StoryIntegrationChecks.swift:379-392`, `Sources/Verification/StoryPresentationChecks.swift:210-213`, `Sources/SelfTest.swift:7608-7617, 7789, 8033-8036`, `Sources/Verification/HistoryJournalChecks.swift`
- Copy to trash first: `HistoryJournal.swift`, `SessionStore+Journal.swift`, `HistoryJournalChecks.swift`

- [ ] **Step 1: Copy the files being cut down to the trash**

```bash
T="/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/_trash/2026-09-29-history-tree"
cp Sources/Surfaces/History/HistoryJournal.swift "$T/HistoryJournal.swift"
cp Sources/App/SessionStore+Journal.swift "$T/SessionStore+Journal.swift"
cp Sources/Verification/HistoryJournalChecks.swift "$T/HistoryJournalChecks.swift"
```

Checks retired by name (the baseline in Task 8 subtracts these 10): `newestFirst`, `appUseOnly`, `breakOnlyDay`, `emptyArchive`, `monthBoundary`, `daylightSaving` (the journal's), `keyboardSteps`, `jumpSelects`, `railFallsBackToMonth`, `recentMonthsFloor`. Their subjects are covered by `HistoryTreeChecks` (`clippedToRecord`, `dots`, `dayRollover`, `daylightSaving`, `keyboardWalk`, `pathToDay`, `railFollowsDeepestOpen`).

- [ ] **Step 2: Jump to date and search open the day**

In `StoryChromeBar.jumpToDate` replace the `DayPickerCalendar(...)` call:

```swift
            DayPickerCalendar(
                selected: navigation.reviewSelectedDate ?? Calendar.current.startOfDay(for: store.now()),
                earliest: store.earliestSelectableDay,
                goal: store.goal.goal,
                facts: { store.dayFacts(inMonthOf: $0) }) { day in
                    navigation.openHistory(day: day)
                    historyCalendarShown.value = false
                }
```

- [ ] **Step 3: Remove the old selection**

In `MainWindowModel.swift` delete `historySelection`, `historySelectionOrDefault`, `selectHistory(_:scrolling:)`, `jumpToHistoryDay`, `stepHistorySelection`, `selectReviewDay`, `clearReviewDay`, and simplify:

```swift
    var reviewSelectedDate: Date? { historySession?.day ?? historyOpen.last(where: { $0.level == .day })?.start }
```

In `SessionStore+Journal.swift` remove `JournalQuiet`, the `.quiet` case of `JournalEntry` (and its `id` branch), `HistorySelection`, `entries(days:today:)`, `hasEvidence`, `step`, `neighbour`, `selection(forJump:)`, `anchorID`, `JournalKey` stays (Task 2 uses it), the non-search branch of `historyJournal()` becomes:

```swift
    func historyJournal() -> [JournalEntry] {
        guard historyFilter.isActive else { return [] }
        let calendar = Calendar.current
        let key = SearchJournalKey(filter: historyFilter, evidence: evidenceRevision,
                                   indexGeneration: historyIndexGeneration)
        if let cached = searchJournalCache, cached.key == key { return cached.entries }
        searchJournalComputeCount &+= 1
        let entries = HistoryJournalBuilder.entries(matching: historySearchHits(limit: .max), calendar: calendar)
        searchJournalCache = (key, entries)
        return entries
    }
```

and remove `journalCache`/`journalComputeCount` from `SessionStore.swift` if nothing else reads them (grep first; `HistoryJournalChecks.journalIsCached` did — it is rewritten below).

In `HistoryJournal.swift` remove `HistoryJournal` (keep its `static func matchSummary` by moving it into `HistoryTree` as `static func matchSummary(_ entries: [JournalEntry]) -> String` and update the call in `HistoryTree.body`), `HistoryDayGroup`, `HistoryQuietRow`, the `case .quiet` in `HistorySearchResults`; cut `HistoryMonthHeader` down to its two statics:

```swift
/// A month's name and figures, for the search results' month lines.
enum HistoryMonthHeader {
    static func title(_ start: Date) -> String {
        DateFormats.australian("MMMM yyyy").string(from: start)
    }
}
```

and `HistoryDayHeader` down to its statics `showsTotal` and `title` (an `enum`).

- [ ] **Step 4: Rewrite the checks that used the old API**

`StoryNavigationChecks.swift` lines 20–75: replace the selection walk with:

```swift
            let top = store.historyTop()
            if navigation.historyOpen != HistoryTreeBuilder.pathToToday(top: top, calendar: SessionStore.historyCalendar) {
                failures.append("History did not open to this week")
            }
            navigation.openHistory(day: yesterday)
            if navigation.reviewSelectedDate != Calendar.current.startOfDay(for: yesterday) {
                failures.append("Jump to date did not open the day: \(String(describing: navigation.reviewSelectedDate))")
            }
            if let thread = store.journalThreads(on: yesterday, only: nil).first {
                navigation.selectHistory(session: thread, on: yesterday)
                if navigation.historySession?.thread != thread { failures.append("picking a session did not select it") }
                navigation.stepHistoryFocus(by: -1)
                if navigation.historyFocus != .row(navigation.historyOpen.last!) { failures.append("↑ from the first session did not land on its day") }
            }
            navigation.foldDeepestHistory()
            if navigation.reviewSelectedDate != nil { failures.append("Escape left a day open") }
```

`StoryIntegrationChecks.swift` 379–392: replace `jumpToDay(day)` + the `picks` loop with `navigation.openHistory(day: day)` and, for each of `[.foldDeepestHistory(), .openHistory(day: yesterday)]` style steps, assert `navigation.workspace == .history` throughout (the point of that check is that History never leaves the workspace).

`StoryPresentationChecks.swift` 210–213: unchanged in intent; `reviewSelectedDate` is non-nil once `Snapshotter.navigation` opens a day (Step 5).

`SelfTest.swift` 7608–7617, 7789, 8033–8036: replace `selectReviewDay(x)` with `openHistory(day: x)` and `clearReviewDay()` with `foldDeepestHistory()`; the `reviewSelectedDate` expectations hold.

`HistoryJournalChecks.swift`: remove the ten retired checks and their functions; keep `monthTotals` (it tests `JournalMonth` arithmetic via `HistoryJournalBuilder.month(starting:)`), `searchNarrows`, `liveToday` (rewrite its journal read as a search read or drop it if it only exercised `patching` on the journal — `patching` is still used by search? No: remove `patching` from the builder and drop `liveToday`; the tree's `treeIsCached` covers live today), `journalIsCached` → rename `searchIsCached` and assert `searchJournalComputeCount` only, `journalWording`, `sessionSpeech`, `dayTotalSaidOnce`, `bestHoursSaidOnce`, `monthRailAppUse` (now `HistoryPeriodRail.appUseLine`), `journalRenders` (renamed `historyRenders`: opening → `.historyTree` + `.historyPeriodRail`; then `navigation.openHistory(day: yesterday)` → `.historyDayRail`; then `selectHistory(session:on:)` → `.historySessionRail`; the sparse `firstRun` store → `.historyEmpty`).

- [ ] **Step 5: Snapshot scenarios**

In `Snapshotter.swift`:

- `.reviewHistorySelection` description → `"History — opened to this week"`; its `navigation(for:)` case becomes just `navigation.open(tab: .review)`.
- `.historySession` → `"History — a day open and a session picked"`; its case:

```swift
        case .historySession:
            navigation.open(tab: .review)
            if let day = store.historyDays.first(where: { $0.sessions > 0 })?.date,
               let thread = store.journalThreads(on: day, only: nil).first {
                navigation.selectHistory(session: thread, on: day)
            }
```

- Add `case historySparse` to the enum and `"History — three recorded days"` to its descriptions, `.review` to `tab`, `FixtureFactory.store(for: .firstRun, accurateUsage: true)` with `refreshReview()` in `store(for:)`, `navigation.open(tab: .review)` in `navigation(for:)`. Add it to the scenario lists at `SelfTest.swift:7266`.

- [ ] **Step 6: Build, test, look**

```bash
./build.sh --test 2>&1 | grep -E "FAIL|passed"
./build.sh --run
```

Expected: no `[FAIL]`. In the app: Jump to date → the tree unfolds to the picked day, its sessions showing, the rail describing it. Type in search → matching days with their sessions; click one → the rail describes the session; clear the search → the tree is unfolded to that day.

- [ ] **Step 7: Commit**

```bash
git add Sources/App/MainWindowModel.swift Sources/App/SessionStore.swift Sources/App/SessionStore+Journal.swift Sources/Surfaces/History/HistoryJournal.swift Sources/Surfaces/History/HistoryTree.swift Sources/Surfaces/Main/StoryChromeBar.swift Sources/Surfaces/Snapshotter.swift Sources/Verification/StoryNavigationChecks.swift Sources/Verification/StoryIntegrationChecks.swift Sources/Verification/StoryPresentationChecks.swift Sources/Verification/HistoryJournalChecks.swift Sources/SelfTest.swift
git commit -m "Jump to date and search open the day in place; the journal's flat list is retired

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: The dashboard shows today only

**Files:**
- Modify: `Sources/Surfaces/Main/StoryChromeBar.swift:117-140, 182-233` (period slot)
- Modify: `Sources/App/MainWindowModel.swift` (remove `jumpToDay`, `openDay`, `showDay`, `stepStoryPeriod`, `lastPeriodStep`; `openToday` and `connect` no longer move the day)
- Modify: `Sources/Surfaces/Main/MainWindowView.swift:246-253` (transition)
- Modify: `Sources/App/AppCoordinator.swift:598-601` (the `past` preview)
- Modify: `Sources/Surfaces/Snapshotter.swift` (retire `.todayPast`), `Sources/SelfTest.swift:7266` (scenario list)
- Modify: `Sources/Core/PersistenceStore.swift:35, 676` (`fc.defaultStoryScope`)
- Modify: `Sources/Core/FirstRun.swift:395-408` (tour copy)
- Modify: `Sources/Verification/StoryNavigationChecks.swift:150-175`, `Sources/Verification/StoryIntegrationChecks.swift:320`, `Sources/Verification/StoryInteractionChecks.swift:361`
- Modify: `Sources/Verification/HistoryTreeChecks.swift` (one check)

`SessionStore.selectDay/stepDay/dayOffset` stay: the store's own checks use them to test past-day figures, and nothing in the window reaches them any more.

- [ ] **Step 1: Write the failing check**

Append to `HistoryTreeChecks.tests`:

```swift
        ("The dashboard has no step or calendar, and History never moves its day", dashboardIsToday)
```

and:

```swift
    private static func dashboardIsToday() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            store.refreshReview()
            let navigation = MainWindowModel(store: store)
            navigation.open(tab: .review)
            var failures: [String] = []
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: store.now()))!
            navigation.openHistory(day: yesterday)
            if !store.isToday { failures.append("opening a day in History moved the dashboard's day") }
            if navigation.workspace != .history { failures.append("opening a day left History") }
            let frame = StoryWorkspaceChecks.renderFrame(
                StoryChromeBar(store: store, navigation: navigation, settings: SettingsModel(store: store)),
                width: 1_160, height: 60)
            if frame.accessibilityLabels.contains(where: { $0.contains("Previous day") || $0.contains("Next day") || $0.contains("Opens the calendar") }) {
                failures.append("the story chrome still steps days or opens the calendar")
            }
            return failures
        }
    }
```

If `StoryChromeBar`'s initialiser or `StoryRenderedFrame`'s label list differ from this sketch, read `StoryWorkspaceChecks.renderFrame` and `StoryChromeBar.init` and adapt the two lines; the intent is: render the story chrome for the story workspace and assert none of those three help strings is present.

- [ ] **Step 2: Cut the period navigation from the story chrome**

In `StoryChromeBar.workspaceControls`, the `.story` case becomes:

```swift
        case .story:
            // The story is today. Every other day is History's.
            Spacer(minLength: Tokens.Space.s)
            Text("Today")
                .font(Tokens.Typography.rowTitle)
                .frame(minWidth: Self.periodLabelWidth, minHeight: AccessibilityMetrics.minimumTargetSize)
                .accessibilityAddTraits(.isHeader)
                .coachAnchor(.periodNav)
            Spacer(minLength: Tokens.Space.s)
            crossLinks
```

Delete `periodNavigation`, `calendarShown`, `periodLabel`, `stepHelp`, `canStepBack`, `canStepForward`, `step(_:)`. `periodLabelWidth` stays (the label uses it).

- [ ] **Step 3: Cut the model's day movement**

In `MainWindowModel.swift` delete `jumpToDay`, `openDay`, `showDay`, `lastPeriodStep`, `stepStoryPeriod`. `openToday` becomes:

```swift
    func openToday(date: Date) {
        requestedDate = date
        animated(Tokens.Motion.swap) {
            workspace = .story
            sheet = nil
            store?.selectDay(offset: 0)
        }
    }
```

In `connect(to:)` replace `if let requestedDate { showDay(requestedDate) }` with `store.selectDay(offset: 0)`. Grep `requestedDate` afterwards; if only `openToday` and `init` touch it, leave it (it is harmless state), do not widen the change.

In `MainWindowView.swift` replace `readingTransition` with:

```swift
    private var readingTransition: AnyTransition { Tokens.Motion.unfold }
```

In `AppCoordinator.swift` remove the three lines of the `which == "past"` branch (598–601).

In `Snapshotter.swift` remove `case todayPast` from the enum, its description, its `tab` entry, its `store(for:)` case; remove it from the list at `SelfTest.swift:7266`.

In `PersistenceStore.swift` remove `static let defaultStoryScopeRawValue = "fc.defaultStoryScope"` (line 35) and its entry in the list at line 676.

In `FirstRun.swift` lines 395–408 replace the two History cards' text:

```swift
            Card(sentence: "History is one timeline that unfolds.",
                 body: "Years open into months, months into weeks, weeks into days, and a day "
                     + "into its sessions, each one step in from its parent. Click a row to open "
                     + "it, or press Return; Escape folds the deepest open row.",
                 anchor: .journal,
                 effect: .showHistory),
            Card(sentence: "History goes back to the day you installed the app.",
                 body: "Nothing is drawn from before the app was here, because nothing was "
                     + "recorded. Jump to date opens any recorded day straight away.",
                 anchor: .periodNav,
                 effect: .showHistory),
```

Rewrite `StoryNavigationChecks.swift` 150–175: the check that `openDay` returns to the story and `stepStoryPeriod` moves it is now that `openToday(date:)` lands on today with `store.isToday` true, and that `open(tab: .review)` then `returnToStory()` leaves `store.isToday` true. `StoryIntegrationChecks.swift:320` and `StoryInteractionChecks.swift:361`: replace `navigation.jumpToDay(x)` with `store.selectDay(offset: n)` for the offset those checks need (they test the store's past-day behaviour, not navigation).

- [ ] **Step 4: Build, test, look**

```bash
./build.sh --test 2>&1 | grep -E "FAIL|passed"
./build.sh --run
```

Expected: no `[FAIL]`. The dashboard's chrome reads `Today` with no arrows and no calendar; History still has Jump to date.

- [ ] **Step 5: Commit**

```bash
git add Sources/Surfaces/Main/StoryChromeBar.swift Sources/App/MainWindowModel.swift Sources/Surfaces/Main/MainWindowView.swift Sources/App/AppCoordinator.swift Sources/Surfaces/Snapshotter.swift Sources/SelfTest.swift Sources/Core/PersistenceStore.swift Sources/Core/FirstRun.swift Sources/Verification/StoryNavigationChecks.swift Sources/Verification/StoryIntegrationChecks.swift Sources/Verification/StoryInteractionChecks.swift Sources/Verification/HistoryTreeChecks.swift
git commit -m "The dashboard shows today only; every other day lives in History

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Docs, screenshots and the final verification

**Files:**
- Modify: `docs/usage.md` (History row line 17, keys 30–31, "Reading the story" 44–56, calendar row 15)
- Modify: `README.md:28-30, 122-126`
- Replace: `docs/screenshots/history.png`, `docs/screenshots/history-dark.png`, `docs/screenshots/day-story.png`
- Modify: memory `history-journal-2026-09-29.md` (a one-line pointer that the journal was superseded)

- [ ] **Step 1: Docs**

`docs/usage.md` line 17's History row becomes:

> | History | How have my years, months, weeks and days gone? Where is that session? | One timeline that unfolds. It opens on the smallest period holding your whole record: this week's days, this month's weeks, this year's months, or every year. Click a row to open it: a year into its months, a month into its weeks, a week into its days, a day into its sessions, each one step in from its parent; one row is open per level. Each row shows its focus, its focused days or sessions, and a thin bar per month or day. Nothing is drawn from before the first recorded day or after today. Search at the top, with app and category filters. The rail describes the deepest open row, or the session you click |

Keys (lines 30–31):

> | Up, Down | In History, move through the rows |
> | Return | In History, open or fold the row; select a session |
> | Left, Right | In History, fold or open the row |
> | Escape | In History, fold the deepest open row |

"Reading the story" (lines 44–56): delete "The arrows step a day; the date label opens the calendar." and replace the History sentences with "In History, click a row to open it in place and the rail describes it; **Jump to date** opens a day straight away."

Calendar row (line 15): "Opens from Jump to date in History." (drop "the date label").

`README.md` lines 122–126: "History as one timeline that unfolds: years, months, weeks, days and sessions, each level one step in, back to the first recorded day and no further." Update the two screenshot captions at 28–30 to "History, opened to a day with a session picked, dark" / "History, opened to this week".

- [ ] **Step 2: Screenshots**

```bash
./build.sh
./FocusContinuity.app/Contents/MacOS/FocusContinuity --fixture-window reviewHistorySelection
```

Capture the window (⌘⇧4, space, click) to `docs/screenshots/history.png`; repeat with the system in dark appearance and `historySession` to `docs/screenshots/history-dark.png`; and `storyDay` to `docs/screenshots/day-story.png`. Each is a full-window capture at the default 1160×780.

- [ ] **Step 3: Final verification**

```bash
./build.sh --check 2>&1 | tail -3
git status --short
```

Expected: `N/N passed` where N ≥ (Task 0 baseline − 10 retired + 16 added). `git status` shows only the five activity-rule files as modified.

Then the live pass, in the app (`./build.sh --run`):

1. History opens unfolded to this week; the rail says this week.
2. Click a week; it opens and the other folds. Click a day; sessions appear indented. Click a session; the rail describes it. Escape three times folds back up.
3. Jump to date to the first recorded day: the tree unfolds there; the first week row is clipped to the record.
4. Search "Build"; results show; click one; clear; the tree is unfolded there.
5. ↑ ↓ walk the rows with the highlight; → opens; ← folds; Return toggles.
6. The dashboard reads `Today`; no arrows, no calendar.
7. Reduce Motion on: rows appear without the unfold animation.

- [ ] **Step 4: Commit**

```bash
git add docs/usage.md README.md docs/screenshots/history.png docs/screenshots/history-dark.png docs/screenshots/day-story.png
git commit -m "The docs and screenshots show History as one unfolding timeline

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

Update the memory file `history-journal-2026-09-29.md`: add a line under **How to apply**: "Superseded 2026-09-29 by the unfolding timeline (`docs/specs/2026-09-29-history-unfolding-timeline-design.md`); the journal's session and break rows survive as the deepest level."
