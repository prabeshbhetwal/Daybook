# Ask Daybook v2, part 2: lookups for everything Daybook records — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ask answers questions about stretches, breaks, time away, the Mac's events, notes, work types, app hours, the daily goal, the streak and awards from the readers the screens use, and lists where each answer came from, the Awards sheet included.

**Architecture:** Three new catalogue entries (`dayEvents`, `sessionDetail`, `goals`) follow part 1's pattern: `AskLookups` reads arguments into an `AskRequest`, a `SessionStore+Ask…` file reads the screens' readers into plain Core values, `AskFacts` words them (≤1 KB), and the result carries `AskLink` sources. Two part-1 lookups gain facts (`appTime` hours; `focusTotals` work types, streak, app hours, note line) and `findSessions` lines change wording. One new link target, `.awards`, opens the Awards sheet.

**Tech Stack:** Swift 5 language mode, AppKit/SwiftUI, FoundationModels (macOS 26+, weak-linked), the headless self-check suite (`./build.sh --check`).

**Spec:** `docs/specs/2026-10-11-ask-daybook-v2-part2-lookups-design.md` (read it first; this plan argues from it). Part 1's spec and plan: `docs/specs/2026-10-11-ask-daybook-v2-chat-design.md`, `docs/plans/2026-10-11-ask-daybook-v2-chat.md`.

## Global Constraints

- Part 1's five lookups keep their names, parameters, parameter descriptions, optionality, order and the period guide **byte for byte**. Only `focusTotals` and `appTime` descriptions change, each by one appended sentence: `" Also gives the time in each work type."` and `" Also gives the hours of the day it was in front."`.
- `AskModel.instructions(today:carrying:)` and the greedy sampling options are not touched.
- No lookup writes anything (no file, no preference, not History's filter). `AskLookupChecks.lookupsOnlyRead` must keep passing.
- Every figure comes from the reader the screen that shows it uses; `AskFacts` only words it. Durations via `DurationText.compact` (`4h`, `1h 12m`, `45m`); clock times via `askTime` (`9:10am`); days via `askDay` (`Mon 13 Nov`).
- Time rule: a clock time is never bare beside a duration: `from 2:00pm`, `to 3:12pm`, `at 11:48pm`.
- Each fact ≤ `AskFacts.maximumBytes` (1,024 bytes), cut with `AskFacts.capped(_:keeping:)`.
- Core (`Sources/Core`) stays UI-free and compiles alone; `build.sh` typechecks it separately.
- Source files ≤ 300 lines; near 250, split into a sibling file.
- Lengths in `Sources/App|Design|Surfaces` are tokens or `.zoomed`; supporting text uses `StoryStyle.supportingInk` (`build.sh` fails on `.secondary`/`.tertiary`).
- Checks: `TestClock`, `SelfTest.scratchDirectory()`, `MemoryDefaults.suite(named: "fc-selftest-…")` (never `UserDefaults(suiteName:)`); dates from the calendar the code uses; pass under `TZ=Europe/Berlin` too.
- New check suites are appended at the **end** of `registeredTests` in `Sources/Verification/SelfTest/SelfTest+Registry.swift` (current tail: `…AskFollowChecks.tests + AskPanelChecks.tests + SupportingInkChecks.tests`).
- Edit Swift by exact text, never by line number. Run `./build.sh --check` unsandboxed; the sandbox-safe typecheck recipe is in `CLAUDE.md`.
- Commit subject: one plain present-tense sentence of what is now true for the user; wrapped prose body; ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. No type prefixes. Public repo: no machine paths or personal data.
- Copy: Australian English; no em dashes in user-facing copy.

## Review Focus

1. **A stretch that crosses midnight** (11:00pm to 1:00am): `sessionDetail` and `dayEvents` show it under each day clipped to that day (`from 11:00pm to 12:00am` / `from 12:00am to 1:00am`), never as a 2h stretch on one day. Test in Task 6.
2. **A long history** (all time over 1,000 days): `dayEvents` and `sessionDetail` walk days newest first and stop reading once the 1 KB cap is full; the "Newest N of M" count still names every qualifying day/session, counted from cheap sources (archive records, receipts, the event log), not from a projection per day. Test in Tasks 5 and 6 (`extraThesisDays: 1000` fixture stays ≤ 1,024 bytes and answers).
3. **No Mac event log at all** (`store.machineEventLog == nil`, a fresh install): `dayEvents` lists breaks and answers, says nothing about Mac events and adds no caveat. Test in Task 5.
4. **A session running now and an absence not yet answered**: `sessionDetail` reads `running from 1:00pm, 1h 30m so far`; `dayEvents` reads `away, not answered yet`. Tests in Tasks 5 and 6.
5. **Today's goal not met and no streak**: `goals` reads `not met yet` and `No current streak: a day counts at 1h of focus.`; with no awards earned, `No awards earned yet.`. Test in Task 7.

---

## File map

| File | Task | Responsibility |
|---|---|---|
| `Sources/Core/AskLink.swift` | 1 | `.awards` target, four roles, `names` |
| `Sources/Core/AskSourcePicker.swift` | 1 | Awards naming rule |
| `Sources/App/MainWindowModel+Ask.swift` | 1 | `follow` opens Awards |
| `Sources/Surfaces/Ask/AskSourcesView.swift` | 1 | rosette glyph, "Opens Awards." |
| `Sources/Core/AskRequest.swift` (new) | 2 | `AskRequest`, `AskBest`, `AskSide`, `AskTotals`, `AskSessionLine` moved out of `AskFacts.swift` (move only), then the new request cases and value types |
| `Sources/Core/AskFacts.swift` | 2–4 | session line wording; appTime hours; focusTotals extras |
| `Sources/App/SessionStore+AskClips.swift` | 2 | every listed session's note |
| `Sources/App/SessionStore+AskHours.swift` (new) | 3 | app hours over a period; the rail's hours on one day |
| `Sources/App/SessionStore+HistoryLens.swift` | 3 | `appLens(bundleID:usage:)` extracted for History and Ask |
| `Sources/App/SessionStore+AskTotalsExtras.swift` (new) | 4 | work types, streak, note line for totals |
| `Sources/Core/AskFacts+DayEvents.swift`, `Sources/App/SessionStore+AskDayEvents.swift` (new) | 5 | `dayEvents` facts and reader |
| `Sources/Core/AskFacts+SessionDetail.swift`, `Sources/App/SessionStore+AskSessionDetail.swift` (new) | 6 | `sessionDetail` facts and reader |
| `Sources/Core/AskFacts+Goals.swift`, `Sources/App/SessionStore+AskGoals.swift` (new) | 7 | `goals` facts and reader |
| `Sources/App/AskLookups.swift`, `Sources/App/SessionStore+Ask.swift` | 3–7 | catalogue entries, dispatch |
| `Sources/Verification/AskDataFixture.swift` (new) | 4–7 | shared store fixture for the new suites |
| `Sources/Verification/AskFactsExtensionChecks.swift`, `AskDayEventsChecks.swift`, `AskSessionDetailChecks.swift`, `AskGoalsChecks.swift` (new) | 2–7 | new suites |
| `Sources/Surfaces/Snapshotter.swift`, `Snapshotter+Ask.swift`, `README.md` | 8 | snapshot scenario, README |

---

### Task 1: Sources can point to Awards

**Files:**
- Modify: `Sources/Core/AskLink.swift`, `Sources/Core/AskSourcePicker.swift`, `Sources/App/MainWindowModel+Ask.swift`, `Sources/Surfaces/Ask/AskSourcesView.swift`
- Test: `Sources/Verification/AskSourceOrderChecks.swift`, `Sources/Verification/AskFollowChecks.swift` (add tests to the existing suites)

**Interfaces:**
- Produces: `AskSourceRole` cases `whatHappened = "What happened"`, `stretches = "Stretches"`, `dailyGoal = "Daily goal"`, `streakAndAwards = "Streak and awards"`; `AskLink.Target.awards`; `AskLink.names: [String] = []` (words that name a place with no date: used only by `.awards`); `AskSourcesView.accessibilityLabel(for:)` ending `"Opens Awards."` for `.awards`, `"Opens in History."` otherwise.

- [ ] **Step 1: Write the failing tests**

In `AskSourceOrderChecks`, test `"An answer about the streak or an award names the Awards source"`. Lookups `[[septemberLink(role: .dailyGoal), awards]]` where `awards = AskLink(target: .awards, label: "Awards", role: .streakAndAwards, names: ["streak", "streaks", "award", "awards", "Longest stretch"])`:
- answer `"Your current streak is 5 days."` → `sources.map(\.link.target) == [.awards, septemberLink.target]`, and `sources[0].mention` covers the characters of `streak`;
- answer `"You earned Longest stretch in September."` → `.awards` listed, its mention covers `Longest stretch`;
- answer `"A streaky month."` → no `.awards` in the sources (whole words only; `.awards` is not an anchor, so unnamed it is not listed).

In `AskFollowChecks`, test `"The Awards source opens the Awards sheet in either placement"`: with the sheet placement, `follow(awards)` leaves `sheet == .awards` and the chat's turns unchanged; with the panel placement and the panel open, `follow(awards)` leaves `sheet == .awards` and `askPanelOpen == true`. Same test: `AskSourcesView.accessibilityLabel(for: AskSource(link: awards, mention: nil)) == "Awards, streak and awards. Opens Awards."`, and a day source's label still ends `"Opens in History."`.

- [ ] **Step 2: Run to verify they fail**

Run: `./build.sh --check` (unsandboxed). Expected: compile failure (`.awards`, `names` undefined).

- [ ] **Step 3: Implement**

- `AskLink`: the roles; `case awards` on `Target`; `var names: [String] = []` after `sessionName`.
- `AnswerReader.mention(of:)`: `case .awards:` the earliest whole-word match among `link.names` (reuse `mention(ofName:)`).
- `MainWindowModel.follow(_:)`: switch on the target first; `.awards` calls `open(tab: .awards)` and returns; every other target keeps `open(tab: .review)` then its History call, unchanged.
- `AskSourceRow.glyph`: `"rosette"` for `.awards`. `accessibilityLabel(for:)`: `"Opens Awards."` for `.awards`.

- [ ] **Step 4: Run to verify they pass**

Run: `./build.sh --check`. Expected: all checks pass (count printed as `passed/total`).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/AskLink.swift Sources/Core/AskSourcePicker.swift Sources/App/MainWindowModel+Ask.swift Sources/Surfaces/Ask/AskSourcesView.swift Sources/Verification/AskSourceOrderChecks.swift Sources/Verification/AskFollowChecks.swift
git commit   # subject: "An Ask source can open the Awards sheet"
```

---

### Task 2: Session lists say when a session began and show its note

**Files:**
- Create: `Sources/Core/AskRequest.swift` (move only: `AskRequest`, `AskBest`, `AskSide`, `AskTotals`, `AskSessionLine` and their doc comments, verbatim, from the top of `Sources/Core/AskFacts.swift`)
- Modify: `Sources/Core/AskFacts.swift` (`sessions(_:words:lines:matched:sessionRunning:lead:)`), `Sources/App/SessionStore+AskClips.swift` (`askListing`)
- Create test suite: `Sources/Verification/AskFactsExtensionChecks.swift`; register at the registry tail
- Modify tests that pin the old line format (find them with `grep -rn " · 2:00pm\| · 9:00am\|time:" Sources/Verification/Ask*`): update only the line shape

**Interfaces:**
- Produces: line shape `"<day> · <name> · from <time> · <duration>"` (`" · note: <line>"` appended when the session has a note); `AskFactsExtensionChecks` suite type for Tasks 3 and 4 to add tests to.

- [ ] **Step 1: Move the types** (no behaviour change). Run `./build.sh --check`; expected: same pass count as before.

- [ ] **Step 2: Write the failing tests** in `AskFactsExtensionChecks`:
- `"A session line says when it began with “from”"`: `AskFacts.sessions(.allTime, words: "", lines: [AskSessionLine(day: "Tue 15 Sep", time: "2:00pm", name: "Parser", worked: 14_400)])` `== "Tue 15 Sep · Parser · from 2:00pm · 4h"`; with `time: ""` the line is `"Tue 15 Sep · Parser · 4h"`.
- `"Every listed session shows its note"` (part 1's `AskLookupChecks` fixture, whose Mon 13 Nov Thesis has the note "chapter two outline"): `store.askLookup(.findSessions(words: "", .allTime))` contains `"Thesis · from 9:00am · 1h · note: chapter two outline"`.
- `"A note line that matches the words wins over the first line"`: save the note `"first line\nchapter two outline"` on that record; `findSessions(words: "outline", .allTime)` shows `note: chapter two outline`; with no words it shows `note: first line`.

- [ ] **Step 3: Run to verify they fail.** Expected: the first two fail on the line shape and the missing note.

- [ ] **Step 4: Implement**
- `AskFacts.sessions`: emit `day · name · from time · duration` (time part only when non-empty).
- `askListing`: `note` is `clip.hit.noteSnippet` when present, else the first non-empty line of the first note on any of `clip.hit.recordIDs`, read through `journalNote(for:)`'s source (`metadataArchive.metadata(for:)`), trimmed.

- [ ] **Step 5: Run to verify they pass**; update any older check that pinned `"<day> · <time> · <name>"` to the new shape. Expected: all pass.

- [ ] **Step 6: Commit** — subject: "Ask's session lists say when each session began and show its note".

---

### Task 3: App time names the hours an app was in front

**Files:**
- Create: `Sources/App/SessionStore+AskHours.swift`
- Modify: `Sources/App/SessionStore+HistoryLens.swift` (extract `appLens`), `Sources/App/AskLookups.swift` (appTime description tail), `Sources/App/SessionStore+Ask.swift` (`askAppTime`), `Sources/Core/AskFacts.swift` (`appTime`), `Sources/Verification/AskCatalogueChecks.swift`
- Test: `Sources/Verification/AskFactsExtensionChecks.swift`

**Interfaces:**
- Produces:
  - In `SessionStore+HistoryLens.swift`, the part of `historyAppLens()` after its filter guard (records with the running stretch appended, `HistoryAppLens.build`, `Calendar.current`, `accurateFrom`) moves into `func appLens(bundleID: String, usage: SortedUsage) -> HistoryAppLens`; `historyAppLens()` calls it with `historySortedUsage()` and keeps its cache. Ask never reads or sets `historyFilter`.
  - `func askAppHours(bundleID: String, in interval: DateInterval) -> [TimeInterval]` — 24 entries, seconds per clock hour: `appLens(bundleID:usage:)` given `historySortedUsage().stretches` clipped to `interval` (as a `SortedUsage`), `hoursInSession[h] + hoursOutside[h]`.
  - `func askRailHours(on day: Date) -> [TimeInterval]` — 24 entries from `storyRailDay(on:).rhythm` (`RhythmHour.hour`, `.seconds`).
  - `AskFacts.hoursPhrase(_ hours: [TimeInterval]) -> String?` — the top three hours with at least 60 s, most first, earlier hour on a tie: `"from 2pm to 3pm (31h 20m), then from 3pm to 4pm (24h 5m) and from 10am to 11am (6h 40m)"`; one hour: `"from 2pm to 3pm (1h)"`; nil when none. Hour words as `DateFormats.hourLabel` writes them (`12am`, `1pm`).
  - `AskFacts.appTime(_:app:top:sessionRunning:hours:)` — new trailing `hours: [TimeInterval]? = nil`.

- [ ] **Step 1: Write the failing tests**
- `AskCatalogueChecks.entriesMatchVersionOne`: part 1's five entries in order are the catalogue's first five; descriptions equal version one's, except `appTime` (and, from Task 4, `focusTotals`) equal version one's plus the exact sentence; `schemasMatchVersionOne` unchanged (parameters byte-identical).
- `AskFactsExtensionChecks` `"App time names the hours an app was in front"` (part 1's fixture: Safari 2:00pm–3:00pm on Tue 14 Nov): `askLookup(.appTime(.allTime, app: "safari"))` contains `"; most in front from 2pm to 3pm (1h)"`; `askLookup(.appTime(.yesterday, app: nil))` contains `"Busiest hours: from 2pm to 3pm (1h)."`; `askLookup(.appTime(.thisMonth, app: nil))` contains no `"Busiest hours"`.
- `"App hours are History's lens figures"`: for Safari over all time, `askAppHours` equals `HistoryAppLens.build(bundleID: "com.apple.Safari", records: engine.archive.records, usage: store.historySortedUsage(), calendar: .current, accurateFrom: <the fixture's>)`'s `hoursInSession[h] + hoursOutside[h]` for every hour; `store.historyFilter` is unchanged after the lookup.

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement** the two readers, `hoursPhrase`, the `appTime` wording (named app: `"…; used in N sessions; most in front <phrase>."`; no app on a one-day range: the top list sentence then `" Busiest hours: <phrase>."`), and the description sentence.

- [ ] **Step 4: Run to verify they pass.**

- [ ] **Step 5: Commit** — subject: "Ask can say at what hours an app was in front".

---

### Task 4: Focus totals add work types, the streak, app hours and a matching note

**Files:**
- Create: `Sources/App/SessionStore+AskTotalsExtras.swift`, `Sources/Verification/AskDataFixture.swift`
- Modify: `Sources/Core/AskRequest.swift` (`AskTotals` fields), `Sources/Core/AskFacts.swift` (`focusTotals`), `Sources/App/SessionStore+Ask.swift` (`askTotals`, `askMatchingTotals`), `Sources/App/AskLookups.swift` (focusTotals description tail)
- Test: `Sources/Verification/AskFactsExtensionChecks.swift`, `Sources/Verification/AskCatalogueChecks.swift`

**Interfaces:**
- Consumes: `askAppHours`, `AskFacts.hoursPhrase` (Task 3).
- Produces:
  - `struct AskShare: Equatable { let name: String; let seconds: TimeInterval }` (Core, `AskRequest.swift`).
  - `AskTotals` fields: `workTypes: [AskShare] = []`, `streak: (days: Int, since: String)? = nil`, `appHours: String? = nil` (a `hoursPhrase`), `noteLine: String? = nil`.
  - `func askWorkTypes(_ range: AskRange) -> [AskShare]` — `historyCategories(for: HistoryPlace(level: range.level ?? .year, span: askInterval(range)))`, names `WorkType.displayName`, order kept.
  - `func askStreak() -> (days: Int, since: Date)?` — `engine.archive.currentStreak(includingToday:)` with the same `inFlight` seconds `SessionStore+Refresh.swift` passes where it publishes `\.streak` (extract a shared helper if that expression is inline); `since` = the streak's first day: counting back from today when today has reached `engine.store.streakMinimum`, else from yesterday; nil when 0. Never `Date()`.
  - `func askNoteLine(words: String, in clips: [AskClip]) -> String?` — the first note line, across the clips newest first, that holds a word of `words` (`SearchWords.fold`), as `journalNoteLine(for:)` picks one.
  - `AskDataFixture` (Verification): `static func with(_ body: @MainActor (AskDataFixture, inout [String]) -> Void) -> [String]`, exposing `clock`, `calendar`, `engine`, `store`, `metadata` (the `SessionMetadataArchive`), `directories`, the record values below by name, and `moment(_ back: Int, _ hour: Int, _ minute: Int = 0) -> Date`, built like `AskLookupChecks.makeFixture` at `SelfTest.base` (Wed 15 Nov 2023, 9:13am). It holds **all** the data Tasks 4–7 read, so no later task changes it (later tests add their own data locally):
    - `engine.store.streakMinimum = 3_600`; `engine.store.dailyGoal = 14_400`.
    - Deep work "Thesis" 7:00–8:00am on Fri 10, Sat 11, Sun 12 and Tue 14 Nov (each its own thread), Safari in front throughout; Tue 14's has the note `"tokenizer rewrite"`.
    - Mon 13 Nov: Deep work "Thesis" record A 9:00–10:40am and record B 11:05am–12:25pm, **one thread**, Safari in front throughout; A's note `"chapter three, fixed citations"`; battery readings on A (`.battery` 82% at 9:00am, boundary `.stretchStarted`; 61% at 10:40am, `.stretchEnded`) and external power on B (61% at 11:05am → 88% at 12:25pm), through `metadata.appendPower(_:for:)`. Deep work "Parser" 2:00–3:12pm, Xcode in front; Admin "Email" 4:30–5:00pm, Mail in front. Breaks (`.breakTime`): `"Lunch"` 12:25–1:10pm and unnamed 3:40–3:55pm. Away receipts, injected through the persisted state the engine loads as `DecisionHistoryChecks` does: 10:40–11:05am `"Meeting"` `.mergeTime` crediting 1,500 s; 4:10–4:30pm `"Coffee"` `.tookBreak`.
    - A `MachineEventLog(directory:)` in a scratch folder, set as `store.machineEventLog`: wake Sun 12 Nov 8:00am (the log's first event); lock 12:25pm and unlock 1:10pm Mon 13 Nov; sleep 11:48pm Mon 13 Nov; wake 7:52am Tue 14 Nov; a crash found at a launch at 8:02am Tue 14 Nov (built as `MachineEventStoryChecks` builds one).
    - Deep work "Reading" 9:00–10:00am each day 1–12 Oct 2023 (the 12-day best streak), no app use, except Oct 5's, which runs 9:00am–2:00pm (5h) with Xcode in front 9–10am only.
    - Resulting figures the tests pin: current streak 5 days since Fri 10 Nov (today has no focus at 9:13am); best 12; Mon 13 Nov's focus 4h 42m and goal credit 4h 42m (met); Tue 14 Nov's 1h (not met); Oct 5's focus 5h, goal credit 1h (not met).
    - The receipts carry no inserted record, so they change no focus figure. If `storyTimelineItems(on:)` does not show a receipt without one, give each its record as the engine would and recompute the pinned figures above before writing the tests.

- [ ] **Step 1: Write the failing tests** (`AskFactsExtensionChecks`, on `AskDataFixture`):
- `"Totals give the time in each work type, as History does"`: `askLookup(.focusTotals(.thisMonth, words: nil))` contains `"By work type: Deep work 8h 12m, Admin 30m."`, and those names and figures equal `askWorkTypes(.thisMonth)` (History's `historyCategories` for November 2023).
- `"Words that name a work type give that type's total"`: `askLookup(.focusTotals(.thisMonth, words: "admin"))` starts `"Sessions matching “admin” this month (November 2023)"` and contains `"30m over 1 session"`.
- `"All-time totals name the current streak"`: `askLookup(.focusTotals(.allTime, words: nil))` contains `"The current streak is 5 days, since Fri 10 Nov."`; with `clock` moved to Sat 18 Nov, no streak sentence.
- `"Words that name an app bring its hours"`: `focusTotals(.allTime, words: "safari")` contains `"Most in front from 7am to 8am (4h), then from 9am to 10am (1h) and from 11am to 12pm (55m)."`.
- `"Words found in a note bring the note's line"`: `focusTotals(.allTime, words: "tokenizer")` contains `"A matching note: “tokenizer rewrite”."`.
- `"Totals stay within 1 KB with the new parts"`: `AskLookupChecks.withFixture(extraThesisDays: 1_000)` → every `focusTotals` range's text ≤ 1,024 bytes.
- `AskCatalogueChecks`: `focusTotals` description is version one's plus `" Also gives the time in each work type."`.

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement.** Wording in `AskFacts.focusTotals`, in this order after the existing sentence and the existing app sentence: `" Most in front <appHours>."`, `" A matching note: “<noteLine>”."`, `" By work type: <name> <duration>, …."` (when `sessions > 0`), `" The current streak is N day(s), since <day>."` (all time only); the existing `" By <unit>: …"` breakdown stays last so the cap cuts it first.

- [ ] **Step 4: Run to verify they pass.**

- [ ] **Step 5: Commit** — subject: "Ask's focus totals add work types, the streak, app hours and the note that matched".

---

### Task 5: Ask can tell what happened between sessions

**Files:**
- Create: `Sources/Core/AskFacts+DayEvents.swift`, `Sources/App/SessionStore+AskDayEvents.swift`, `Sources/Verification/AskDayEventsChecks.swift` (register at the tail)
- Modify: `Sources/Core/AskRequest.swift`, `Sources/App/AskLookups.swift`, `Sources/App/SessionStore+Ask.swift` (dispatch), `Sources/Verification/AskCatalogueChecks.swift`

**Interfaces:**
- Produces:
  - `AskRequest.dayEvents(AskRange)`; provenance `"what happened (\(range.title))"`.
  - Core values: `struct AskEventItem: Equatable { enum Kind: Equatable { case breakTaken(name: String?), away(answer: String?, outcome: String?, credited: TimeInterval?), pending, mac(title: String, found: String?) }; let kind: Kind; let from: String; let to: String?; let length: TimeInterval? }` and `struct AskEventDay: Equatable { let label: String; let items: [AskEventItem]; let breaks: Int; let breakTime: TimeInterval; let answers: Int; let pending: Int; let macSummary: String? }`.
  - `AskFacts.dayEvents(_ range: AskRange, days: [AskEventDay], total: Int, logFrom: String?, beforeLog: Bool) -> String` — `days` newest first; `total` = days with anything to tell in the range.
  - Catalogue entry 6 `dayEvents`, description and parameter exactly as spec §1.
  - Reader: `func askDayEvents(_ range: AskRange) -> AskLookupResult` — per day in `periodCalendar`: breaks from `storyDayProjection(on:calendar:)` `.rest` entries; answers and pending absences from `storyTimelineItems(on:)` (`.decision(receipt, range)`: `answer = receipt.name`, `outcome = receipt.title`, `credited` only for `.mergeTime`; `.pending(range)`); Mac rows from `macAccount(on:)?.rows` (`title`, span, `foundAt`) and `macAccount(on:)?.summary`. Links: `askPeriodLink(range, role: .whatHappened)` then `askPlaceLink` for each day listed.

- [ ] **Step 1: Write the failing tests** (`AskDayEventsChecks`, on `AskDataFixture`; data a test needs beyond it is added inside that test):
- `"One day lists breaks, answers and the Mac's rows in time order"`: `askLookup(.dayEvents(<Mon 13 Nov>))` starts `"Mon 13 Nov:\n"`; contains, in this order, `"from 10:40am to 11:05am · away · answered “Meeting”: Counted as focus, 25m"`, `"from 12:25pm to 1:10pm · break “Lunch” · 45m"`, a line `"from 12:25pm to 1:10pm · <title>"` for the lock row with its `title` from `macAccount(on:)`, `"from 3:40pm to 3:55pm · break · 15m"`, `"from 4:10pm to 4:30pm · away · answered “Coffee”: Recorded as a break"`, and the sleep row clipped to the day, `"from 11:48pm to 12:00am · <title>"`; every `macAccount(on:)?.rows` title appears. Items that start together keep the order breaks, answers, Mac.
- `"A crash is told with when it was found"`: Tue 14 Nov's text contains the crash row's title and `"found at 8:02am"`.
- `"A longer period is one line a day, newest first"`: `.thisWeek` (Mon 13 – Sun 19 Nov) text has `"Tue 14 Nov · "` before `"Mon 13 Nov · 2 breaks, 1h · 2 answers about time away · <summary>"` where `<summary>` is `macAccount(on: Mon 13 Nov)?.summary`.
- `"The event log's first day is said"`: `.lastWeek` contains `"The Mac's events are recorded from Sun 12 Nov."`; a period wholly before Sun 12 Nov contains `"No Mac events were recorded before Sun 12 Nov."`.
- `"With no event log, nothing is said about the Mac"`: `store.machineEventLog = nil` → no `"Mac"` in Mon 13 Nov's text, breaks and answers still listed.
- `"An absence not yet answered says so"`: a pending away range today → `"away, not answered yet"`.
- `"Nothing to tell says so"`: a day with no events → `"No breaks, time away or Mac events recorded on <title>."` (`range.inPhrase`).
- `"A long history stays within 1 KB and counts every day"`: 1,000 extra days, each with one unnamed break (added in the test) → `.allTime` text ≤ 1,024 bytes and ends `"Newest N of M days."` where N is the number of day lines listed, N < M, and M equals 1,000 plus the fixture's days with anything to tell, counted in the test from the same sources.
- `"What happened lists the period and each day it names"` (the spec's `AskLookupLinkChecks` coverage for the new lookups lives in each new suite): links `[period(.whatHappened), day Mon 13 Nov, …]`.
- `AskCatalogueChecks`: entry 6 name, description, schema (one required `range` with part 1's guide).

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement** the values, `AskFacts.dayEvents` (one-day form when the range is one day; else one line per day: `"<label> · N break(s), <time> · N answer(s) about time away · N absence(s) not answered yet · <macSummary>"`, parts left out when zero; `"Newest N of M days."` kept whole as the tail when not all fit), the reader (walk newest first, stop once the text is full; count `M` from archive break records, receipts and event-log days, not projections), the dispatch (with `askStillToCome`), and the catalogue entry.

- [ ] **Step 4: Run to verify they pass.**

- [ ] **Step 5: Commit** — subject: "Ask can say what happened between sessions: breaks, time away and what the Mac did".

---

### Task 6: Ask can give a session's stretches, notes and battery readings

**Files:**
- Create: `Sources/Core/AskFacts+SessionDetail.swift`, `Sources/App/SessionStore+AskSessionDetail.swift`, `Sources/Verification/AskSessionDetailChecks.swift` (register at the tail)
- Modify: `Sources/Core/AskRequest.swift`, `Sources/App/AskLookups.swift`, `Sources/App/SessionStore+Ask.swift`, `Sources/Verification/AskCatalogueChecks.swift`

**Interfaces:**
- Produces:
  - `AskRequest.sessionDetail(AskRange, words: String?)`; provenance `"session detail" + matching(words) + " (\(range.title))"`.
  - `struct AskStretchLine: Equatable { let from: String; let to: String?; let worked: TimeInterval; let power: String?; let note: String? }` (`to == nil` is the running stretch); `struct AskSessionDetail: Equatable { let name: String; let day: String; let stretches: [AskStretchLine] }`.
  - `AskFacts.sessionDetail(_ range: AskRange, words: String?, sessions: [AskSessionDetail], matched: Int) -> String`.
  - Catalogue entry 7 `sessionDetail`, description and parameters exactly as spec §1 (with "such as whether the Mac was plugged in").
  - Reader `func askSessionDetail(_ range: AskRange, words: String?) -> AskLookupResult`: days to read from `askHits(matching:in:)` (words) or every day with focus, newest first; per day `storyDayProjection(on:calendar:)` `.session` entries (running included), each stretch one of `session.recordIDs`' records clipped to the day (the running stretch from `engine.runningSpan`); `power = powerSummary(for: [recordID], interval: <stretch>)?.headline`; `note` = the record's note, first line. At most ten sessions. Links: `askPeriodLink(range, role: .stretches)` then `askSessionLink(thread:name:day:role: .stretches)` per session.

- [ ] **Step 1: Write the failing tests** (`AskSessionDetailChecks`, on `AskDataFixture`; data beyond it is added inside the test that needs it):
- `"A session's stretches are listed with their times, note and power"`: `askLookup(.sessionDetail(<Mon 13 Nov>, words: "thesis"))` `==` `"Thesis · Mon 13 Nov · 2 stretches: from 9:00am to 10:40am, 1h 40m, <powerA>, note “chapter three, fixed citations”; from 11:05am to 12:25pm, 1h 20m, <powerB>"` where `<powerA>`/`<powerB>` are `store.powerSummary(for: [A.id], interval: A's span)?.headline` and B's.
- `"A stretch across midnight is split at midnight"`: with a Deep work record "Late" 11:00pm Tue 14 Nov – 1:00am Wed 15 Nov added, Tue 14 Nov reads `"Late · Tue 14 Nov · 1 stretch: from 11:00pm to 12:00am, 1h"`; today reads `"Late · Wed 15 Nov · 1 stretch: from 12:00am to 1:00am, 1h"`.
- `"The running session reads as running"`: with a "Review" session started at 9:00am today (clock at 9:13am), today's text contains `"Review · Wed 15 Nov · 1 stretch: running from 9:00am, 13m so far"`.
- `"More than ten sessions end with how many there were"`: twelve sessions in a week → ten listed, ends `"Newest 10 of 12."`.
- `"No session says so"`: words `"nothing"` → `"No sessions match “nothing” on <title>."`.
- `"A long history stays within 1 KB"`: `.allTime` over 1,000 extra days ≤ 1,024 bytes.
- `"Session detail lists the period and each session"`: links `[period(.stretches), session Thesis Mon 13 Nov (.stretches), …]`.
- `AskCatalogueChecks`: entry 7 name, description, schema (`range` required with part 1's guide, `words` optional).

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement** the values, the facts (`"<name> · <day> · N stretch(es): <stretch>; <stretch>"`, a stretch `"from <from> to <to>, <worked>[, <power>][, note “<note>”]"` or `"running from <from>, <worked> so far"`; one session per line; `"Newest N of M."` tail kept whole), the reader, dispatch and entry.

- [ ] **Step 4: Run to verify they pass.**

- [ ] **Step 5: Commit** — subject: "Ask can give a session's stretches with their notes and battery readings".

---

### Task 7: Ask can tell the daily goal, the streak and awards

**Files:**
- Create: `Sources/Core/AskFacts+Goals.swift`, `Sources/App/SessionStore+AskGoals.swift`, `Sources/Verification/AskGoalsChecks.swift` (register at the tail)
- Modify: `Sources/Core/AskRequest.swift`, `Sources/App/AskLookups.swift`, `Sources/App/SessionStore+Ask.swift`, `Sources/Verification/AskCatalogueChecks.swift`

**Interfaces:**
- Consumes: `askStreak()` (Task 4), `.awards` target and roles (Task 1).
- Produces:
  - `AskRequest.goals(AskRange?)`; provenance `range.map { "goals (\($0.title))" } ?? "goals"`.
  - `struct AskAwardLine: Equatable { let title: String; let detail: String }`; `struct AskGoals: Equatable { let goal: TimeInterval; let today: TimeInterval; let todayPercent: String; let period: AskGoalPeriod?; let streakDays: Int; let streakSince: String?; let streakMinimum: TimeInterval; let bestStreak: Int; let earned: [AskAwardLine]; let toEarn: [AskAwardLine] }`; `struct AskGoalPeriod: Equatable { let label: String; let met: Int; let days: Int }`.
  - `AskFacts.goals(_ goals: AskGoals) -> String`.
  - Catalogue entry 8 `goals`, description and parameter exactly as spec §1.
  - Reader `func askGoals(_ range: AskRange?) -> AskLookupResult`: `goal` = the goal the Story rail's Daily goal tile reads; `today` = `storyDayProjection(on: today, calendar: periodCalendar).goalCredit`; `todayPercent` with the percent wording that tile uses; period days met counted as `SessionStore+Notes` counts them (`goalCredit >= goal`, days from `max(period start, first recorded day)` up to and including today); streak from `askStreak()`, best from `engine.archive.bestStreak()`, minimum `engine.store.streakMinimum`; awards from `store.awards` (`title`, `detail`, `isEarned`). Links: `askPeriodLink(range ?? .today, role: .dailyGoal)`, then `AskLink(target: .awards, label: "Awards", role: .streakAndAwards, names: ["streak", "streaks", "award", "awards"] + awards.map(\.title))`.

- [ ] **Step 1: Write the failing tests** (`AskGoalsChecks`, on `AskDataFixture`):
- `"Goals read the goal, today's progress, the streak and awards"`: `askLookup(.goals(nil))` `==` `"Daily goal: 4h of focus during recorded app use. Today so far: 0m, 0%, not met yet.\nCurrent streak: 5 days with at least 1h of focus, since Fri 10 Nov. Longest: 12 days.\n" + <awards>` where `<awards>` is built from `store.awards`: `"Awards earned: <title> (<detail>); …. Still to earn: <title> (<detail>); …."`, or `"No awards earned yet."` for the earned part when none.
- `"Days met are counted on goal credit against today's goal"`: `.goals(.thisWeek)` contains `"This week (13 Nov – 19 Nov): met on 1 of 3 days, against today's goal."`; and `.goals(.day(<Thu 5 Oct 2023>))` contains `"met on 0 of 1 days"`: 5h of focus but 1h of goal credit (mutation guard: judged on focus it would read `1 of 1`).
- `"The streak follows the store's clock"`: move `clock` to Sat 18 Nov → `"No current streak: a day counts at 1h of focus. Longest: 12 days."` (mutation guard: a wall-clock read would not move).
- `"Goals list the period and Awards"`: links `[period(.dailyGoal) or today(.dailyGoal), .awards (.streakAndAwards)]`; the awards link's `names` include every award title.
- `"With no award earned, goals say so"` (Core only): `AskFacts.goals(<an AskGoals with earned: [] and one toEarn line>)` contains `"No awards earned yet. Still to earn: "`.
- `"Goals for a period still to come say so"`: `.goals(.day(<next Monday>))` → part 1's `"… is still to come."`.
- `AskCatalogueChecks`: entry 8; the catalogue's names are part 1's five then `dayEvents`, `sessionDetail`, `goals`.

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement** the values, `AskFacts.goals` (lines: goal and today — `"Today so far: <today>, <percent>, not met yet."` or `"Today: <today>, met."`; the period line when given; streak — `"Current streak: N day(s) with at least <minimum> of focus, since <day>. Longest: N day(s)."` or `"No current streak: a day counts at <minimum> of focus. Longest: N day(s)."`; awards), the reader, dispatch and entry.

- [ ] **Step 4: Run to verify they pass.**

- [ ] **Step 5: Commit** — subject: "Ask can tell the daily goal, the streak and awards, and open Awards".

---

### Task 8: Snapshot of an answer with an Awards source; README

**Files:**
- Modify: `Sources/Surfaces/Snapshotter.swift` (case `askGoals`, title `"Ask — an answer whose sources open History and Awards"`, grouped with the other Ask cases everywhere they are listed), `Sources/Surfaces/Snapshotter+Ask.swift` (its turns), `README.md` (Ask's paragraph)

**Interfaces:**
- Consumes: roles and `.awards` (Task 1).

- [ ] **Step 1:** `askGoals` shows one answered turn — question `"Did I keep my streak going this week?"`, answer `"This week you met your goal on 3 of 5 days, and your current streak is 5 days, since Fri 10 Nov. You worked on Thesis most."` — with sources: `This week` (period, `.dailyGoal`), `Awards` (`.awards`, `.streakAndAwards`), `Thesis · Mon 13 Nov` (session, `.stretches`).
- [ ] **Step 2:** Render it (`--snapshot`, `FC_SNAPSHOT_ONLY=askGoals`, `FC_SNAPSHOT_ZOOM=1.0|1.4`, light and dark, sheet; and panel via the panel scenarios' window) and look at it: the rosette row aligns with the calendar and clock rows; nothing is clipped at 140%.
- [ ] **Step 3:** README: Ask's paragraph lists what Ask can now answer (stretches, breaks, time away, the Mac's events, notes, work types, app hours, the daily goal, the streak and awards) and that every answer lists where it came from; privacy sentences unchanged.
- [ ] **Step 4:** `./build.sh --check`; commit — subject: "The README says what Ask can answer, and snapshots show an answer that opens Awards".

---

### Task 9 (controller): live-model probes, recorded in the spec

Not a subagent task: it needs the on-device model and the git-ignored probe kit in `.superpowers/sdd/2026-10-11-ask-daybook-v2-part2/probe/`.

- [ ] Extend the kit's fixture (`AskProbe-v2.swift` `makeStore()`) with the spec §5 fixture data, mirroring `AskDataFixture` on Fri 9 Oct 2026; drop the routing stubs (build with the real catalogue).
- [ ] Probe 1: the 32 family questions (`probe/routing/key.tsv`) plus one per miss; grade with `grade.py` adapted to real lookup names; read every answer for invented figures. Pass: ≥ 28/32 right lookup, no invented figure, sources include the place named.
- [ ] Probe 2: the 37 baseline questions, three runs (`run-all.sh` with the memory-pressure retry). Pass: every answer right; Parser `4h`.
- [ ] Probe 3: depth, part 1's ten follow-ups ×3. Record the turn where the context fills and the carried answer.
- [ ] Probe 4: speed on a quiet machine (no `swift-frontend`, pressure level 1). Pass: median ≤ 4.7 s, max ≤ 10 s; record the extra-first-lookup share.
- [ ] Add an "After" section to the spec's Evidence with the four results, as part 1's spec did; commit.

### Task 10 (controller): finish

- [ ] Mutations, each in a temporary copy (`rsync -a build.sh Sources Assets scripts`): streak via `Date()` → `AskGoalsChecks` fails; goal met judged on focus → fails; Awards naming rule removed → `AskSourceOrderChecks` fails.
- [ ] `fix-reviewer` on the branch diff; fix findings.
- [ ] Final review: whole-branch code review (opus), design critique of the Task 8 renders, hand checks on an isolated fixture app (`scripts/build-fixture-app.sh`, addressed by pid; spec §5 table), fixes in one wave.
- [ ] Merge `origin/main`; renumber the registry tail if it moved; `./build.sh --check` and `TZ=Europe/Berlin ./build.sh --check` unsandboxed, both all-pass.
- [ ] Push the branch; post "ready" on the sessions board with head, pass counts and registry tail; message the "Review open sessions" director with the PR body.
