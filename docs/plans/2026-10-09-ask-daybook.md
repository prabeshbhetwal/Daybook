# Ask Daybook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A ⌘K sheet where typed questions about focus history are answered by Apple's on-device model, which picks read-only lookups whose every figure is computed by the same code History and Insights use.

**Architecture:** Core gets `AskRange`, `AskRequest` and pure text formatting (`AskFacts`). `SessionStore+Ask` turns a request into finished text by calling History's and Insights' own read methods. A `@MainActor` `AskModel` owns the `LanguageModelSession` and four `Tool`s that call back into it. A third `StorySheetKind` case shows the sheet.

**Tech Stack:** Swift 5 mode, `swiftc` via `build.sh`, SwiftUI/AppKit, `FoundationModels` (macOS 26+, gated with `@available`), deployment target macOS 14.

**Spec:** `docs/specs/2026-10-09-ask-daybook-design.md`

## Global Constraints

- Deployment target stays macOS 14.0. Every `FoundationModels` symbol sits behind `@available(macOS 26, *)` or `if #available(macOS 26, *)`. `build.sh` is not changed: `swiftc` already emits `LC_LOAD_WEAK_DYLIB` for `FoundationModels` at a 14.0 target (probe 2026-10-09).
- Nothing is sent off the Mac. No network code, no API keys.
- Read-only: no Ask code calls a `SessionStore` action or writes `historyFilter`, the archive, metadata or defaults.
- Every tool output ≤ 1,024 UTF-8 bytes. Durations come from `DurationText.compact` (whole minutes: `2h 15m`, `4h`, `15m`).
- Ranges are exactly: today, yesterday, this week, last week, this month, last month, last 30 days, all time; boundaries from `periodCalendar` (Gregorian, Monday-first, Mac's zone).
- Lengths in App/Design/Surfaces are tokens or `N.zoomed`; text uses `Tokens.Typography` roles (build guards `lengths_outside_zoom`, `type_outside_roles`).
- New checks go at the end of `registeredTests` in `Sources/Verification/SelfTest/SelfTest+Registry.swift`. Checks use `TestClock`, scratch directories and an isolated `fc-selftest-…` defaults suite, and hold in any time zone (build fixture dates from the calendar under test; `SelfTest.base` is Wed 15 Nov 2023 09:13:20 local).
- Edit Swift by exact text. Commit subjects: one present-tense sentence of what is now true for the user, no prefixes; body wrapped prose; end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- `build.sh` must run with the sandbox disabled. Sandboxed compile check: `swiftc -typecheck -module-cache-path "$TMPDIR/mc" -swift-version 5 -parse-as-library -warnings-as-errors -target arm64-apple-macos14.0 -F .build/vendor/Sparkle-2.10.0 $(find Sources -name '*.swift')` (point `-F` at the main checkout's `.build/vendor` if this worktree has none).

## Review Focus

1. **Today while a session runs.** "How long today?" must include the live session, as the dashboard does (`historySummary` patches today live). Task 2 pins it.
2. **Ranges that reach into the future or past the record.** "This week" on a Wednesday and "all time" on a two-day record must not list future or pre-record days. Task 2 pins it.
3. **Questions in another language or about nothing.** Unsupported-locale and refusal errors must show one plain line, never a crash or an empty sheet. Task 3 pins every `GenerationError` case.
4. **App names typed loosely.** "safari", "Safari." and "VS code" must resolve the way History's app picker would (fold case and accents; substring). An unknown app must say so. Task 2 pins it.
5. **The search behaviour History already has.** The `historySearchHits(matching:limit:)` extraction must leave History search identical. The existing search suites must pass unchanged. Task 2 runs them.

---

### Task 1: Ranges, requests and wording (Core)

**Files:**
- Create: `Sources/Core/AskFacts.swift`
- Create: `Sources/Verification/AskChecks.swift`
- Modify: `Sources/Verification/SelfTest/SelfTest+Registry.swift` (append `+ AskChecks.tests` after `+ ComponentEdgeChecks.tests`)

**Interfaces:**
- Produces:
  - `enum AskRange: String, CaseIterable, Sendable` with cases and raw values `today`, `yesterday`, `thisWeek = "this week"`, `lastWeek = "last week"`, `thisMonth = "this month"`, `lastMonth = "last month"`, `last30Days = "last 30 days"`, `allTime = "all time"`.
  - `func interval(now: Date, firstDay: Date, calendar: Calendar) -> DateInterval` on `AskRange`: half-open [start, end) using `calendar.dateInterval(of:for:)`. `last30Days` runs from the start of the day 29 days before today to the start of tomorrow. `allTime` runs from `startOfDay(firstDay)` to the start of tomorrow.
  - `var level: HistoryLevel?` on `AskRange`: `.day` for today and yesterday, `.week` for both weeks, `.month` for both months and last30Days, `nil` for allTime.
  - `var inPhrase: String` on `AskRange`: `today`, `yesterday`, `this week`, `last week`, `this month`, `last month`, `in the last 30 days`, `in all your history`.
  - `enum AskRequest: Equatable, Sendable` with cases `focusTotals(AskRange, words: String?)`, `bestHours(AskRange)`, `findSessions(words: String, AskRange)` and `appTime(AskRange, app: String?)`, plus `var provenance: String`, e.g. `focus totals (this week)`, `best hours (last 30 days)`, `sessions matching “thesis” (last month)`, `app time for Safari (this week)`.
  - `enum AskFacts` with:
    - `static let maximumBytes = 1_024`
    - `static func capped(_ text: String) -> String`. Text over the cap is cut at the last `"\n"` or `"; "` that keeps the result, with `"…"` appended, within `maximumBytes` UTF-8 bytes.
    - `static func focusTotals(_ range: AskRange, words: String?, focused: TimeInterval, sessions: Int, focusedDays: Int, best: (unit: String, label: String, focused: TimeInterval)?, parts: (name: String, items: [(label: String, focused: TimeInterval)])?) -> String`
    - `static func bestHours(_ range: AskRange, span: String, window: (startHour: Int, seconds: TimeInterval)?, strongest: String?) -> String`
    - `static func sessions(_ range: AskRange, words: String, hits: [(day: String, name: String, worked: TimeInterval, note: String?)]) -> String`
    - `static func appTime(_ range: AskRange, app: (query: String, name: String?, total: TimeInterval, sessions: Int)?, top: [(name: String, total: TimeInterval)]) -> String`
  - Every formatter returns `capped(...)`.

Exact wording. `X` is `DurationText.compact`; sentences end with `.`:

| Function | Something found | Nothing found |
|---|---|---|
| `focusTotals`, no words | `This week: X focused over N session(s) on D day(s); best day Tue 14 Nov, X. By day: Mon 13 Nov X, Tue 14 Nov X.` (`best <unit> <label>, X` only when `best` is non-nil, unit `day` or `month`; `By <parts.name>: …` only when `parts` is non-nil) | `No focus recorded this week.` |
| `focusTotals`, words | `Sessions matching “thesis” this week: X over N session(s) on D day(s).` | `No sessions match “thesis” this week.` |
| `bestHours` | `<span>: most focus 9–11am (X)[; strongest <strongest>].` (`strongest` arrives as `on Tuesdays`) | `Not enough focus <inPhrase> to tell; it needs at least 30m.` |
| `sessions` | One line per hit: `Tue 14 Nov · Thesis · 1h[ · note: <≤80 chars>]` | `No sessions match “thesis” this week.` |
| `appTime`, app found | `Safari this week: X in front; used in N session(s).` | `No app called “Figma” was used this week.` |
| `appTime`, no app | `Most-used apps this week: Safari X, Xcode X, …` (≤ 5) | `No app use recorded this week.` |

Capitalise the first letter of `inPhrase` when it starts a sentence. Use singular for one (`1 session`, `1 day`). The window label is `h–(h+2)` in 12-hour form: `9–11am`, `11am–1pm`, `12–2am`.

- [ ] **Step 1: Write the failing checks** in `Sources/Verification/AskChecks.swift`: `enum AskChecks: CheckSuite` with `static let tests` holding:
  - `rangesFollowPeriodCalendar`. `calendar = Calendar.current.forPeriods`, `now = SelfTest.base`. For each range, assert the interval equals the dates built from `calendar` at midnight:
    - today = 15→16 Nov 2023
    - yesterday = 14→15
    - this week = Mon 13→Mon 20
    - last week = 6→13
    - this month = 1 Nov→1 Dec
    - last month = 1 Oct→1 Nov
    - last 30 days = 17 Oct→16 Nov
    - all time with `firstDay` = 2 Sep 2023 14:00 gives 2 Sep 00:00→16 Nov
  - `rangeNamesRoundTrip`: `AskRange(rawValue: r.rawValue) == r` for all cases, and all raw values are distinct.
  - `nothingFoundIsSaid`: each formatter's nothing-found case returns exactly the wording in the table, for `.thisWeek` and words `thesis` / app `Figma`.
  - `figuresAreDurationText`: `focusTotals(.thisWeek, words: nil, focused: 24_000, sessions: 5, focusedDays: 4, best: (unit: "day", label: "Tue 14 Nov", focused: 7_500), parts: nil)` returns `This week: 6h 40m focused over 5 sessions on 4 days; best day Tue 14 Nov, 2h 5m.`
  - `outputStaysUnderCap`: `sessions` with 200 hits, each with an 80-character note, returns a result with `utf8.count <= 1_024` that ends with `…`.
  - `windowLabels`: `bestHours` with window start 9 contains `9–11am`; start 11 contains `11am–1pm`; start 0 contains `12–2am`.

  Append `+ AskChecks.tests` to the registry.
- [ ] **Step 2: Run** the sandboxed `swiftc -typecheck` command from Global Constraints. Expected: errors `cannot find 'AskRange' in scope`.
- [ ] **Step 3: Implement** `Sources/Core/AskFacts.swift` to the Interfaces above. Use `Calendar.forPeriods` only via the passed calendar. No `FoundationModels` import.
- [ ] **Step 4: Run** `./build.sh --check` (sandbox disabled). Expected: build passes; the summary shows all checks passing, including the six new ones. Then `TZ=Europe/Berlin ./build.sh --check`: same result.
- [ ] **Step 5: Commit** both files and the registry. Subject: `Daybook can name a period and word an answer about it the same way History does`.

### Task 2: Lookups through History's own figures

**Files:**
- Modify: `Sources/App/SessionStore+HistoryFind.swift`: extract `historySearchHits(matching:limit:)`
- Create: `Sources/App/SessionStore+Ask.swift`
- Modify: `Sources/Verification/AskChecks.swift`: store fixture and lookup checks

**Interfaces:**
- Consumes: Task 1's `AskRange`, `AskRequest` and `AskFacts`.
- Produces:
  - `func historySearchHits(matching filter: HistoryFilter, limit: Int = 200) -> [HistorySearchHit]`. This is today's body of `historySearchHits(limit:)` with `let filter = historyFilter` removed. `historySearchHits(limit:)` becomes `historySearchHits(matching: historyFilter, limit: limit)`. Move-only.
  - `func askLookup(_ request: AskRequest) -> String` in `extension SessionStore`, synchronous.

How each request is answered. `interval = range.interval(now: now(), firstDay: historyTop().firstDay, calendar: periodCalendar)`:

| Request | Figures |
|---|---|
| `focusTotals`, words nil | Place = `HistoryPlace(level: range.level!, span: interval)`, or nil for allTime. `historySummary(for: place)` gives `focused`, `sessions`, `focusedDays` and `best`. Pass `best` as unit `day` with label `"EEE d MMM"` when its place level is `.day`, and as unit `month` with label `"MMMM yyyy"` when `.month`. `parts` come from `historyRows(under: place)`, dropping rows whose `place.start` > today. Name them `day`, `week` or `month` from the row level. Pass nil when there are no rows or the range is today or yesterday. |
| `focusTotals`, words | Hits = `historySearchHits(matching: HistoryFilter(query: words), limit: 1_000)` filtered to `interval.contains(hit.day)` and to focus types (`hit.workType.countsAsFocus`). Focused = sum of `worked`. Sessions = distinct `threadID`. Days = distinct `day`. |
| `bestHours` | `interval.duration <= 86_400 * 1.5` uses `insightReading(scope: .day, anchoredAt: interval.start, limit: 1, calendar: periodCalendar)`, with span `Today` or `Yesterday`. Anything longer uses scope `.week`, anchored at the last day of `interval`, limit `min(14, weeks covering interval)`, with span `Over the N weeks to d MMM`. Take `facts.bestWindow` as the window. For `.week` scope, `strongest` is `facts.rowPhrases[i]` for the row with the largest sum, or nil when every row is 0. |
| `findSessions` | The hits from the words row above, without the focus-only filter. The first 10. Day as `"EEE d MMM"`. `note` = `noteSnippet` cut to 80 characters. |
| `appTime`, app nil | `historySortedUsage().uniqueUse(within: [interval])`, sorted by total descending with name as tiebreak, top 5. |
| `appTime`, app | The bundle ID is the key of `historyAppNames` whose folded name contains `SearchWords.fold(app)` (trimmed, `.` dropped) with the most use in `interval`. Total = `uniqueUse(within: [interval])[id].total`. Sessions = distinct `threadID` of `historySearchHits(matching: HistoryFilter(appBundleID: id), limit: 1_000)` inside `interval`. No match passes `name: nil`. |

- [ ] **Step 1: Write the failing checks.** Add a private fixture `makeStore(_ clock: TestClock, calendar: Calendar)`, shaped like `StoryAccountingChecks.makeStore` (`Sources/Verification/StoryAccountingChecks.swift:435`). Add a `SessionMetadataArchive` and records written through the archive, as `StoryIntegrationChecks.Fixture` does (`:25-57`), and call `store.setDashboardVisible(true)` so History's day index builds. Fixture records, built from `calendar` relative to `SelfTest.base` (Wed 15 Nov):

  | Name | Category | When | Note |
  |---|---|---|---|
  | Thesis | Deep work | Mon 13 Nov 09:00–10:00 | `chapter two outline` |
  | Parser | Deep work | Tue 14 Nov 14:00–15:30 | |
  | Thesis | Deep work | Tue 17 Oct 09:00–11:00 | |
  
  Usage: Safari (`com.apple.Safari`) Tue 14 Nov 14:00–15:00, inside Parser.

  New checks:
  - `focusTotalsMatchHistory`:
    - `askLookup(.focusTotals(.thisWeek, words: nil))` starts with `This week: 2h 30m focused over 2 sessions on 2 days; best day Tue 14 Nov, 1h 30m.`
    - Its focused figure equals `historySummary(for:)` for the same place.
    - Its `By day` list names Mon 13 Nov, Tue 14 Nov and Wed 15 Nov, and no later day.
  - `liveSessionCountsToday`: start a Thesis session at 09:13 and advance the clock 20 minutes. `.focusTotals(.today, nil)` contains `20m`.
  - `wordsNarrowTotals`:
    - `.focusTotals(.thisWeek, words: "thesis")` is `Sessions matching “thesis” this week: 1h over 1 session on 1 day.`
    - `.focusTotals(.lastMonth, words: "thesis")` contains `2h`.
  - `findSessionsStaysInRange`:
    - `.findSessions(words: "thesis", .thisWeek)` has one line, `Mon 13 Nov · Thesis · 1h · note: chapter two outline`.
    - `.lastMonth` has one line, dated `Tue 17 Oct`.
    - `"zebra"` gives the nothing-found wording.
  - `bestHoursNamesWindow`: `.bestHours(.last30Days)` contains `9–11am` and `on Tuesdays`.
  - `appTimeResolvesLooseNames`:
    - `.appTime(.thisWeek, app: "safari.")` is `Safari this week: 1h in front; used in 1 session.`
    - `app: "Figma"` gives `No app called “Figma” was used this week.`
    - `app: nil` starts `Most-used apps this week: Safari 1h`.
  - `allTimeStartsAtRecord`: `.focusTotals(.allTime, nil)` contains `4h 30m` (2h + 1h + 1h 30m) and names no month before October 2023.
  - `lookupsOnlyRead`:
    - Before and after running every request above, compare the bytes of every file under the session, usage and metadata scratch directories, and the fixture defaults' `dictionaryRepresentation()`. Assert equal.
    - Assert `store.historyFilter == HistoryFilter()` afterwards.
- [ ] **Step 2: Run** the sandboxed typecheck. Expected: errors `value of type 'SessionStore' has no member 'askLookup'`.
- [ ] **Step 3: Extract** `historySearchHits(matching:limit:)` in `SessionStore+HistoryFind.swift`, exactly as described in Produces.
- [ ] **Step 4: Implement** `askLookup(_:)` in `Sources/App/SessionStore+Ask.swift` to the table. Date labels use `DateFormats.australian(_:in: periodCalendar.timeZone)`.
- [ ] **Step 5: Run** `./build.sh --check` and `TZ=Europe/Berlin ./build.sh --check`. Expected: all checks pass, including the eight new ones and the existing `HistorySearchChecks`, `HistoryJournalChecks` and `HistoryAppLensChecks` unchanged.
- [ ] **Step 6: Commit.** Subject: `Daybook can answer a question about a period from History's own figures`.

### Task 3: The model, its tools and their failures

**Files:**
- Create: `Sources/App/AskModel.swift`
- Create: `Sources/App/AskTools.swift`
- Modify: `Sources/App/MainWindowModel.swift`: hold the model
- Modify: `Sources/Verification/AskChecks.swift`

**Interfaces:**
- Consumes: Task 2's `SessionStore.askLookup(_:)`, and `AskRequest.provenance`.
- Produces:
  - `struct AskNotice: Equatable { let text: String; let opensSettings: Bool }`
  - `@MainActor final class AskModel: ObservableObject`:
    - `init(store: SessionStore)`, holding the store weakly, as `MainWindowModel` does.
    - `@Published private(set) var question = ""`, `answer = ""`, `used = ""`, `notice: AskNotice?` and `isAnswering = false`.
    - `var canAsk: Bool`: macOS 26+ and the model is available.
    - `func prepare()`: below macOS 26 sets `notice = needsNewerMacOS`; otherwise refreshes availability into `notice` and calls `prewarm()`. Called when the sheet appears.
    - `func ask(_ text: String)`: ignored when the trimmed text is empty or `isAnswering` is true. Otherwise it clears `used`, sets `isAnswering`, and streams `streamResponse(to:)` snapshots into `answer`.
    - `func newQuestion()`: drops the session and clears `question`, `answer`, `used` and `notice`.
    - `func lookup(_ request: AskRequest) -> String`: returns `store?.askLookup(request) ?? ""` and appends `request.provenance` to `used`. The line reads `Used: a · b`.
    - `func openIntelligenceSettings()`
    - `func present(answer: String, used: String)`: a fixture seam for snapshots only.
    - `static let needsNewerMacOS = AskNotice(text: "Ask needs macOS 26 or later.", opensSettings: false)`
    - `@available(macOS 26, *) static func notice(for availability: SystemLanguageModel.Availability) -> AskNotice?`
    - `@available(macOS 26, *) static func notice(for error: Error) -> AskNotice`
  - The session is held as `private var session: AnyObject?` so the class compiles on macOS 14, and is cast inside `if #available(macOS 26, *)`.
  - Instructions (exact): `You answer questions about the user's own focus history in Daybook. Look figures up with the tools and answer only from what they return. Copy durations, dates and names exactly as the tools give them; never add, average or convert numbers yourself. If the tools find nothing, say so plainly. Answer in one to three sentences. Today is <EEEE d MMMM yyyy>.`
  - Tools, `@available(macOS 26, *)`, each `struct …: Tool` holding `let model: AskModel` and calling `await model.lookup(…)`:
    - `focusTotals`: arguments `range: String`, `words: String?`
    - `bestHours`: `range: String`
    - `findSessions`: `words: String`, `range: String`
    - `appTime`: `range: String`, `app: String?`

    Every `range` is `@Guide(description: "Time range", .anyOf(AskRange.allCases.map(\.rawValue)))`. An unknown raw value falls back to `.thisWeek`. Empty `words`/`app` strings are treated as nil. Descriptions are one sentence each and name what the tool returns.
  - `MainWindowModel`: `private(set) var askModel: AskModel?` and `func openAsk()`, which builds the model from `store` on first use and then calls `openSheet(.ask)`. Task 4 adds the `.ask` case. Until then, `openAsk()` only builds the model.

Notice mapping (exact text):

| Input | `AskNotice` |
|---|---|
| `.available` | nil |
| `.unavailable(.deviceNotEligible)` | `This Mac can't run Apple's on-device model.`, false |
| `.unavailable(.appleIntelligenceNotEnabled)` | `Turn on Apple Intelligence in System Settings › Apple Intelligence & Siri.`, true |
| `.unavailable(.modelNotReady)` | `The on-device model is still downloading. Try again shortly.`, false |
| unknown availability | `Ask isn't available on this Mac right now.`, false |
| `GenerationError.exceededContextWindowSize` | `Started a new thread — the last one was full.`, false. `ask` also drops the session so the next ↩ starts fresh |
| `.guardrailViolation`, `.refusal` | `Can't answer that one.`, false |
| `.unsupportedLanguageOrLocale` | `Ask doesn't understand this language yet.`, false |
| anything else | `Couldn't answer: <localizedDescription>`, false. `answer` keeps the previous text |

- [ ] **Step 1: Verify the settings URL.** Run `open "x-apple.systempreferences:com.apple.Siri-Settings.extension"` once on this Mac and confirm the Apple Intelligence & Siri pane opens. If it does not, use `x-apple.systempreferences:` (the System Settings root) and note it in the commit body.
- [ ] **Step 2: Write the failing checks.** Each one returns `[]` under `if #available(macOS 26, *)` else.
  - `noticesCoverEveryCase`: every row of the mapping table. Build errors with `LanguageModelSession.GenerationError.<case>(.init(debugDescription: "probe"))`.
  - `toolsMatchLookups`: on the Task 2 fixture, call each tool's `call(arguments:)` with memberwise `Arguments(...)` inside `Task { @MainActor in … }`. Wait with `InstalledAppCatalog.turnRunLoop(until: { output != nil }, timeout: 5)`. Assert each output equals `store.askLookup(<same request>)`. Cover `range: "nonsense"` (falls back to this week) and `words: ""` (treated as nil).
  - `provenanceRecordsLookups`: `model.lookup(.focusTotals(.thisWeek, words: nil))` then `model.lookup(.bestHours(.last30Days))` gives `model.used == "Used: focus totals (this week) · best hours (last 30 days)"`. `newQuestion()` empties it.
  - `blankQuestionIsIgnored`: `model.ask("   ")` leaves `isAnswering == false` and `answer == ""`.
  - `askModelIsBuiltOnce`: `openAsk()` twice gives the identical (`===`) `askModel`.
- [ ] **Step 3: Run** the sandboxed typecheck. Expected: `cannot find 'AskModel' in scope`.
- [ ] **Step 4: Implement** `AskModel.swift`, `AskTools.swift` and the `MainWindowModel` members to the Interfaces.
- [ ] **Step 5: Run** `./build.sh --check`. Expected: all checks pass. Then `otool -l Daybook.app/Contents/MacOS/Daybook | grep -B3 FoundationModels.framework | grep cmd`, run on the candidate the build staged (path printed by `build.sh`). Expected: `LC_LOAD_WEAK_DYLIB`.
- [ ] **Step 6: Commit.** Subject: `Daybook can ask Apple's on-device model about your history and says plainly when it can't`.

### Task 4: The Ask sheet on ⌘K

**Files:**
- Create: `Sources/Surfaces/Ask/AskSheet.swift`
- Modify:
  - `Sources/App/MainWindowModel.swift`: `StorySheetKind` gains `ask`, title `Ask Daybook`
  - `Sources/Surfaces/Main/MainWindowView.swift`: `sheetBody` case
  - `Sources/Surfaces/Settings/SettingsView.swift`: `SettingsLayout.sheetSize` gives `.ask` 640 × 520, zoomed and clamped like the others
  - `Sources/Surfaces/Main/MainWindowCommands.swift`: `Button("Ask Daybook…") { navigation.openAsk(); revealMainWindow() }.keyboardShortcut("k", modifiers: [.command])`, after Find in History
  - `Sources/Surfaces/Snapshotter.swift`: scenario `askAnswered`
  - `Sources/Verification/SelfTest/SelfTest+Snapshots.swift`: add `.askAnswered` to `required` after `.awardsEmpty`
  - `Sources/Verification/AskChecks.swift`
  - `README.md`: privacy paragraph

**Interfaces:**
- Consumes: Task 3's `AskModel` and `MainWindowModel.openAsk()` / `askModel`.
- Produces: `struct AskSheet: View { @ObservedObject var model: AskModel }`.

The sheet, top to bottom, inside the existing `StorySheet` chrome:
1. **Question field.** A one-line `TextField("Ask about your focus…", text:)` styled like `HistoryFindBar`'s private field (`Sources/Surfaces/Review/HistoryFind.swift`): plain style, `Space.m` horizontal padding, `Colour.elevated` fill, `Radius.nested`, focus stroke, height `FilterChip.height`, focused on appear. ↩ calls `model.ask`. Disabled while `isAnswering`. Hidden when `!model.canAsk`.
2. **Notice.** One `Typography.body` line. When `opensSettings` is true, it has a link-style button, `Open Settings`.
3. **Answer.** `Typography.control`, selectable text. While answering with no text yet, show a `ProgressView().controlSize(.small)`.
4. **Used line.** `Typography.caption`, secondary colour.
5. **New question button.** Trailing, shown once an answer exists.

`prepare()` runs on appear. VoiceOver: the answer is announced when answering finishes (`AccessibilityNotification.Announcement`), and the field's label is `Question`.

- [ ] **Step 1: Write the failing checks.**
  - `askOpensAsASheet`: on a fixture `MainWindowModel`, `openAsk()` gives `sheet == .ask`; `StorySheetKind.ask.title == "Ask Daybook"`; `closeSheet()` gives nil.
  - `askSheetFitsWindow`: `SettingsLayout.sheetSize(for: .ask, within: CGSize(width: 600, height: 400))` fits inside 600 × 400.
  - Update `SelfTest+Snapshots` `required` with `.askAnswered`.
- [ ] **Step 2: Run** the sandboxed typecheck. Expected: `type 'StorySheetKind' has no member 'ask'`.
- [ ] **Step 3: Implement** the case, sheet body, size, command, `AskSheet` and the `askAnswered` scenario. In `navigation(for:store:)`, call `openAsk()` and then `askModel?.present(answer: "Mornings. Over the 4 weeks to 15 Nov: most focus 9–11am (2h); strongest on Tuesdays.", used: "Used: best hours (last 30 days)")`.
- [ ] **Step 4: Add** the README sentence to the "Private by construction" paragraph, after the dictation sentence: `Ask Daybook answers with Apple's on-device model, and your question, history and answers are not sent anywhere.`
- [ ] **Step 5: Run** `./build.sh --check`. Expected: all checks pass. Then run the snapshot at both zoom ends, sandbox disabled: `FC_SNAPSHOT_ONLY=askAnswered FC_SNAPSHOT_ZOOM=0.8` and `=1.4`, each with `<built binary> --snapshot "$(mktemp -d)"`. Read both PNGs and confirm nothing clips and the field, answer and used line are all visible.
- [ ] **Step 6: Commit.** Subject: `⌘K opens Ask Daybook, a sheet for questions about your focus history`.

### Task 5: Proof before merge

**Files:**
- Modify: `docs/specs/2026-10-09-ask-daybook-design.md` §7: record the hand-check answers.

- [ ] **Step 1: Mutation test.** Copy the tree: `T="$(mktemp -d "$TMPDIR/fc-tree.XXXXXX")"; rsync -a build.sh Sources Assets scripts .build "$T/"`. In the copy, make `AskRange.thisWeek` start one day later. Run `./build.sh --check` there. Expected: `rangesFollowPeriodCalendar` and `focusTotalsMatchHistory` fail. Remove `$T`.
- [ ] **Step 2: Run the `fix-reviewer` agent** on the branch diff (ranges are time arithmetic). Address findings or record why not.
- [ ] **Step 3: Hand checks.** These need the real app on this Mac with Apple Intelligence on. **Ask the user before replacing the installed app** with `./build.sh --test`. After their yes, ask the five §7 questions in the sheet and record each answer and pass/fail in the spec.
- [ ] **Step 4: Ship** with the `ship` skill: it runs the check, commits the spec update and merges through the PR flow.
