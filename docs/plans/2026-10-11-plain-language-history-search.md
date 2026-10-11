# Plain-language History Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** History's search box reads periods, recurring weekdays, session length and exact app or category names into filters shown as chips, on every Mac, with the on-device model rescuing phrasings the parser cannot read.

**Architecture:** A pure Core parser (`SearchQuery`) turns the field's text into a `ParsedSearch`. `SessionStore` keeps the raw text as the source of truth, folds the parse into `HistoryFilter`, and the existing search and map honour the new fields. An App-layer `SearchRescue` asks the model, on Return only, to rewrite unread words into phrases the parser must accept. A chips row shows what was understood.

**Tech Stack:** Swift 5 mode, SwiftUI/AppKit, `FoundationModels` (weak-linked, `@available(macOS 26, *)`), headless self-checks.

**Spec:** `docs/specs/2026-10-11-plain-language-history-search-design.md`

## Global Constraints

- On-device only: `SystemLanguageModel.default`. AI runs only when `ModelGate.modelAvailable` and the "Use Apple Intelligence" switch (`store.appleIntelligenceEnabled`) are both true.
- `Sources/App/ModelGate.swift` stays byte-identical (another branch copies it).
- Field text is the single source of truth; chips and filters are derived from it on every change.
- Spans are half-open (`DateInterval.holds`) and built with `store.periodCalendar` (Monday weeks, Gregorian months), the calendar History builds its places with.
- The parser and the model never run on the 1 Hz ticker; the model runs only on Return.
- Copy: "No overlap"; chip remove label "Remove <chip label>"; the Apple Intelligence mark is `Image(systemName: "apple.intelligence")`.
- Files under 300 lines; lengths are `Tokens` or `.zoomed`; text uses `Tokens.Typography` roles.
- Checks: `MemoryDefaults`, `TestClock`, fixtures built through the calendar, never the live model; new suites appended at the end of `registeredTests`.
- `./build.sh` runs with the sandbox disabled; never launch the live app.
- Commits: one plain present-tense subject, wrapped prose body, the Co-Authored-By line for the committing model. No type prefixes; no machine paths.

## Plan adjustments to the spec (record in the spec in Task 5)

- **App and category names match only when typed with the name's own leading capital** ("Notes" → the Notes app; "notes" → a word search). Common app names ("Notes", "Mail", "Music", "Messages") are ordinary words people search for; the spec's "case-insensitive" grammar would have turned "notes" into an app filter. The rest of the grammar stays case-insensitive.
- **Menus keep their own choice**: `historyMenuApp` and `historyMenuWorkType` hold the menu picks. The effective filter is the typed name if one is typed, otherwise the menu pick. Picking in a menu removes any typed name of that kind from the text.
- **Rescue keeps search words**: the model returns phrases plus the words to keep as search words. Kept words must be a subset of the leftover words, so the model can drop words but never add them.

## Review Focus

1. Typing "last week" just after midnight on a Monday must still mean the previous Monday–Sunday. Test in Task 1.
2. A session named with phrase-like words ("Mondays standup", "Over budget"): typing it in quotes must search the words literally. Test in Task 1.
3. Typing "notes" (lowercase) must search words, not filter to the Notes app. Typing "Notes" filters to the app. Test in Task 1.
4. A number in a session name next to a phrase ("Sprint 42 over 1h") must keep "Sprint 42" as words and read only "over 1h". Test in Task 1.
5. A rescue that would drop every search word and add no phrase must change nothing. Test in Task 3.

---

### Task 1: The Core parser

**Files:**
- Create: `Sources/Core/SearchQuery.swift` (types, `parse`, chip labels)
- Create: `Sources/Core/SearchQueryGrammar.swift` (phrase matchers), so each file stays under 300 lines
- Create: `Sources/Verification/HistorySearchQueryChecks.swift`
- Modify: `Sources/Verification/SelfTest/SelfTest+Registry.swift` (append last)

**Interfaces:**
- Consumes: `AskRange` (`resolving(_:now:calendar:)`, `interval(now:firstDay:calendar:)`, `.thisWeek` etc.), `NoteNumberWords` (number words), `NoteFigure.read` if it suits duration reading (else parse durations directly), `DurationText.compact`, `DateFormats.australian(_:in:)`, `WorkType`.
- Produces:

```swift
struct SearchPhrase: Equatable {
    enum Kind: Equatable { case period, weekdays, length, app, category }
    let kind: Kind
    let range: Range<String.Index>   // in the parsed text
    let label: String                // chip text
}
struct ParsedSearch: Equatable {
    var span: DateInterval?          // intersection of every period phrase
    var noOverlap = false            // periods given but disjoint; span is then nil and nothing matches
    var weekdays: Set<Int>?          // Calendar weekday numbers, 1 = Sunday … 7 = Saturday
    var minLength: TimeInterval?
    var maxLength: TimeInterval?
    var appBundleID: String?
    var workType: WorkType?
    var leftover: String             // every unread word, in order, single-spaced, quotes kept
    var phrases: [SearchPhrase]      // in text order
}
enum SearchQuery {
    static func parse(_ text: String, now: Date, calendar: Calendar,
                      apps: [String: String],          // bundle ID → display name
                      categories: [WorkType]) -> ParsedSearch
}
```

Grammar (spec §2), longest match first, left to right, quoted text skipped and kept in `leftover`:
- Period: `today`, `yesterday`, `this|last week|month|year` (via `AskRange`); `the week|month before last` (offset −2); `N days|weeks|months ago` (that day, week or month); `last N days|weeks` (rolling, ending today); a month name with or without a year, a day and month with or without a year, a four-digit year (via `AskRange.resolving` on the matched words). N accepts digits or number words.
- Weekdays: a plural weekday name (`mondays`, three-letter prefixes allowed like `AskRange`), optionally after `on`; several joined by `and` or `,`; `weekends` = {1, 7}; `weekdays` = {2…6}. A singular weekday is not a phrase.
- Length: `over|longer than|more than|at least D`, `under|shorter than|less than|at most D`, `between D and D`. D: `1h`, `1 h`, `1 hour`, `90m`, `90 min`, `90 minutes`, `1h 30m`, `1.5h`, `an hour`, number words.
- App: an app display name from `apps`, matched as whole words, with the typed first letter equal to the name's first letter in case (plan adjustment).
- Category: a `WorkType.displayName`, same rule.

Chip labels (exact):
- Relative period: `<Capitalised phrase> · <dates>`, e.g. `Last week · 6–12 Oct`, `Yesterday · Sat 10 Oct`, `Week before last · 28 Sep – 4 Oct`, `Last 7 days · 5–11 Oct`.
- Named month, day or year: the dates only, e.g. `September 2026`, `Sat 3 Oct 2026`, `2025`.
- Dates: one day is `EEE d MMM`. Within a month it is `d–d MMM`; across months `d MMM – d MMM`. The year is added (` yyyy`) only when the span is not in `now`'s year.
- Weekdays: `Mondays`, `Mondays, Fridays`, `Weekends`, `Weekdays`. Length: `Over 1h`, `Under 20m`, `30m–1h` (`DurationText.compact`). App and category: the display name.

- [ ] **Step 1: Write the failing checks** (`enum HistorySearchQueryChecks: CheckSuite`). Fix `now` at `SelfTest.base` (Wednesday 15 Nov 2023, 9:13 am local; the Ask fixture's date) and build expected spans with `calendar.forPeriods`:

```swift
("The search box reads periods, weekdays, lengths and names out of free text", grammarRows),
// "Thesis last week on Mondays over 1h" → span == last week's interval, weekdays == [2], minLength == 3600,
//   leftover == "Thesis", phrases.map(\.label) == ["Last week · 6–12 Nov", "Mondays", "Over 1h"]
// one assertion per grammar row in the spec's §2 table (period forms, weekdays forms, length forms, app, category)
("The longest phrase wins and the rest stays as words", longestMatch),
// "the week before last" → one period phrase (offset −2), leftover == ""; "Sprint 42 over 1h" → leftover "Sprint 42"
("Quoted words and a single weekday stay words", literalWords),
// "\"Mondays standup\"" → no phrases, leftover keeps the quoted text; "Monday" → no phrases
("Names match only with their own capital", nameCase),
// apps ["com.apple.Notes": "Notes"]: "Notes" → appBundleID "com.apple.Notes"; "notes" → nil, leftover "notes"
("Periods intersect, and disjoint ones say No overlap", intersection),
// "September last year" → span == September 2022; "today last week" → noOverlap == true, span == nil
("A week just after midnight on Monday is the week before", mondayMidnight),
// now = Monday 13 Nov 2023 00:30 → "last week" == 6–12 Nov; run also under TZ=Europe/Berlin
("A week holding a daylight-saving change keeps its seven days", dstWeek),
// with calendar.timeZone = Australia/Sydney, now inside the week of 2 Oct 2023 (clocks forward 1 Oct): "this week" span
//   starts Mon 2 Oct 00:00 and ends Mon 9 Oct 00:00 local; repeat with Europe/Berlin around 29 Oct 2023
("Number words read in counts and lengths", numberWords),
// "two weeks ago" == week of 30 Oct; "over an hour" minLength 3600; "under forty minutes" maxLength 2400
```

- [ ] **Step 2: Register** `+ HistorySearchQueryChecks.tests` last; typecheck (`swiftc -typecheck … -F .build/vendor/Sparkle-2.10.0 $(find Sources -name '*.swift')`). Expected: errors naming `SearchQuery`.
- [ ] **Step 3: Implement** the two Core files to the interfaces and grammar. Core imports Foundation only.
- [ ] **Step 4: Run** `./build.sh --check` and `TZ=Europe/Berlin ./build.sh --check`. Expected: all pass.
- [ ] **Step 5: Mutation**: in a scratch tree, make `holds` closed (`<=` end) in span building, and separately drop the capital rule. The matching checks must fail.
- [ ] **Step 6: Commit** — "History's search box can read periods, weekdays, lengths and names out of what is typed"

---

### Task 2: Filters, store and the existing search

**Files:**
- Modify: `Sources/Core/HistoryStats.swift` (`HistoryFilter`)
- Modify: `Sources/App/SessionStore.swift` (three stored properties beside `historyFilter`)
- Modify: `Sources/App/SessionStore+Review.swift` (`setHistoryQuery`, `setHistoryApp`, `setHistoryWorkType`, `clearHistoryFilters`)
- Modify: `Sources/App/SessionStore+HistoryFind.swift` (`historySearchHits(matching:)`)
- Create: `Sources/Verification/HistorySearchFilterChecks.swift`; registry

**Interfaces:**
- Consumes: Task 1's `SearchQuery.parse`, `ParsedSearch`.
- Produces:

```swift
// HistoryFilter gains
var span: DateInterval?
var noOverlap = false
var weekdays: Set<Int>?
var minLength: TimeInterval?
var maxLength: TimeInterval?
// isActive also true when any of these is set (noOverlap counts)

// SessionStore (SessionStore.swift)
@Published private(set) var historySearchText = ""
@Published private(set) var historyParsedSearch = ParsedSearch(leftover: "", phrases: [])
private(set) var historyMenuApp: String?          // menu picks
private(set) var historyMenuWorkType: WorkType?

// SessionStore+Review.swift
func setHistoryQuery(_ text: String)              // stores text, parses with now(), periodCalendar,
                                                  // historyAppNames, WorkType.allCases; folds into historyFilter:
                                                  // query = leftover; span/weekdays/lengths/noOverlap from parse;
                                                  // appBundleID = parsed ?? historyMenuApp; workType = parsed ?? historyMenuWorkType
func setHistoryApp(_ bundleID: String?)           // sets historyMenuApp, removes any typed app phrase from the text, re-parses
func setHistoryWorkType(_ workType: WorkType?)    // same for category
func removeHistoryPhrase(_ phrase: SearchPhrase)  // removes phrase.range from historySearchText (collapsing spaces), re-parses
func clearHistoryFilters()                        // text, parse, menus and filter all reset
```

Matching rules in `historySearchHits(matching:)`:
- The guard becomes `listingAll || filter.isActive`. `noOverlap` returns `[]`.
- Span: `filter.span?.holds(day)` on the session-day.
- Weekdays: `calendar.component(.weekday, from: day)`.
- Length: the group's `records.reduce(0) { $0 + $1.workSeconds }`. Breaks never pass a length filter.

`HistoryFilter.apply(to:)` honours span, weekdays and `noOverlap` on `HistoryDay.date`. Length is not applied to days.

- [ ] **Step 1: Write the failing checks** with `AskLookupChecks.withFixture` (clock Wed 15 Nov 2023; read its `makeFixture` for the sessions and apps it records, and build expectations from those):

```swift
("A period alone lists the sessions in it", periodOnly),
// setHistoryQuery("last week") → historySearchHits() non-empty and every hit.day in last week's span
("The list and the map agree on span and weekdays", listMapAgree),
// for "this week on Mondays": Set(hits.map(\.day)) == Set(filteredHistoryDays.filter(has a session).map(\.date))
("Length counts focus without pauses, and breaks never pass it", lengthRule),
("A typed name and its menu set the same filter, and the menu wins its kind back", typedVersusMenu),
// setHistoryQuery("<an app name from the fixture's usage, as capitalised>") → historyFilter.appBundleID == its id;
//   setHistoryApp(<another id>) → historySearchText no longer holds that name
("Removing a chip removes its words from the text", removePhrase),
("Disjoint periods list nothing", noOverlapEmpty),
```

- [ ] **Step 2: Register; typecheck.** Expected: errors naming `historySearchText`.
- [ ] **Step 3: Implement.** Update every reader of `historyFilter.query` that means the typed text (the journal's word highlighting keeps using `query`, which now holds only the leftover words; that is intended).
- [ ] **Step 4: Run** both suites (Sydney, Berlin). Expected: all pass.
- [ ] **Step 5: Mutation**: drop the span condition in `historySearchHits`; `listMapAgree` or `periodOnly` must fail.
- [ ] **Step 6: Commit** — "History lists sessions by the periods, weekdays and lengths typed into its search"

---

### Task 3: The model rescue

**Files:**
- Create: `Sources/App/SearchRescue.swift`
- Modify: `Sources/App/MainWindowModel.swift` (`var searchRescue: SearchRescue?`, built on first read like `notes`)
- Create: `Sources/Verification/HistorySearchRescueChecks.swift`; registry

**Interfaces:**
- Consumes: Task 2's store API, `ModelGate.modelAvailable`, `store.appleIntelligenceEnabled`, `store.historySearchHits()`, `SearchQuery.parse`.
- Produces:

```swift
@MainActor final class SearchRescue: ObservableObject {
    init(store: SessionStore)
    @Published private(set) var isRescuing: Bool
    @Published private(set) var rescuedTexts: Set<String>   // phrase texts the model supplied; chips mark these
    var isUsable: Bool          // store.appleIntelligenceEnabled && (responder != nil || ModelGate.modelAvailable)
    /// Checks only: leftover words in, (phrases, kept words) out.
    var responder: (@MainActor (String) async throws -> (phrases: [String], keep: [String]))?
    func rescue(undoManager: UndoManager?)
}
```

`rescue` behaviour:
1. It runs only if all of these hold: `isUsable`; `historyParsedSearch.leftover` is non-empty; `historySearchHits()` is empty; nothing is already rescuing.
2. The live path makes one greedy call: a `LanguageModelSession(instructions:)` and `@Generable struct RescuedSearch { phrases: [String]; keep: [String] }`, with greedy options copied from `NoteWriter`.
3. Accepted phrases are those where `SearchQuery.parse(phrase, …)` yields exactly one phrase and an empty leftover.
4. Kept words must all occur in the leftover words; otherwise none are kept.
5. If no phrase is accepted, nothing changes.
6. Otherwise the new text is the original text with every leftover word removed, followed by the accepted phrases, followed by the kept words, space-joined.
7. Register `undoManager?.registerUndo(withTarget: store) { $0.setHistoryQuery(old) }` and call `store.setHistoryQuery(new)`.
8. Add the accepted phrases to `rescuedTexts`. Drop an entry from `rescuedTexts` once the text no longer contains it.
9. Any thrown error leaves everything unchanged.

Instructions (exact):

```swift
"You turn words typed into a focus app's search box into search phrases it understands. Today is \(today). "
    + "Use only these forms: today; yesterday; this week; last week; this month; last month; this year; last year; "
    + "the week before last; the month before last; N days ago; N weeks ago; N months ago; last N days; last N weeks; "
    + "a month name and year; a day, month and year; a year; a weekday in the plural such as Mondays; weekends; weekdays; "
    + "over D; under D; between D and D, where D is like 1h or 30m. "
    + "Put words that name a task or session, not a time or length, in keep, exactly as typed. Give no phrase you are unsure of."
```

`today` is formatted `EEEE d MMMM yyyy` in `periodCalendar`.

- [ ] **Step 1: Write the failing checks** with the fixture and `rescue.responder`:

```swift
("A rescued phrase replaces the unread words and is marked", accepted),
// text "Parser fortnight before last", responder → (["the week before last"], ["Parser"]) →
//   historySearchText == "the week before last Parser", rescuedTexts == ["the week before last"]
("A phrase the parser cannot read changes nothing", rejected),
// responder → (["sometime soon"], ["Parser"]) → text unchanged, rescuedTexts empty
("The model is not asked when results exist, the switch is off, or nothing is left over", notAsked),
("A rescue never adds words and never empties a search without a phrase", keptWords),   // Review Focus 5
// responder → ([], []) → unchanged; responder → (["last week"], ["Invented"]) → kept words ignored, phrase accepted
("Undo restores the typed text", undo),
// UndoManager(); rescue; undoManager.undo() → historySearchText == original
```

- [ ] **Step 2: Register; typecheck.** Expected: errors naming `SearchRescue`.
- [ ] **Step 3: Implement.** Every FoundationModels use is `@available(macOS 26, *)`. Do not edit `ModelGate.swift`.
- [ ] **Step 4: Run** both suites. Expected: all pass.
- [ ] **Step 5: Mutation**: accept phrases without the parser check; `rejected` must fail.
- [ ] **Step 6: Commit** — "Pressing Return asks the on-device model to rewrite unread search words into phrases History understands"

---

### Task 4: Chips and the search field

**Files:**
- Create: `Sources/Surfaces/History/HistorySearchChips.swift`
- Modify: `Sources/Surfaces/Review/HistoryFind.swift`. The field binds to `store.historySearchText` through `setHistoryQuery`; the placeholder and clear button read `historySearchText`; `.onSubmit` calls `navigation.searchRescue?.rescue(undoManager:)` with `@Environment(\.undoManager)`; the chips row sits under the field.
- Modify: `Sources/Surfaces/Snapshotter.swift` (the `historySearch` scenario types `"Build last week over 30m"` so chips render)

**Interfaces:**
- Consumes: `store.historyParsedSearch.phrases`, `store.removeHistoryPhrase(_:)`, `searchRescue.rescuedTexts`, `searchRescue.isRescuing`.
- Produces:

```swift
struct HistorySearchChips: View {
    @ObservedObject var store: SessionStore
    let rescued: Set<String>       // texts marked as Apple Intelligence
}
```

Rules:
- One chip per phrase in text order: the label, then a × `Button` with accessibility label "Remove <label>".
- An app chip leads with the app's icon (the History app picker's icon source). A category chip leads with its colour dot (`Tokens.Palette.workType`).
- A chip whose phrase text is in `rescued` leads with `Image(systemName: "apple.intelligence")` and adds ", from Apple Intelligence" to its accessibility label.
- `noOverlap` shows a trailing caption "No overlap" in secondary style.
- While `isRescuing`, a small `ProgressView` sits at the field's trailing edge.
- The row reads only published values; nothing parses in `body`.

- [ ] **Step 1: Build the view and wiring.**
- [ ] **Step 2: Run** `./build.sh --test` (sandbox disabled; replaces only this worktree's bundle). Expected: all checks pass.
- [ ] **Step 3: Snapshots**: `FC_SNAPSHOT_ONLY=historySearch` at `FC_SNAPSHOT_ZOOM=0.8` and `1.4`, light and dark. Open each PNG: chips fit, no clipping, × reachable. Copy one at each zoom into the SDD workspace for review; remove the temp folder.
- [ ] **Step 4: Commit** — "History's search shows what it understood as chips you can remove"

---

### Task 5: Live probe and docs

**Files:**
- Modify: `docs/specs/2026-10-11-plain-language-history-search-design.md` (status, the three plan adjustments, §5a probe results)

- [ ] **Step 1: Probe.** In a temp tree copy (as the review-notes probe did), call `SearchRescue`'s live path for these 20 phrasings with leftover words and the fixture store. Print `input | accepted phrases | kept | resulting chips`.
  - fortnight before last
  - first week of september
  - the last three mondays
  - past fortnight
  - a month ago
  - this past weekend
  - three weeks back
  - early october
  - since monday
  - the 1st
  - longer than an hour and a half
  - quick ones under ten minutes
  - mornings last week
  - xmas
  - new year's day
  - q3
  - the weekend before last
  - last tuesday's sessions
  - two months back
  - parser stuff from last fortnight
- [ ] **Step 2: Judge** each row: right / wrong / nothing. Target: at least 18 right or honestly nothing, and 0 accepted phrases the parser rejected. A valid-but-wrong rescue is counted and listed.
- [ ] **Step 3: Record** in spec §5a with the date; set Status to "built; hand checks pending"; fold in the plan adjustments.
- [ ] **Step 4: Run** both suites one last time. Commit — "The History search spec records how the live model rescued twenty phrasings"
