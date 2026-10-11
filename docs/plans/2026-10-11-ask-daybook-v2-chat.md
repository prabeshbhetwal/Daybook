# Ask Daybook v2, part 1: chat, sources and the side panel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ask becomes a chat whose answers list their sources in reading order and open History at them, with a lookup cap per answer and an optional side panel.

**Architecture:** Lookups are defined once in a catalogue; the on-device adapter turns each into a dynamic FoundationModels `Tool` whose calls all pass through one gate per answer (count, cap, progress, sources). `AskModel` holds the chat as `[AskTurn]`; a pure Core picker orders each answer's sources; `MainWindowModel` opens Ask as a sheet or a window-level trailing panel and follows a source into History.

**Tech Stack:** Swift 5 language mode, SwiftUI + AppKit, FoundationModels (macOS 26+, weak-linked), Daybook's headless self-check suite.

**Spec:** `docs/specs/2026-10-11-ask-daybook-v2-chat-design.md`

## Global Constraints

- Swift 5 mode, target macOS 14.0; every FoundationModels use behind `@available(macOS 26, *)` / `#available`. No SwiftPM or other new dependency.
- `Sources/Core` stays UI-free and compiles alone; a Core file may not use an App type.
- Lookup text does not change: every existing `AskLookup*`, `AskAccuracyChecks`, `AskEdgeChecks`, `AskOverlapChecks`, `AskRunningSessionChecks`, `AskMidnightAskChecks`, `AskLiveAppTimeChecks`, `AskRangeZoneChecks` check passes untouched.
- `AskModel.instructions(today:)` with nothing carried, the tool names, descriptions and parameter schemas, the tool order and greedy sampling are byte-identical to v1.
- Cap: lookups 1–5 are real; calls 6 and 7 get "Lookup limit reached for this question. Answer from what the earlier lookups returned."; call 8 ends the answer.
- Lengths in `Sources/App`, `Design`, `Surfaces` are tokens or `.zoomed`; a 100%-size base carries `// zoom: fixed`. Text uses `Tokens.Typography` roles only.
- Checks use `TestClock`, `SelfTest.scratchDirectory()`, `MemoryDefaults.suite(named: "fc-selftest-…")` (never `UserDefaults(suiteName:)`), dates from the calendar the code uses. New suites go at the end of `registeredTests`.
- `keep_internals`: add a method on `SessionEngine`/`SessionStore` instead of touching a listed internal member from elsewhere.
- Edit Swift by exact text, never by line number. New files stay under 300 lines.
- Copy is Australian English, with no em dashes in interface text.
- The repository is public: no machine-specific paths, secrets or personal data in commits.
- Commit subject: one plain present-tense sentence of what is now true; body wrapped prose; end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

**Commands** (run `build.sh` with the sandbox disabled):

- Typecheck, about 100 s: `swiftc -typecheck -module-cache-path "$TMPDIR/mc" -swift-version 5 -parse-as-library -warnings-as-errors -target arm64-apple-macos14.0 -F "$SPARKLE" $(find Sources -name '*.swift')`, where `$SPARKLE` is `.build/vendor/Sparkle-2.10.0` in a checkout that has run `build.sh` (the main checkout's when this worktree has none). Expected: no output.
- Suite: `./build.sh --check`. Expected: every check passes, the run reports passed equal to total.
- Other zone: `TZ=Europe/Berlin ./build.sh --check`. Same expectation.

## Review Focus

1. **A date the picker does not read** ("15/9", "the 15th"): the answer gets its lookups' anchors, never a wrong place. Test: Task 1 `unreadFormatsFallBackToAnchors`.
2. **A source whose session was renamed or deleted before it is clicked**: a deleted one opens its day; a renamed one still opens by thread. Test: Task 6 `missingSessionOpensItsDay`, `renamedSessionStillOpensByThread`.
3. **New chat or Stop while a lookup is in flight**: the late lookup is answered but counted nowhere. Test: Task 5 `lateLookupAfterStopIsNotCounted`.
4. **Panel open on a small screen or at 140%**: the window minimum is held to the screen, nothing grows off it. Test: Task 8 `panelMinimumHeldToScreen`.
5. **An answer naming many sessions, or a very long session name**: five rows then "Show N more"; a long label is cut to one line with its full text in help and VoiceOver. Test: Task 7 `sourcesShowFiveThenMore`, `longLabelKeepsFullTextForVoiceOver`.

## Spec adjustments made by this plan

- `AskNotice` moves from `AskModel.swift` to Core (`AskTurn.swift`), unchanged, so a Core `AskTurn` can hold one.
- The placement is read by `MainWindowModel.openAsk()` from the store's preferences at call time (`store.engine.store.askPlacement`), so ⌘K, the bar button and Settings need no extra wiring. A placement changed while the panel is open closes it when Settings closes (`closeSheet()`), which is the moment the change becomes visible.
- The README's backup sentence states the default truthfully (see Task 9): new installs back up daily to iCloud Drive. The owner chose this wording on 2026-10-11 over softening the claim or making backups opt-in.

## File map

| File | Task | Responsibility |
|---|---|---|
| `Sources/Core/AskLink.swift` (new) | 1, 3 | `AskSourceRole`, `AskLink`, `AskSource`, `AskLookupResult` |
| `Sources/Core/AskSourcePicker.swift` (new) | 1 | Reads an answer for named sources; orders them |
| `Sources/Core/AskLookupSpec.swift` (new) | 2 | `AskParameter`, `AskLookupSpec` |
| `Sources/App/AskLookups.swift` (new) | 2 | The five catalogue entries |
| `Sources/App/AskOnDeviceTool.swift` (new) | 2 | Dynamic `Tool` per entry |
| `Sources/App/AskTools.swift` | 2 | Moved to `_trash/` (its `@Generable` structs live on in `AskCatalogueChecks` as v1's reference) |
| `Sources/App/SessionStore+Ask.swift`, `+AskClips.swift` | 3 | Lookups return text and sources |
| `Sources/App/SessionStore+AskLinks.swift` (new) | 3 | Building a source from a range, place or session |
| `Sources/Core/AskFacts.swift` | 4 | Limit line, unknown-lookup line |
| `Sources/App/AskGate.swift` (new) | 4 | Per-answer count, cap, progress, sources |
| `Sources/Core/AskTurn.swift` (new) | 5 | `AskNotice` (moved), `AskTurnState`, `AskTurn`, `AskPlacement` |
| `Sources/App/AskModel.swift`, `AskModel+Notices.swift` (new) | 5 | The chat; notices moved out |
| `Sources/App/ModelGate.swift` (new unless main has it) | 5 | Copied byte for byte from the notes branch |
| `Sources/Core/PersistenceStore.swift`, `Sources/App/SettingsModel.swift`, `Surfaces/Settings/SettingsSidebar.swift` | 6 | `fc.askPlacement` and its Settings control key |
| `Sources/App/MainWindowModel.swift`, `MainWindowModel+Ask.swift` (new) | 6 | Panel state, `openAsk`, `follow`, `openHistory(place:)` |
| `Sources/Surfaces/Ask/AskChatView.swift`, `AskTurnView.swift`, `AskSourcesView.swift` (new), `AskSheet.swift` | 7 | Chat surface; sheet wrapper |
| `Sources/Surfaces/Ask/AskPanel.swift` (new), `Main/MainWindowView.swift`, `Main/AskChromeButton.swift`, `Main/StoryChromeBar.swift`, `Design/Components/ZoomWindowFit.swift`, `Settings/SettingsAskPanel.swift` | 8 | Side panel |
| `Sources/Surfaces/Snapshotter.swift`, `Surfaces/Story/StoryColumns.swift` | 7, 8 | Scenarios; render evidence |
| `README.md`, the spec | 9 | Privacy paragraph; recorded evidence |

---

### Task 1: Sources and the picker

**Files:**
- Create: `Sources/Core/AskLink.swift`, `Sources/Core/AskSourcePicker.swift`, `Sources/Verification/AskSourceOrderChecks.swift`
- Modify: `Sources/Verification/SelfTest/SelfTest+Registry.swift` (append `+ AskSourceOrderChecks.tests`)

**Interfaces:**
- Consumes: `HistoryPlace`, `HistoryLevel` (Core/HistoryTree.swift).
- Produces:
```swift
enum AskSourceRole: String, Equatable {
    case totals = "Totals", bestDay = "Most focused day", bestWeek = "Most focused week",
         bestMonth = "Most focused month", longestSession = "Longest session", session = "Session",
         compared = "Compared", bestHours = "Best hours", appTime = "App time"
}
struct AskLink: Hashable {
    enum Target: Hashable { case day(Date), session(thread: UUID, day: Date), period(HistoryPlace), history }
    let target: Target
    let label: String          // "Tue 15 Sep", "Thesis · Tue 15 Sep", "5 Oct – 11 Oct", "August 2026", "All time"
    let role: AskSourceRole
    var sessionName: String? = nil
}
/// `mention`: character offsets of its first mention in the answer; nil for an anchor the answer did not name.
struct AskSource: Equatable { let link: AskLink; let mention: Range<Int>? }
enum AskSourcePicker {
    static let shownAtOnce = 5
    /// `lookups`: each lookup's links, its anchor first, in the order the lookups were made.
    static func sources(answer: String, lookups: [[AskLink]], calendar: Calendar, now: Date) -> [AskSource]
}
```

- [ ] **Step 1: Write the failing checks** in `AskSourceOrderChecks.swift`. Fixture: `calendar = Calendar.current.forPeriods`, `now` = 10 Oct 2026 17:30 built from components in that calendar; links built with that calendar: `tue15` = `.day(15 Sep 2026)` "Tue 15 Sep" `.bestDay`; `sep` = `.period(month Sep 2026)` "September 2026" `.totals`; `week` = `.period(week 5–11 Oct)` "5 Oct – 11 Oct" `.bestWeek`; `fri9` = `.day(9 Oct)` "Fri 9 Oct"; `thesisSep` / `thesisOct` = `.session` named "Thesis" on 15 Sep / 9 Oct; `cafe` = `.session` named "Café notes" on 9 Oct; `all` = `.history` "All time" `.totals`. Each test asserts the ordered `link.label`s:

| Test | Answer | Lookups | Expected labels (mention) |
|---|---|---|---|
| `namedDayThenAnchor` | "The most focused day in the entire year was Tuesday, 15 September." | `[[all, tue15, sep]]` | `Tue 15 Sep` (mentioned), `All time` (nil) |
| `readingOrderNotLookupOrder` | "Tue 15 Sep was the best day of September 2026." | `[[sep, tue15]]` | `Tue 15 Sep`, `September 2026` |
| `readingOrderOtherWay` | "In September 2026, the best day was Tue 15 Sep, with 9h." | `[[sep, tue15]]` | `September 2026`, `Tue 15 Sep`; mention of `Tue 15 Sep` equals the offsets of that substring |
| `wrongYearIsNotNamed` | "Your best day was 15 September 2025." | `[[sep, tue15]]` | `September 2026` (nil) only |
| `dayNumberDoesNotNameMonth` | "The best day was 15 September." | `[[sep, tue15]]` | `Tue 15 Sep` (mentioned), `September 2026` (nil) |
| `yesterdayNamesDay` | "Yesterday you focused 3h 42m." | `[[fri9]]` | `Fri 9 Oct` (mentioned) |
| `weekByEndsOrThisWeek` | "The most focused week was 5 Oct – 11 Oct." and "This week was your best." | `[[week]]` | `5 Oct – 11 Oct` mentioned in both |
| `sharedNameUsesNamedDay` | "Thesis ran longest on Friday 9 October." | `[[thesisSep, thesisOct]]` | `Thesis · Fri 9 Oct` first; `Thesis · Tue 15 Sep` (nil, as the anchor) second |
| `sharedNameDefaultsToNewest` | "Thesis ran longest." | `[[thesisSep], [thesisOct]]` | `Thesis · Fri 9 Oct` (mentioned), `Thesis · Tue 15 Sep` (nil) |
| `accentsAndCaseIgnored` | "Most of it went to cafe NOTES." | `[[cafe]]` | `Café notes · Fri 9 Oct` mentioned |
| `unreadFormatsFallBackToAnchors` | "Your best day was 15/9, a Tuesday." | `[[sep, tue15], [all]]` | `September 2026`, `All time`, both nil |
| `sameTargetListedOnce` | "Tue 15 Sep." | `[[tue15], [tue15, sep]]` | `Tue 15 Sep`, `September 2026` |

- [ ] **Step 2: Register and typecheck.** Expected: errors naming `AskSourcePicker`, `AskLink`.

- [ ] **Step 3: Implement** the types in `AskLink.swift` and the picker in `AskSourcePicker.swift`. Rules (spec §5): named links first, sorted by first mention offset (ties keep lookup order), then each lookup's first link whose target is not yet listed; one entry per target, at its first place. Matching runs on the original string with case- and diacritic-insensitive comparison so offsets stay true. Mentions to read:
  - day: `(\d{1,2})(st|nd|rd|th)?( of)? MONTH` or `MONTH (\d{1,2})(st|nd|rd|th)?`, optional leading weekday and comma, optional `,? (\d{4})` after; MONTH = `jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|may|june?|july?|aug(ust)?|sep(t(ember)?)?|oct(ober)?|nov(ember)?|dec(ember)?` as a whole word; `today` / `yesterday` as whole words.
  - month: MONTH not inside a day mention, optional following year. Year: a four-digit `19xx`/`20xx` not inside a date. Week: both end days mentioned, `week of` + its first day, or `this week` / `last week` when the week is `calendar.dateInterval(of: .weekOfYear, for: now)` or the one before.
  - session: whole-word occurrence of `sessionName`; when several links share the folded name, keep those whose day is mentioned, else the newest.
  - `.history` links are never named; they appear only as anchors.

- [ ] **Step 4: Run** `./build.sh --check`. Expected: all pass. Then in a temporary tree copy, sort named links by lookup order instead of offset: `readingOrderNotLookupOrder` must fail. Remove the copy.

- [ ] **Step 5: Commit** — "Ask can tell which days, weeks, months and sessions an answer names, in reading order".

---

### Task 2: The catalogue and the dynamic tool

**Files:**
- Create: `Sources/Core/AskLookupSpec.swift`, `Sources/App/AskLookups.swift`, `Sources/App/AskOnDeviceTool.swift`, `Sources/Verification/AskCatalogueChecks.swift`
- Modify: `Sources/App/AskModel.swift` (`liveSession()` builds tools from the catalogue; new `lookup(name:arguments:generation:)`), `Sources/Verification/AskModelChecks.swift` (`toolChecks` moves to `AskCatalogueChecks`), registry (append `+ AskCatalogueChecks.tests`)
- Move: `Sources/App/AskTools.swift` → `_trash/AskTools.swift` (ignored by git; `git add -A Sources` records the removal)

**Interfaces:**
- Consumes: `AskRequest`, `AskRange.resolving` via `AskModel.range(_:)`, `AskFacts.noSuchPeriod`.
- Produces:
```swift
// Core
struct AskParameter: Equatable { let name: String; let description: String; let required: Bool }
struct AskLookupSpec: Equatable { let name: String; let description: String; let parameters: [AskParameter] }
// App
enum AskLookupCall: Equatable { case request(AskRequest), refusal(String) }
struct AskLookup {
    let spec: AskLookupSpec
    /// Arguments trimmed; an empty string is absent. `period` reads a period as AskModel.range(_:) does.
    let read: (_ arguments: [String: String], _ period: (String) -> AskRange?) -> AskLookupCall
}
enum AskLookups {
    static let all: [AskLookup]                 // focusTotals, compareFocus, bestHours, findSessions, appTime
    static func named(_ name: String) -> AskLookup?
}
@available(macOS 26, *)
struct AskOnDeviceTool: Tool {
    typealias Arguments = GeneratedContent
    let name: String; let description: String; let parameters: GenerationSchema
    init(_ lookup: AskLookup, model: AskModel, generation: Int) throws
    static func schema(for spec: AskLookupSpec) throws -> GenerationSchema
    func call(arguments: GeneratedContent) async -> String   // → model.lookup(name:arguments:generation:)
}
// AskModel (this task routes to the v1 path; Task 5 routes it to the gate)
func lookup(name: String, arguments: [String: String], generation: Int) -> String
```

- [ ] **Step 1: Write the failing checks** in `AskCatalogueChecks.swift`. Copy v1's five `@Generable struct Arguments` verbatim from `AskTools.swift` into `private enum V1 { struct FocusTotalsTool { @Generable struct Arguments … } … }` (same nesting, same guides, `AskToolArguments.rangeGuide` text inlined as a constant):
  - `entriesMatchVersionOne`: names in order `["focusTotals", "compareFocus", "bestHours", "findSessions", "appTime"]`; each description equals v1's string literal.
  - `schemasMatchVersionOne` (macOS 26): for each entry, `AskOnDeviceTool.schema(for:)` encodes (`JSONEncoder`, `.sortedKeys`) to the same bytes as `V1.<Tool>.Arguments.generationSchema`. If `GenerationSchema` is not `Encodable` in the SDK, compare `debugDescription` and say so in the check's comment.
  - `argumentsReadAsVersionOne`: v1's twelve `toolChecks` cases, each as `AskLookups.named(name)!.read(args, model.range)` == the same `AskRequest`; plus `bestHours` with no range → `.bestHours(.allTime)`, `findSessions` with no words → `words: ""`, `focusTotals` range "31 february" → `.refusal("There is no such date as “31 february”.")`, empty `words` → `nil`.
  - `toolCallReturnsLookup` (macOS 26): `AskOnDeviceTool(AskLookups.named("focusTotals")!, …).call(arguments: GeneratedContent(properties: ["range": "this week"]))` returns `f.store.askLookup(.focusTotals(.thisWeek, words: nil))` (turn the run loop until it lands, as v1's `toolChecks` does).

- [ ] **Step 2: Register and typecheck.** Expected: errors naming `AskLookups`, `AskOnDeviceTool`.

- [ ] **Step 3: Implement** the catalogue (names, descriptions, parameter names, descriptions, optionality and order copied from v1; `rangeGuide` text moves into `AskLookups`), `AskOnDeviceTool` (`DynamicGenerationSchema` with one `String` property per parameter, `isOptional: !required`; root schema name chosen so `schemasMatchVersionOne` passes; `call` reads each property with `try? arguments.value(String.self, forProperty:)`), `AskModel.lookup(name:arguments:generation:)` (unknown name → `""` for now; `.refusal(text)` → text; `.request(r)` → existing `lookup(r, generation:)`), and `liveSession()` building `AskLookups.all.compactMap { try? AskOnDeviceTool($0, model: self, generation: generation) }` in catalogue order. Move `AskTools.swift` to `_trash/`. Delete `toolChecks`/`toolsMatchLookups` from `AskModelChecks` (now covered here).

- [ ] **Step 4: Run** `./build.sh --check`. Expected: all pass.

- [ ] **Step 5: Parity probe.** Build the `--askprobe` harness (the session's probe kit: a temporary copy of `Sources/`, `AskProbe.swift` with the 2026-10-10 fixture, the `--askprobe` entry patched into `DaybookApp.swift`, plain `swiftc -Onone … -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker "$SPARKLE"`) from this tree and run the 37 baseline questions. Compare tool-call lines and answers with the 2026-10-11 baseline log. Expected: identical. On any difference, stop and fix the schema before Task 3; if a difference survives and every answer is still right, record it in the spec's evidence and continue only with the owner's agreement.

- [ ] **Step 6: Commit** — "Ask's lookups are defined once, and the on-device model reaches them through one tool shape".

---

### Task 3: Lookups return their sources

**Files:**
- Create: `Sources/App/SessionStore+AskLinks.swift`, `Sources/Verification/AskLookupLinkChecks.swift`
- Modify: `Sources/Core/AskLink.swift` (add `AskLookupResult`), `Sources/App/SessionStore+Ask.swift`, `Sources/App/SessionStore+AskClips.swift`, registry (append `+ AskLookupLinkChecks.tests`)

**Interfaces:**
- Consumes: Task 1 `AskLink`, `AskSourceRole`.
- Produces:
```swift
struct AskLookupResult: Equatable { let text: String; let links: [AskLink] }     // Core
extension SessionStore {
    func askLookupResult(_ request: AskRequest) -> AskLookupResult
    func askLookup(_ request: AskRequest) -> String      // unchanged signature: askLookupResult(request).text
}
```

- [ ] **Step 1: Write the failing checks** with `AskLookupChecks.withFixture` (Wed 15 Nov 2023 09:13; Thesis Mon 13 Nov 9–10; Parser Tue 14 Nov 14:00–15:30; Thesis Tue 17 Oct 9–11). Assert targets and roles in order:
  - `totalsThisWeek`: `.focusTotals(.thisWeek, nil)` → `[.period(week 13–19 Nov) .totals, .day(14 Nov) .bestDay, .session(Parser, 14 Nov) .longestSession]`; labels `13 Nov – 19 Nov`, `Tue 14 Nov`, `Parser · Tue 14 Nov`.
  - `totalsAllTime`: first link `.history` labelled `All time`, role `.totals`; contains `.day(17 Oct) .bestDay` and `.session(Thesis 17 Oct) .longestSession`.
  - `totalsOneDay`: `.focusTotals(.day(2023, 11, 13), nil)` → `[.day(13 Nov) .totals]`.
  - `compareBothPeriods`: `.compare(.thisWeek, with: .day(2023, 10, 17), nil)` → `[.period(week) .compared, .day(17 Oct) .compared]`.
  - `findSessionsListsSessions`: `.findSessions(words: "thesis", .allTime)` → `[.history, .session(Thesis 13 Nov), .session(Thesis 17 Oct)]`, sessions `.session` role with `sessionName == "Thesis"`.
  - `widenedSearchKeepsAskedPeriod`: `.findSessions(words: "outline", .today)` (nothing today, found in all history) → first `.day(15 Nov)`, then `.session(Thesis 13 Nov)`.
  - `bestHoursAndAppTimeNameTheirPeriod`: `.bestHours(.last30Days)` → `[.history]` labelled with the range's title and dates, `.bestHours`; `.appTime(.thisWeek, app: "Safari")` → `[.period(week) .appTime]`.
  - `refusalsHaveNoSources`: a period still to come → `links.isEmpty`.
  - `textUnchanged`: for each request above, `askLookupResult(r).text == askLookup(r)`.

- [ ] **Step 2: Register and typecheck.** Expected: errors naming `askLookupResult`.

- [ ] **Step 3: Implement.** In `SessionStore+AskLinks.swift`: `askPeriodLink(_ range: AskRange, role: AskSourceRole) -> AskLink` (day level → `.day(start)` labelled `askDay`; week, month, year → `.period(place)` labelled `askLabel`; no level → `.history` labelled `range.title` capitalised, with `askDates(range)` in brackets when there are any), `askPlaceLink(_ place: HistoryPlace, role:)`, `askSessionLink(thread: UUID, name: String, day: Date, role:)` (label `"\(name) · \(askDay(day))"`). In `SessionStore+Ask.swift` each private builder returns `AskLookupResult` built in the same pass as its text; `askLongest` also returns the thread and first day; `askSessions` and its widened form return the listed clips' sessions (day = the clip's first day in the range). `askLookup` becomes `askLookupResult(request).text`.

- [ ] **Step 4: Run** `./build.sh --check`. Expected: all pass, every pre-existing Ask suite unchanged.

- [ ] **Step 5: Commit** — "Each Ask lookup says which days, periods and sessions its figures come from".

---

### Task 4: The gate

**Files:**
- Create: `Sources/App/AskGate.swift`, `Sources/Verification/AskGateChecks.swift`
- Modify: `Sources/Core/AskFacts.swift`, registry (append `+ AskGateChecks.tests`)

**Interfaces:**
- Consumes: Task 2 `AskLookups`, `AskLookupCall`; Task 3 `askLookupResult`.
- Produces:
```swift
extension AskFacts {
    static let lookupLimitReached = "Lookup limit reached for this question. Answer from what the earlier lookups returned."
    static func unknownLookup(_ name: String) -> String    // "No lookup called “\(name)”."
}
@MainActor final class AskGate {
    static let lookupLimit = 5
    static let endsAt = 8
    init(store: SessionStore?, period: @escaping (String) -> AskRange?,
         onProgress: @escaping (String) -> Void, onEnd: @escaping () -> Void)
    private(set) var calls: Int
    private(set) var provenance: [String]      // AskRequest.provenance, in call order
    private(set) var lookups: [[AskLink]]      // one entry per real lookup, for AskSourcePicker
    var isOpen: Bool                            // true until the turn ends; a closed gate answers, records nothing
    func lookup(name: String, arguments: [String: String]) -> String
}
```

- [ ] **Step 1: Write the failing checks** with `AskLookupChecks.withFixture`:
  - `fiveRealLookupsThenLimit`: seven `focusTotals` calls ("this week") → calls 1–5 return the store's text and `provenance.count == 5`, `lookups.count == 5`; calls 6 and 7 return `AskFacts.lookupLimitReached`; `onEnd` not called.
  - `eighthCallEndsAnswer`: eight calls → `onEnd` called exactly once, on the eighth.
  - `progressNamesLookup`: one call → `onProgress` received `"Looking up focus totals (this week)…"`.
  - `closedGateRecordsNothing`: `isOpen = false`, then a call → returns the store's text; `provenance`, `lookups` empty; `calls` unchanged.
  - `unknownAndRefusalCount`: `lookup(name: "nope", …)` → `"No lookup called “nope”."`, `calls == 1`; `focusTotals` with range "31 february" → the refusal text, `calls == 2`, `provenance` empty.

- [ ] **Step 2: Register and typecheck.** Expected: errors naming `AskGate`.

- [ ] **Step 3: Implement** `AskGate` and the two `AskFacts` members to the interface. Calls are counted only while `isOpen`.

- [ ] **Step 4: Run** `./build.sh --check`. Expected: all pass. In a temporary tree copy set `lookupLimit = 6`: `fiveRealLookupsThenLimit` must fail. Remove the copy.

- [ ] **Step 5: Commit** — "Ask stops looking things up after five lookups and ends an answer that keeps trying".

---

### Task 5: The chat model

**Files:**
- Create: `Sources/Core/AskTurn.swift`, `Sources/App/AskModel+Notices.swift`, `Sources/App/AskModel+Answer.swift` (answering, Stop, carry and retry, so `AskModel.swift` stays under 300 lines), `Sources/Verification/AskChatChecks.swift`, `Sources/App/ModelGate.swift` (only if main does not have it: `git show e85a2ea:Sources/App/ModelGate.swift > Sources/App/ModelGate.swift`, byte for byte, from the Apple Intelligence notes branch)
- Modify: `Sources/App/AskModel.swift`, `Sources/App/AskModel+Availability.swift`, `Sources/Surfaces/Ask/AskSheet.swift` (compile against `turns`; Task 7 replaces it), `Sources/Surfaces/Snapshotter.swift` (`askAnswered` uses `present(turns:)`), `Sources/Verification/AskModelChecks.swift`, `AskThreadChecks.swift`, `AskEntryChecks.swift`, registry (append `+ AskChatChecks.tests`)

**Interfaces:**
- Consumes: Task 1 `AskSourcePicker`, `AskSource`; Task 4 `AskGate`.
- Produces:
```swift
// Core/AskTurn.swift
struct AskNotice: Equatable { let text: String; let opensSettings: Bool }        // moved unchanged
enum AskTurnState: Equatable {
    case lookingUp(String?), answering, answered, stopped, failed(AskNotice)
    var isInProgress: Bool                                                         // lookingUp or answering
}
struct AskTurn: Identifiable, Equatable {
    let id: UUID; let question: String
    var answer = ""; var state: AskTurnState = .lookingUp(nil)
    var provenance: [String] = []; var sources: [AskSource] = []
}
enum AskPlacement: String, CaseIterable { case sheet, panel }                      // used from Task 6
// AskModel
@Published private(set) var turns: [AskTurn]
@Published private(set) var notice: AskNotice?          // availability only
var isAnswering: Bool                                    // turns.last?.state.isInProgress == true
var canAsk: Bool                                         // ModelGate.modelAvailable
func ask(_ text: String); func stop(); func newChat(); func prepare(); func retireStaleSession()
func present(turns: [AskTurn])                           // snapshots and fixtures only
func lookup(name: String, arguments: [String: String], generation: Int) -> String
private(set) var generation: Int; private(set) var sessionDay: Date?; private(set) var carried: [AskTurn]
var responder: (@MainActor (String, (String) -> Void) async throws -> Void)?   // unchanged
static func instructions(today: String, carrying: [AskTurn] = []) -> String
static func isContextFull(_ error: Error) -> Bool        // AskModel+Notices
static let contextFull = AskNotice(text: "That question needs more room than Apple's on-device model has. Try a shorter question, or start a new chat.", opensSettings: false)
static let keptLooking = AskNotice(text: "Ask kept looking things up without answering. Try asking about one period or one thing.", opensSettings: false)
```
`instructions(today:carrying:)` with an empty list returns v1's text exactly; each carried turn appends ` Earlier in this chat the user asked “\(question)” and you answered “\(answer)”.`

- [ ] **Step 1: Port the v1 checks to `turns`, keeping each assertion:** `AskModelChecks` (notices: a full context now maps to `contextFull`; provenance → `turns.last?.provenance == ["focus totals (this week)", "best hours (last 30 days)"]` after a responder makes both lookups through `model.lookup(name:arguments:generation:)`; `present(turns:)` shows what it was given; `newChat()` empties `turns`, `notice`; a blank question adds no turn; the model is built once; a failed answer changes only its own turn). `AskThreadChecks` (a lookup from the old generation after `newChat()` is not in the new turn's provenance; asking appends a turn whose answer is empty and state `.lookingUp` while earlier turns are unchanged; midnight drops the session, keeps `turns`, and the next session is today's). `AskEntryChecks.examplesAskThemselves` → `turns.last?.question == examples[0]`.

- [ ] **Step 2: Write the failing checks** in `AskChatChecks.swift` (responder seam, `AskThreadChecks.withModel`):
  - `followUpAppends`: ask "A" (answers "One."), ask "B" → `turns.count == 2`, `turns[0]` unchanged, both `.answered`.
  - `askWhileAnsweringIsIgnored`: a held responder; a second `ask` → `turns.count == 1`.
  - `sourcesPickedAtFinish`: responder looks up `focusTotals` "this week" then shows "Your best day was Tue 14 Nov." → `turns[0].sources.first?.link.target == .day(14 Nov)`, mention set.
  - `stopKeepsTextAndCarries`: two answered turns, then a held responder that shows "Partly" → `stop()` → last turn `.stopped`, answer "Partly", `generation` +1, `carried` == the two answered turns, `turns[...].sources` empty for the stopped turn.
  - `lateLookupAfterStopIsNotCounted`: responder captures `generation`, waits; `stop()`; ask "next"; the held lookup lands with the old generation → not in the new turn's provenance.
  - `contextFullCarriesTwoAndRetries`: three answered turns; next responder throws `exceededContextWindowSize` on its first call only → responder called twice with the same question; `carried` (as passed to the rebuilt session) == `turns[1...2]`; turn `.answered`; `instructions(today: d, carrying: turns[1...2])` contains both questions and answers; `instructions(today: d)` == v1's literal text (copied into the check).
  - `secondFullContextShowsNotice`: responder throws it every time → turn `.failed(AskModel.contextFull)`, called exactly twice.
  - `eighthLookupEndsWithNotice`: responder makes eight lookups → turn `.failed(AskModel.keptLooking)`; with six lookups the sixth returns `AskFacts.lookupLimitReached` and the turn answers.
  - `midnightCarriesNothing`: after a day change and `retireStaleSession()`, `carried.isEmpty`.

- [ ] **Step 3: Register and typecheck.** Expected: errors naming `AskTurn`, `turns`, `stop`.

- [ ] **Step 4: Implement.** `AskModel` keeps one `AskGate` per answer (progress → `.lookingUp(text)`; first streamed text → `.answering`; finish → `.answered`, `provenance = gate.provenance`, `sources = AskSourcePicker.sources(answer:lookups: gate.lookups, calendar: store.periodCalendar, now: store.now())`). `lookup(name:arguments:generation:)` uses the open gate when `generation == self.generation` and the last turn is in progress; otherwise reads through the catalogue and records nothing. Stop, the gate's `onEnd` and a full context cancel the task, close the gate and drop the session (`session = nil`, `sessionDay = nil`, `generation += 1`) with `carried` = the last two `.answered` turns; a full context retries once. `newChat()` and the midnight drop clear `carried`. `liveSession()` builds with `instructions(today:carrying: carried)` and then empties `carried`. Move the notices and `notice(for:)` to `AskModel+Notices.swift`; `AskModel+Availability.swift` reads `ModelGate`. Adapt `AskSheet` to show `turns` in order so the app still builds.

- [ ] **Step 5: Run** `./build.sh --check`. Expected: all pass. In a temporary tree copy remove the carry (rebuild with `instructions(today:)`): `contextFullCarriesTwoAndRetries` must fail. Remove the copy.

- [ ] **Step 6: Commit** — "Ask keeps a conversation: follow-ups, Stop, and a full context carried into a fresh session".

---

### Task 6: Placement and following a source

**Files:**
- Create: `Sources/App/MainWindowModel+Ask.swift`, `Sources/Verification/AskFollowChecks.swift`, `Sources/Verification/AskPanelChecks.swift`
- Modify: `Sources/Core/PersistenceStore.swift` (key `fc.askPlacement`, property, `removeAll` list), `Sources/App/SettingsModel.swift` (`askPlacement`, `SettingsControlKey.askPlacement`), `Sources/Surfaces/Settings/SettingsSidebar.swift` (General: label `"Open Ask in"`, key `.askPlacement`, search terms `["Side panel", "Sheet", "Sidebar", "Inspector", "Panel"]`), `Sources/Verification/SelfTest/SelfTest+SettingsSurfaces.swift` (expected controls), `Sources/App/MainWindowModel.swift` (`askPanelOpen`, `openHistory(place:)`, `closeSheet()` rule; `openAsk()` moves to the extension), registry (append `+ AskFollowChecks.tests + AskPanelChecks.tests`)

**Interfaces:**
- Consumes: Task 1 `AskLink`; Task 5 `AskPlacement`.
- Produces:
```swift
PersistenceStore.askPlacement: AskPlacement            // default .sheet; unreadable → .sheet
SettingsModel.askPlacement: AskPlacement
// MainWindowModel
@Published private(set) var askPanelOpen = false
func openAsk()                     // builds askModel once; .sheet → openSheet(.ask); .panel → toggles askPanelOpen
func closeAskPanel()
func follow(_ link: AskLink)
func openHistory(place: HistoryPlace)
```

- [ ] **Step 1: Write the failing checks.** `AskFollowChecks` (fixture as Task 3, `MainWindowModel(store:)`):
  - `dayOpensHistoryDay`: `follow(.day(13 Nov))` → `workspace == .history`, `sheet == nil`, `historyOpen.last` is the day 13 Nov.
  - `sessionIsPicked`: `follow(.session(Parser, 14 Nov))` → `historySession == HistorySessionPick(thread: Parser, day: 14 Nov)`.
  - `missingSessionOpensItsDay`: an unknown thread on 14 Nov → `historySession == nil`, day 14 Nov open.
  - `renamedSessionStillOpensByThread`: rename Parser's thread (`SessionArchive.rename(thread:to:)`), then `follow(.session(Parser thread, 14 Nov))` → that session picked.
  - `periodUnfoldsToItsRow`: `follow(.period(week 13–19 Nov))` → `historyOpen.last` equals that week place, `historyFocus == .row(week)`.
  - `historyOpensTop`: `follow(link with .history)` → `historyOpen.isEmpty`, `workspace == .history`.
  - `sheetClosesPanelStays`: placement `.sheet`: `openAsk()` → `sheet == .ask`; `follow` → `sheet == nil`, same `askModel`. Placement `.panel`: `openAsk()` → `askPanelOpen`, `sheet == nil`; `follow` → `askPanelOpen` still true; `openAsk()` again → false.
  `AskPanelChecks` (preferences part):
  - `placementSavedDefaultSheet`: a fresh `MemoryDefaults` store reads `.sheet`; `SettingsModel.askPlacement = .panel` is saved; `"sideways"` reads `.sheet`; `SettingsControlKey.askPlacement.modelKeyPath == \SettingsModel.askPlacement`; `SettingsSection.matching("Side panel")` includes General.
  - `placementChangeClosesPanelWhenSettingsClose`: panel open, `openSheet(.settings)`, placement set to `.sheet`, `closeSheet()` → `askPanelOpen == false`.

- [ ] **Step 2: Register and typecheck.** Expected: errors naming `askPlacement`, `follow`.

- [ ] **Step 3: Implement.** `openAsk()` reads `store?.engine.store.askPlacement ?? .sheet`. `follow`: `open(tab: .review)` (which already clears `sheet`), then by target: day → `openHistory(day:)`; session → `selectHistory(session:on:)` when `store.journalThreads(on: day, only: nil)` contains the thread, else `openHistory(day:)`; period → `openHistory(place:)`; history → `navigateHistory(to: nil)`. `openHistory(place:)`: `HistoryTreeBuilder.path(to: place.start, top:calendar:)` cut after the element equal to `place`; not found → `navigateHistory(to: nil)`; found → same open, focus and scroll steps as `openHistory(day:)`. `closeSheet()`: when `askPanelOpen` and the placement is now `.sheet`, close the panel.

- [ ] **Step 4: Run** `./build.sh --check`. Expected: all pass.

- [ ] **Step 5: Commit** — "Ask can open as a side panel, and a source opens History at its day, session or period".

---

### Task 7: The chat surface

**Files:**
- Create: `Sources/Surfaces/Ask/AskChatView.swift`, `AskTurnView.swift`, `AskSourcesView.swift`
- Modify: `Sources/Surfaces/Ask/AskSheet.swift` (wraps `AskChatView`), `Sources/Surfaces/Settings/SettingsView.swift` (`sheetSize(for: .ask)` wants 640 × 600 `.zoomed`), `Sources/Surfaces/Main/MainWindowView.swift` (`AskSheet(model:onFollow: navigation.follow)`), `Sources/Surfaces/Story/StoryColumns.swift` (evidence `.askTranscript`, `.askSources`), `Sources/Surfaces/Snapshotter.swift` (scenarios `askAnswered` with two turns and sources, `askFailed`, `askStopped`), `Sources/Verification/AskChecks.swift` (`askSheetFitsWindow` expectations), `Sources/Verification/AskPanelChecks.swift`

**Interfaces:**
- Consumes: Task 5 `AskModel`, `AskTurn`; Task 6 `follow`.
- Produces:
```swift
struct AskChatView: View { init(model: AskModel, onFollow: @escaping (AskLink) -> Void) }
struct AskSourcesView: View {
    static func visible(_ sources: [AskSource], expanded: Bool) -> (shown: [AskSource], hidden: Int)
    /// "<label>, <role, lowercased>. Opens in History."
    static func accessibilityLabel(for source: AskSource) -> String
}
extension AskTurnView {
    /// Mentions become `.link` runs to `daybook-ask://source/<index>`; handled by an OpenURLAction, never opened by the system.
    static func attributed(answer: String, sources: [AskSource]) -> AttributedString
}
```

- [ ] **Step 1: Write the failing checks** (in `AskPanelChecks`):
  - `sourcesShowFiveThenMore`: eight sources → `visible(_, expanded: false)` shows 5, hides 3; expanded shows 8, hides 0.
  - `mentionsBecomeLinks`: answer "In September 2026, the best day was Tue 15 Sep." with two mentioned sources → two link runs, covering exactly those substrings, URLs `daybook-ask://source/0` and `/1`.
  - `longLabelKeepsFullTextForVoiceOver`: `AskSourcesView.accessibilityLabel(for:)` of a 120-character session name contains the whole label, the role, then "Opens in History."; `Mon 3 Aug` with `.bestDay` reads "Mon 3 Aug, most focused day. Opens in History."
  - `sheetSize`: `SettingsLayout.sheetSize(for: .ask, within: nil)` == 640 × 600 `.zoomed`; within 1000 × 680 → height 600; within 980 × 600 → 520 (margin 40).
  - `chatRendersTurnsAndSources`: `StoryWorkspaceChecks.renderFrame(AskChatView(model: presented two turns), width: 640, height: 600)` evidence contains `.askTranscript` and `.askSources`.

- [ ] **Step 2: Register and typecheck.** Expected: errors naming `AskChatView`, `AskSourcesView`.

- [ ] **Step 3: Implement** to spec §6 and §8: transcript `ScrollView` with `.defaultScrollAnchor(.bottom)`; question as a trailing neutral pill (`Tokens.Colour.elevated`, `Tokens.Radius.nested`, `Typography.body`); answer as prose (`Typography.control`, selectable) with inline links in `StoryStyle.action`; progress line `ProgressView().controlSize(.small)` + provenance text; "Sources" heading (`Typography.eyebrow`); rows: number, `calendar` or `clock` glyph, label (`Typography.label`, one line, full text in `.help`), role (`Typography.body`, secondary), chevron, height ≥ `AccessibilityMetrics.minimumTargetSize`, `StoryLinkStyle`-like hover; "Show N more" link; failed turn: notice in `Typography.body` with the danger token only for errors; stopped: "Stopped." caption; composer: field ("Ask about your focus…", stays editable, ↩ ignored while answering), Send ↔ Stop (`StoryActionStyle`), availability notice and Open Settings above it; footer: Apple Intelligence glyph line (v1 wording) and "New chat" once a turn exists; empty chat: "Ask about your focus. Each answer lists the days and sessions it came from." then "Try asking" and `AskModel.examples`. VoiceOver: each turn `.accessibilityElement(children: .contain)` labelled "You asked … Ask answered …"; row label "Mon 3 Aug, most focused day. Opens in History."; on finish announce the answer and "N sources". No avatar, typing dots, emoji, gradient or nested card.

- [ ] **Step 4: Run** `./build.sh --check`. Expected: all pass. Render `askEmpty`, `askAnswered`, `askFailed`, `askStopped` (standalone snapshot binary, `FC_SNAPSHOT_ONLY=<scenario>`, `FC_SNAPSHOT_ZOOM=80|100|140`, light and dark) and look at every image.

- [ ] **Step 5: Commit** — "Ask shows a conversation, and each answer lists the sources it came from in reading order".

---

### Task 8: The side panel

**Files:**
- Create: `Sources/Surfaces/Ask/AskPanel.swift`
- Modify: `Sources/Surfaces/Main/MainWindowView.swift`, `Sources/Design/Components/ZoomWindowFit.swift`, `Sources/Surfaces/Main/AskChromeButton.swift`, `Sources/Surfaces/Main/StoryChromeBar.swift`, `Sources/Surfaces/Settings/SettingsAskPanel.swift`, `Sources/Surfaces/Story/StoryColumns.swift` (evidence `.askPanel`, `.askButtonActive`), `Sources/Surfaces/Snapshotter.swift` (scenarios `askPanelStory`, `askPanelHistory`), `Sources/Verification/AskPanelChecks.swift`

**Interfaces:**
- Consumes: Task 6 `askPanelOpen`, `closeAskPanel()`, `follow`; Task 7 `AskChatView`.
- Produces:
```swift
enum AskLayout {
    static let panelBaseWidth: CGFloat = 360   // zoom: fixed, the 100% size
    static var panelWidth: CGFloat { 360.zoomed }
}
extension MainWindowView { static func contentBase(askPanelOpen: Bool) -> CGSize }   // 980 × 680, or 1340 × 680
struct AskChromeButton: View { init(isActive: Bool = false, action: @escaping () -> Void) }
```

- [ ] **Step 1: Write the failing checks** (in `AskPanelChecks`):
  - `panelWidensMinimum`: `contentBase(askPanelOpen: false) == 980 × 680`; `true` → `1340 × 680`.
  - `panelMinimumHeldToScreen`: `InterfaceZoom.windowMinimum(base: contentBase(askPanelOpen: true), scale: 1.4, visible: 1280 × 800)` fits within 1280 × 800 less the screen margin.
  - `anchorGrowsWindowWhenBaseGrows`: following `ZoomWindowChecks.grownWindowReturnsOnScreen`'s window setup, a visible window holding a `ZoomWindowFitAnchor` at base 980 × 680 grows its content width to at least 1340 when the anchor's base becomes 1340 × 680, and stays on screen.
  - `panelBesideStoryAndHistory`: render `MainWindowView` at 1340 × 760 with `askPanelOpen` → evidence contains `.askPanel` and `.dayStory`; after `open(tab: .review)` → `.askPanel` and `.historyTree`; closed → no `.askPanel`.
  - `buttonShowsOpenPanel`: the bar rendered with the panel open and `showsAsk` → the Ask button reports active (evidence `.askButtonActive`).

- [ ] **Step 2: Register and typecheck.** Expected: errors naming `AskLayout`, `contentBase`.

- [ ] **Step 3: Implement** to spec §7: in `MainWindowView` the reading workspace and, when `navigation.askPanelOpen` and `askModel` exists, a `Divider` and `AskPanel` (width `AskLayout.panelWidth`, `StoryStyle.rail` fill) in one `HStack`; `minimum` and `ZoomWindowFit(base:)` use `contentBase(askPanelOpen:)`. `ZoomWindowFitAnchor.base` gains a `didSet` that calls `fit()` when it grows. `AskPanel`: header (title in `Typography.heading`, "New chat", 28-point close `IconButton` with help "Close Ask (⌘K)"), `AskChatView`, field focused on appear, `.onExitCommand { navigation.closeAskPanel() }`. `AskChromeButton(isActive:)` draws the pressed fill and `.accessibilityAddTraits(.isSelected)` when active; `StoryChromeBar` passes `navigation.askPanelOpen`. `SettingsAskPanel`: a row "Open Ask in" with a segmented `Picker` (`Sheet`, `Side panel`, `.fixedSize()`), detail "A side panel stays beside Story and History, so sources open next to the chat.", disabled unless `AskModel.isOffered`.

- [ ] **Step 4: Run** `./build.sh --check`. Expected: all pass. Render `askPanelStory` and `askPanelHistory` at 80, 100, 140%, light and dark, and look at each.

- [ ] **Step 5: Commit** — "Ask can sit in a side panel beside Story and History".

---

### Task 9: Probes, README and recorded evidence

**Files:**
- Modify: `README.md`, `docs/specs/2026-10-11-ask-daybook-v2-chat-design.md` (evidence section: "After")

- [ ] **Step 1: Update the probe kit** to the `turns` interface (print each turn's answer, state, provenance and source labels in order) and run, over the final tree:
  1. Parity: the 37 baseline questions. Expected: answers as in Task 2's parity run.
  2. Depth: one chat of ten follow-ups ("How much did I focus in August?", "And in September?", "Which day that month was best?", "What did I work on that day?", "How long was the longest one?", "Did I write any notes?", "And the week before?", "Which app did I use most then?", "When do I focus best?", "Is that true for Mondays too?"). Record where the context fills and whether the carried follow-up is still right.
  3. Cap: in the probe tree only, add a sixth catalogue entry `focusOutlook` returning a fixed text whatever it is given; ask "What should I change to focus more next week?". Expected: the turn ends `.failed(keptLooking)` at the eighth call.
  4. Speed: median and maximum time per answer, and time to the first progress line. Expected: median ≤ 4.8 s, maximum ≤ 8.4 s.

- [ ] **Step 2: Record** each result in the spec's Evidence section under "After (date)", in the style of the baseline table.

- [ ] **Step 3: README.** The "Private by construction" paragraph opens with "Nothing leaves your Mac unless you want it to." The update-check clause becomes "the update check asks GitHub for the latest version, which you can turn off in Settings". The backup sentence states the default: "Backups are on from the start: every day they are copied into iCloud Drive, which uploads them to your own iCloud account when iCloud Drive is on, or into a folder you choose; Settings can change how often, or turn them off." Ask's sentence stays as it is.

- [ ] **Step 4: Commit** — "The README says nothing leaves your Mac unless you want it to, and the Ask v2 spec records its probe results".

---

### Task 10: Whole-branch verification and shipping

- [ ] **Step 1:** `./build.sh --check` and `TZ=Europe/Berlin ./build.sh --check`. Expected: all pass in both.
- [ ] **Step 2:** Design review of the Task 7 and 8 renders: impeccable critique and design critique; fix what they find in this branch and re-render.
- [ ] **Step 3:** `fix-reviewer` agent over the branch diff (session state and date reading); fix its findings with checks.
- [ ] **Step 4:** Merge `main`; if the notes branch landed, keep its `ModelGate.swift` (identical), resolve `MainWindowModel` beside `askModel`, the preference keys, the README paragraph and the registry tail; renumber nothing by hand (positions follow the registry). Re-run Step 1.
- [ ] **Step 5:** Post `ready` on the sessions board, then ship with the `ship` skill as a pull request listing spec §12's hand checks for the owner.
