# History as one unfolding timeline

Date: 2026-09-29
Status: approved in conversation 2026-09-29; spec awaiting review

## Why

History is one scrolling journal (2026-09-29, `HistoryJournalBuilder`). It is honest and complete, but:

1. **It is a long scroll.** Every session of every day is listed, so a month is hundreds of rows and a year is thousands. Looking back three years means scrolling past everything in between.
2. **It is not organised above the day.** Months are headers in a list, not places to stand. There is no view of a year or a week.
3. **"Open its day" leaves History.** It switches the window to the story and moves the dashboard's day. The dashboard should show today and nothing else.
4. **The dashboard duplicates History's job.** Its ‹ › and calendar step to past days, so two pages do the same thing differently.

Goal: History is one timeline that unfolds. Years open into months, months into weeks, weeks into days, days into sessions, each level indented one step under its parent on its own spine, the way the dashboard already draws a day. The whole record is on one page, nothing leaves it, and every level shows only what was recorded, from the first recorded day to today.

## Decisions

| Question | Decision |
|---|---|
| Shape of History | One tree of rows on a spine: years › months › weeks › days › sessions. A row opens in place; its children appear indented under it. |
| How many open | One open row per level. Opening August folds September. |
| Root rows | The children of the smallest period that holds the whole record (§2). |
| Before the first record, after today | Nothing is drawn. |
| The day | Its sessions unfold under it as rows. No separate day page. |
| Rail | Follows the deepest open row, or the selected session. |
| Dashboard | Today only. Its ‹ ›, calendar and the "Opens on" preference go. |
| Chrome | Unchanged: `‹` · History · Jump to date · Start focus · Settings. No breadcrumb, no ‹ ›. |
| Journal | Its month headers and quiet-run folding are retired. Its day, session and break rows are kept as the deepest levels. Search stays. |

## 1. The tree

```
 2026                                              │ rail: the deepest
 You focused 412h across 201 days.                 │ open row
 best month October · longest streak 23 days       │
                                                   │
 ●  September    20h 40m · 14 days   ▁▂▃▅▂▁▆▃▅▆    │
 │   ○  22 – 28 Sep    9h 35m · 6 days   ▃▅▇█▆▂    │
 │   ●  15 – 21 Sep    8h 10m · 5 days   ▂▄▆▃▅     │
 │   │   ●  Sun 21    1h 15m · 2 sessions  ▁▁▃▃▁▁  │
 │   │   ●  Sat 20    1h 45m · 1 session   ▁▁▂▂▂▁  │
 │   │   │   ●  9:00 – 10:45   Review evidence   1h 45m
 │   │   │      Meetings · Xcode, Terminal          │
 │   │   ○  Fri 19    nothing recorded              │
 │   │   ●  Thu 18    2h 10m · 3 sessions  ▁▂▃▂▃▁  │
 │   │   ●  Wed 17    50m · 1 session      ▁▁▁▂▁▁  │
 ●  August       …                                 │
```

Levels, top down: **years › months › weeks › days › sessions**. The headline names the top period (§2). Below it, rows on a spine, newest first, as the journal's rows are now.

### Rows

A folded row is one line: a dot, a name, its focused total, a count, and thin bars.

| Level | Name | Count | Bars |
|---|---|---|---|
| year | `2026` | focused days | one per month |
| month | `September` | focused days | one per day |
| week | `15 – 21 Sep` | focused days | one per day |
| day | `Thu 18` (today: `Today`) | sessions | the day's sessions laid across the hours, in their category colours |
| session | the journal's session row as now: time range, name, category chip, apps, length | | |

Breaks stay as the journal's break rows under their day.

- The **dot** is the row's main category colour (most focused seconds), as a session's dot is. A period with app use but no focus has a hollow dot and reads "at the Mac, no session" as the journal's app-use-only day does. A period with nothing recorded has a hollow dot, the line "nothing recorded", and cannot open.
- The **bars** are one decorative group. They are not targets; the row is.
- Each figure is said once: the headline gives the top period's totals; a row gives its own and never its parent's. A day of one session shows its figure on the session row, not the day row too (kept from the journal).

### Opening and folding

- Clicking a row, or Return on it, opens it: its children appear under it, indented one step, on their own spine, with the unfold motion. Clicking it again folds it and everything under it.
- **One open row per level.** Opening a row folds its open sibling.
- Opening a row scrolls it into view at the top of the column, so its children are what the reader sees next.
- Escape folds the deepest open row. With nothing open, Escape does nothing; Back returns to the story.
- A session row does not open; clicking it selects it (the rail describes it), as now.

### The record boundary

Every level is clipped to `[first recorded day, today]`, where the first recorded day is `SessionStore.earliestDay` (`HistoryStats.earliestRecordedDay()`).

- A row covers only the days inside its parent **and** inside the record. Installed on Wednesday 17 September: the September row has 14 bars (17th to 30th), not 30; the first week row reads `17 – 20 Sep` with 4 bars and opens to Wednesday to Saturday.
- Weeks are Monday to Sunday. A week that crosses a month boundary appears under both months, each time clipped to that month (`28 – 30 Sep` under September, `1 – 4 Oct` under October), so a month's rows sum to its headline. Under either, it opens to only that month's days.
- Nothing is drawn after today: no future months in a year, no future days in a week.

## 2. The top and what opens first

The top period is the smallest period that holds the whole record. Its children are the root rows; the top itself is the headline, not a row.

| The record fits in | Headline | Root rows |
|---|---|---|
| this week (Mon – today) | this week | its days |
| this month | this month | its weeks |
| this year | this year | its months |
| otherwise | the record (`Since 17 Sep 2024`) | its years |

As the record grows, the top steps up when the record first leaves the current period. A three-day user sees this week's days; a three-week user sees September's weeks; a fourteen-month user sees two years.

History opens with the path to today unfolded down to **this week**: today's year and month are open, this week's days are in view, none of them open. The rail describes this week. If the top is the week, nothing is unfolded.

## 3. Moving around

### Chrome

`‹` · **History** · `Jump to date` · Start focus · Settings, as now.

- **Back** (`‹`) returns to the story.
- **Jump to date** keeps the `DayPickerCalendar` with its per-day figures, limited to recorded days. Picking a day unfolds the path to it, opens the day so its sessions show, scrolls to it, and the rail describes it.
- **Search** keeps its field above the tree. Typing shows the existing results (`historySearchHits`), newest first, in place of the tree; Escape clears; picking a result unfolds to its day and selects the session.

### Keys

- ↑ ↓ move through the visible rows in reading order, as the journal's arrows do now.
- Return opens or folds the focused row; on a session row it selects it.
- → opens a folded row; ← folds an open row, or moves to the parent of a folded one.
- Escape folds the deepest open row. ⌘F reaches search, as now.
- VoiceOver reads a row as one element with its state: "September 2026, 20 hours 40 minutes across 14 days, collapsed"; "Thursday 18 September, 2 hours 10 minutes, 3 sessions, expanded". The bars are one group that names its span and is skipped by default. Indentation is spoken as the level: "week, level 3".

### Motion

Children unfold under their row (`Tokens.Motion.unfold`); folding is the reverse. With Reduce Motion, they appear and disappear with a crossfade.

## 4. Rails

The rail describes the deepest open row, or the selected session, and nothing from another time frame (the 2026-09-28 rule).

| Deepest open | Tiles |
|---|---|
| nothing (top = the record, year, month or week) | the top period's tiles |
| year, month, week | today's month rail, computed over the row's span: focus by category with where each lands, best two hours, apps with recorded use; then pace, focus quality and continuity. A year or the record adds **Best month**; a month or week adds **Best day**. |
| day | the History day rail as now (`HistoryDayRail`) |
| a selected session | the session rail as now (`HistorySessionRail`) |

`HistoryMonthRail` becomes a period rail over a `DateInterval`; the month is one case of it.

## 5. Dashboard

The story workspace shows today only.

- The ‹ › buttons and the calendar leave `StoryChromeBar.periodNavigation`; the period slot reads `Today` as a label. `MainWindowModel.stepStoryPeriod`, `jumpToDay`, `openDay`, `showDay` and `SessionStore.selectDay/stepDay/canStepBack/canStepForward` go with them once nothing else calls them.
- The `fc.defaultStoryScope` preference and any Settings row that sets it are removed.
- The first-run tour's `periodNav` anchor moves to History's Jump to date.
- History never switches the workspace to the story. "Open its day" and "Open as a story" are gone: the day is already open on the page.

## 6. Under the hood

### Types (`Sources/App/HistoryTree.swift`)

```swift
enum HistoryLevel: Int { case year, month, week, day }

/// One period on the spine: its level and start.
struct HistoryPlace: Hashable {
    let level: HistoryLevel
    let start: Date
}

/// A row as drawn: what it covers, clipped to its parent and the record.
struct HistoryRow: Identifiable, Equatable {
    let place: HistoryPlace
    let span: DateInterval
    let focused, tracked: TimeInterval
    let focusedDays, sessions: Int
    let mainWorkType: WorkType?
    let bars: [HistoryBar]           // months, days, or the hour strip
    var isEmpty: Bool                // nothing recorded: cannot open
    var id: HistoryPlace { place }
}
```

`MainWindowModel` replaces `historySelection: HistorySelection?` with:

- `@Published private(set) var historyOpen: [HistoryPlace]` — the open path, root first, one place per level, and
- `@Published private(set) var historySession: (thread: UUID, day: Date)?` — the selected session,

with `toggle(_ place:)`, `foldDeepest()`, `open(day:)` (Jump to date, search) and `select(session:on:)`. `reviewSelectedDate` reads the open day.

### Builder (`Sources/Core/HistoryTreeBuilder.swift`)

Pure, from the existing `HistoryDay` index, a `today` and a calendar, as `HistoryJournalBuilder` is:

- `top(days:today:)` → the top period and its level, the §2 rule.
- `rows(under parent: HistoryPlace?, days:today:)` → `[HistoryRow]`, newest first, clipped to the parent and the record, with §1's dot and bar rules. `nil` gives the root rows.
- `pathToToday(days:today:)` for the opening state; `path(to day:)` for Jump to date and search.

Figures reuse `JournalMonth`'s arithmetic and `PeriodStats` where they fit. Day and session rows reuse the journal's `JournalDay`, its session and break rows and `store.storyDayProjection(on:)`; the dashboard's `selectedDay` is not touched. Rows are cached as the journal is: a ticking clock does not rebuild them, and today's live figures reach its rows.

### Views (`Sources/Surfaces/History/`)

- `HistoryWorkspace` keeps its column and rail. The column is `HistoryTree`: headline, search field, then the root rows.
- `HistoryTreeRow`: dot, name, figures, `HistoryBars` (the journal's month bars, made a view that takes any span) or `HistorySessionStrip` for a day; when open, its children indented by one `Tokens.Space.l` on their own spine. Day rows reuse the journal's day row body; session and break rows are the journal's.
- `HistoryJournalRail` keeps its scopes and gains the period case.

### Retired

To `_trash/2026-09-29-history-tree/` in the main checkout: the journal's month header, `JournalEntry`, `JournalQuiet` and the quiet-run folding, `HistorySelection`, `HistoryRailScope`, "Open its day" and "Open as a story", the story chrome's period navigation and its calendar, the `fc.defaultStoryScope` key and row. Their checks are rewritten (§7), not dropped.

Docs: `docs/usage.md` (History and Settings tables), `README.md`, the two History screenshots and `day-story.png` are re-taken.

## 7. Checks

`HistoryTreeChecks` replaces `HistoryJournalChecks`; the journal checks still true (search, live today, caching, daylight saving, wording, session speech, day figure said once) are carried over.

1. The top at 3 days, 20 days in one month, 20 days across a month boundary, 3 months, 14 months; and the root rows each gives.
2. Nothing before the first recorded day: a September row for a record from the 17th has 14 bars; the first week row is `17 – 20 Sep` and opens to four days; no row exists before the record.
3. Nothing after today: no future months, weeks or days.
4. A week across a month boundary appears under both months, clipped, and a month's rows sum to its headline.
5. Opening a row folds its open sibling; folding a row folds everything under it; an empty row cannot open.
6. The opening state unfolds to this week and no further; with the week as top, nothing is open.
7. Jump to date and a search pick unfold to the day and open it; Escape folds one level at a time.
8. Dots: main category, hollow for app use only, hollow with "nothing recorded" for an empty period inside the record.
9. Arrow keys walk the visible rows in reading order; ← → fold and open; Return toggles.
10. The rail follows the deepest open row and the selected session, and falls back when a searched-away session is gone.
11. Each figure is said once across headline, rows and rail (`RedundancyChecks` extended).
12. VoiceOver wording and expanded/collapsed state for rows; bars are one skipped group.
13. The dashboard has no step or calendar; `historyOpen` never changes `selectedDay`.
14. Snapshot renders: the opening state, a year open to a day with a session selected, a search, and the three-day case, in light and dark, via `Snapshotter`'s matrix.

The build discipline stands: `./build.sh --test` green before any commit.

## Out of scope

- Editing from rows above the session (rename, change type). They stay on the session.
- Exporting a period.
- A year-over-year comparison tile.
- Opening more than one sibling at a time.
