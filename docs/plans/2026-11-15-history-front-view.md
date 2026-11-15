# History Front View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redraw the first view of History as a headline, a month-block day grid and a quiet spine of periods, leaving every level below it unchanged.

**Architecture:** Three pure Core calculations (day grid, row facts, category split) feed two new read models on `SessionStore`, cached with the History tree and patched for today on each read. Two new Surfaces views (the grid, the period row) replace the "Each day" chart and the boxed period card at depth 0. Words stay in `HistoryRowText`, apart from the views, so checks read them without rendering.

**Tech Stack:** Swift 5 mode, SwiftUI and AppKit, macOS 14, one module built by `build.sh`. No new dependency.

**Spec:** `docs/specs/2026-11-15-history-front-view-design.md`

## Global Constraints

- `./build.sh --check` passes before each commit, sandbox disabled. Final gate also runs `TZ=Europe/Berlin` and `TZ=Pacific/Kiritimati`.
- Core is UI-free: no `Tokens`, no SwiftUI in `Sources/Core`. Words that need `Tokens.duration` live in Surfaces.
- Every length in App, Design and Surfaces is a token or `N.zoomed`; a fixed one carries `// zoom: fixed`.
- Read text uses `StoryStyle.supportingInk`; a fainter ink only on a drawn mark, with `// ink: quiet` and why.
- Source files stay at or under 300 lines. `HistoryTreeRow.swift` (276) and `HistoryTreeColumn.swift` (284) take no net growth: new code goes in new files.
- Checks never touch live data; fixture dates come from `HistoryTreeChecks.calendar`, `.today`, `.row`, never a fixed epoch.
- New suites are appended at the end of `registeredTests`. An existing check is rewritten in place; none is removed or reordered, since a check's position is its number.
- Day arithmetic goes through `Calendar`, never multiples of 86 400.
- No entrance animation. Hover uses `Tokens.Motion.hover`; row open and close keep `reveal`, `unfold`, `dismiss`.
- Steps: none = 0; under 2h; 2h to under 5h; 5h to under 8h; 8h or more.
- Ramp strengths of `Tokens.Colour.focus`: light 0.46, 0.64, 0.82, 1.0; dark 0.35, 0.55, 0.76, 1.0. Lightest filled step at least 2:1 on canvas and card; neighbouring steps at least 1.3:1; lightness strictly increasing.
- Grid cells 12 points, gap 3, radius 3, 14 between blocks, at most six blocks in a row (all `.zoomed`).
- Commit subjects are one plain present-tense sentence for any user of the app. Commits stay on this branch; no push, no pull request, no release until the owner asks.

## Review Focus

1. A daylight-saving month and a far-east zone: every block has exactly one cell per calendar day (Task 1 check 6).
2. Midnight passes with History open: yesterday loses the ring, today gains it, a day to come becomes recorded (Task 4 check 3).
3. Ties and zeros: two months with equal focus name no "biggest"; a previous month with no focus gives no change and no division by zero (Task 2 checks 4 and 6).
4. Month edges: a record starting on the 1st, a record of exactly 12 and of 13 months, January carrying the year (Task 1 checks 3 to 5).
5. Every category under 3%, and two neighbours sharing a hue (Task 3 checks 2 and 3).

## Who runs what

| Work | Runner | Why |
|---|---|---|
| Task 0, every build, check and snapshot run | `haiku-runner` (Haiku 5.5) | Mechanical; reports exit code and failing lines only |
| Tasks 1 to 5, 7, 8, and Task 9's fixtures | `sonnet-worker` (Sonnet 5.5, effort xhigh on 1, 2, 4) | Bounded implementation with a stated interface |
| Task 6 | general-purpose agent on Opus 5.5 | Custom layout, hover state and VoiceOver in one view |
| Task 10, snapshot review, adjudication, final verification | main session | Cross-cutting; holds the spec and the conversation |
| Review of Tasks 1, 2, 4 | `fix-reviewer` agent | Repo rule for time arithmetic and session state |
| Review of the whole branch | `code-reviewer` panel (GPT, Gemini, DeepSeek, Nemotron) plus Claude | Multi-file change finished |

Stages, each merged and fully checked before the next starts:

| Stage | Tasks | Together? | Why it is safe |
|---|---|---|---|
| 0 | 0 | alone | Registers every new suite, so no later task edits the registry |
| A | 1, 2, 3 | parallel worktrees | Three new Core files and three suite files; no shared file, no shared type |
| B | 4, 5 | parallel worktrees | 4 owns `SessionStore+HistoryTree.swift`; 5 owns Design and the two shared view pieces; both read Stage A, neither reads the other |
| C | 6, 7 | parallel worktrees | Each owns its own views, words file and suite; both read only Stages A and B |
| D | 8, 9, 10 | in order | 8 is the only task that edits `HistoryTreeColumn.swift` and removes the old card |

A file belongs to one task per stage. Workers in a worktree prove their logic with the compile-only typecheck and a Core probe (`CLAUDE.md`, Runtime probes); the full `./build.sh --check` runs once per stage after the merge, by `haiku-runner`. The new suites sit after every existing check, so existing check numbers never move; the new checks' own numbers settle when the branch is done, and no comment cites them before then.

---

### Task 0: Empty suites, registered

**Files:**
- Create, in `Sources/Verification/`: `HistoryDayGridChecks.swift`, `HistoryRowFactsChecks.swift`, `HistorySplitChecks.swift`, `HistoryFrontStoreChecks.swift`, `FocusRampChecks.swift`, `HistoryGridViewChecks.swift`, `HistoryPeriodRowChecks.swift`, `HistoryFrontViewChecks.swift`
- Modify: `Sources/Verification/SelfTest/SelfTest+Registry.swift` (end of `registeredTests`)

- [ ] **Step 1:** Create each file as `enum <Name>: CheckSuite { static let tests: [(String, () -> [String])] = [] }` with a one-line doc comment.
- [ ] **Step 2:** Append the eight `+ <Name>.tests` lines, in the order above, at the end of `registeredTests`.
- [ ] **Step 3:** Run `./build.sh --check`. Expected: the same pass count as before, exit 0.
- [ ] **Step 4:** Commit: "History's checks have room for its new front view".

### Task 1: The day grid model (Core)

**Files:**
- Create: `Sources/Core/HistoryDayGrid.swift`
- Test: `Sources/Verification/HistoryDayGridChecks.swift`

**Interfaces:**
- Consumes: `HistoryTop`, `HistoryDay`, `HistoryTreeBuilder.period`, `.dayAfter`.
- Produces:

```swift
enum HistoryFocusStep: Int, CaseIterable, Comparable {
    case none, under2h, under5h, under8h, over8h
    static func step(for focused: TimeInterval) -> HistoryFocusStep
}
struct HistoryGridCell: Equatable {
    enum Kind: Equatable { case recorded(HistoryFocusStep), toCome }
    let day: Date            // startOfDay in the grid's calendar
    let focused: TimeInterval
    let kind: Kind
    let isToday: Bool
}
struct HistoryGridBlock: Equatable, Identifiable {
    let month: DateInterval  // the whole calendar month
    let leadingBlanks: Int   // rows above the first cell, Monday = 0
    let cells: [HistoryGridCell]
    let showsYear: Bool
    var id: Date { month.start }
}
struct HistoryDayGrid: Equatable { let blocks: [HistoryGridBlock] }
enum HistoryDayGridBuilder {
    static let maximumMonths = 12
    /// Built from the day index alone, so it can be cached. Today is
    /// `top.today`, in `calendar`. nil when the top is a week or there is
    /// no recorded day.
    static func grid(top: HistoryTop, byDate: [Date: HistoryDay], calendar: Calendar) -> HistoryDayGrid?
    /// The same grid as it stands on `today`: today's cell rebuilt from
    /// `live` (or left as indexed when `live` is nil), `isToday` cleared on
    /// every other cell, and any cell on or before `today` that was still
    /// `.toCome` made `.recorded`. Needs no earlier value: cells are
    /// replaced, not adjusted.
    static func patching(_ grid: HistoryDayGrid, live: HistoryDay?, today: Date, calendar: Calendar) -> HistoryDayGrid
    /// The weekday letter beside each of the seven rows, Monday first:
    /// "M", "", "W", "", "F", "", "".
    static let weekdayLetters: [String]
}
```

- [ ] **Step 1: Write the failing checks** in `HistoryDayGridChecks`:
  1. "A day's shade steps at 2, 5 and 8 hours": `step(for:)` gives `.none` at 0, `.under2h` at 1 and 7_199, `.under5h` at 7_200 and 17_999, `.under8h` at 18_000 and 28_799, `.over8h` at 28_800.
  2. "A record inside one week draws no grid": `grid` is nil for a top of level `.week`; nil for no days.
  3. "The grid starts on the first recorded day and ends with the month": with `HistoryTreeChecks.september` plus a January day, the first block's first cell is the first recorded day, its `leadingBlanks` equals that day's Monday-first weekday index, and no cell precedes it. A record starting on the 1st has a first cell on the 1st.
  4. "A long record draws its last twelve months": 12 months gives 12 blocks, 13 months gives 12, the first block starting on the 1st of its month.
  5. "January and the first block carry the year when the grid spans two years"; no block carries it inside one year.
  6. "A block has one cell for each calendar day": for every block, `cells.count + days before the first cell` equals the month's day count, in `Europe/Berlin` across the March and October changes and in `Pacific/Kiritimati`.
  7. "Days after today wait as days to come": in the current month every cell after today is `.toCome` with focus 0, today is `isToday`, and exactly one cell is.
  8. "A recorded day without focus is shaded none, not left out".
  9. "A running session lifts today's cell without a rebuild": `patching` with a live day of 7_200 turns today's `.under2h` into `.under5h` and changes no other cell.
- [ ] **Step 2:** Typecheck (the `CLAUDE.md` compile-only command). Expected: errors naming the missing types.
- [ ] **Step 3:** Implement `Sources/Core/HistoryDayGrid.swift`. Range: from the month of `max(top.firstDay, first day of the month eleven months before today's)` to today's month. A past month's cells run to its last day; the current month's run to its last day with `.toCome` after today. Step boundaries are half-open as in check 1.
- [ ] **Step 4:** Typecheck, then a Core probe that prints check 1, 4 and 6 outcomes. Expected: all as stated.
- [ ] **Step 5:** Commit: "History can lay its days out as a calendar of months".

### Task 2: Row facts (Core)

**Files:**
- Create: `Sources/Core/HistoryRowFacts.swift`
- Test: `Sources/Verification/HistoryRowFactsChecks.swift`

**Interfaces:**
- Consumes: `HistoryRow`, `HistoryTop`, `HistoryDay`, `HistoryTreeBuilder.period`.
- Produces:

```swift
enum HistoryRowFact: Equatable {
    case recordDay(day: Date, focused: TimeInterval)
    case biggest
    case change(percent: Int, previous: HistoryPlace)   // signed, never 0
    case started(day: Date)
}
struct HistoryRowFacts: Equatable {
    let facts: [HistoryRowFact]   // at most two, in the order above
    let daysLeft: Int?            // the current period only; nil at 0
    static let none = HistoryRowFacts(facts: [], daysLeft: nil)
}
struct HistoryRecord: Equatable {
    let longestDay: Date?; let longestFocus: TimeInterval; let focusedDays: Int
    static func of(byDate: [Date: HistoryDay]) -> HistoryRecord
    func patched(live: HistoryDay?, cachedToday: HistoryDay?, calendar: Calendar) -> HistoryRecord
}
enum HistoryRowFactsBuilder {
    static let recordDayMinimumDays = 14
    static let changeMinimumPercent = 10
    static let biggestMinimumRows = 3
    /// Keyed by `HistoryPlace.id`. Day rows get `.none`.
    static func facts(rows: [HistoryRow], top: HistoryTop, record: HistoryRecord, calendar: Calendar) -> [String: HistoryRowFacts]
}
```

- [ ] **Step 1: Write the failing checks** in `HistoryRowFactsChecks`:
  1. "The month holding the longest day says so": `.recordDay` with that day and its focus, on that row only; the earliest day wins a tie.
  2. "A record under 14 focused days names no longest day".
  3. "The month with the most focus is the biggest, once there are three": present with three rows, absent with two.
  4. "Two months level on focus name no biggest".
  5. "A whole month is compared with the whole month before": October against September gives `.change(percent: 63, …)` for 7_450 against 4_567 units scaled to seconds; a fall gives a negative percent; under 10% gives none.
  6. "A month is not compared with a part month, a month without focus, or while it is still running": no `.change` when the previous row starts on the first recorded day mid-period, when it has no focus, or when the row holds today.
  7. "The month the record starts in says when": `.started(day: top.firstDay)`.
  8. "A row says at most two things, in order": a row that qualifies for record day, biggest and started carries the first two.
  9. "The period still running counts its days left": 15 for a month with today on the 15th of 30; nil on the last day; nil for a finished period.
  10. "A day row says nothing extra".
- [ ] **Step 2:** Typecheck. Expected: errors naming the missing types.
- [ ] **Step 3:** Implement. "Whole" means the row's span equals `HistoryTreeBuilder.period(level, containing: start)`. Percent is `((row - previous) / previous * 100).rounded()`. "Previous" is the next older row in `rows`.
- [ ] **Step 4:** Typecheck and a Core probe for checks 1, 5, 6 and 9. Expected: as stated.
- [ ] **Step 5:** Commit: "History can say what stands out about each month".

### Task 3: Category split (Core)

**Files:**
- Create: `Sources/Core/HistorySplit.swift`
- Test: `Sources/Verification/HistorySplitChecks.swift`

**Interfaces:**
- Consumes: `WorkTypeShare`, `WorkType.hue`.
- Produces:

```swift
struct HistorySplitPart: Equatable, Identifiable {
    let workType: WorkType?   // nil is "Other"
    let share: Double
    let isMuted: Bool         // same hue as the part before it
    var id: String { workType?.rawValue ?? "other" }
}
enum HistorySplit {
    static let otherBelowPercent = 3
    static func parts(_ shares: [WorkTypeShare]) -> [HistorySplitPart]
}
```

- [ ] **Step 1: Write the failing checks** in `HistorySplitChecks`:
  1. "Slivers fold into Other, so no label reads 0%": shares 0.98, 0.008, 0.007, 0.005 give two parts, the second nil with share 0.02; a share of 0.025 (which rounds to 3) is kept and one of 0.024 is folded; the parts still sum to 1.
  2. "The largest category is never folded": fifty equal shares of 0.02 give the first category (in `WorkTypeShare.shares` order) at 0.02 and "Other" at 0.98.
  3. "A category sharing its neighbour's colour is drawn muted": two neighbours with one hue give `isMuted` false then true; a third with the same hue is false again; "Other" is never muted.
  4. "Nothing in, nothing out".
- [ ] **Step 2:** Typecheck. Expected: errors naming the missing types.
- [ ] **Step 3:** Implement. A share folds when `(share * 100).rounded() < 3`, except the first share, which is always kept. "Other" comes last and is omitted when nothing folds.
- [ ] **Step 4:** Typecheck and a Core probe for checks 1 to 3.
- [ ] **Step 5:** Commit: "A month's categories no longer list ones that round to nothing".

### Task 4: Read models on the store (App)

**Files:**
- Modify: `Sources/App/SessionStore+HistoryTree.swift` (120 lines now; the three methods go in this file, so `tree()` and `liveToday` stay `private` and nothing outside the file can reach them)
- Test: `Sources/Verification/HistoryFrontStoreChecks.swift`

**Interfaces:**
- Consumes: Tasks 1 to 3; the existing `historyTreeComputeCount`, `HistoryTreeCache`, `historyRows(under:)`.
- Produces, on `SessionStore`:

```swift
func historyDayGrid() -> HistoryDayGrid?
func historyRowFacts() -> [String: HistoryRowFacts]      // for the root rows, keyed by place id
func historySplit(for place: HistoryPlace) -> [HistorySplitPart]
```

`HistoryTreeCache` gains: `gridBuilt: Bool` with `grid: HistoryDayGrid?` (built without today's live figures); `record: HistoryRecord?`; `categories: [String: [WorkType: TimeInterval]]` keyed by place id, holding each place's seconds by category with today left out.

- [ ] **Step 1: Write the failing checks** (store built as `HistoryLivePatchChecks` builds its own, inside `MainActor.assumeIsolated`):
  1. "The front view is worked out once, not on every redraw": read `historyDayGrid()`, `historyRowFacts()` and `historySplit(for:)` for every root row once; then ten more rounds of the same reads raise `historyTreeComputeCount` by exactly 0.
  2. "A running session lifts today's cell, its month's split and its facts without a rebuild": after the clock advances inside a session, today's cell focus, the current row's split and the record's longest day all move, and the compute count does not.
  3. "At midnight the ring moves to the new day": advancing `TestClock` past midnight gives exactly one `isToday` cell, on the new day, and yesterday's cell is `.recorded`.
  4. "A month's split agrees with its figure": `historySplit(for:)` shares sum to 1 for a row with focus, are empty for one without, and equal `HistorySplit.parts(historyCategories(for:))` for every root row.
- [ ] **Step 2:** `./build.sh --check`. Expected: the four new checks fail to compile or fail.
- [ ] **Step 3:** Implement. Each cache miss raises `historyTreeComputeCount`, as the rows do. The grid, the record and each place's category seconds are cached without today and patched from `liveToday` on read. Facts come from the already patched root rows and the patched record on each read: one pass over at most a few dozen rows, no walk over days. `historyCategories(for:)` keeps its signature and result; it may read the same cache.
- [ ] **Step 4:** `./build.sh --check`. Expected: all pass, including every existing History check.
- [ ] **Step 5:** Run the `fix-reviewer` agent on Tasks 1, 2 and 4. Fix what it confirms.
- [ ] **Step 6:** Commit: "History keeps its new front view current while a session runs".

### Task 5: The focus ramp and the shared view pieces

**Files:**
- Create: `Sources/Design/FocusRamp.swift`, `Sources/Surfaces/History/HistoryGridLink.swift`
- Modify: the file that declares `StoryRenderEvidence` (add `case historyGrid`, beside `historyTree`)
- Test: `Sources/Verification/FocusRampChecks.swift`

**Interfaces:**
- Consumes: `HistoryFocusStep` from Task 1 (merged in Stage A), `Tokens.Colour.focus`, `StoryStyle.canvas`, `StoryStyle.card`.
- Produces:

```swift
enum FocusRamp {
    static func strength(_ step: HistoryFocusStep, dark: Bool) -> Double   // 0 for .none
    static func fill(_ step: HistoryFocusStep) -> Color                   // follows the appearance
    static var none: Color
    static var toCome: Color   // the outline of a day to come
}
/// What the pointer has picked out, shared by the grid and the rows.
final class HistoryGridLink: ObservableObject {
    @Published var span: DateInterval?   // cells inside stay at full strength
    @Published var day: Date?            // the cell the readout describes
}
// StoryRenderEvidence.historyGrid
```

- [ ] **Step 1: Write the failing checks**, reusing the contrast helper `SupportingInkChecks` uses:
  1. "Every shade of focus can be told from the page": the lightest filled step is at least 2.0:1 on canvas and on card, light and dark.
  2. "Each shade is clearly darker than the one before": neighbours at least 1.3:1, lightness strictly increasing, on both surfaces and appearances.
- [ ] **Step 2:** Typecheck. Expected: errors naming `FocusRamp`.
- [ ] **Step 3:** Implement with the strengths in Global Constraints.
- [ ] **Step 4:** Typecheck. Expected: clean.
- [ ] **Step 5:** Commit: "Focus has five shades that read in light and dark".

### Task 6: The grid view (Surfaces)

**Files:**
- Create: `Sources/Surfaces/History/HistoryDayGridView.swift`, `Sources/Surfaces/History/HistoryGridWords.swift`
- Test: `Sources/Verification/HistoryGridViewChecks.swift`

**Interfaces:**
- Consumes: `HistoryDayGrid`, `HistoryDayGridBuilder.weekdayLetters` (Task 1); `FocusRamp`, `HistoryGridLink`, `StoryRenderEvidence.historyGrid` (Task 5). Nothing from Task 7.
- Produces:

```swift
struct HistoryDayGridView: View {
    let grid: HistoryDayGrid
    @ObservedObject var link: HistoryGridLink
    let focusedSpan: DateInterval?       // the row keyboard focus is on
    let onPickDay: (Date) -> Void
    let onPickMonth: (DateInterval) -> Void
    static func rows(blockWidths: [CGFloat], fitting width: CGFloat, gap: CGFloat, mostPerRow: Int) -> [Range<Int>]
    /// Whether a drawn day is lowered: only when `span` holds at least one
    /// drawn day of the grid and this day is outside it.
    static func isDimmed(_ day: Date, by span: DateInterval?, in grid: HistoryDayGrid) -> Bool
}
enum HistoryGridWords {   // in HistoryGridWords.swift
    static func readout(_ cell: HistoryGridCell, calendar: Calendar) -> String
    static func spokenDay(_ cell: HistoryGridCell, calendar: Calendar) -> String
    /// A block's VoiceOver value, from its own cells: "61 hours 10 minutes across 9 days".
    static func blockValue(_ block: HistoryGridBlock) -> String
    static func blockLabel(_ block: HistoryGridBlock, calendar: Calendar) -> String   // "November 2026"
    static let legend: [(HistoryFocusStep?, String)]   // nil is "still to come"
}
```

- [ ] **Step 1: Write the failing checks**:
  1. "The readout names the day and its focus": "Thu 12 Nov · 9h 20m"; "Sun 15 Nov (today) · 1h 5m so far"; "Sun 15 Nov (today) · no focus yet"; "Mon 2 Nov · no focus"; "Mon 16 Nov · still to come".
  2. "The legend states its steps in hours": "none", "under 2h", "2 to 5h", "5 to 8h", "8h or more", "still to come", in that order.
  3. "Month blocks wrap by whole months, six to a row": twelve equal blocks at a width fitting seven give 0..<6 and 6..<12; at a width fitting four give three rows of four; a width narrower than one block still gives one block per row.
  4. "A block speaks its month, its total and each recorded day": `blockLabel` "November 2026"; `blockValue` "61 hours 10 minutes across 9 days"; `spokenDay` "Thursday 12 November, 9 hours 20 minutes"; a day to come has no spoken child.
  5. "Weekday letters sit beside the first row of months only": the rendered view carries M, W and F once each for a twelve-block grid.
  6. "The grid draws inside its column at 980 and at 160% zoom": `drawnBox`, as `ComponentEdgeChecks` uses, stays within the offered width, and the view carries `.historyGrid` evidence.
  7. "A period with no days in the grid dims nothing": `isDimmed` is false for every day when the span is nil, and when it is a year that ended before the grid's first block; with October's span it is true for a November day and false for an October day.
- [ ] **Step 2:** `./build.sh --check`. Expected: the seven fail.
- [ ] **Step 3:** Implement. Layout per the spec, section 2, with weekday letters left of the first row of blocks in the caption role. A cell for which `isDimmed(day, by: link.span ?? focusedSpan, in: grid)` holds drops to 40% with `Tokens.Motion.hover`, without animation under Reduce Motion; month labels keep full strength. Pointing at a cell sets `link.day`; pointing at a block or its label sets `link.span` to the block's month. Each block is one accessibility element (`blockLabel`, `blockValue`) whose children are one button per recorded day (`spokenDay`, `onPickDay`). No `.help` on cells. Today's ring is the primary ink. Increase Contrast adds a hairline to filled cells. The legend and the fixed-height readout sit under the grid; at rest the readout describes today.
- [ ] **Step 4:** `./build.sh --check`. Expected: all pass.
- [ ] **Step 5:** Commit: "History shows every day at a glance, month by month".

### Task 7: The period row (Surfaces)

**Files:**
- Create: `Sources/Surfaces/History/HistoryPeriodRow.swift`, `Sources/Surfaces/History/HistorySplitBar.swift`, `Sources/Surfaces/History/HistoryRowWords.swift`
- Modify: `Sources/Surfaces/History/HistoryTreeRow.swift` (`isCard` and `header`, lines 134 to 147; the `children` padding; `spoken`, lines 48 to 67, for depth 0 only). `HistoryRowText` moves to `HistoryRowWords.swift` unchanged apart from the additions, which brings `HistoryTreeRow.swift` under 200 lines.
- Modify: `Sources/Verification/HistoryOverviewChecks.swift` (both checks rewritten in place, same count, same order)
- Test: `Sources/Verification/HistoryPeriodRowChecks.swift`
- Not touched here: `HistoryPeriodCard.swift` (Task 8 removes it), `HistoryTreeColumn.swift`, `CategoryShareBar`, the rail.

**Interfaces:**
- Consumes: `HistoryRowFacts` (Task 2), `HistorySplitPart` (Task 3), `store.historyRowFacts()`, `store.historySplit(for:)` (Task 4). Nothing from Task 6.
- Produces:

```swift
extension HistoryRowText {
    static func gutter(_ place: HistoryPlace, calendar: Calendar) -> String        // "Nov", "2026", "9 to 15"
    static func sentence(_ row: HistoryRow, today: Date) -> (figure: String?, rest: String)
    static func detail(_ facts: HistoryRowFacts, row: HistoryRow, calendar: Calendar) -> String?
}
struct HistoryPeriodRow: View {   // the label of the row's existing Button
    @ObservedObject var store: SessionStore
    let row: HistoryRow; let facts: HistoryRowFacts
    let isCurrent: Bool; let isOpen: Bool; let isFocused: Bool
    /// The gutter beside the spine for a root level: 0 for days,
    /// 56 for weeks, 32 for months, 36 for years (`.zoomed`).
    static func gutterWidth(for level: HistoryLevel) -> CGFloat
}
struct HistorySplitBar: View { let parts: [HistorySplitPart] }
```

- [ ] **Step 1: Write the failing checks**:
  1. "A month says its focus and its days in one sentence": ("61h 10m", "across 9 days so far.") for the current row; ("74h 30m", "across 14 days."); "across one day."; (nil, "Nothing focused.") for evidence without focus; (nil, "Nothing recorded.") for an empty row; (nil, the existing "Recorded app use only · …" words) for app use only.
  2. "The second line is built only from facts": "Thu 12 Nov was your longest day yet, at 9h 20m. 15 days left."; "Your biggest month so far, up 63% on September."; "Down 20% on September."; "You started on 13 Aug."; "1 day left."; nil for `.none`.
  3. "The gutter names the period briefly": "Nov", "2026", "9 to 15"; `gutterWidth(for: .day)` is 0.
  4. "VoiceOver reads a top month as the screen does": `spoken` at depth 0 gives "November 2026, 61 hours 10 minutes across 9 days so far, month, level 1, collapsed".
  5. "Rows below the first view read exactly as before": for a week at depth 1 and a day at depth 2 from `HistoryTreeChecks.september`, `title`, `facts` and `spoken` equal the literal strings they return on `main` (captured before the change and pasted into the check).
  6. "A first week keeps its day rows": with a top of level `.week`, a depth-0 day row draws the plain header, with no gutter and no card.
  7. `HistoryOverviewChecks`, in place: "Only the period holding today is drawn as a card" and "A row's second line names no figure the record does not hold".
- [ ] **Step 2:** `./build.sh --check`. Expected: these fail.
- [ ] **Step 3:** Implement. At depth 0, a week, month or year row draws an `HStack` of the gutter label (`gutterWidth(for:)`, right-aligned, body role, supporting ink) and `HistoryPeriodRow`; its children are padded by the same gutter width, so their spine still hangs under the row's dot. A day row at any depth, and every row below depth 0, keeps `plainHeader` untouched. `isCurrent` is `row.place.span.holds(top.today)`: the card (`StoryStyle.card`, `entryRadius`, `entryInsets`, hairline, the existing open and focus treatment). Other rows have no fill or border and keep the hover tint. The figure uses the ink `StoryHeadline` uses for its highlight. The dot keeps `dotColour`. `HistorySplitBar` draws a muted part at 55% of its category colour and "Other" in `Tokens.Palette.warmGrey`, with labels laid out as `CategoryShareBar`'s are. The current row keeps `.storyRenderEvidence(.historySoFar)` on its sentence.
- [ ] **Step 4:** `./build.sh --check`. Expected: all pass.
- [ ] **Step 5:** Commit: "History's months read as a timeline, with the current one as its card".

### Task 8: Wiring (Surfaces)

**Files:**
- Modify: `Sources/Surfaces/History/HistoryTreeColumn.swift:133-164` (`overviewChart` becomes the grid; the root spine's leading padding adds `HistoryPeriodRow.gutterWidth(for: top.rootLevel)`)
- Modify: `Sources/Surfaces/History/HistoryTreeRow.swift` (every row sets `link.span` to its place's span while the pointer is over it)
- Delete: `Sources/Surfaces/History/HistoryPeriodCard.swift`, with `trashmv`, once the typecheck shows nothing reads it
- Test: `Sources/Verification/HistoryFrontViewChecks.swift`

**Interfaces:**
- Consumes: Tasks 4 to 7; `navigation.openHistory(day:)`, `navigation.toggleHistory(_:)`, `navigation.historyFocus`.

- [ ] **Step 1: Write the failing checks**:
  1. "A search or filter shows results, not the grid": with `historyFilter.isActive` the column renders no `.historyGrid` evidence; without it, it does.
  2. "Clicking a month's name opens that month": `onPickMonth` opens the place whose span is that month clipped to the record, through `navigation.openHistory(place:)`.
  3. "A first week shows no grid": a top of level `.week` renders `.historyTree` and no `.historyGrid`.
  4. "The spine meets the dots at every root level": the root spine's leading offset equals the gutter width plus the dot's centre for week, month and year tops, and the dot's centre alone for a week top's day rows.
- [ ] **Step 2:** `./build.sh --check`. Expected: these fail.
- [ ] **Step 3:** Implement. `HistoryTree` owns one `@StateObject HistoryGridLink`, handed to the grid and the rows. `focusedSpan` is the span of `navigation.historyFocus` when it is a row. `HistoryResultChart` stays for search results; only the overview stops using it.
- [ ] **Step 4:** `./build.sh --check`, then `TZ=Europe/Berlin ./build.sh --check`. Expected: all pass in both.
- [ ] **Step 5:** Commit: "History opens on a headline, a calendar of days and a timeline of months".

### Task 9: Fixtures and snapshots

**Files:**
- Modify: `Sources/Surfaces/Snapshotter.swift` (scenarios `historyFrontMonths`, `historyFrontYears`, `historyFrontMonth`), `Sources/Surfaces/GalleryView.swift` (fixture days for them)

- [ ] **Step 1:** Add the three scenarios: four months inside one year with two categories sharing a hue and one under 3%; fourteen months across two years; one month. All from `SelfTest.base`-style relative dates. The first-week state is the existing `historySparse` scenario ("three recorded days"), which must look as it does today.
- [ ] **Step 2:** Run `--snapshot` for the History scenarios, light and dark, at 980 and 1,160 points, into a scratch folder. Expected: an image per scenario, appearance and width.
- [ ] **Step 3:** Commit: "History's new front view has fixtures for a month, a year and longer".

### Task 10: Review, documents, verification

**Files:**
- Modify: `DESIGN.md:46-55` (focus identity, to match the code), `:72-76` (History journal), `:85-87` (calendar)

- [ ] **Step 1:** Main session reads every snapshot against the spec and `mac-design`'s `design-rules.md`: alignment of gutter, spine and dots; no clipped text; nothing under 10 points; both appearances; the 980 width.
- [ ] **Step 2:** Fix what the review finds; re-run the affected snapshots.
- [ ] **Step 3:** Prove the new checks bite: in a scratch copy (`CLAUDE.md`, Runtime probes) apply each of four mutations in turn and run `./build.sh --check`: the 2h boundary to `<=`, the change floor to 0, the Other floor to 0, the card rule back to `depth == 0`. Expected: each fails a named check.
- [ ] **Step 4:** Update `DESIGN.md` to what is now built.
- [ ] **Step 5:** `./build.sh --check`, then with `TZ=Europe/Berlin` and `TZ=Pacific/Kiritimati`. Expected: all pass in all three.
- [ ] **Step 6:** `code-reviewer` panel on the branch diff; adopt or reject each point in a table.
- [ ] **Step 7:** superpowers:verification-before-completion, then commit: "Daybook's design notes describe History's new front view".
