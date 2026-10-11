# Name Suggestions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An ended, unnamed focus session from today or yesterday is offered a name in a Story rail notice. The name is one of the person's earlier names, picked by the on-device model from candidates that code ranks, or a fresh short name that code audits. It is written only on "Name it".

**Architecture:**
- Pure Core ranking (`NameCandidates`) and audit (`NameAudit`).
- An App store extension that chooses the sessions to offer and builds their facts.
- An App `NameSuggester` (the `NoteWriter`/`SearchRescue` shape) that asks the model once per session, caches the answer and publishes the current suggestion.
- A Surfaces notice in today's rail tile.

**Tech Stack:** Swift 5 mode, SwiftUI/AppKit, `FoundationModels` (weak-linked, `@available(macOS 26, *)`), headless self-checks.

**Spec:** `docs/specs/2026-10-12-name-suggestions-design.md`

## Global Constraints

- **Model:** on-device only (`SystemLanguageModel.default`). It runs only when `ModelGate.modelAvailable` and `store.appleIntelligenceEnabled` are both true. `Sources/App/ModelGate.swift` stays byte-identical.
- **Copy:** "Suggested by on-device AI". The mark is `Image(systemName: "sparkles")`, never `apple.intelligence`. Buttons are "Name it" and "Keep as is".
- **Numbers:** window 60 days; threshold 0.3; category bonus 0.1; at most 3 candidates; minimum focused time 600 s; fresh name 1–4 words and at most 30 characters; model timeout 10 s.
- **Days:** a session is one `DaySession` (a thread's stretches on one day). Its day is the day it started, in `store.periodCalendar`. Spans are half-open.
- **Threads:** never call the model or the ranking from the 1 Hz ticker. Views read published values only.
- **Files and styling:** files under 300 lines. Lengths are `Tokens` or `.zoomed`. Text uses `Tokens.Typography` roles. Supporting text uses `StoryStyle.supportingInk`.
- **Checks:** use `MemoryDefaults`, `TestClock` and calendar-built fixtures, and never the live model. Append new suites after the last entry of `registeredTests`.
- **Builds:** run `./build.sh` with the sandbox disabled, and run `./build.sh --check` then `TZ=Europe/Berlin ./build.sh --check`. Never launch the live app.
- **Commits:** one plain present-tense subject, a wrapped prose body, and the committing model's Co-Authored-By line.

## Review Focus

1. **A session named on its card while the model is answering.** The answer is dropped and the next session is offered. Test in Task 3.
2. **Earlier names that differ only in case or accents** ("daybook", "Daybook"). They are one candidate, shown in the most recent spelling. Test in Task 1.
3. **A session that starts yesterday at 23:30 and ends today at 00:40.** It belongs to yesterday and its lead reads "last night's". Test in Task 2.
4. **A session with a note but no app evidence.** The model is asked with no candidates. **A session with neither** is never asked. Test in Task 2 (facts) and Task 3 (not asked).
5. **Undo after "Name it".** The same session is not offered again in the same run. Test in Task 3.

---

### Task 1: Core ranking and audit

**Files:**
- Create: `Sources/Core/NameCandidates.swift`
- Create: `Sources/Core/NameAudit.swift`
- Create: `Sources/Verification/NameSuggestionCoreChecks.swift`
- Modify: `Sources/Verification/SelfTest/SelfTest+Registry.swift` (append last)

**Interfaces (produces):**

```swift
struct NameHistoryEntry: Equatable {          // one earlier named session
    let name: String
    let workType: WorkType
    let end: Date
    let appSeconds: [String: TimeInterval]    // bundle ID → seconds in front within the session
}
struct NameCandidate: Equatable {
    let name: String                           // most recent spelling
    let score: Double                          // shared time + 0.1 category bonus
    let usualWorkType: WorkType                // most common category of its sessions
    let usualApps: [String]                    // bundle IDs by share, at most 3
}
enum NameCandidates {
    static let threshold = 0.3, categoryBonus = 0.1, limit = 3
    /// Σ over apps of min(share in a, share in b); 0 when either is empty.
    static func shared(_ a: [String: TimeInterval], _ b: [String: TimeInterval]) -> Double
    /// Groups `history` by folded name (case- and diacritic-insensitive), keeps groups whose shared
    /// time with `appSeconds` is ≥ threshold, ranks by score, ties to the more recent `end`.
    static func rank(appSeconds: [String: TimeInterval], workType: WorkType,
                     history: [NameHistoryEntry]) -> [NameCandidate]
}
enum NameChoice: Equatable { case earlier(Int), fresh(String), none }   // Int is 1…3
enum NameAudit {
    static let maxWords = 4, maxCharacters = 30
    static func accepts(_ name: String, categories: [WorkType], appNames: [String]) -> Bool
    /// The name to offer, or nil. `.earlier(n)` → candidates[n-1].name exactly (nil if out of range);
    /// `.fresh` → nil unless `accepts`, then the earlier spelling if it equals any of `earlierNames`
    /// (case-insensitive), else the trimmed fresh text; `.none` → nil.
    static func resolve(_ choice: NameChoice, candidates: [NameCandidate], earlierNames: [String],
                        categories: [WorkType], appNames: [String]) -> String?
}
```

- [ ] **Step 1: Write the failing checks** in `enum NameSuggestionCoreChecks: CheckSuite`:

```swift
("Shared app time ranks earlier names", ranking),
// session ["xcode":3000,"safari":1200,"terminal":600] vs Daybook ["xcode":5000,"terminal":1000] → shared 0.69;
//   Thesis ["pages":4000,"safari":1000] → 0.25 (dropped, < 0.3); ranking returns ["Daybook"]
("A matching category adds 0.1, and a tie goes to the more recent name", bonusAndTie),
("Names differing only in case or accents are one candidate in the latest spelling", folding),  // Review Focus 2
("At most three candidates", limitThree),
("A fresh name passes only when short, plain and not a category or an app", auditRows),
// accepts: "Daybook parser" ✓; rejects: "Fix 2 bugs", "\"Daybook\"", "Deep work", "Xcode",
//   "one two three four five", 31 characters
("A choice resolves to exact candidate text or an audited fresh name", resolveRows),
// .earlier(1) → candidates[0].name; .earlier(4) → nil; .fresh("daybook") with earlier ["Daybook"] → "Daybook";
//   .fresh("Deep work") → nil; .none → nil
```

- [ ] **Step 2: Register last; typecheck.** Expected: errors naming `NameCandidates`.
- [ ] **Step 3: Implement** both files. Core imports Foundation only. Use `SessionNaming`'s folding for case and accents, the same as `SessionNaming.category(named:)`.
- [ ] **Step 4: Run** both suites. Expected: all pass.
- [ ] **Step 5: Mutation** in a temp tree: drop the threshold, and the ranking check must fail.
- [ ] **Step 6: Commit:** "Earlier session names can be ranked by the apps a new session used"

---

### Task 2: Which sessions, and their facts

**Files:**
- Create: `Sources/App/SessionStore+NameSuggestion.swift`
- Modify: `Sources/Core/PersistenceStore.swift`: add `Key.nameSuggestionKept = "fc.nameSuggestionKept"` and `var nameSuggestionKept: Set<String>` (UUID strings), in the `skippedConfirmations` style. Add the key to the `removeAll` list.
- Create: `Sources/Verification/NameSuggestionStoreChecks.swift`; registry.

**Interfaces:**
- **Consumes:**
  - Task 1's types.
  - `storyDayProjection(on:calendar:)`.
  - `historySortedUsage().uniqueUse(within:)` and `HistoryAppLens.minimumUse`.
  - `metadataArchive.metadata(for:)?.note`.
  - `engine.archive.records`.
  - `engine.store.activityRules`.
  - `SessionNaming.category(named:)`.
  - `SessionStore.timeOfDay(_:calendar:)`.
  - `renameSession(_:to:)`.
  - Durations from `DurationText.compact` (Core, not `Tokens`).
- **Produces:**

```swift
struct NameFacts: Equatable {          // added to Sources/Core/NameCandidates.swift (no App types)
    let text: String                   // exactly the spec §2 layout (lines below)
    let candidates: [NameCandidate]
    let appNames: [String]             // display names of the session's apps, for NameAudit
    let cacheKey: String               // "\(threadID)|\(end)|\(workType.id)|\(note ?? "")"
}
extension SessionStore {
    /// Today's then yesterday's ended, unnamed focus sessions with worked ≥ 600, not kept, newest first.
    func nameSuggestionTargets() -> [DaySession]
    func nameFacts(for session: DaySession) -> NameFacts?   // nil when no app evidence and no note
    /// "this morning's 1h 20m session", "yesterday evening's 45m session", "last night's 2h session"
    func nameSuggestionLead(for session: DaySession) -> String
    func earlierSessionNames() -> [String]                  // the folded-unique pool, latest spellings
    @discardableResult func acceptNameSuggestion(_ name: String, for session: DaySession) -> Bool  // renameSession
    func keepSessionUnnamed(_ session: DaySession)          // adds threadID; trims to threads ending in the last 2 days
}
```

**Facts text, exactly:**
```text
Session: <EEE d MMM>, <h:mm>–<h:mm a>, <compact worked> focused, category <displayName>.
Apps: <name> <compact>, … (apps ≥ minimumUse, largest first; the line is omitted when there are none)
Note: “<note>”                       (omitted when there is no note)
Earlier names that fit:              (omitted when there are no candidates)
1. <name> (usually <app names, comma-separated>; <usual category>)
```

**Earlier-name history:**
- Only records whose `end` falls in the last 60 days (`periodCalendar`, from the start of today minus 60 days) count, and only those with a non-empty name.
- Leave out `isAuto` records unless the name equals an `ActivityRule.name`.
- Leave out names where `SessionNaming.category(named:)` is not nil.
- Each record's `appSeconds` is `uniqueUse(within: [DateInterval(start:end:)])` filtered by `minimumUse`.

**Lead words:**
- Today: "this morning's", "this afternoon's", "this evening's", "tonight's".
- Yesterday: "yesterday morning's", "yesterday afternoon's", "yesterday evening's", "last night's".
- The words come from `timeOfDay(session.start)`.

- [ ] **Step 1: Write the failing checks.** Use a store on `MemoryDefaults` and a `TestClock`, with records appended through `engine.archive.append` (the `AutomaticNamingChecks` pattern). Build days through `periodCalendar`.

```swift
("Only ended, unnamed focus sessions of 10 minutes or more from today and yesterday are offered, newest first", targets),
// a break, the running session, a 9m59s session, a named session, a 2-days-ago session, a kept one → none of them
("A session from 23:30 to 00:40 belongs to yesterday and reads last night's", midnightLead),  // Review Focus 3
("The 60-day window holds in another zone", windowZones),    // Berlin calendar base; a record 60 days + 1 h ago excluded
("Facts list apps, the note and the candidates in the spec's layout", factsText),
("A session with a note but no apps gets facts; one with neither gets none", evidence),        // Review Focus 4
("Auto names and category names are not earlier names; rule names are", earlierPool),
("Name it renames through a correction that Undo reverses", acceptUndo),
("Keep as is is remembered and trimmed to two days", keepTrim),
```

- [ ] **Step 2: Register; typecheck.** Expected: errors naming `nameSuggestionTargets`.
- [ ] **Step 3: Implement.** Add any new store member to `build.sh`'s `keep_internals` list if the guard asks for it.
- [ ] **Step 4: Run** both suites. Expected: all pass.
- [ ] **Step 5: Mutation:** make the day test closed (`<=` end), and `midnightLead` or `targets` must fail.
- [ ] **Step 6: Commit:** "Unnamed sessions from today and yesterday can be listed with the facts a name suggestion needs"

---

### Task 3: The suggester

**Files:**
- Create: `Sources/App/NameSuggester.swift`
- Modify: `Sources/App/MainWindowModel.swift`: `private var nameSuggesterStore: NameSuggester?` and `var nameSuggester: NameSuggester?`, built on first read like `notes`.
- Create: `Sources/Verification/NameSuggesterChecks.swift`; registry.

**Interfaces:**
- **Consumes:** Task 1 and Task 2 APIs; `ModelGate.modelAvailable`; `store.appleIntelligenceEnabled`.
- **Produces:**

```swift
struct NameSuggestion: Equatable { let session: DaySession; let name: String; let lead: String }
@MainActor final class NameSuggester: ObservableObject {
    init(store: SessionStore)
    @Published private(set) var current: NameSuggestion?
    @Published private(set) var isAsking: Bool
    var responder: (@MainActor (NameFacts) async throws -> NameChoice)?   // checks only
    var timeout: Duration = .seconds(10)
    var isUsable: Bool        // store.appleIntelligenceEnabled && (responder != nil || ModelGate.modelAvailable)
    func refresh()            // walks nameSuggestionTargets(); cached answers first; asks for the first uncached one
    func accept()             // store.acceptNameSuggestion; remembers the session's cacheKey for this run; refresh()
    func keep()               // store.keepSessionUnnamed; refresh()
    func cancelAll()          // switch turned off
}
```

**Behaviour:**
1. `refresh` sets `current` to the first target whose cached answer is a name.
   - It skips targets cached as nil, targets whose cacheKey was accepted this run (Review Focus 5; a change to the session's facts makes a new key, so it can be offered again, as spec §3 says), and targets whose name is no longer empty.
   - If it reaches an uncached target before finding a name, it asks the model for that target only, then calls `refresh` again.
   - When `!isUsable` it sets `current = nil` and asks nothing.
2. The cache is `[String: String?]`, keyed by `NameFacts.cacheKey`. `nameFacts(for:)` returning nil is cached as nil without asking the model.
3. **Asking:** one call at a time, using the `SearchRescue` generation-and-timer pattern.
   - A timeout, error or late reply caches nil for that key.
   - A reply whose session was named meanwhile is dropped (Review Focus 1).
4. **The live path:** `@available(macOS 26, *) @Generable struct SuggestedName { choice: String; name: String }`.
   - Use one `LanguageModelSession(instructions:)` with greedy options copied from `NoteWriter`.
   - Map `choice` "1"/"2"/"3" to `.earlier`, "new" to `.fresh(name)`, and anything else to `.none`.
   - Resolve with `NameAudit.resolve`.
5. **Instructions** (exact):

```swift
"You name a stretch of focused work for the person who did it. You get the session's facts and up to three "
    + "earlier names they used for similar work. Answer 1, 2 or 3 to reuse an earlier name when it fits the work. "
    + "Answer new, with a name of one to four words, only when no earlier name fits and the note or the apps say "
    + "clearly what the work was. Otherwise answer none. Never put times, durations or numbers in a name."
```

- [ ] **Step 1: Write the failing checks** with the Task 2 fixture and `responder`:

```swift
("An earlier name is offered with its lead", offersEarlier),        // responder → .earlier(1)
("A fresh name that fails the audit offers nothing and the next session is tried", auditFallthrough),
("Each session is asked once; a redraw does not ask again", askedOnce),   // refresh() ×3 → responder called once per target
("Nothing is asked with the switch off, without evidence, or when the model is unusable", notAsked),
("A timeout or error offers nothing and does not wedge the suggester", timeoutAndError),   // timeout 0.15 s, hung responder
("A session named on its card while the model answers is not offered", namedMeanwhile),    // Review Focus 1
("After Name it and Undo the session is not offered again this run", undoNotReoffered),    // Review Focus 5
("Keep as is moves to the next session", keepNext),
```

- [ ] **Step 2: Register; typecheck.** Expected: errors naming `NameSuggester`.
- [ ] **Step 3: Implement.** Do not edit `ModelGate.swift`.
- [ ] **Step 4: Run** both suites. Expected: all pass.
- [ ] **Step 5: Mutation:** drop the "named meanwhile" guard, and `namedMeanwhile` must fail.
- [ ] **Step 6: Commit:** "A name for an unnamed session is asked of the on-device model once and offered only when the session is still unnamed"

---

### Task 4: The notice

**Files:**
- Create: `Sources/Surfaces/Story/NameSuggestionNotice.swift`
- Modify: `Sources/Surfaces/Story/StoryRail.swift`: in `if day == nil { … }` after `NameCategoryNotice`, add `if let suggester = navigation.nameSuggester { NameSuggestionNotice(store: store, suggester: suggester) }`.
- Modify: `Sources/Surfaces/Snapshotter.swift`: add the scenario `storyNameSuggestion` (case, title "Story — name suggestion", tab `.story`, store from `FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)` plus an unnamed session, and navigation whose `nameSuggester.responder` returns `.earlier(1)` or `.fresh("Release notes")`).

**Rules:**
- **Layout:**

```text
[sparkles] Name <lead> “<name>”?
           Suggested by on-device AI          (supportingInk, caption role)
           [Name it]   [Keep as is]
```

- **Buttons:**
  - "Name it" uses `StoryActionStyle(tint: Tokens.Palette.workType(session.workType))` and calls `suggester.accept()`.
  - "Keep as is" uses `StoryLinkStyle(tint: StoryStyle.supportingInk)` and calls `suggester.keep()`.
  - Copy the spacing and styles from `NameCategoryNotice`.
- **Accessibility:** the mark's label is "Suggested by on-device AI". The notice is one container with two buttons.
- **Triggers:** `.task(id: store.nameSuggestionKey)` calls `suggester.refresh()`. Add `var nameSuggestionKey: Int` to `SessionStore+NameSuggestion.swift`, a hash of `evidenceRevision`, `corrections.count`, the kept list and the start of today, so it never changes on the 1 Hz tick. `.onChange(of: store.appleIntelligenceEnabled)` calls `suggester.cancelAll()` when it turns false.
- **Not drawn:** nothing appears when `suggester.current == nil`.

- [ ] **Step 1: Build the view, the wiring and the scenario.**
- [ ] **Step 2: Run** `./build.sh --test` (sandbox disabled), then `TZ=Europe/Berlin ./build.sh --check`. Expected: all pass, including any snapshot-matrix count check.
- [ ] **Step 3: Snapshots:** `FC_SNAPSHOT_ONLY=storyNameSuggestion` at `FC_SNAPSHOT_ZOOM=0.8` and `1.4`, light and dark. Open each PNG and check that nothing is clipped and both buttons are reachable. Copy one per zoom into the SDD workspace.
- [ ] **Step 4: Commit:** "Today's Story offers a name for an unnamed session, suggested by on-device AI"

---

### Task 5: Live probe and docs

**Files:**
- Modify: `docs/specs/2026-10-12-name-suggestions-design.md`: the status, §5a with the probe results, and any rulings that change the spec's promises.

- [ ] **Step 1: Probe.** In a temp tree copy, build a probe binary (the pattern from the History search probe: rsync `Sources/`, inject a `--nameprobe` flag into `DaybookApp.main`, swiftc with the Sparkle `-F`). Smoke-test the model with a 60 s timeout; if it hangs, stop and report. Run `NameSuggester`'s live path on 20 hand-built sessions over one fixture history. Write the expected answer for each before running.
  - Six repeats of an earlier name with matching apps.
  - Four repeats where only the note says which earlier name applies.
  - Four new pieces of work with a telling note (a fresh name is expected).
  - Three sessions with mixed apps and no note (`none` or an earlier name).
  - Three with no apps and no note (never asked).
  Print `facts | choice | name | offered`.
- [ ] **Step 2: Judge** each row as right, none or wrong. The target is ≥ 16 right-or-none and 0 offered names that fail `NameAudit`. A wrong earlier-name pick is fixed in the ranking or the facts, never the prompt; re-run once after any fix.
- [ ] **Step 3: Record** the results in spec §5a with the date and macOS version. Set the status to "built; hand checks pending".
- [ ] **Step 4: Run** both suites. Commit: "The name suggestions spec records how the live model named twenty sessions"
