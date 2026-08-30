# FocusContinuity Premium Interface Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Make every FocusContinuity surface coherent, legible and native-feeling while fixing Review's implicit cross-tab navigation, chart clipping, History controls and History table hierarchy.

**Architecture:** Preserve Core → App → Design/Surfaces. Core supplies pure canonical records and small layout helpers; App owns Review selection and routes; Design owns tokens and repeatable visual grammar; Surfaces compose controls and read models without recalculating time. Review becomes a stable workbench: selection stays in Review, then an explicit action opens Today.

**Tech Stack:** Swift 5 language mode, Swift 6.4 compiler, SwiftUI, AppKit, Charts, macOS 13+, direct swiftc, no packages or Xcode project.

**Spec:** docs/superpowers/specs/2026-08-30-premium-interface-design-system.md

## Global Constraints

- Work in the repository's main checkout and keep every commit local until the user explicitly authorises a push.
- Preserve macOS 13, direct swiftc, warnings-as-errors, one existing repeating ticker, no packages, network services, accounts, telemetry, third-party fonts, or new TCC permission.
- Preserve canonical Focused, Tracked/At the Mac, break, Watching, pending-overlay, local-calendar, legacy-accuracy, and historical-record semantics.
- Keep Core free of SwiftUI. Views never read archives directly or perform accounting.
- Use existing dynamic colour tokens, system fonts, SF Symbols, Australian English, practical hit targets, light/dark appearances, Reduce Motion and literal accessibility labels.
- Do not rewrite historical records or mask accuracy qualifications for presentation.
- Tests use suite-scoped defaults and temporary directories. Do not touch live user history.
- Generated bundles, snapshots and Finder metadata stay ignored and uncommitted.
- Each task is test-first, ends with ./build.sh --check, git diff --check, and a local commit containing only that task's files.

## File map

| File | Responsibility after this work |
|---|---|
| Sources/App/MainWindowModel.swift | Top-level route plus selected Review day; the sole place an explicit Review-to-Today route is initiated. |
| Sources/App/SessionStore+Review.swift | Canonical Review-derived day detail and selection validity after period/filter changes. |
| Sources/Core/PeriodStats.swift | Pure chart-domain helper based on canonical PeriodChartPoint dates. |
| Sources/Design/Components/SurfacePrimitives.swift | Shared table header and metric grammar where reuse is genuine. |
| Sources/Surfaces/Dashboard/PeriodViews.swift | Non-clipping tracked-time chart, leading y-axis, selected-bar state and accessible chart content. |
| Sources/Surfaces/Review/ReviewView.swift | Review workbench hierarchy, inline selected-day detail and explicit Today action. |
| Sources/Surfaces/Review/HistoryView.swift | Compact range summary/popover and one labelled History table header. |
| Sources/Surfaces/Review/ReviewDayDetail.swift | Inline detail composition only; it receives a canonical read model. |
| Sources/Surfaces/Insights/InsightSection.swift | Short finding first; expandable calculation provenance. |
| Sources/Surfaces/Today/TodayRecap.swift | Day recap uses shared metric grammar and avoids repetitive visual noise. |
| Sources/Surfaces/Focus/FocusView.swift | Operational canvas remains purposefully narrow and avoids report-style decoration. |
| Sources/Surfaces/Settings/SettingsView.swift | Native-feeling configuration measure and deliberate whitespace at wide/narrow sizes. |
| Sources/SelfTest.swift | Pure route, selection, chart-domain, range-summary, table, and source-of-truth regressions. |
| Sources/Surfaces/Snapshotter.swift | Material Review-selection and History scenarios in the visual matrix. |

---

### Task 1: Keep Review selection in Review

**Files:**

- Modify: Sources/App/MainWindowModel.swift:88-117
- Modify: Sources/Surfaces/Review/ReviewView.swift:3-15
- Modify: Sources/SelfTest.swift:7164-7180 and 7637-7653

**Interfaces:**

- Produces:

~~~
@MainActor final class MainWindowModel: ObservableObject {
    @Published var selectedTab: AppTab
    @Published private(set) var requestedDate: Date?
    @Published private(set) var reviewSelectedDate: Date?

    func selectReviewDay(_ date: Date, calendar: Calendar = .current)
    func clearReviewDay()
    func openSelectedReviewDayInToday()
}

@MainActor enum ReviewDayRoute {
    static func select(store: SessionStore,
                       navigation: MainWindowModel) -> (Date) -> Void
}
~~~

- selectReviewDay stores calendar.startOfDay(for: date), changes no tab, and leaves requestedDate unchanged.
- openSelectedReviewDayInToday calls openToday(date:) only when a selected Review day exists.

- [ ] **Step 1: Write failing route tests**

Replace the existing assertion that expects a Review bar to route to Today:

~~~
let navigation = MainWindowModel(selectedTab: .review)
navigation.selectReviewDay(yesterday, calendar: calendar)
expect(navigation.selectedTab == .review,
       "selecting a Review day keeps Review selected", &problems)
expect(calendar.isDate(navigation.reviewSelectedDate ?? base,
                       inSameDayAs: yesterday),
       "Review stores the literal selected local day", &problems)
expect(navigation.requestedDate == nil,
       "Review selection does not change Today scope", &problems)
navigation.openSelectedReviewDayInToday()
expect(navigation.selectedTab == .today && navigation.requestedDate == yesterday,
       "only the explicit Review action opens the selected day in Today", &problems)
~~~

Call ReviewDayRoute.select(store:navigation:) in the period-bar fixture and assert the store's selected Today date remains unchanged.

- [ ] **Step 2: Run the test to verify RED**

Run:

~~~bash
./build.sh --check
~~~

Expected: the new model APIs are missing and the old callback still changes selectedTab to Today.

- [ ] **Step 3: Implement the narrow navigation state**

Add this behaviour to MainWindowModel:

~~~
func selectReviewDay(_ date: Date, calendar: Calendar = .current) {
    reviewSelectedDate = calendar.startOfDay(for: date)
}

func clearReviewDay() {
    reviewSelectedDate = nil
}

func openSelectedReviewDayInToday() {
    guard let reviewSelectedDate else { return }
    openToday(date: reviewSelectedDate)
}
~~~

Replace ReviewDayRoute.callback with ReviewDayRoute.select. It calls navigation.selectReviewDay(date), and must not call store.selectDate(date) or navigation.openToday(date:).

- [ ] **Step 4: Run the full suite to verify GREEN**

~~~bash
./build.sh --check
git diff --check
~~~

Expected: every self-test passes and Review selection no longer changes the active tab.

- [ ] **Step 5: Commit locally**

~~~bash
git add Sources/App/MainWindowModel.swift Sources/Surfaces/Review/ReviewView.swift Sources/SelfTest.swift
git commit -m "fix: keep Review day selection in context"
~~~

### Task 2: Publish canonical inline Review-day detail

**Files:**

- Modify: Sources/App/SessionStore+Review.swift:1-345
- Create: Sources/Surfaces/Review/ReviewDayDetail.swift
- Modify: Sources/Surfaces/Review/ReviewView.swift
- Modify: Sources/SelfTest.swift

**Interfaces:**

- Produces:

~~~
struct ReviewDayDetail: Equatable {
    let day: HistoryDay
    let periodDay: PeriodDay?
    let appEntries: [LogEntry]
    let focusEntries: [ReviewFocusEntry]
}

extension SessionStore {
    func reviewDayDetail(for date: Date,
                         calendar: Calendar = .current) -> ReviewDayDetail?
    func reviewDayIsAvailable(_ date: Date,
                              section: ReviewSection,
                              calendar: Calendar = .current) -> Bool
}

struct ReviewDayDetailPanel: View {
    let detail: ReviewDayDetail
    let onOpenInToday: () -> Void
    let onClose: () -> Void
}
~~~

- ReviewDayDetail derives from existing historyDays, reviewDays, reviewLog, and reviewFocusSessions. It never reads an archive from a View or mutates records.
- A selected day is valid for Week/Month when it is in reviewDays; it is valid for History when it is in filteredHistoryDays.

- [ ] **Step 1: Write failing canonical-detail tests**

Create a fixture with app usage, a focus stretch and a break on yesterday, then derive its local-day end:

~~~
let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: yesterday)!
guard let detail = store.reviewDayDetail(for: yesterday, calendar: calendar) else {
    return problems + ["selected Review day should derive a detail"]
}
expect(detail.day.date == yesterday, "detail keeps the literal day", &problems)
expectClose(detail.day.tracked, 45 * 60,
            "detail uses canonical History tracked time", &problems)
expect(detail.appEntries.allSatisfy { $0.day == yesterday },
       "detail log contains only the selected local day", &problems)
expect(detail.focusEntries.allSatisfy { $0.start < endOfYesterday && $0.end > yesterday },
       "detail focus rows intersect the selected local day", &problems)
expect(!store.reviewDayIsAvailable(twoDaysAgo, section: .week, calendar: calendar),
       "a day outside the selected period is unavailable", &problems)
~~~

- [ ] **Step 2: Run the test to verify RED**

~~~bash
./build.sh --check
~~~

Expected: ReviewDayDetail and the detail/availability APIs do not exist.

- [ ] **Step 3: Implement the App read model**

Define ReviewDayDetail beside ReviewFocusEntry. Normalise the input with calendar.startOfDay(for:), locate HistoryDay, filter reviewLog by entry.day, and filter reviewFocusSessions by interval intersection with the local day.

Do not recompute tracked/focused values from entries. detail.day is the displayed source of truth. Return nil when no canonical HistoryDay exists.

- [ ] **Step 4: Implement a side-effect-free panel**

Create ReviewDayDetailPanel with:

~~~text
Selected date and close button
Tracked | Focused | Sessions metric band
Selected-day app and focus-session evidence, grouped and bounded
[Open in Today]
~~~

Use SurfacePanel, existing AppUsageRow, Tokens.duration, and Tokens.preciseDuration. The Open-in-Today and close controls are separate Buttons. No row action may call either closure.

- [ ] **Step 5: Clear stale selection**

In ReviewView, clear navigation.reviewSelectedDate when the changed section, period, or History filter makes it unavailable. Do not clear an available date merely because Review refreshes.

- [ ] **Step 6: Verify GREEN and commit locally**

~~~bash
./build.sh --check
git diff --check
git add Sources/App/SessionStore.swift Sources/App/SessionStore+Review.swift \
        Sources/Surfaces/Review/ReviewDayDetail.swift Sources/Surfaces/Review/ReviewView.swift \
        Sources/SelfTest.swift
git commit -m "feat: show selected Review day inline"
~~~

### Task 3: Make period charts non-clipping, legible and selectable

**Files:**

- Modify: Sources/Core/PeriodStats.swift:16-42
- Modify: Sources/Surfaces/Dashboard/PeriodViews.swift:87-225
- Modify: Sources/Surfaces/Review/ReviewView.swift:91-104
- Modify: Sources/SelfTest.swift

**Interfaces:**

- Produces:

~~~
enum PeriodChartLayout {
    static func domain(for points: [PeriodChartPoint],
                       calendar: Calendar = .current) -> ClosedRange<Date>
}

struct PeriodChart: View {
    let days: [PeriodDay]
    let average: TimeInterval
    var selectedDay: Date?
    var onPickDay: ((Date) -> Void)?
}
~~~

- The domain has one whole local calendar-day of padding on each side of the first/last point.
- The y-axis is explicitly leading, uses minutes, and begins at zero.

- [ ] **Step 1: Write failing chart-layout tests**

~~~
let first = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!
let last = calendar.date(byAdding: .day, value: 6, to: first)!
let domain = PeriodChartLayout.domain(for: [
    PeriodChartPoint(date: first, seconds: 60),
    PeriodChartPoint(date: last, seconds: 3_600)
], calendar: calendar)
expect(domain.lowerBound <= calendar.date(byAdding: .day, value: -1, to: first)!,
       "chart reserves a full leading bar width", &problems)
expect(domain.upperBound >= calendar.date(byAdding: .day, value: 1, to: last)!,
       "chart reserves a full trailing bar width", &problems)
~~~

Retain the existing accessibility test that names each literal date and exact tracked duration.

- [ ] **Step 2: Run the test to verify RED**

~~~bash
./build.sh --check
~~~

Expected: PeriodChartLayout is absent.

- [ ] **Step 3: Implement the pure domain helper**

Add PeriodChartLayout to PeriodStats.swift. Use calendar.startOfDay(for:) and calendar.date(byAdding: .day, value: ...). Do not add a fixed 86,400-second interval, because local daylight-saving days can differ from 24 hours.

- [ ] **Step 4: Make axes and selected-bar state explicit**

In PeriodViews.swift apply:

~~~
.chartXScale(domain: PeriodChartLayout.domain(for: trackedPoints))
.chartYScale(domain: 0...max(1, yMaximum))
.chartYAxis {
    AxisMarks(position: .leading) {
        AxisGridLine().foregroundStyle(Tokens.Colour.line)
        AxisTick().foregroundStyle(Tokens.Colour.line)
        AxisValueLabel().foregroundStyle(.secondary)
    }
}
~~~

Compute yMaximum from bars and average, rounded to a readable minute scale. Give the selected bar a restrained focus-colour/opacity distinction while retaining exact tracked-time encoding. Keep hover and VoiceOver content; do not create a trailing y-axis or crop the final mark.

- [ ] **Step 5: Wire the Review selection**

Pass navigation.reviewSelectedDate and ReviewDayRoute.select(store:navigation:) to PeriodChart. Selection must not call openToday.

- [ ] **Step 6: Verify GREEN and commit locally**

~~~bash
./build.sh --check
git diff --check
git add Sources/Core/PeriodStats.swift Sources/Surfaces/Dashboard/PeriodViews.swift \
        Sources/Surfaces/Review/ReviewView.swift Sources/SelfTest.swift
git commit -m "fix: make Review charts readable at their edges"
~~~

### Task 4: Replace History steppers with a contained range control and real table header

**Files:**

- Modify: Sources/Surfaces/Review/HistoryView.swift:1-347
- Modify: Sources/Design/Components/SurfacePrimitives.swift
- Modify: Sources/SelfTest.swift

**Interfaces:**

- Produces:

~~~
struct HistoryRangePresentation: Equatable {
    let label: String
    let accessibilityLabel: String

    init(start: Date, end: Date, calendar: Calendar = .current)
}

struct HistoryRangeControl: View {
    @Binding var start: Date
    @Binding var end: Date
    let bounds: ClosedRange<Date>
    let onReset: () -> Void
}

enum HistoryTableLayout {
    static let trackedWidth: CGFloat = 88
    static let focusedWidth: CGFloat = 88
    static let sessionWidth: CGFloat = 72
}

struct TableColumnHeader: View {
    let title: String
    let width: CGFloat?
    let alignment: Alignment
}
~~~

- The existing HistoryNativeDatePicker may remain as the keyboard/VoiceOver control inside the popover, but it is no longer permanently visible with stepper arrows.
- HistoryRangePresentation normalises reversed dates for display only and formats a concise Australian-English label.

- [ ] **Step 1: Write failing range/table tests**

~~~
let startDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))!
let endDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!
let range = HistoryRangePresentation(start: endDate, end: startDate, calendar: calendar)
expect(range.label == "12 Aug – 30 Aug 2026",
       "History range label sorts displayed endpoints", &problems)
expect(range.accessibilityLabel.contains("from Thursday 12 August 2026"),
       "History range exposes literal endpoints", &problems)
expect(HistoryTableLayout.trackedWidth >= 76 && HistoryTableLayout.sessionWidth >= 60,
       "History numeric columns remain scanable", &problems)
~~~

- [ ] **Step 2: Run the test to verify RED**

~~~bash
./build.sh --check
~~~

Expected: the range presentation and table layout APIs do not exist.

- [ ] **Step 3: Implement the compact range summary**

Replace permanent From/To steppers with one capsule or borderless button labelled by HistoryRangePresentation. Its popover contains All dates, two labelled native date pickers and one accessible range label. It uses existing bounds and bindings; filteredHistoryDays keeps its existing order normalisation.

Keep search, app and work-type filters in the same group. Use ViewThatFits to stack only when controls cannot fit at 980 points.

- [ ] **Step 4: Implement History table anatomy**

Add one header before filteredHistoryDays:

~~~text
Day and context                         Tracked     Focused    Sessions
~~~

Use HistoryTableLayout widths for both header and body. Remove HistoryMetric's per-row labels; it displays only right-aligned values. Preserve full VoiceOver row wording, selected state and chevron disclosure. The row action calls ReviewDayRoute.select, not Today navigation.

- [ ] **Step 5: Verify GREEN and commit locally**

~~~bash
./build.sh --check
git diff --check
git add Sources/Surfaces/Review/HistoryView.swift Sources/Design/Components/SurfacePrimitives.swift \
        Sources/SelfTest.swift
git commit -m "ui: clarify History filters and day rows"
~~~

### Task 5: Recompose Review into a readable analytical sequence

**Files:**

- Modify: Sources/Surfaces/Review/ReviewView.swift:17-344
- Modify: Sources/Surfaces/Review/ReviewDayDetail.swift
- Modify: Sources/Surfaces/Review/HistoryView.swift
- Modify: Sources/Surfaces/Snapshotter.swift
- Modify: Sources/SelfTest.swift

**Interfaces:**

- Produces:

~~~
enum ReviewContentOrder: CaseIterable {
    case periodNavigation, summary, trend, selectedDetail, breakdowns, evidenceLists

    static func visible(selectedDay: Date?) -> [ReviewContentOrder]
}
~~~

- Review uses the invariant order: header/period navigation, period answer, trend, optional selected-day detail, supporting breakdowns, bounded evidence lists.

- [ ] **Step 1: Write failing hierarchy tests**

~~~
expect(ReviewContentOrder.visible(selectedDay: nil) == [
    .periodNavigation, .summary, .trend, .breakdowns, .evidenceLists
], "Review omits selected detail until a day is chosen", &problems)
expect(Array(ReviewContentOrder.visible(selectedDay: yesterday).prefix(4)) == [
    .periodNavigation, .summary, .trend, .selectedDetail
], "Review explains the selected day directly after its trend", &problems)
~~~

Add a route regression asserting that only ReviewDayDetailPanel's Open-in-Today closure may alter MainWindowModel.selectedTab.

- [ ] **Step 2: Run the test to verify RED**

~~~bash
./build.sh --check
~~~

Expected: ReviewContentOrder is undefined and the canvas still has the previous fixed order.

- [ ] **Step 3: Implement the period answer and detail placement**

Move periodSummary before Tracked by day. Render valid selected detail immediately after PeriodChart. Do not duplicate the selected day's raw log again in the full period log.

Keep Top apps and Work type after selected detail. Keep Focus sessions and App usage after those supporting breakdowns. Every bounded list states its shown and total count.

- [ ] **Step 4: Make History use the same selection contract**

History renders ReviewDayDetailPanel immediately beneath its selected row, or beneath the Days header if filtering moves the selected row. The title, close and Open-in-Today controls must be identical to a chart selection.

- [ ] **Step 5: Add visual scenarios**

Extend Snapshotter with Review Week and History-selection fixtures. Select the first and last chart dates so snapshot inspection catches both edge and inline-detail regressions.

- [ ] **Step 6: Verify GREEN and commit locally**

~~~bash
./build.sh --check
git diff --check
git add Sources/Surfaces/Review/ReviewView.swift Sources/Surfaces/Review/ReviewDayDetail.swift \
        Sources/Surfaces/Review/HistoryView.swift Sources/Surfaces/Snapshotter.swift \
        Sources/SelfTest.swift
git commit -m "ui: organise Review around selected evidence"
~~~

### Task 6: Apply evidence hierarchy to Today and Focus

**Files:**

- Modify: Sources/Surfaces/Today/TodayView.swift:26-121
- Modify: Sources/Surfaces/Today/TodayRecap.swift:1-77
- Modify: Sources/Surfaces/Focus/FocusView.swift:4-54
- Modify: Sources/Design/Components/SurfacePrimitives.swift
- Modify: Sources/SelfTest.swift

**Interfaces:**

- Produces:

~~~
enum DaySurfaceOrder: CaseIterable {
    case header, qualification, timeline, selectedDetail, supportingGroups, recap

    static func visible(hasQualification: Bool, hasSelection: Bool) -> [DaySurfaceOrder]
}

enum FocusSurfaceLayout {
    static let operationalMeasure: CGFloat = 760
    static func permitsSupportingReport(state: SessionState) -> Bool
}
~~~

- FocusSurfaceLayout.permitsSupportingReport always returns false: Focus remains an operational canvas and never becomes a report/grid.

- [ ] **Step 1: Write failing hierarchy tests**

~~~
expect(DaySurfaceOrder.visible(hasQualification: true, hasSelection: true) == [
    .header, .qualification, .timeline, .selectedDetail, .supportingGroups, .recap
], "Today qualifies data before its timeline and keeps inspection near selection", &problems)
expect(FocusSurfaceLayout.operationalMeasure == 760,
       "Focus keeps a deliberate operational measure", &problems)
expect(!FocusSurfaceLayout.permitsSupportingReport(state: .running),
       "Focus does not become a running dashboard", &problems)
~~~

- [ ] **Step 2: Run the test to verify RED**

~~~bash
./build.sh --check
~~~

Expected: the presentation contracts are absent.

- [ ] **Step 3: Implement Today's compact recap grammar**

Make TodayView's sections follow DaySurfaceOrder. Update TodayRecap to use shared metric-band styling: labels once, tabular values, concise qualifiers, and one optional evidence sentence with a disclosure when it exceeds compact reading measure.

Do not alter timeline selection, past-day navigation, Escape, goal calculations, break representation or At the Mac semantics.

- [ ] **Step 4: Preserve Focus as a quiet instrument**

Replace the literal 760 in FocusView with FocusSurfaceLayout.operationalMeasure. Keep the continuation section as its only supporting panel and the break line outside decorative card treatment. Do not add metrics/charts to fill vertical space.

- [ ] **Step 5: Verify GREEN and commit locally**

~~~bash
./build.sh --check
git diff --check
git add Sources/Surfaces/Today/TodayView.swift Sources/Surfaces/Today/TodayRecap.swift \
        Sources/Surfaces/Focus/FocusView.swift Sources/Design/Components/SurfacePrimitives.swift \
        Sources/SelfTest.swift
git commit -m "ui: reinforce day and focus hierarchy"
~~~

### Task 7: Make Insights and Settings concise, native and deliberate

**Files:**

- Modify: Sources/Surfaces/Insights/InsightSection.swift:3-55
- Modify: Sources/Surfaces/Insights/InsightsView.swift:30-111
- Modify: Sources/Surfaces/Settings/SettingsView.swift:5-164
- Modify: Sources/SelfTest.swift

**Interfaces:**

- Produces:

~~~
struct InsightPresentation: Equatable {
    let title: String
    let headline: String
    let provenance: String
    var disclosureLabel: String { "How this is calculated" }

    init(title: String, insight: Insight)
}

enum SettingsLayout {
    static let detailMeasure: CGFloat = 720
    static func usesSidebar(at width: CGFloat) -> Bool
}
~~~

- InsightPresentation never manufactures a fact; it wraps an existing non-nil Insight.

- [ ] **Step 1: Write failing presentation tests**

~~~
let insight = Insight(id: "pace", headline: "10m behind your usual pace",
                      detail: "1h 15m focused-active today", symbolName: "gauge")
let presentation = InsightPresentation(title: "Pace", insight: insight)
expect(presentation.disclosureLabel == "How this is calculated",
       "Insights keep methodology behind a literal disclosure", &problems)
expect(SettingsLayout.usesSidebar(at: 1_080),
       "Settings uses the native-like sidebar at the comfortable threshold", &problems)
expect(!SettingsLayout.usesSidebar(at: 1_079),
       "Settings switches before its sidebar becomes cramped", &problems)
expect(SettingsLayout.detailMeasure == 720,
       "Settings controls retain a readable measure", &problems)
~~~

- [ ] **Step 2: Run the test to verify RED**

~~~bash
./build.sh --check
~~~

Expected: InsightPresentation and SettingsLayout are absent.

- [ ] **Step 3: Implement concise Insight cards**

Have InsightSection construct InsightPresentation. Render category and headline by default. Move provenance to DisclosureGroup(presentation.disclosureLabel), collapsed by default, retaining full text in accessibility label/value. InsightsView's evidence gating may change only layout and adaptive measure, never whether an insight exists.

- [ ] **Step 4: Implement Settings layout constants**

Move SettingsView.usesSidebar(at:) into SettingsLayout and replace literal 720 measure. Keep a small selected group naturally small instead of stretching a panel. Preserve search, selected-group navigation, keyboard order and all existing backed controls.

- [ ] **Step 5: Verify GREEN and commit locally**

~~~bash
./build.sh --check
git diff --check
git add Sources/Surfaces/Insights/InsightSection.swift Sources/Surfaces/Insights/InsightsView.swift \
        Sources/Surfaces/Settings/SettingsView.swift Sources/SelfTest.swift
git commit -m "ui: refine insight and settings presentation"
~~~

### Task 8: Validate the complete premium system and update project documentation

**Files:**

- Modify: Sources/Surfaces/Snapshotter.swift
- Modify: Sources/SelfTest.swift
- Modify: README.md
- Modify: docs/superpowers/specs/2026-08-30-premium-interface-design-system.md

**Interfaces:**

- Extends Snapshotter scenarios without changing its CLI contract:

~~~text
Focus: first run, running, paused, awaiting decision
Today: current, past, selected app/session, integrity qualification
Review: Week, Month, History, first/last selected day, range filter
Insights: enough/partial/empty evidence
Settings: each group, wide and narrow layout
~~~

- [ ] **Step 1: Write final visual-contract tests**

Add a self-test that asserts every material surface is represented by at least one SnapshotScenario and that Review selected-day fixtures include both period-chart and History-row selection. Keep the test pure by inspecting scenario cases/labels, not image pixels.

- [ ] **Step 2: Run the test to verify RED**

~~~bash
./build.sh --check
~~~

Expected: the current scenario matrix lacks the required Review-selection variants.

- [ ] **Step 3: Extend snapshots and inspect actual renders**

Render to a temporary directory:

~~~bash
snapshot_dir=$(mktemp -d /tmp/focuscontinuity-premium-snapshots.XXXXXX)
FocusContinuity.app/Contents/MacOS/FocusContinuity --snapshot "$snapshot_dir"
~~~

Inspect every listed state in light/dark and minimum/comfortable widths. Inspect the running app separately for titlebar/traffic lights, range popover, date-picker keyboard operation, tab focus, scroll behaviour and Review selection. Any observed defect begins a new red/green task; do not weaken a test or omit a scenario.

- [ ] **Step 4: Refresh documentation truthfully**

Update README only with shipped behaviour: Review stays in context on selection; selected data has an explicit Open in Today action; History uses a date-range control/table headers; charts compare exact tracked time. Update the design-spec status to implemented and verified only after Step 5 succeeds.

- [ ] **Step 5: Run final verification**

~~~bash
./build.sh --check
./build.sh --test
codesign --verify --deep FocusContinuity.app
git diff --check
git status --short
~~~

Expected:

- A fresh staged build and every headless test pass.
- The local app passes ordinary signature verification.
- The snapshot matrix contains every material state and manual native-control inspection is recorded.
- No generated app, snapshot, Finder metadata or unrelated local file is staged.

- [ ] **Step 6: Commit locally without pushing**

~~~bash
git add Sources/Surfaces/Snapshotter.swift Sources/SelfTest.swift README.md \
        docs/superpowers/specs/2026-08-30-premium-interface-design-system.md
git commit -m "test: verify premium interface system"
~~~

## Plan self-review

### Spec coverage

| Specification requirement | Implementing task |
|---|---|
| Review remains in context; explicit Today route | Tasks 1, 2 and 5 |
| Inline selected-day evidence | Tasks 2 and 5 |
| Final chart bar/axis overflow | Task 3 |
| Premium date range control | Task 4 |
| History headers rather than repeated labels | Task 4 |
| Clear Review information hierarchy | Task 5 |
| Whole-day Today narrative and quiet Focus | Task 6 |
| Concise Insights and intentional Settings layout | Task 7 |
| Tokens, accessibility, light/dark, native visual evidence | Global constraints and Task 8 |
| No semantic changes to accounting/history/privacy | Global constraints and Tasks 1–8 |

### Placeholder scan

The plan contains no unfinished markers, unspecified tests, unowned interfaces or deferred implementation steps. The only deferred work is explicitly outside the approved design specification.

### Type consistency

- reviewSelectedDate, selectReviewDay, clearReviewDay and openSelectedReviewDayInToday are defined in Task 1 and consumed by Tasks 2, 3 and 5.
- ReviewDayDetail, reviewDayDetail(for:) and reviewDayIsAvailable are defined in Task 2 and consumed by Task 5.
- PeriodChartLayout.domain(for:calendar:) is defined in Task 3 and has no unrelated callers.
- HistoryRangePresentation, HistoryRangeControl, HistoryTableLayout and TableColumnHeader are defined in Task 4 and remain owned by History/table grammar.
- DaySurfaceOrder, FocusSurfaceLayout, InsightPresentation and SettingsLayout are pure presentation contracts with testable behaviour.
