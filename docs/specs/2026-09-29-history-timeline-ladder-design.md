# History as a timeline ladder

Date: 2026-09-29
Status: approved in conversation 2026-09-29; spec awaiting review

## Why

History is one scrolling journal (2026-09-29, `HistoryJournalBuilder`). It is honest and complete, but:

1. **It is a long scroll.** Every session of every day is listed, so a month is hundreds of rows and a year is thousands. Looking back three years means scrolling past everything in between.
2. **It is not organised above the day.** Months are headers in a list, not places to stand. There is no view of a year or a week.
3. **"Open its day" leaves History.** It switches the window to the story and moves the dashboard's day. The dashboard should show today and nothing else.
4. **The dashboard duplicates History's job.** Its ‹ › and calendar step to past days, so two pages do the same thing differently.

Goal: History shows the whole record at a glance and lets the reader step down, years to a day, in the app's own grammar: a timeline of dots and cards, newest at the top, the one the dashboard already draws for a day. Every level shows only what was recorded, from the first recorded day to today.

## Decisions

| Question | Decision |
|---|---|
| Shape of History | A ladder of levels: Years › Year › Month › Week › Day. Each level is a vertical timeline. |
| Where it opens | The smallest period that holds the whole record (see §2). Levels above it do not exist. |
| Before the first record | Nothing. No empty months, no empty days, no bars for days before the record began. After today, nothing either. |
| Month level | Week cards on the spine, each with a bar per day. Not a calendar grid. |
| Day level | The day story column as the dashboard draws it, for that date. |
| Dashboard | Today only. Its ‹ ›, calendar and the "Opens on" preference go. |
| Journal | Retired. Search stays. |

## 1. One timeline at every level

The column is always a spine with nodes, newest at the top, as the day story is. What a node is changes with the level:

| Level | A node is | Its card |
|---|---|---|
| Years | a year | `2026` · focused total · focused days · one bar per month |
| Year | a month | `September` · focused total · focused days · one bar per day |
| Month | a week | `21 – 27 Sep` · focused total · focused days · one bar per day |
| Week | a day | `Thu 24` · focused total · sessions · its categories · a strip of the sessions across the hours |
| Day | a session | the day story (`ProjectedDayStoryColumn`), unchanged |

A node:

- has a dot on the spine in the colour of its main category (most focused seconds), as a session's dot does. A period with app use but no focus has a hollow dot; a period with nothing recorded at all has a hollow dot and one quiet line, "nothing recorded", and no card.
- has a card that is one target: click, Return or double-tap drills to the next level. The bars inside a month or week card are also targets: a day's bar opens that day.
- says each figure once. The headline above the spine gives the period's totals; a card gives its own and never the parent's.

The headline is a `StoryHeadline`: eyebrow (the period), sentence ("You focused 20h 40m across 14 days."), facts (best day or month, longest streak, average per focused day). The rail is a 300pt column of the tiles for that period (§4).

### The record boundary

Every level is clipped to `[first recorded day, today]`, where the first recorded day is `SessionStore.earliestDay` (`HistoryStats.earliestRecordedDay()`).

- A card covers only the days inside its parent **and** inside the record. Installed on Wednesday 17 September: the September card has 14 bars (17th to 30th), not 30; the first week card reads `17 – 20 Sep` with 4 bars; the Week level for that week lists Wednesday to Saturday.
- Weeks are Monday to Sunday. A week that crosses a month boundary appears under both months, each time clipped to that month (`28 – 30 Sep` under September, `1 – 4 Oct` under October), so the month's cards sum to its headline. Opening either card shows the full week at the Week level.
- Nothing is drawn after today: no future months in a year, no future days in a week.
- ‹ › stop at the first recorded period and at today.

## 2. Where History opens

The top level is the smallest period that holds the whole record:

| The record fits in | History opens on |
|---|---|
| this week (Mon – today) | Week: today and the recorded days before it |
| this month | Month: its weeks |
| this year | Year: its months |
| otherwise | Years |

Levels above the top do not exist: no crumb, no ‹ › target, nothing to step up to. As the record grows, a new top appears when the record first leaves the current period. A three-day user sees a week and today; a three-week user sees September's weeks; a fourteen-month user sees two years.

At the top, ‹ › are disabled: there is nothing outside it.

## 3. Moving around

### Chrome

`‹` · **breadcrumb** · `Jump to date` · Start focus · Settings

- **Breadcrumb** in the context slot: `History › 2026 › September › 21 – 27 Sep › Thu 24`. `History` is the top level, whatever it is. Every crumb is a button to that level. The last crumb is the level shown and is not a button. Long crumbs shorten to the period's short form (`Sep`, `21–27`) before they wrap; the crumb never takes two lines.
- **‹ ›** in the period slot step between siblings at the level shown: month to month, week to week, day to day, across a parent boundary when the record continues there (the crumb updates). Clamped to the record.
- **Back** (`‹`) and **Escape** go up one level. At the top, Back returns to the story, as now.
- **Jump to date** keeps the `DayPickerCalendar` with its per-day figures, limited to recorded days. Picking a day opens its Day level with the full breadcrumb built.
- **Search** keeps its field above the column at every level. Typing shows the existing results (`historySearchHits`), newest first, in place of the spine; Escape clears; picking a result opens its Day and scrolls to the session.

### Keys

- ↑ ↓ move between nodes; ← → do too, for the bars inside a card once it is focused.
- Return drills in. Escape goes up. ⌘F reaches search, as now.
- VoiceOver reads a node as one element: "September 2026, 20 hours 40 minutes across 14 days, opens the month"; a day node as "Thursday 24 September, 2 hours 10 minutes, 3 sessions, Deep work and Learning, opens the day". Bars inside a card are one group that names its span; each bar is reachable and reads its date and figure.

### Motion

Drilling in: the chosen card scales up and fades while the next level fades in beneath it (`Tokens.Motion.swap`). Going up is the reverse. ‹ › slide sideways, as the story does now. With Reduce Motion all three are a crossfade.

## 4. Rails

The rail describes only the period shown, nothing from another time frame (the 2026-09-28 rule).

| Level | Tiles |
|---|---|
| Years, Year, Month, Week | today's month rail, computed over the level's span: focus by category with where each lands, best two hours, apps with recorded use; then pace, focus quality and continuity. Year and Years add **Best month**; Month and Week add **Best day**. |
| Day | the History day rail as now (`HistoryDayRail`): the day's focus, categories, apps, best hours. Selecting a session in the day story shows the session rail (`HistorySessionRail`). |

`HistoryMonthRail` becomes a period rail over a `DateInterval`; the month is one case of it.

## 5. Dashboard

The story workspace shows today only.

- The ‹ › buttons and the calendar leave `StoryChromeBar.periodNavigation`; the period slot reads `Today` as a label. `MainWindowModel.stepStoryPeriod`, `jumpToDay`, `openDay`, `showDay` and `SessionStore.selectDay/stepDay/canStepBack/canStepForward` go with them once nothing else calls them.
- The `fc.defaultStoryScope` preference and any Settings row that sets it are removed.
- The first-run tour's `periodNav` anchor moves to History's breadcrumb.
- History never switches the workspace to the story. "Open its day" and "Open as a story" become the Day level.

## 6. Under the hood

### Types (`Sources/App/HistoryLadder.swift`)

```swift
enum HistoryLevel { case years, year, month, week, day }

/// Where History stands: the level and the period it shows.
struct HistoryPlace: Hashable {
    let level: HistoryLevel
    let start: Date          // start of the year, month, week or day; .distantPast for years
}

/// The crumb: the top place first, the place shown last.
struct HistoryPath: Hashable {
    let places: [HistoryPlace]
    var current: HistoryPlace { places.last! }
    func up() -> HistoryPath?
    func down(to place: HistoryPlace) -> HistoryPath
}

struct HistoryNode: Identifiable, Equatable {
    let place: HistoryPlace          // what it opens
    let span: DateInterval           // the days it covers, clipped to parent and record
    let focused, tracked: TimeInterval
    let focusedDays, sessions: Int
    let mainWorkType: WorkType?
    let bars: [HistoryBar]           // one per month, day or hour strip, clipped
}
```

`HistoryPath` replaces `HistorySelection`. `MainWindowModel` holds `@Published private(set) var historyPath: HistoryPath` and offers `drill(to:)`, `up()`, `step(by:)`, `open(day:)`, `open(session:on:)`.

### Builder (`Sources/Core/HistoryLadderBuilder.swift`)

Pure, from the existing `HistoryDay` index, a `today` and a calendar, as `HistoryJournalBuilder` is:

- `topLevel(days:today:)` → `HistoryPlace`, the §2 rule.
- `nodes(at place: HistoryPlace, days:today:)` → `[HistoryNode]`, newest first, clipped to the record and the parent, with §1's dot and bar rules.
- `siblings(of place:)` for ‹ › and their clamping.
- `path(to day: Date, top:)` for Jump to date and search: the full crumb from the top to that day.

Figures reuse `JournalMonth`'s arithmetic and `PeriodStats` where they fit; nothing is computed twice. The day story reuses `store.storyDayProjection(on:)` with the path's day; the dashboard's `selectedDay` is not touched.

### Views (`Sources/Surfaces/History/`)

- `HistoryWorkspace` switches on `historyPath.current.level`: `HistoryLadderColumn` for Years to Week, `ProjectedDayStoryColumn(context: .main)` for Day.
- `HistoryLadderColumn`: headline, search field, spine of `HistoryNodeCard`s.
- `HistoryNodeCard`: dot, title, figures, `HistoryBars` (the journal's month bars, made a view that takes any span) or, for a day, `HistorySessionStrip` (sessions across the hours in their category colours).
- `HistoryBreadcrumb` in the chrome's context slot.
- The rails as §4.

### Retired

To `_trash/2026-09-29-history-ladder/` in the main checkout: `HistoryJournal.swift` (the list, its day and quiet rows), `HistoryJournalBuilder.entries`, `JournalEntry`, `JournalQuiet`, `HistorySelection`, `HistoryRailScope`, the story chrome's period navigation and its calendar, the `fc.defaultStoryScope` key and row. Their checks are rewritten (§7), not deleted silently.

Docs: `docs/usage.md` (History and Settings tables), `README.md`, the two History screenshots and `day-story.png` are re-taken.

## 7. Checks

`HistoryLadderChecks` replaces `HistoryJournalChecks`:

1. The top level at 3 days, 20 days in one month, 20 days across a month boundary, 3 months, 14 months.
2. Nothing before the first recorded day: a September card for a record from the 17th has 14 bars; the first week card is `17 – 20 Sep`; no node exists before the record.
3. Nothing after today: no future months, weeks or days.
4. A week across a month boundary appears under both months, clipped, and the month's cards sum to its headline.
5. The breadcrumb after each drill, after Jump to date, after a search pick, and after ‹ › across a parent boundary.
6. ‹ › clamp at the record's ends and are disabled at the top.
7. Up and Escape from every level; Back at the top returns to the story.
8. Dots: main category, hollow for app use only, hollow with "nothing recorded" for an empty period inside the record.
9. Search never counts breaks as focus (kept), and a pick opens the Day level.
10. Live today reaches the cached nodes, and a ticking clock does not rebuild them (kept).
11. Each figure is said once: headline, cards and rail (`RedundancyChecks` extended).
12. VoiceOver wording for nodes and bars.
13. The dashboard has no step or calendar; `historyPath` never changes `selectedDay`.
14. Daylight-saving and month-boundary days appear once (kept).
15. Snapshot renders: each level in light and dark, and a Day reached from History, via `Snapshotter`'s matrix.

The build discipline stands: `./build.sh --test` green before any commit.

## Out of scope

- Editing from levels above Day (rename, change type). They stay in the day story.
- Exporting a period.
- A year-over-year comparison tile.
