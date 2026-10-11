# Apple Intelligence Review Notes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Short notes about a day, week or month, written by Apple's on-device model from figures Daybook computes, shown in History, as a Today wrap-up and as a Yesterday notice.

**Architecture:** Core builds `NoteFacts` (plain text lines plus candidate observations) from values History and the Story day projection already compute, and `NoteAudit` rejects any note whose digits are not in those facts. App adds `ModelGate` (is the model usable now), `NoteWriter` (one greedy `LanguageModelSession` call per period, in-memory cache keyed by place and facts text) and `SessionStore+Notes` (gathers inputs). Surfaces add one `PeriodNote` view used in every place and a `YesterdayNotice`.

**Tech Stack:** Swift 5 mode, SwiftUI/AppKit, `FoundationModels` (weak-linked, every use `@available(macOS 26, *)`), the headless self-check suite.

**Spec:** `docs/specs/2026-10-10-apple-intelligence-notes-design.md`

## Global Constraints

- Model: `SystemLanguageModel.default` only. No Private Cloud Compute, no network.
- AI floor: macOS 26 via `#available(macOS 26, *)`; app minimum stays macOS 14. No `build.sh` flag.
- Model unusable or switch off: no note, no link, no Yesterday notice, no switch row. Ask unchanged.
- Switch: "Use Apple Intelligence", Settings › Data and privacy › Privacy panel, default on, detail "Writes notes and suggestions with Apple's on-device model. Nothing leaves this Mac."
- Caption on every note: "Apple Intelligence · on this Mac".
- Requested-note failure line: "Couldn't write a note for this period."
- Tip labels (app-rendered): "For tomorrow:" on Today, "For today:" on the Yesterday notice. History never shows the tip.
- Model never runs on the 1 Hz ticker; past periods write on first open, current ones on request.
- Greedy sampling, same `#if compiler(>=6.4)` switch as `AskModel.options`.
- Files under 300 lines. Lengths are `Tokens` or `.zoomed`; text uses `Tokens.Typography` roles.
- Checks: `MemoryDefaults`, `TestClock`, `SelfTest.scratchDirectory()`; never the live model; new suites appended after `AskAccuracyChecks.tests` in `SelfTest+Registry.swift`.
- `./build.sh` runs with the sandbox disabled. Commit subjects: one plain present-tense sentence, no prefix; body wrapped prose; end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. A session name containing digits ("Q4 plan", "v2") must not make every note fail the audit: names are in the facts, so their digits pass. Test in Task 1.
2. A day whose only entries are breaks (no sessions) gets no note and no Yesterday notice. Test in Task 1 and Task 3.
3. Opening a past week that includes today-minus-one at 00:30 (just after midnight) must treat yesterday as finished, not current. Test in Task 3.
4. Turning the switch off while a note is writing must leave no "Writing…" line and publish nothing when the call returns. Test in Task 4.
5. A session running across midnight: yesterday's note uses only yesterday's clipped share and stays the same while the session grows today, so it is neither rewritten nor wrong. Test in Task 3.

## Spec adjustments made by this plan

Record these in the spec in Task 7:
- `NoteWriter` publishes note state (as `AskModel` does), not `SessionStore`; the store only builds facts. Views observe `NoteWriter`, reached as `navigation.notes`. Reason: no new stored properties or `keep_internals` entries on `SessionStore`.
- The History day note sits at the top of the opened day row (above `ProjectedDayStoryColumn`), the same slot as week and month notes, rather than inside a Story rail.
- Core gets three files (`NoteFacts`, `NoteFactsBuilder`, `NoteAudit`) to stay under 300 lines.
- The cache key is place id plus the facts text itself; no separate hash.

---

### Task 1: Core facts and audit

**Files:**
- Create: `Sources/Core/NoteFacts.swift`
- Create: `Sources/Core/NoteFactsBuilder.swift`
- Create: `Sources/Core/NoteAudit.swift`
- Create: `Sources/Verification/ReviewNoteFactsChecks.swift`
- Modify: `Sources/Verification/SelfTest/SelfTest+Registry.swift` (append after `+ AskAccuracyChecks.tests`)

**Interfaces:**
- Consumes: `DaySession`, `AppRank`, `HistorySummary`, `HistoryLevel`, `DurationText.compact(_:)`, `DateFormats.australian(_:in:)`.
- Produces:

```swift
struct NoteFacts: Equatable {
    enum Kind: Equatable { case day, period }
    let kind: Kind
    let lines: [String]
    let observations: [String]          // 2–4, in the order below
    var text: String                    // lines, then "Observations:", then "- " + each observation, joined by "\n"
}
struct WrittenNote: Equatable { let story: String; let pattern: String; let tip: String? }
struct NoteDayInput {
    let date: Date; let isCurrent: Bool
    let sessions: [DaySession]; let apps: [AppRank]
    let focused: TimeInterval; let goal: TimeInterval; let goalCredit: TimeInterval
    let previousFocused: TimeInterval
}
struct NotePeriodInput {
    let span: DateInterval; let level: HistoryLevel; let isCurrent: Bool
    let summary: HistorySummary
    let sessionTotals: [(name: String, worked: TimeInterval)]   // busiest first
    let goal: TimeInterval; let goalMetDays: Int
    let previousFocused: TimeInterval
}
extension NoteFacts {
    static func day(_ input: NoteDayInput, calendar: Calendar) -> NoteFacts?        // nil when input.sessions is empty
    static func period(_ input: NotePeriodInput, calendar: Calendar) -> NoteFacts?  // nil when summary.sessions == 0
    static func figuresLine(focused: TimeInterval, sessions: Int, goal: TimeInterval, goalCredit: TimeInterval) -> String
}
enum NoteAudit {
    static func digitRuns(in text: String) -> Set<String>   // maximal runs of ASCII digits, leading zeros trimmed ("05" → "5", "0" stays)
    static func passes(_ note: WrittenNote, facts: NoteFacts) -> Bool
}
```

Content rules (formats: durations `DurationText.compact`, times `"h:mm a"`, dates `"EEEE d MMMM yyyy"`, both via `DateFormats.australian(_:in: calendar.timeZone)`):

- Day lines: `Day: <date>` plus ` (so far)` when current; `Focus: <compact> over <n> session(s)`; when goal > 0 `Daily goal: <compact>, met: yes|no` (met = goalCredit >= goal); `Sessions in order: <name> at <time>, <compact>; …` — when more than 8, keep the 8 with most `worked`, sort those by start, append `; and <k> more`; `Top apps: <name> <compact>, …` (first 3 with total > 0, omitted when none).
- Day observations, first four that apply, in this order: longest single span across all `spans` when ≥ 600 s → `Longest stretch: <compact> in <name>, from <time>`; `Focus began at <time> with <name>`; top app share > 0.4 → `Most app time was in <app> (<compact>)`; previousFocused > 0 → `<compact |diff|> more|less focus than the day before` (skip when diff < 60 s); total stretches > session count → `<n> sessions ran as <m> stretches`.
- Period lines: `Week of <start date>` or `Month: <MMMM yyyy>`, plus ` (so far)` when current; `Focus: <compact> over <sessions> session(s) on <focusedDays> day(s)`; `Most time went to: <name> <compact>, …` (first 5 of `sessionTotals`).
- Period observations, in order: `summary.best` → `Best day: <date> with <compact>`; previousFocused > 0 → `<compact |diff|> more|less focus than the <week|month> before` (skip < 60 s); goal > 0 → `Goal met on <goalMetDays> of <focusedDays> days with focus`; first session total share of `summary.focused` > 0.4 → `<name> took <compact> of the <week|month>`.
- `figuresLine`: `<compact focused> focus · goal met|goal missed · <n> session(s)`; the goal part is left out when goal is 0.
- `passes`: every run in `digitRuns(story + " " + pattern + " " + (tip ?? ""))` is in `digitRuns(facts.text)`. Add `// ponytail: digits only; numbers written as words pass unchecked, widen if the note probe finds any.`

- [ ] **Step 1: Write the failing checks** in `ReviewNoteFactsChecks.swift` as `enum ReviewNoteFactsChecks: CheckSuite`. Build `DaySession` values by hand from `SelfTest.base` and `Calendar.current` (not fixed epoch dates).

```swift
("A day's note facts list sessions in start order with their times", dayFactsOrder),
// "Parser": spans 9:13–10:13 and 10:30–11:00, worked 1h 30m; "Thesis": span 2:00–2:45 pm, worked 45m
// (times from SelfTest.base and calendar.date(bySettingHour:minute:second:of:)):
// expect(facts.lines.contains("Sessions in order: Parser at 9:13 am, 1h 30m; Thesis at 2:00 pm, 45m"))
// expect(facts.observations.first == "Longest stretch: 1h in Parser, from 9:13 am")
// expect(facts.observations.contains("2 sessions ran as 3 stretches"))
("A day with ten sessions names its eight longest and counts the rest", dayFactsCap),
// expect(line.hasSuffix("; and 2 more")) and exactly 8 "at " occurrences
("A day without sessions has no note facts, even with breaks and app use", dayWithoutSessions),
// NoteFacts.day(... sessions: [] ...) == nil
("A period's note facts carry History's figures and its best day", periodFacts),
// summary focused 9000, sessions 2, focusedDays 2, best Tue: lines contain "Focus: 2h 30m over 2 sessions on 2 days"
("The figures line says focus, goal and sessions and drops the goal when there is none", figuresLine),
// figuresLine(15000, 3, 14400, 14400) == "4h 10m focus · goal met · 3 sessions"
// figuresLine(3600, 1, 0, 0) == "1h focus · 1 session"
("The audit passes a note whose figures are all in the facts", auditPasses),
// story "Parser from 9:13 am for 1h 30m" passes against dayFactsOrder's facts
("The audit drops a note with a figure the facts do not hold", auditFails),
// pattern "Your longest stretch was 2h 10m" fails (10 absent)
("Digits in a session name are facts, so they pass the audit", auditNameDigits),
// session named "Q4 plan v2": a story quoting "Q4 plan v2" passes
```

- [ ] **Step 2: Register** `+ ReviewNoteFactsChecks.tests` at the end of `registeredTests`.

- [ ] **Step 3: Run to see them fail**

Run: `swiftc -typecheck -module-cache-path "$TMPDIR/mc" -swift-version 5 -parse-as-library -warnings-as-errors -target arm64-apple-macos14.0 -F .build/vendor/Sparkle-2.10.0 $(find Sources -name '*.swift')`
Expected: errors naming `NoteFacts`, `NoteAudit`, `NoteDayInput`.

- [ ] **Step 4: Implement the three Core files** to the interfaces and content rules above. No `FoundationModels` or App import.

- [ ] **Step 5: Run the suite**

Run: `./build.sh --check` (sandbox disabled)
Expected: all checks pass, including the 8 new ones.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/NoteFacts.swift Sources/Core/NoteFactsBuilder.swift Sources/Core/NoteAudit.swift Sources/Verification/ReviewNoteFactsChecks.swift Sources/Verification/SelfTest/SelfTest+Registry.swift
git commit -m "Daybook can describe a day or period as plain facts and audit a note against them"
```

---

### Task 2: Model gate and the Settings switch

**Files:**
- Create: `Sources/App/ModelGate.swift`
- Modify: `Sources/App/AskModel.swift` (`canAsk`)
- Modify: `Sources/Core/PersistenceStore.swift` (keys + two properties beside `hapticsEnabled`)
- Modify: `Sources/App/SettingsModel.swift` (proxies; settings-control enum case beside `.haptics`)
- Modify: `Sources/Surfaces/Settings/SettingsGroups.swift` (`data` → "Privacy" panel)
- Create: `Sources/Verification/ReviewNoteGateChecks.swift`
- Modify: `SelfTest+Registry.swift`

**Interfaces:**
- Produces:

```swift
enum ModelGate {
    /// macOS 26 and `SystemLanguageModel.default.availability == .available`, read on every call.
    static var modelAvailable: Bool { get }
}
// PersistenceStore
var useAppleIntelligence: Bool            // key "fc.useAppleIntelligence", default true
var yesterdayNoteDismissedDay: Date?      // key "fc.yesterdayNoteDismissedDay"
// SettingsModel
var useAppleIntelligence: Bool            // get/set through write { store.useAppleIntelligence = $0 }
```

- [ ] **Step 1: Write the failing checks** in `ReviewNoteGateChecks.swift` (`enum ReviewNoteGateChecks: CheckSuite`), using `PersistenceStore(defaults:)` over `MemoryDefaults.suite(named: "fc-selftest-notes-\(UUID().uuidString)")` (returns `UserDefaults?`; fail the check on nil), then `MemoryDefaults.remove(named:)`.

```swift
("Apple Intelligence notes are on until the switch is turned off", switchDefaultsOn),
// fresh store: expect(store.useAppleIntelligence == true); set false → reads false from a second PersistenceStore on the same suite
("The Yesterday notice remembers the day it was dismissed", dismissedDayPersists),
// set yesterdayNoteDismissedDay = SelfTest.base; second store reads the same Date
```

- [ ] **Step 2: Register and run typecheck** (command from Task 1 Step 3). Expected: errors naming `useAppleIntelligence`.

- [ ] **Step 3: Implement** `ModelGate`, the two `PersistenceStore` properties and the `SettingsModel` proxy. Point `AskModel.canAsk` at `ModelGate.modelAvailable` (same result; Ask's notices unchanged). Add `.appleIntelligence` to the settings-control enum with `\SettingsModel.useAppleIntelligence`, and fill every `switch` the compiler then flags with the title "Use Apple Intelligence".

- [ ] **Step 4: Add the switch row** in the "Privacy" `SurfacePanel` of `data`, after the "App use measured precisely since" row, only when `ModelGate.modelAvailable`:

```swift
rowDivider
toggleRow("Use Apple Intelligence",
          detail: "Writes notes and suggestions with Apple's on-device model. Nothing leaves this Mac.",
          isOn: $model.useAppleIntelligence)
```

- [ ] **Step 5: Run** `./build.sh --check`. Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git commit -m "Settings can turn Apple Intelligence notes off, and Ask reads one shared model check"
```

---

### Task 3: Gathering a period's facts from the store

**Files:**
- Create: `Sources/App/SessionStore+Notes.swift`
- Create: `Sources/Verification/ReviewNoteStoreChecks.swift`
- Modify: `SelfTest+Registry.swift`

**Interfaces:**
- Consumes: Task 1 builders; `storyDayProjection(on:calendar:)`, `historySummary(for:)`, `historyRows(under:)`, `periodCalendar`, `now()`, `engine.store.dailyGoal`, `engine.store.useAppleIntelligence`, `engine.store.yesterdayNoteDismissedDay`.
- Produces (all on `SessionStore`, `@MainActor`):

```swift
func notePlace(forDayContaining date: Date) -> HistoryPlace          // level .day, span = that day in periodCalendar
func noteFacts(for place: HistoryPlace) -> NoteFacts?                // .day → NoteFacts.day; .week/.month → NoteFacts.period; .year → nil
func noteIsCurrent(_ place: HistoryPlace) -> Bool                    // place.span.holds(now())
func noteFiguresLine(for place: HistoryPlace) -> String              // History's focused/sessions for the day, goal credit from the projection
var appleIntelligenceEnabled: Bool { get }                           // engine.store.useAppleIntelligence
var wrapUpOffered: Bool { get }                                      // today has ≥1 session and none isRunning
func yesterdayNotePlace() -> HistoryPlace?                           // yesterday's place when it had a session and yesterdayNoteDismissedDay != its start
func dismissYesterdayNote()                                          // stores yesterday's start in yesterdayNoteDismissedDay
```

Period inputs: `sessionTotals` sums `DaySession.worked` by `name` over `storyDayProjection(on:)` for each day in the span (past days are cached by the projection), busiest first. `goalMetDays` counts days whose projection `goalCredit >= goal`. `previousFocused` is `historySummary(for:)` of the span immediately before, same level, built with `periodCalendar`.

- [ ] **Step 1: Write the failing checks** with `AskLookupChecks.withFixture` (sessions Mon 13 Nov, Tue 14 Nov, Tue 17 Oct 2023; clock Wed 15 Nov):

```swift
("A past day's note facts match the day History shows", dayFactsMatchHistory),
// facts(for: notePlace(Tue 14 Nov)) lines contain "Focus: 1h 30m over 1 session"; noteIsCurrent == false
("A week's note facts carry History's week figures", weekFactsMatchHistory),
// week of 13 Nov: lines contain "Focus: \(DurationText.compact(summary.focused)) over \(summary.sessions) sessions"
("An empty day and a year have no note facts", noFactsWhereNoNote),
("Yesterday is finished just after midnight", yesterdayFinishedAfterMidnight),
// advance clock to Thu 16 Nov 00:30: noteIsCurrent(notePlace(Wed 15 Nov)) == false
("A session running across midnight changes yesterday's facts as it grows", runningAcrossMidnight),
// start a session 23:30, advance to 00:30 then 00:45: facts text for yesterday is identical (its yesterday share is clipped) and today's differs
("Today and this week are current, so their notes wait for a request", currentPeriods),
// noteIsCurrent(today) && noteIsCurrent(this week) && noteIsCurrent(this month); !noteIsCurrent(last week)
("The Yesterday notice is offered once per day until dismissed", yesterdayOffer),
// with a session yesterday: yesterdayNotePlace() != nil; dismissYesterdayNote(); == nil; advance a day with a session on the new yesterday → != nil;
// a yesterday holding only a recorded break → nil
("Wrap up today is offered only when today has a session and none is running", wrapUpOffer),
```

- [ ] **Step 2: Register and typecheck.** Expected: errors naming `noteFacts(for:)`.

- [ ] **Step 3: Implement** `SessionStore+Notes.swift` to the interface. Read only through existing methods; add no stored properties.

- [ ] **Step 4: Run** `./build.sh --check`, then `TZ=Europe/Berlin ./build.sh --check`. Expected: all pass in both.

- [ ] **Step 5: Commit**

```bash
git commit -m "The store can hand a note writer any day's or period's facts"
```

---

### Task 4: The note writer

**Files:**
- Create: `Sources/App/NoteWriter.swift`
- Modify: `Sources/App/MainWindowModel.swift` (beside `askModel`)
- Create: `Sources/Verification/ReviewNoteWriterChecks.swift`
- Modify: `SelfTest+Registry.swift`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:

```swift
enum NoteState: Equatable { case writing, written(WrittenNote), failed(requested: Bool) }

@MainActor final class NoteWriter: ObservableObject {
    @Published private(set) var states: [String: NoteState]      // key: place.id
    init(store: SessionStore)
    var isUsable: Bool { get }          // store.appleIntelligenceEnabled && (responder != nil || ModelGate.modelAvailable)
    func state(for place: HistoryPlace) -> NoteState?
    /// Writes unless a note for this place and these exact facts is cached.
    func request(_ place: HistoryPlace, requested: Bool)
    func cancel(_ place: HistoryPlace)  // views call this on disappear
    /// Checks only.
    var responder: (@MainActor (NoteFacts) async throws -> WrittenNote)?
    /// Snapshots only.
    func present(_ note: WrittenNote, for place: HistoryPlace)
}
// MainWindowModel
var notes: NoteWriter? { get }          // built on first read from `store`, like openAsk() builds askModel
```

Behaviour: cache `[String: WrittenNote]` keyed `place.id + "\n" + facts.text`. One `Task` at a time; a request for a different place cancels the running one and clears its `.writing` state. On return, drop the result unless `isUsable` and the task is still current. Audit failure, any thrown error, or `facts == nil` → `.failed(requested:)`. Tip kept only for `.day` facts and only when non-empty.

Live path (`@available(macOS 26, *)`): fresh `LanguageModelSession(instructions:)` per request; `respond(to: facts.text, generating: GeneratedNote.self, options:)` with greedy options copied from `AskModel.options`.

```swift
@available(macOS 26, *)
@Generable struct GeneratedNote {
    @Guide(description: "At most two sentences on what the person worked on and in what order. Quote session names exactly as written.")
    var story: String
    @Guide(description: "One sentence building on exactly one of the listed observations.")
    var pattern: String
    @Guide(description: "For a day: one sentence of advice for the next day, building on one listed observation. For a week or month: empty.")
    var tip: String
}
```

Instructions (exact):

```swift
"You write a short private note for the person who recorded this focus history in Daybook. "
    + "Use only the facts given. Write every figure in digits, exactly as the facts write it, and add no figure of your own. "
    + "Never total, average or compare figures yourself; use the comparisons the facts give. "
    + "Write in plain Australian English, in the second person, past tense for a finished period and present tense for one marked so far. "
    + "Do not praise or scold."
```

- [ ] **Step 1: Write the failing checks** with the Ask fixture and `writer.responder`, waiting with `InstalledAppCatalog.turnRunLoop(until: { writer.state(for: place) != .writing }, timeout: 5)` as `AskModelChecks` does. The switch is `f.store.engine.store.useAppleIntelligence`.

```swift
("A note for unchanged facts is written once and then served from memory", cacheHit),
// responder counts calls; request twice for Tue 14 Nov → count == 1, state .written
("A note stating a figure the facts lack is never shown", failedAuditHidden),
// responder returns story "You focused 9h 59m" → state == .failed(requested: false)
("Nothing is written when Apple Intelligence is switched off", switchOff),
// f.store.engine.store.useAppleIntelligence = false → request → states empty, responder never called
("Switching off mid-write publishes nothing when the answer returns", switchOffMidWrite),
// responder suspends; flip switch; resume → state is not .written and not .writing
("Opening another period cancels the note being written", newerWins),
("A week's note never carries a tip", weekHasNoTip),
("Renaming a session writes the day's note again", renameRewrites),
// f.store.renameSession(<Tue 14 Nov's DaySession>, to: "Lexer") → second request calls responder again
```

- [ ] **Step 2: Register, typecheck.** Expected: errors naming `NoteWriter`.

- [ ] **Step 3: Implement** `NoteWriter.swift` and `MainWindowModel.notes`.

- [ ] **Step 4: Run** `./build.sh --check`. Expected: all pass.

- [ ] **Step 5: Mutation test.** In `T="$(mktemp -d "$TMPDIR/fc-tree.XXXXXX")"; rsync -a build.sh Sources Assets scripts "$T/"` (copy `.build/vendor` too), make `NoteAudit.passes` return `true`, run `./build.sh --check` there. Expected: "A note stating a figure the facts lack is never shown" fails. Remove `$T`.

- [ ] **Step 6: Commit**

```bash
git commit -m "Daybook writes audited notes with Apple's on-device model and keeps them in memory"
```

---

### Task 5: Notes in History, Today and the Yesterday notice

**Files:**
- Create: `Sources/Surfaces/Story/PeriodNote.swift`
- Create: `Sources/Surfaces/Story/YesterdayNotice.swift`
- Modify: `Sources/Surfaces/History/HistoryTreeRow.swift` (`children`)
- Modify: `Sources/Surfaces/Story/StoryRail.swift` (top of `body` VStack, `day == nil`)
- Modify: `Sources/Surfaces/Snapshotter.swift` (scenario `reviewNotes`)

**Interfaces:**
- Consumes: `NoteWriter` (Task 4) via `navigation.notes`; store methods (Task 3).
- Produces:

```swift
struct PeriodNote: View {
    enum Trigger { case automatic, onRequest(label: String) }   // "Write a note" / "Wrap up today"
    @ObservedObject var writer: NoteWriter
    let place: HistoryPlace
    let trigger: Trigger
    let tipLabel: String?                                        // nil hides the tip
}
struct YesterdayNotice: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var writer: NoteWriter
}
```

Rules:
- `PeriodNote` draws nothing unless `writer.isUsable`. `.automatic` calls `request(place, requested: false)` in `.onAppear`; `.onRequest` shows a `StoryLinkStyle` button until pressed. All call `writer.cancel(place)` in `.onDisappear`.
- States: `.writing` → "Writing…" (secondary); `.written` → story and pattern as one paragraph, then `tipLabel + " " + tip` when both exist, then the caption; `.failed(requested: true)` → the failure line; `.failed(requested: false)` → nothing.
- Caption: `Label("Apple Intelligence · on this Mac", systemImage: "apple.intelligence")` in `Tokens.Typography` caption role, secondary. `.accessibilityElement(children: .combine)` on the note.
- An on-request note announces itself when written, with the existing `.announcesChanges(to:)` modifier used by `StoryColumns`.
- `HistoryTreeRow.children`: for `.day`, `.week`, `.month`, when `navigation.notes` is non-nil and `store.noteFacts(for: row.place) != nil`, put `PeriodNote(trigger: store.noteIsCurrent(row.place) ? .onRequest(label: "Write a note") : .automatic, tipLabel: nil)` first, padded like the day column.
- `StoryRail` (`day == nil`), above `BackupOfferNotice`: `YesterdayNotice` when `store.yesterdayNotePlace() != nil`; then `PeriodNote(place: store.notePlace(forDayContaining: store.now()), trigger: .onRequest(label: "Wrap up today"), tipLabel: "For tomorrow:")` when `store.wrapUpOffered`.
- `YesterdayNotice`: title "Yesterday" (rowTitle role), `store.noteFiguresLine(for:)` (body, monospaced digits), `PeriodNote(trigger: .automatic, tipLabel: "For today:")`, and a `Done` button (`StoryLinkStyle(tint: .secondary)`) calling `store.dismissYesterdayNote()`. Hidden when `!writer.isUsable`.
- Snapshot `reviewNotes`: today's rail with a Yesterday notice and a History day note, both via `writer.present(_:for:)` with fixed text whose figures match the fixture.

- [ ] **Step 1: Add the views and placements** to the rules above.

- [ ] **Step 2: Run** `./build.sh --test` (sandbox disabled; replaces this worktree's `Daybook.app` only). Expected: all checks pass.

- [ ] **Step 3: Snapshots at both zoom ends**

```bash
P="$(mktemp -d "$TMPDIR/fc-snap.XXXXXX")"
FC_SNAPSHOT_ONLY=reviewNotes FC_SNAPSHOT_ZOOM=0.8 ./Daybook.app/Contents/MacOS/Daybook --snapshot "$P/80"
FC_SNAPSHOT_ONLY=reviewNotes FC_SNAPSHOT_ZOOM=1.4 ./Daybook.app/Contents/MacOS/Daybook --snapshot "$P/140"
```

Expected: PNGs in both folders; open them: no clipped text, caption on one line, Done reachable. Remove `$P`.

- [ ] **Step 4: Commit**

```bash
git commit -m "Notes appear in History, as a Today wrap-up and as a Yesterday notice"
```

---

### Task 6: Live-model probe

No committed code. Follows the Ask probe recipe (memory: temp tree copy plus an entry that calls the model with a fixture store).

- [ ] **Step 1:** In a temp tree copy, add a `--noteprobe` entry that builds the Ask fixture plus 17 more fixture periods (days with 1, 3, 9 sessions; digit-named sessions; a running session; weeks and months, current and past), requests each through a live `NoteWriter`, and prints `place | audit=pass|fail | story | pattern | tip`.
- [ ] **Step 2:** Run it on this Mac (macOS 27.2, Apple Intelligence on). Expected: `audit=fail` count 0 of 20. If any fail, fix the facts (spec rule: fixes go in facts, not prompts), re-run.
- [ ] **Step 3:** Paste the 20 lines into the spec under a new "§6a Probe (date)" heading for Sir's read of tone and accuracy. Remove the temp copy.

---

### Task 7: Docs and ship

**Files:**
- Modify: `README.md:80` paragraph
- Modify: `docs/specs/2026-10-10-apple-intelligence-notes-design.md` (status, "Spec adjustments" above, probe results)

- [ ] **Step 1:** In README's privacy paragraph, after the Ask sentence, add: "Review notes are written by the same on-device model, and nothing is sent anywhere."
- [ ] **Step 2:** Apply the four spec adjustments listed at the top of this plan; set Status to "built; hand checks pending".
- [ ] **Step 3:** Run `./build.sh --check` and `TZ=Europe/Berlin ./build.sh --check`. Expected: all pass.
- [ ] **Step 4:** Run the `fix-reviewer` agent over the branch diff (it touches settings persistence and time arithmetic). Fix findings with a check each.
- [ ] **Step 5:** Ship with the `ship` skill (PR flow through the review session per the sessions board). Hand checks in spec §7 run on Sir's build before merge.
