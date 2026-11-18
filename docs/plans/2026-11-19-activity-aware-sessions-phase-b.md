# Activity-aware sessions, Phase B: provenance, corrections, split and merge, leisure

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every session says how it began and where its category came from; the
person's category changes are remembered and suggested back; a label that the
evidence contradicts gets one factual line; a session that held two pieces of
work can be split in hindsight and merged back; and leisure outside sessions is
recorded as its own non-focus block.

**Architecture:** Two optional, tolerantly decoded fields on `SessionRecord`
(origin, category source) plus a small name flag carry provenance. Corrections
live in their own Core store keyed by Phase A's `ActivityFingerprint`. Split and
merge are engine operations built the way away corrections are, with one undo
entry each. Leisure blocks live in their own file, so no build, old or new, can
count them as focus, a break, a goal or a streak.

**Tech Stack:** Swift 5 mode, AppKit and SwiftUI, macOS 14; `build.sh` self-checks.

**Spec:** `docs/specs/2026-11-17-activity-aware-sessions-design.md` (sections 4,
5, 6, 10, "Phasing" row B, "Left to the builder"), with
`docs/specs/2026-11-17-self-answering-away-design.md` section 7 for the shared
source vocabulary. The spec is the binding authority; where this plan rules on
something the spec leaves open, the ruling is written below with its reason.

Written 19 November 2026 by the Phase B controller session while the owner was
asleep. Phase C stacks on this branch: the Interfaces section is its contract.

## Rulings (open Phase B decisions, decided here)

Fixed by the owner and not reopened: privacy first; Daybook never changes a
category, Activity Rule or name the person made; nothing is changed silently.

| # | Ruling | Reason |
|---|---|---|
| B1 | `SessionRecord` gains `origin: SessionOrigin?` (`manual`, `rule`, `automatic`), `originRuleID: UUID?`, `originRuleName: String?`, `categorySource: DecisionSource?` and `nameByApp: Bool?`. All optional keys; nil means "recorded before Phase B". | Spec section 4 names `origin`; older builds ignore unknown keys, so the file stays readable both ways. |
| B2 | Reading rules: missing `origin` reads `.automatic` when `isAuto`, else `.manual` (spec text). An unknown raw origin reads `.automatic`. Missing `categorySource` reads `.builtIn` when `isAuto`, else `.user`. An unknown raw source reads `.builtIn`. | Spec section 4; and the away design's rule that a newer build's automatic source is never shown as the person's own. |
| B3 | `DecisionSource` is the away design's enum, `user, rule, correction, ai, builtIn`, defined once in Core in this phase. The away design extends it later, not a second enum. | One vocabulary (away design section 7), whichever lands first builds it. |
| B4 | The rule's name is stored at start (`originRuleName`) beside its id. The mark shows the rule's current name when the rule still exists, else the stored one, else "a rule". | Spec: "started by a rule (naming the rule)"; rules are renamed and deleted. |
| B5 | A remembered correction is never applied to a stored record. It appears as a one-click suggestion on an ended session whose category source is `builtIn` ("You usually file this as Coding"). It is written into a record only where a record is being created by Daybook anyway: the tail of a split. | Spec: "A session's stored category never changes on its own"; precedence then still holds wherever Daybook chooses. |
| B6 | Corrections are recorded when the person changes the category of an ended session that has a stored shape with a fingerprint: `chosen` is the new category, `vetoed` is the old one unless its source was `user`. Store kind `category` only; `awayAnswer` is a reserved kind for the away design. File `corrections.json` beside `sessions.json`, included in backups (it is the person's own choices), expiry 90 days applied on read and pruned on write. | Spec section 6; one store (away design section 8). The live-data guard already covers the whole `Daybook` folder. |
| B7 | Contradiction mapping: built-in categories map to purposes, `deepWork` to the focused purposes (coding, writing and AI, design), `meetings` to communication, `admin` to utility and communication, `learning` to research, media and the focused purposes; `breakTime` has no line. A custom category maps to the focused purposes. The line shows only for sources `user` and `rule`, in the session report, never in the row. | The spec requires a category-to-purpose mapping and none exists; this is the smallest honest one, and it catches the main case (work label, mostly video). |
| B8 | "Unsorted" as a non-focus category, and the stored "counts toward focus goals" property, move to Phase C, which needs them for kept labels. In Phase B a split tail whose dominant purpose is not focused keeps the head's category with source `builtIn`, and the contradiction line still tells the truth. | Adding a non-focus category changes what counts, which Phase B must not do silently; flagged for the owner. |
| B9 | "Split here?" and "Merge back" are one engine pair: `splitRecord(id:at:)` and `mergeRecords(head:tail:)`, each one undo entry. Head keeps id, name, category, thread and source; tail gets a new id and thread, origin of the head, `nameByApp` true with the dominant activity name when the head's name was the app's, else the head's name. | Spec section 4 "How an automatic split is written". |
| B10 | Manual and rule sessions: the report of an ended session with a split candidate shows "Split here?" with Split and Keep Together. Keep Together stores a declined override in the sidecar (`declinedSplits: [Date]`) and the offer does not come back. | Spec table "Who may split"; section 5 "accepted or declined splits" are stored overrides. |
| B11 | Automatic sessions (`origin == .automatic` only) split themselves at the split candidates when the session ends. While running, the strip shows the provisional phase only; a split of the running session is deferred (B12). | Spec: nothing is written while provisional; final at session end is the spec's second trigger. |
| B12 | Splitting a still-running automatic session when its return window closes is Task 8, built last and droppable on budget. If dropped, ended-session splitting stands and the owner is told. | It changes the live engine state and carries the most risk. |
| B13 | Merge back is offered on a tail while head and tail are adjacent (`head.end == tail.start`), both carry the split link, and neither has been renamed or recategorised since the split. The link is a sidecar entry on the tail (`splitFrom: UUID`, plus the head's and tail's name and category at split time). | Spec: "adjacent and unedited". |
| B14 | Leisure blocks live in `leisure.json`, a Core `LeisureBlock { id, start, end, bundleID, activity }` file, never in `sessions.json`. They are found from beats after the run ends (held or passive media, automatic mode on, no session running, at least `leisureMinRun` 600 s), written once, shown on the day timeline with the activity name and app, and read by nothing that totals focus, goals, streaks or breaks. | Spec "Left to the builder": an old build reading `sessions.json` counts every non-break record as focus; a separate file makes the guarantee structural. |
| B15 | "Carried on after an away answer" is derived, not stored: a receipt with decision `.mergeTime` whose range lies inside the record. The mark reads "Carried on after you were away (your answer)". | Today every away answer is the person's; the away design adds other sources later through `DecisionSource`. |
| B16 | A name is "chosen by the app" when `AutoSessionDetector.sessionName` produced it (automatic mode). A rule's name is the person's. Any rename clears `nameByApp`. | Spec "Origin is shown, quietly". |
| B17 | `ActivityConstants` gains `leisureMinRun` 600, `correctionExpiryDays` 90, `contradictionLow` 0.30, `contradictionHigh` 0.60. `algorithmVersion` stays 1: no derivation rule changes. | Spec section 10. |
| B18 | Visual treatment: one `OriginMark` component in `Design/Components`, `StoryStyle.supportingInk`, caption size, an SF Symbol plus a few words, with an accessibility label carrying the full sentence. Design review by the controller from `--snapshot` images. | Spec: quiet mark, design review before it ships. |

## Global Constraints

- `./build.sh --check` passes before each commit, sandbox disabled, one build at a time. The final gate also runs `TZ=Europe/Berlin` and `TZ=Pacific/Kiritimati`.
- Never `--install`, `--test` or `--run`; never launch a built Daybook except with `--snapshot`; never touch live data.
- Core is UI-free and compiles alone. Views never recalculate time. No new timer.
- Files at most 300 lines; files already over (`SessionStore.swift`, `SessionStore+History.swift`, `SessionStore+StoryDetails.swift`, `SessionMetadataArchive.swift`, `Surfaces/Today/DayStory.swift`) take no net growth: new code goes in new files.
- New stored `SessionStore` or `SessionEngine` members join the `keep_internals` lists in `build.sh`.
- Checks: `TestClock`, `SelfTest.scratchDirectory()`, `MemoryDefaults`, times as offsets from `SelfTest.base`; new suites at the end of `registeredTests`; each fix with a check that fails on the old behaviour.
- Lengths in App, Design and Surfaces are tokens or `.zoomed`.
- Persistence, settings, session state or time arithmetic: `fix-reviewer` before the task is complete.
- Commit subjects: one plain present-tense sentence for any user of the app. No push until the final step; draft pull request only.
- Do not touch goals files, the Yesterday card or awards (another session owns them).

## Review Focus

1. A `sessions.json` written by this build, read by today's release: decodes, totals unchanged. Task 1 check decodes with a copy of the pre-Phase-B `SessionRecord` decoder shape (unknown keys ignored) and compares totals.
2. Split then edit then undo: undo order stays coherent (Task 6 check: split, rename tail, undo twice returns the original single record).
3. A split at a time that is not strictly inside the record (at start, at end, inside a paused span) is refused, not written (Task 6).
4. A leisure run that overlaps a session that starts later (backdated automatic start) is trimmed to the gap or dropped, never double-counted on the timeline (Task 7).
5. A correction recorded in one time zone and read in another: matching uses the fingerprint only, expiry uses whole seconds, never calendar days (Task 3).

## Interfaces (Phase C contract)

```swift
// Core/SessionProvenance.swift
enum SessionOrigin: String, Codable { case manual, rule, automatic }
enum DecisionSource: String, Codable { case user, rule, correction, ai, builtIn }
extension SessionRecord {
    var effectiveOrigin: SessionOrigin { get }          // B2
    var effectiveCategorySource: DecisionSource { get } // B2
}
// Core/CategoryCorrections.swift
struct CategoryCorrection: Codable, Equatable {
    let kind: String            // "category"
    let fingerprint: ActivityFingerprint
    var chosen: String          // WorkType raw value
    var vetoed: [String]
    var count: Int
    var lastUsed: Date
}
struct CategoryCorrections {
    func suggestion(for fingerprint: ActivityFingerprint, now: Date) -> String?   // never a vetoed one
    mutating func record(fingerprint: ActivityFingerprint, chosen: String, vetoed: String?, at: Date)
    mutating func pruned(now: Date)
}
// Core/ContradictionLine.swift
enum ContradictionLine { static func text(category: WorkType, source: DecisionSource, credited: [String: TimeInterval]) -> String? }
// Core/LeisureBlocks.swift
struct LeisureBlock: Codable, Equatable, Identifiable { let id: UUID; let start: Date; let end: Date; let bundleID: String; let activity: AppPurpose }
```

Engine operations (Task 5): `SessionEngine.splitRecord(id: UUID, at: Date, tail: SplitTail) -> Bool` and `SessionEngine.mergeRecords(head: UUID, tail: UUID) -> Bool`, each staged through `prepareCorrection` and `commitCorrection` so `undoLastCorrection()` reverses it.

---

### Task 1: Provenance fields and their reading rules (Core)

**Files:** Create `Sources/Core/SessionProvenance.swift`; modify `Sources/Core/SessionState.swift` (record fields, init, decode); test `Sources/Verification/ProvenanceChecks.swift`, registered last.

**Interfaces:** Produces the enums and `effectiveOrigin` / `effectiveCategorySource` above; record memberwise init gains `origin:`, `originRuleID:`, `originRuleName:`, `categorySource:`, `nameByApp:`, all defaulting to nil.

- [ ] Write checks: legacy JSON without the keys reads origin `.automatic` for `isAuto` true and `.manual` otherwise, source `.builtIn` / `.user`; unknown raw values read `.automatic` and `.builtIn`; a full record round-trips; a record encoded by this build decodes through a frozen copy of today's decode (keys ignored) with identical `workSeconds`, `workType`, `isAuto`.
- [ ] Run `./build.sh --check`; expect the new checks to fail to compile, then implement, then pass.
- [ ] fix-reviewer (persistence). Commit: "Each session now remembers how it began and where its category came from".

### Task 2: Write provenance at every start and edit (App and engine)

**Files:** modify `Sources/Core/SessionEngine+Sessions.swift` (`start`, `startAutomatically(action:)`, `claim`), `Sources/Core/SessionEngine+SessionControl.swift` (rule switch), `Sources/App/SessionStore+Automation.swift` (`startAutomatically` passes `nameByApp: true`), the record-writing sites in `SessionEngine` (archive current session, away splits keep the live record's provenance), `SessionStore+History.swift` correction path through a new `SessionStore+Provenance.swift` (rename clears `nameByApp`; `setWorkType` by the person sets source `.user`). New engine stored members (`activeOrigin`, `activeOriginRuleID`, `activeOriginRuleName`, `activeCategorySource`, `activeNameByApp`) join `keep_internals` and `PersistedState` (optional).

- [ ] Checks: manual start writes `.manual`/`.user`; rule start writes `.rule` with id and name and source `.rule`; automatic start writes `.automatic`/`.builtIn`/`nameByApp` true; claim of an automatic session keeps origin and sets source `.user`; rename clears `nameByApp`; an away split's before-record keeps the provenance; relaunch mid-session (PersistedState round trip) keeps it; a learned category on an automatic start is still `.builtIn` (B5).
- [ ] Build, pass. fix-reviewer (session state). Commit: "Sessions keep their origin through pauses, away answers and relaunches".

### Task 3: Corrections store and the suggestion

**Files:** create `Sources/Core/CategoryCorrections.swift` (pure, Codable file model, `ActivityConstants.correctionExpiryDays`), `Sources/App/CorrectionsStore.swift` (load and save `corrections.json` atomically beside `sessions.json`; included in `DataBackup`), `Sources/App/SessionStore+Corrections.swift` (record on the person's category change of an ended session with a fingerprint; publish `correctionSuggestion(for: recordID) -> WorkType?` only for `builtIn` sources and startable categories); report row in `Sources/Surfaces/Story/CorrectionSuggestionRow.swift` with "Use <Category>" (sets the category through the normal person path, source `.user`).

- [ ] Checks: record then suggest for the same fingerprint; vetoed never suggested; count increments; 90 days plus 1 s later no suggestion and pruned on write; retired category not suggested; suggestion never shown for `user` or `rule` sources; a corrupt file reads empty and is not overwritten until the next record (keep a `.bad` copy, as other stores do); suggestion does not change the stored record until clicked.
- [ ] Build, pass. fix-reviewer (persistence). Commit: "Daybook remembers how you file a kind of session and suggests it next time".

### Task 4: Origin mark, carried-on mark and the contradiction line

**Files:** create `Sources/Design/Components/OriginMark.swift`, `Sources/Core/ContradictionLine.swift`, `Sources/App/SessionStore+OriginText.swift` (builds the mark text from record, current rule names and receipts: B4, B15, B16); add the mark to the session row through `SessionEntryCard+Activity.swift` and `SessionCardSignature` (no net growth in `DayStory.swift`) and to `SessionReportView`; the contradiction line in the report only.

Copy (sentence case): "Started by you", "Started by rule ‘<name>’", "Started automatically", "Carried on after you were away (your answer)", "Name chosen by Daybook". Contradiction: "Mostly <activity>: <n> of <m> minutes" with minutes from code, activity names from `SessionPhaseText`.

- [ ] Checks: text for each origin and fallback rule names; contradiction fires at focused share 0.29 and other share 0.61, not at 0.30 or 0.60; not for `builtIn`; built-in mapping per B7; mark has an accessibility label equal to the full sentence; signature changes when origin changes.
- [ ] Build, pass, `--snapshot` the row and report; controller design review recorded in `docs/reviews/2026-11-19-origin-mark.md`. Task reviewer. Commit: "Each session shows quietly how it began, and the report notes when the activity contradicts the label".

### Task 5: Split and merge engine operations

**Files:** create `Sources/Core/SessionEngine+Split.swift` (`splitRecord`, `mergeRecords`, `SplitTail { name, workType, source, nameByApp }`), `Sources/Core/SplitLink.swift` (sidecar entry on the tail, B13), `Sources/App/SessionStore+Split.swift` (store wrappers, undo through the existing correction snapshot, `canMergeBack(recordID:) -> Bool`). Sidecar additions in a new `SessionMetadataArchive+Split.swift`.

- [ ] Checks: split inside an ended record writes head `[start, at)` and tail `[at, end)` with work seconds divided by counted time (paused spans honoured), totals unchanged; split at start, end or inside a paused span refused; merge restores one record equal to the original (id, thread, seconds); undo of split equals merge; merge refused after a rename of either part; Review Focus 2; goals, streak and daily totals unchanged across split and merge.
- [ ] Build, pass. fix-reviewer (session state, time arithmetic). Commit: "A session can be split in two and merged back without changing your totals".

### Task 6: "Split here?" and "Merge back" in the report; automatic sessions split at the end

**Files:** create `Sources/Surfaces/Story/SplitOfferRow.swift`, `Sources/App/SessionStore+SplitOffer.swift` (offer = ended record, origin manual or rule, split candidate inside it, not declined; tail choice per B5, B8, B9), automatic end-of-session split in `SessionStore+SplitOffer.swift` called after the stop path writes the snapshot (origin `.automatic` only), "Merge back" button on the tail's report.

- [ ] Checks: manual session with a candidate shows the offer, Keep Together stores the decline and hides it after relaunch; rule session the same; automatic session ends and is written as head plus tail with Merge back available; tail category from a matching correction, else `suggestedWorkType` for the tail's top app when its dominant purpose is focused, else the head's with source `builtIn`; a session without candidates is untouched; Undo after the automatic split restores one record.
- [ ] Build, pass, snapshot review. fix-reviewer. Commit: "Daybook offers to split a session that held two pieces of work, and automatic sessions split themselves with Merge back".

### Task 7: Leisure blocks

**Files:** create `Sources/Core/LeisureBlocks.swift` (`LeisureFinder.blocks(beats:sessions:autoModeOn:after:) -> [LeisureBlock]`, pure), `Sources/App/LeisureStore.swift` (`leisure.json`, written once per finished run), `Sources/App/SessionStore+Leisure.swift` (run at a beat edge only when no session runs and automatic mode is on), `Sources/Surfaces/Story/LeisureBlockRow.swift` on the day timeline.

- [ ] Checks: 10 min of held media with no session gives one block, 9 min 59 s gives none; a run inside a session gives none; automatic mode off gives none; Review Focus 4; a block never appears in daily totals, goals, streaks, break statistics or History focus figures (assert each read model unchanged with and without the file); written once (second pass adds nothing); old `sessions.json` unchanged byte for byte.
- [ ] Build, pass. fix-reviewer (persistence). Commit: "Watching or listening outside a session shows on the timeline as leisure, never as focus".

### Task 8 (droppable): Split a running automatic session when its window closes

**Files:** `Sources/Core/SessionEngine+Split.swift` (`splitRunning(at:tail:)`: the archive gains the head ending at the departure; the running session continues as the tail with a new record id and thread), `Sources/App/SessionStore+SplitOffer.swift` hook at the beat edge when Phase A reports a closed window for an `.automatic` origin.

- [ ] Checks: running automatic session, departure at 10 min, no return by 25 min: head written ending at 10 min, live session's start becomes 10 min, elapsed shown is continuous, totals unchanged; a return at 24 min writes nothing; manual and rule sessions never split; relaunch mid-window writes nothing until the window closes; Merge back on the tail rejoins.
- [ ] Build, pass. fix-reviewer. Commit: "Automatic sessions split as soon as the work clearly changed".

### Task 9: Documentation and the whole branch

- [ ] Settings help and README: origin marks, corrections file (what it keeps, 90 days), leisure blocks (never focus).
- [ ] Whole-branch review (opus, read-only) against spec and rulings; fix round.
- [ ] `./build.sh --check` in local, `TZ=Europe/Berlin`, `TZ=Pacific/Kiritimati`.
- [ ] Push branch, open a draft pull request. No merge, no release.
