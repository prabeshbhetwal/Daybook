# Activity-aware sessions, Phase C: the model's category pick, AI-made labels, the AI mark, shadow mode

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An automatic session whose evidence is unclear gets one question to
Apple's on-device model, which picks one of the person's categories or proposes
a short new label. The answer is first only a one-click suggestion (shadow
mode); Settings shows how often it matched the person's own choices, and the
person may switch on "Let AI assign categories to automatic sessions". An
AI-sourced category carries a small sparkle (the AI mark). An AI-made label
stays on its sessions and joins the person's categories only when they keep it.

**Architecture:** Core gains a stored "counts toward focus goals" property on
categories, a hidden non-focus "Unsorted" category, and a pure label book
(labels, cached answers, the shadow tally) with the trigger, the question text
and the audit of answers. App gains `ai-labels.json`, a `CategoryAssistant`
built on the `NameSuggester` pattern (switch, `ModelGate`, injected responder,
timeout, generation counter), the person's actions, and the Settings row.

**Tech Stack:** Swift 5 mode, AppKit and SwiftUI, macOS 14 (FoundationModels
behind `#available(macOS 26, *)`); `build.sh` self-checks.

**Spec:** `docs/specs/2026-11-17-activity-aware-sessions-design.md` sections 6
(precedence, the AI mark), 7 (the on-device model, AI-made labels, shadow
mode), 9 (tiers), 10 (constants), "Phasing" row C and "Left to the builder".
The spec is binding; where it leaves a point open, the ruling below decides it
with its reason. Phase B's plan (`2026-11-19-activity-aware-sessions-phase-b.md`)
is the contract for provenance, corrections and split.

Written 19 November 2026 by the Phase C controller session. The branch starts
from Phase B's branch (PR 93) and merges `origin/main` once PR 93 merges.

## Owner rules (fixed, not reopened)

AI labels are suggestions. An AI-made label keeps the AI mark and joins the
person's category list only when they keep it. Daybook never changes a category
or an Activity Rule the person made. Privacy first, on-device only. Nothing is
changed silently.

## Rulings

| # | Ruling | Reason |
|---|---|---|
| C1 | Scope is the Phasing row C only. Not here: the "Unsorted" fallback for non-focused automatic sessions at start (spec section 6), changing B8's split-tail rule to use Unsorted, Phase B's deferred Tasks 7 and 8. | Each changes recorded totals for every user; they need their own review. Listed as follow-ups. |
| C2 | Asked about: an ended record with `effectiveOrigin == .automatic`, `effectiveCategorySource == .builtIn`, a stored activity shape with a fingerprint, and at least 600 s of counted time. Never a record whose source is `user`, `rule`, `correction` or `ai`, and never one with a remembered correction for its fingerprint (precedence 3 beats 4; B5's suggestion shows instead). | Spec precedence (section 6) and "for sessions under 10 minutes" skip. Manual and rule sessions already carry the person's choice. |
| C3 | Trigger. The spec's "top category's share of credited seconds" is read as the top activity's share of `shape.credited`, since categories have no activity table (spec section 6). Ask when the top share is under `modelShare` 0.60, or its lead over the next is under `modelMargin` 0.15, or the top activity is not a focused purpose (the fallback gives no category). Otherwise not asked. | The snapshot credits seconds by purpose, not by category; this is the only reading computable from what is stored. |
| C4 | Gates, read when the record ends: the existing Apple Intelligence switch (`useAppleIntelligence`, one switch for every AI feature), `ModelGate.modelAvailable`, Low Power Mode off, `ProcessInfo.thermalState` below `.serious`. A record that ends while gated is not asked later: there is no catch-up queue. | Spec "Skipped in". A backlog would need its own scheduling and cost review. |
| C5 | Input, exactly: each activity with whole minutes from code, the depth word, the display names of up to two top apps, the site kind when the site signal is on, and a numbered list of at most 20 category names that can be started (catalogue order; Break, Unsorted, retired categories and unkept labels excluded). Never the session's name, note, window titles, addresses or bundle identifiers. A fresh `LanguageModelSession` per question, greedy sampling, 10 s timeout. | Spec section 7 "Input"; NameSuggester's pattern. 20 bounds the `.anyOf` list. |
| C6 | Output: `@Generable CategoryAnswer { choice: "1"..."20" \| "new" \| "none"; label: String }`. A number beyond the list is none. "new" passes `LabelAudit`: one to three words, at most 24 characters, letters in any script and single spaces only. A label equal to an existing category or unkept label ignoring case and a final "s" or "es" is a pick of that one. A label in the removed names is none. | Spec section 7 "Output" and "Names". |
| C7 | Cache: answers are kept in `ai-labels.json` keyed by fingerprint plus a digest of the offered category ids, so the same pattern is not asked twice until the person's category list changes. An answer unused for 90 days (whole seconds) is pruned on write. | Spec "Cached by fingerprint"; a cached "none" must not outlive the category the person just made. |
| C8 | Shadow mode. New setting `fc.aiAssignsCategories`, default off. Off: the answer shows only as a one-click suggestion in the report of that automatic session, and only when no remembered-correction suggestion shows (C2). On: a pick is written to the record (`workType`, source `.ai`) when the record is still `builtIn` with the category it ended with; a new label (C9) is written the same way. An AI write is not a correction and not an undo entry: the AI mark is the way to change it. | Spec section 7 "Shadow mode"; nothing changes silently while off, and the person opted in when on. |
| C9 | Labels in shadow mode are offered ("New category: Films", Keep) and created only when the person keeps one, so shadow mode never makes an unkept label. With assigning on, a label is created unkept and written to the record. Limits apply to unkept creation only: `newLabelsPerDay` 1 in a rolling 24 hours (seconds), `maxUnkeptLabels` 3 among unarchived unkept labels. At a limit nothing is written (C12). | Owner rule: AI labels are suggestions. Rolling seconds hold in every time zone. |
| C10 | Unkept labels live in `ai-labels.json`, never in the `workTypes` defaults, and `WorkTypeCatalog` merges them as hidden definitions (`isUnkeptAILabel`: not active, not startable, in no picker, not offered to the model, not in Settings). Ids are `"ai." + UUID`. Keep moves the definition into the person's customisations with the same id, so no record is rewritten. A build without Phase C reads an unkept label as "Other" and counts it as focus: accepted downgrade cost, as B32. | Spec "Where unkept labels are stored" is left to the builder; a separate file keeps them out of the person's list in every build. |
| C11 | `WorkTypeDefinition.countsTowardFocus: Bool` (decoded if present, default true; Break false). `WorkType.countsAsFocus` becomes "not Break and `countsTowardFocus`". Every one of the call sites of `countsAsFocus` is sorted into "counts toward focus" (totals, goals, streaks, dashboards, History focus figures) or "is not a break" (`startable`, `startableOrFallback`, continuation, activity choices, away corrections), the latter through a new `WorkType.isBreak`. `startable` excludes Break, retired, Unsorted and unkept labels. An unkept label's value is fixed when made: true exactly when its dominant activity is a focused purpose. | Spec "Left to the builder" and section 7 "Focus"; B8 moved this here. Without the split a non-focus kept category could never be started. |
| C12 | When the model answers none, or a limit is reached, nothing is written: the category the session ended with stands. "Unsorted" is written only by the person's Remove (C13). | Owner rule (nothing silently); the spec's Unsorted fallback is section 6, outside row C (C1). |
| C13 | The person's actions, in the session report (the row shows only the mark). On an AI pick: **Keep** (source `user`, mark goes) and **Change…** (the category picker; source `user`; a correction is recorded per B6 with the AI pick vetoed). On an unkept label: **Keep**; **Rename…** (kept under the typed name: a name the person typed is theirs); **Merge Into** a category (every record carrying the label takes it, source `user`, one undo entry; the label is deleted and its name joins the removed names); **Remove** (its records become Unsorted, source `user`, one undo entry; the name is never proposed again). Amended by Task 4: merged or removed labels are archived, not deleted, so records an Undo brings back still read the label's name; archived labels are never reused, offered or counted (C15). | Spec sections 6 and 7; one undo entry per action, as split and merge (B9). |
| C14 | Tally: one entry per record the model answered (shadow or assigning), the last 50 kept. The person's choice is recorded whenever they set that record's category by any path (Keep, Change, Use, the card's picker, Merge, Remove). Matched when the chosen id equals the answer's id. Settings: "AI matched 17 of your last 20 choices" over the last 20 entries with a choice; "No choices to compare yet" at none. | Spec: count only sessions where the person made a choice, in plain words. |
| C15 | An unkept label unused for `labelArchiveAfter` 30 days (seconds) is archived: it is not reused, does not count toward the limit, and records carrying it keep showing it. History is never rewritten. | Spec section 7 "Limits". |
| C16 | A new label's symbol and colour come from its dominant activity through a small Core table (coding, writing and AI, design, communication, research, media, utility); both can be changed after Keep in the category editor. | Spec "colour and symbol come from the dominant activity and can be changed". |
| C17 | The AI mark: one `AIMark` component in `Design/Components`, SF Symbol `sparkle`, `StoryStyle.supportingInk`, caption size, accessibility label "assigned by AI", help "Assigned by on-device AI. Open the session to keep or change it." (amended: the build forbids the trademark in source copy, so the help text names on-device AI; see `docs/reviews/2026-11-19-ai-mark.md`). Shown beside the category on the row and in the report when the source is `.ai`. Design review by the controller from `--snapshot` images. | Spec section 6 "The AI mark"; spec "design review before it ships". |
| C18 | `ActivityConstants` gains `modelShare` 0.60, `modelMargin` 0.15, `modelMinCounted` 600, `newLabelsPerDay` 1, `maxUnkeptLabels` 3, `labelArchiveAfter` 30 days, `answerExpiry` 90 days. `algorithmVersion` is unchanged: no derivation rule changes. | Spec section 10; Phase D's version 2 stands. |
| C19 | `ai-labels.json` is included in backups (it holds the person's labels and choices, like `corrections.json`). `fc.aiAssignsCategories` is not: assigning is switched on per Mac by the person after seeing the tally. | Spec "never switched on for them". |
| C20 | Settings: in the Apple Intelligence group, a switch "Let AI assign categories to automatic sessions" (disabled with the reason while Apple Intelligence is off or unavailable) and the tally line under it. The category editor gains "Counts toward focus goals" (not shown for Break). | Spec section 7 and "Once kept, the category has an ordinary setting". |
| C21 | Privacy copy (README, Settings help): what the model sees (C5 list), what it never sees, that it runs on the Mac through Apple Intelligence with a fresh session per question, that while the switch is off Daybook still asks in the background when Apple Intelligence is on and shows the answer only as a suggestion, and what `ai-labels.json` keeps (labels, fingerprints, answers, the last 50 comparisons; no session names, notes, titles or addresses). No claim the code does not back. | Native-app safety gate; owner rule privacy first. |
| C22 | Checks never reach the live model: `CategoryAssistant.responder` stands in for the model, and `ModelGate` is consulted only when no responder is set. The switch, Low Power and thermal gates are read through injectable closures so checks drive them. | Brief: no check may reach the live model; NameSuggester precedent. |
| C23 | The prompt (instructions) is fixed in this plan (Task 3) and changed only with a ruling. | Brief: prompt design is opus-level work. |
| C24 | Plan review (19 Nov, outside models; DeepSeek and Nemotron Super approve with changes, Nemotron Ultra reject, Codex received no file). When an answer arrives, everything is checked again before anything is cached as on offer or written: the Apple Intelligence switch, the assigning switch, the record still exists, its source is still `builtIn`, its category is the one it ended with, and no correction now matches. Any change drops the write. | Adopted: the end-time gate alone lets a late answer overwrite a choice made meanwhile (Review Focus 2, 3). |
| C25 | A proposed label gets its id (`"ai." + UUID`) when the answer is cached, and that id is the one in the cache, the tally and the category made by Keep, so a kept suggestion counts as a match. | Adopted: without a stable id the tally cannot compare a kept label. |
| C26 | A category the person sets not to count toward focus is counted as focus by a build without Phase C, which ignores the key: accepted downgrade cost, like C10 and B32, stated in the pull request. | Adopted as a stated cost; no build can make an older build read a key it does not know. |
| C28 | Amends C18: the model's constants live in a new `AILabelConstants`, not `ActivityConstants`. `AIAnswer` has four cases: `pick(id)` (a category), `label(id)` (an existing unkept label), `proposed(id, name)` (a new label with its C25 id), `none`. The question builder in Core takes a plain facts value (activity names and minutes, depth word, app names, site kind, categories) that the App fills, since activity wording lives above Core. | `ActivityConstants.signature` is pinned to `algorithmVersion`; these are not derivation rules and must not force a version bump. |
| C29 | From building Task 2: the lead rule cannot bite through a shape (a top share of 0.60 or more always leads by 0.20 or more), so it is checked on numbers; a `none` answer is not tallied (it names nothing to match), amending C14; `tallyText` says "AI matched your last choice" for one; `addUnkeptLabel` refuses at a limit itself. The daily limit counts label creations kept in their own list (`madeAt`), so a label kept, merged or removed the same day still counts. A proposed label whose name matches any category that was not offered (Break, Unsorted, retired, beyond 20) is none. `forget(labelID:)` purges a removed or merged label's cached answers. A label keeps at most 50 fingerprints. A cache hit is recorded again through `recordAnswer` (Task 3), so a pattern in daily use does not lapse. | Task 2 review: without `madeAt`, Remove then reinvent makes a label a day without limit; without the extra names, "Break" could be invented as a label. |
| C30 | From building and reviewing Task 3: a pick equal to the record's current category is tallied but neither written nor offered, amending C8, so no AI mark appears on an unchanged category. AI writes stay out of the correction journal (a journalled AI write would count as the person's own choice), so the assistant never asks about a record that an undoable action still holds by exact value (a live split link, a correction or an away answer's receipt), and never writes while a correction is pending. Only records that end after the first sweep since launch are asked about (C4 holds for a pre-launch record re-minted by a split, merge or undo). An app whose stored name is its bundle id is left out of the facts. A pick or label is written only after the answer and label are saved. Unkept AI labels live in `WorkTypeCatalog` (`install(aiLabels:)`) so every later `apply` keeps them. | Task 3 review: an AI write on an auto-split head refused that split's Undo and Merge Back (probe); a usage fallback name sent a bundle id to the model. |
| C31 | From reviewing Task 4: Keep on an AI-made label leaves its records' category source as `ai` (C10: no record is rewritten), so the AI mark stays until the person keeps each pick. Spec section 7's "the mark goes" is superseded for labels; Task 5 copy must match. | Task 4 review. |
| C32 | From reviewing Task 5: an archived AI-made label whose name is not in the removed names (archived for age, C15, not merged or removed by the person) can still be kept or renamed from its sessions; the AI never reuses or offers it. One merged or removed by the person offers only Merge Into and Remove. | Task 5 review, finding S1. |
| C33 | A daily goal whose category is set not to count toward focus is judged as paused, not missed, so a perfect day and streaks are not broken; the goal stays stored and is judged again once the category counts. Closing reads the catalogue as it is when the day is closed, so a day still waiting to be closed when the setting changes is judged by the new setting. This touches goal judging despite the Global Constraint; the owner approved it. The edge for a day still waiting to be closed is kept as the least surprising choice: turning a category off makes those days' goals paused, never missed, and turning it on judges them with credit computed under the same current setting, so the result stays consistent; removing the edge would mean storing each category's setting history, which is not cheap. | Commit 4b26df1, goals on a category that does not count. |
| C27 | Task 1 writes the Review Focus 1 totals check first and runs it green on the untouched code before any call site changes. The question builder takes a value type holding only C5's fields, and the privacy check feeds a fixture whose session has a distinctive name, note, bundle id and remembered site address, asserting none reaches the text. | Adopted. Rejected: "the split breaks historical totals" (every existing category reads true, so totals are unchanged; the check proves it). |

## Global Constraints

- HOLD: no build of any kind until the controller receives "release published".
  Then one build at a time machine-wide: `pgrep -f "build.sh"` empty before every build.
- `./build.sh --check` passes before each commit, sandbox disabled. Final gate also `TZ=Europe/Berlin` and `TZ=Pacific/Kiritimati`.
- Never `--install`, `--test` or `--run`; never launch a built Daybook except with `--snapshot`; never touch live data.
- Core is UI-free and compiles alone. Views never recalculate time. No new timer (the assistant's timeout is a sleeping task per question, as NameSuggester).
- Files at most 300 lines; files already over take no net growth: new code goes in new files.
- New stored `SessionStore` or `SessionEngine` members join `keep_internals` in `build.sh`.
- Checks: `TestClock`, `SelfTest.scratchDirectory()`, `MemoryDefaults`, offsets from `SelfTest.base`; new suites at the end of `registeredTests`; each fix with a check that fails on the old behaviour.
- Lengths in App, Design and Surfaces are tokens or `.zoomed`.
- Persistence, settings, session state or time arithmetic: `fix-reviewer` (opus) before the task is complete.
- Commit subjects: one plain present-tense sentence for any user. Squash `Sources/` commits into one or two before the PR.
- Do not touch goals files, the Yesterday card or awards.

## Review Focus

1. Totals: with no AI label and no category set to non-focus, every daily total, goal, streak and History focus figure is identical before and after Task 1 (a check over a fixture archive).
2. A record the person touched is never written by the assistant: rename, recategorise or claim between end and answer, then the answer arrives; nothing is written.
3. The answer arrives after the switch is turned off, or for a record that was split, merged or removed meanwhile: dropped.
4. Merge Into and Remove across many records undo as one step and restore every record's category and source.
5. `ai-labels.json` written by this build and a `workTypes` list with an unkept label never meet: the person's customisations never contain an `ai.` id unless kept.

## Interfaces

```swift
// Core/WorkTypeCatalog.swift (+ a new file for the merge if it would grow past 300)
struct WorkTypeDefinition { var countsTowardFocus: Bool; var isUnkeptAILabel: Bool /* not encoded into workTypes */ }
extension WorkType { static let unsorted: WorkType; var isBreak: Bool }
// Core/AILabelBook.swift
struct AILabel: Codable, Equatable, Identifiable { let id: String; var name: String; var symbolName: String; var hue: WorkTypeHue
    var countsTowardFocus: Bool; var fingerprints: [ActivityFingerprint]; let created: Date; var lastUsed: Date; var archived: Bool }
enum AIAnswer: Codable, Equatable { case pick(String), label(String), none }   // ids
struct AILabelBook: Codable, Equatable {
    var labels: [AILabel]; var answers: [CachedAnswer]; var removedNames: [String]; var tally: [TallyEntry]
    func cachedAnswer(for: ActivityFingerprint, offered: [String], now: Date) -> AIAnswer?
    func reusableLabel(for: ActivityFingerprint, now: Date) -> AILabel?      // code reuse, no model call
    func canMakeLabel(now: Date) -> Bool                                      // C9 limits
    mutating func recordAnswer(_: AIAnswer, recordID: UUID, fingerprint: ActivityFingerprint, offered: [String], now: Date)
    mutating func recordChoice(recordID: UUID, chosen: String)
    func tallyText() -> String
}
// Core/AITrigger.swift
enum AITrigger { static func shouldAsk(record: SessionRecord, shape: SessionActivityShape, hasCorrection: Bool) -> Bool }
// Core/LabelAudit.swift
enum LabelAudit { static func clean(_ proposal: String) -> String?; static func matches(_ a: String, _ b: String) -> Bool }
// Core/CategoryQuestion.swift
struct CategoryQuestion: Equatable { let text: String; let offered: [WorkType]; let fingerprint: ActivityFingerprint }
// App/CategoryAssistant.swift
@MainActor final class CategoryAssistant: ObservableObject {
    var responder: (@MainActor (CategoryQuestion) async throws -> CategoryAnswerChoice)?
    var timeout: Duration
    func sessionEnded(_ recordID: UUID)
}
```

---

### Task 0: Apple Intelligence on this Mac (controller, after "release published")

- [ ] In `mktemp -d`, a `main.swift` that prints `SystemLanguageModel.default.availability` and, when available, one greedy `respond` to a fixed neutral prompt ("Answer with the word ready.") with its latency. No personal data, no Daybook launch.
- [ ] Record macOS version, availability and the result in `docs/debug/2026-11-19-apple-intelligence-probe.md`. If unavailable, Tasks 1 to 6 still build (checks use the responder) and the report says the live path is unverified.

### Task 1: Counts toward focus, isBreak, Unsorted (Core)

**Files:** `Sources/Core/WorkTypeCatalog.swift` (field, decode, merge of hidden definitions), `Sources/Core/SessionState.swift` (`countsAsFocus`, `isBreak`, `startable`, `unsorted`), every caller of `countsAsFocus` sorted per C11; checks in `Sources/Verification/FocusPropertyChecks.swift`.

- [ ] Checks: an old `workTypes` list without the key reads true for all and false for Break; a category set to false is startable and absent from daily totals, goals, streaks, dashboard and History focus figures; Unsorted is not startable, not focus, not in active types; Review Focus 1 over a fixture archive; a definition flagged unkept is never written into `workTypes`.
- [ ] Red first, then implement. fix-reviewer (persistence, totals). Commit: "Categories can be set not to count toward focus goals".

### Task 2: The label book, the trigger, the question and the audit (Core)

**Files:** create `Sources/Core/AILabelBook.swift`, `AILabelBook+Tally.swift`, `AITrigger.swift`, `LabelAudit.swift`, `CategoryQuestion.swift`, `LabelLook.swift` (C16); constants per C18; checks `Sources/Verification/AILabelBookChecks.swift`, `AITriggerChecks.swift`.

- [ ] Checks: trigger at top share 0.59 asks and 0.60 does not; lead 0.14 asks, 0.15 does not; a non-focused top asks; under 600 s counted, a `user`, `rule`, `correction` or `ai` source, a manual origin, or a correction present: not asked. Audit: "Films" ok; four words, 25 characters, digits, punctuation, a newline: rejected; "film" matches "Films", "Classes" matches "Class". Cache hit by fingerprint and offered digest; a changed offered list misses; 90 days plus 1 s pruned. Limits: second label within 24 h refused, after 24 h allowed; fourth unkept refused; archived after 30 days plus 1 s, not reused, not counted. Tally text at 0, 1 and 25 entries (last 20). Question text contains no name, note or bundle id (fixture with a distinctive name and note, asserted absent) and minutes equal the shape's credited seconds rounded.
- [ ] Commit: "Daybook can remember labels and how well its suggestions matched your choices".

### Task 3: `ai-labels.json` and the assistant (App)

**Files:** create `Sources/App/AILabelStore.swift` (load, atomic save, `UnreadableFile.setAside`, `DataBackup`), `Sources/App/CategoryAssistant.swift` (+ `CategoryAssistant+Model.swift` for `@Generable` and the prompt), `Sources/App/SessionStore+CategoryAssistant.swift` (called after the end-of-session path and Phase B's automatic split, for each resulting record; writes under C8), the setting in `PersistenceStore` and `SettingsModel` (new file if needed); checks `Sources/Verification/CategoryAssistantChecks.swift` with a fake responder.

Prompt (C23):

> You file one finished stretch of time for the person who spent it. You get
> what the time was spent on, measured by the app, and a numbered list of the
> person's categories. Answer with the number of the category that fits. Answer
> new, with a label of one to three words, only when no category fits and the
> activities say clearly what the time was. Answer none when the time was mixed
> or unclear. Never put times, numbers or app names in a label.

- [ ] Checks: switch off, Low Power, thermal serious, a responder present with the Apple Intelligence switch off: no question. Shadow: answer cached, record untouched, suggestion published. Assigning: pick written with source `.ai`; Review Focus 2 and 3; a new label created unkept and written, a second within 24 h not; a matching fingerprint later reuses the label with no responder call (call count asserted); timeout leaves the record untouched and does not cache; an unreadable file is set aside; the file round-trips.
- [ ] fix-reviewer (persistence, session state, settings). Commit: "Apple Intelligence can suggest a category for an unclear automatic session".

### Task 4: The person's actions and the tally (App)

**Files:** create `Sources/App/SessionStore+AILabels.swift` (Keep, Change, Rename, Merge Into, Remove, Use; each through the existing correction snapshot, one undo entry), a hook in the person's category-change path that records the tally choice (no net growth in over-limit files).

- [ ] Checks: Keep on a pick sets `user` and records a match; Change records a correction with the AI pick vetoed; Keep on a label moves it into customisations with the same id and the record is unchanged; Rename keeps it under the new name; Merge Into and Remove over three records undo as one step (Review Focus 4); a removed or merged name is never proposed again; Review Focus 5.
- [ ] fix-reviewer (persistence, session state). Commit: "AI-made labels can be kept, renamed, merged or removed".

### Task 5: The AI mark, the suggestion and the Settings row (Surfaces)

**Files:** create `Sources/Design/Components/AIMark.swift`, `Sources/Surfaces/Story/AISuggestionRow.swift`, `Sources/Surfaces/Story/AILabelActions.swift`, `Sources/Surfaces/Settings/SettingsGroups+AICategories.swift`; the row's mark through `SessionEntryCard+Activity.swift` and `SessionCardSignature`; the category editor toggle.

- [ ] Load `bama:ux-design`, `bama:mac-design`, `bama:swift-swiftui`. Checks: the mark's accessibility label is "assigned by AI"; the signature changes with the source; the suggestion is hidden when a correction suggestion shows; the Settings switch is disabled while Apple Intelligence is off.
- [ ] `--snapshot` row, report (pick, label, suggestion) and Settings, light and dark; controller design review in `docs/reviews/2026-11-19-ai-mark.md`. Commit: "Categories assigned by AI carry a small sparkle you can keep or change".

### Task 6: Documentation and the whole branch

- [ ] README and Settings help per C21.
- [ ] Whole-branch review (opus, read-only) against spec, owner rules and rulings; fix round.
- [ ] `./build.sh --check` in local, `TZ=Europe/Berlin`, `TZ=Pacific/Kiritimati`.
- [ ] Squash `Sources/` commits, push, open the pull request (ready), Codex review, merge per the brief.

## Follow-ups (not in this phase)

- C1 items: Unsorted for non-focused automatic sessions; B8 split tail as Unsorted; Phase B Tasks 7 and 8.
- A catch-up question for records that ended while gated (C4).
