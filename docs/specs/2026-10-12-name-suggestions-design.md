# Name suggestions for unnamed sessions

Date: 2026-10-12
Status: built; hand checks pending (2026-10-12)

## Why

A session that ends without a name shows only its category ("Deep work").
History, its search box and Ask then cannot find it by what the work was:
"Thesis" misses every unnamed thesis session. Naming after the fact is one
field on the session's card today, and nothing suggests what to type.

This is project 3 of the on-device AI roadmap
(`docs/specs/2026-10-10-apple-intelligence-notes-design.md`, "Projects, in
order"). It writes one session, and only when the person accepts.

## Decisions

| Question | Decision |
|---|---|
| Source of a name | One of the person's own earlier names when one fits; otherwise a fresh short name. Earlier names keep History's groups and search consistent. |
| Rejected: earlier names only | Never covers new work. |
| Rejected: fresh names only | Names drift from the person's own words ("Coding in Xcode" against their "Daybook"). |
| Approach | Code ranks earlier names by shared app time and category, and offers the top 3. With one clear leader, the on-device model is asked to confirm it, and code offers that earlier name. With two close earlier names, nothing is asked and nothing is offered. With none, the model is asked for a fresh name or to decline. Code checks any fresh name before it is shown. In the live probes the model never declined or chose a different earlier name (§5a), so an earlier-name offer comes from the ranking and says so. |
| Rejected: code alone for earlier names | Cannot read the note, and it would put a non-AI suggestion on every Mac. |
| Rejected: the model reads every name | Hard to check, likely to pick a plausible wrong name, and against the shared rule that code offers the candidates. |
| Which sessions | Ended focus sessions from today and yesterday whose name is empty, focused for at least 10 minutes, and not kept as they are. A session is one thread's stretches, as History shows one card; its day is the day it started, in `periodCalendar`. A session that crosses midnight is offered once, on the day it started, and its focused time for the 10-minute test is its total across both days. A session that began before yesterday is not offered. |
| Rejected: any day you open | Older guesses are harder to judge; tidying older history is project 4. |
| Cadence | One suggestion at a time, newest first: today's sessions, then yesterday's. |
| Rejected: a batch with "Name all" | One wrong guess rides along with the right ones. |
| Form | A Story rail notice in the `NameCategoryNotice` pattern: one action ("Name it"), "Keep as is", and Undo through the Story's existing saved-action row. |
| Wording | "On-device AI", never "Apple Intelligence", and the `sparkles` mark. Sir decided this app-wide on 2026-10-12; a separate PR renames the shipped wording. `apple.intelligence` is reserved for naming Apple Intelligence itself. Only a fresh name, worded by the model, is called on-device AI and carries the mark; an earlier name reads "From your earlier names" with no mark. |
| Shared rules | On-device only (`SystemLanguageModel.default`); `ModelGate.modelAvailable` and the "Use on-device AI" switch; nothing drawn on Macs that cannot run it; never on the 1 Hz ticker; no history change until the person accepts. |

## 1. Parts

| Layer | File | Responsibility |
|---|---|---|
| Core | `Sources/Core/NameCandidates.swift` (new) | Pure. From one session's app minutes and category, and every named session in the last 60 days grouped by name, returns earlier names ranked by shared app time (§2). |
| Core | `Sources/Core/NameAudit.swift` (new) | Pure. Accepts or rejects a fresh name (§2). |
| App | `Sources/App/SessionStore+NameSuggestion.swift` (new) | Which sessions to offer, in order (§3); their facts; "Name it" through `renameSession`; "Keep as is". |
| App | `Sources/App/NameSuggester.swift` (new) | `@MainActor` and `ObservableObject`, in the `NoteWriter` shape: one greedy `LanguageModelSession` call per session, a 10 s timeout, cancellation, a `responder` seam for checks, and an in-memory cache keyed by the session's thread ID, end time, category and note. A session with no earlier name is asked a second question whose only answers are `new` and `none`. |
| App | `Sources/App/MainWindowModel.swift` | `nameSuggester`, built on first read like `notes`. |
| Surfaces | `Sources/Surfaces/Story/NameSuggestionNotice.swift` (new) | The notice in today's rail tile, under `NameCategoryNotice` when both show. Its caption and mark follow the offer's source (§3). |

Rules kept: Core stays UI-free and free of `FoundationModels`; views read
published values and compute nothing; files under 300 lines; lengths are
tokens or `.zoomed`; supporting text uses `StoryStyle.supportingInk`;
`Sources/App/ModelGate.swift` stays byte-identical.

## 2. Choosing a name

**Earlier names (code).**
- A session's app mix is each app's share of its focused time, counting only apps in front for at least `HistoryAppLens.minimumUse` within the session.
- An earlier name's mix is the same, built from all its sessions in the last 60 days, using `periodCalendar` and half-open spans.
- Shared time is the sum over apps of the smaller of the two shares, so it runs from 0 to 1.
- An earlier name scores its shared time, plus 0.1 when its most common category is the session's category.
- The top 3 with a shared time of at least 0.3 are offered. A tie goes to the more recently used name.
- The best name must lead the second by at least 0.1 (`NameCandidates.margin`, ruling S13). With a smaller lead, including a tie, the session is ambiguous: the model is not asked and nothing is offered. One candidate always leads.
- Earlier names are names the person typed and activity-rule names. Generic auto names (`AutoSessionDetector.sessionName`) and names that spell a category (`SessionNaming`) are left out.

**Facts given to the model** (an example):

```text
Session: Mon 13 Oct, 9:10–10:30 am, 1h 20m focused, category Deep work.
Apps: Xcode 52m, Safari 18m, Terminal 6m.
Note: “fixed parser for fortnight”
Earlier names that fit:
1. Daybook (usually Xcode, Terminal; Deep work)
2. Thesis (usually Pages, Safari; Writing)
```

The note is sent as one line, its line breaks collapsed and cut at 200
characters, so a pasted page cannot pass for another line of the facts.

A session with no app evidence and no note is not sent to the model and
gets no suggestion.

**The model's answer.** A `@Generable` choice of `1`, `2`, `3`, `new` or `none`, plus a name that is used only with `new`. The `choice` is constrained to exactly those five values at generation (`@Guide` with `.anyOf`), so it cannot come back as an earlier name's text or free words (§5a, first run). The call is greedy and runs once. A session with no candidate gets a second question instead, with the same instructions: its `choice` is constrained to `new` or `none`, plus a name. The first run showed free text in `choice`; the second showed that the five-value constraint made the model answer `1` every time and removed fresh names; the third restored them (§5a).

**What code accepts.**

| Answer | Result |
|---|---|
| `1`–`3` | That candidate's exact text; the model cannot alter it. |
| `new` | Only if `NameAudit` passes: 1–4 words, at most 30 characters, no digits, no quotes, not a category name, not just an app's name. A fresh name equal to any earlier name, ignoring case, takes the earlier spelling. An apostrophe inside a word counts as a quote, so a fresh name such as "Sir's thesis" is not offered yet; an earlier name with one still can be. |
| `none`, a failed audit, an error or the timeout | No suggestion for this session; the next session is tried. |

## 3. The notice

**Shape.**

```text
Name this morning's 1h 20m session “Daybook”?
From your earlier names
[Name it]   [Keep as is]

✦ Name this morning's 1h 20m session “Parser work”?
  Suggested by on-device AI
  [Name it]   [Keep as is]
```

The first is an earlier name, picked by the ranking: its caption reads "From your earlier names" and it has no mark. The second is a fresh name worded by the model: it keeps "Suggested by on-device AI" and the sparkles mark.

- The opening follows the session: "this morning's", "this afternoon's", "this evening's", "yesterday evening's", using `SessionStore.timeOfDay` and the focused time from `DurationText`.
- A session that started before 05:00 today reads "last night's", as one that started the evening before does; both can show at once, and both are true.
- VoiceOver reads the caption, whichever it is. The sparkles mark, shown only with a fresh name, is decorative and hidden from it.

**Behaviour.**

| Case | Behaviour |
|---|---|
| Name it | `renameSession`, an ordinary correction. The Story's saved-action row shows "Named … · Undo". The notice moves on to the next session. |
| Undo | The session's name is empty again. It is offered again only after a relaunch or a change to its facts. |
| Keep as is | The thread is remembered in `fc.nameSuggestionKept`, trimmed to threads that ended in the last two days, and the next session is shown. |
| Named on its card | The session drops out. |
| Name it or Keep as is on a stale notice | Each acts only if the session is still unnamed and not kept. Otherwise nothing is written, and the notice moves on. |
| Switch off, or model unusable | Nothing is drawn, and a call in flight is cancelled. |
| Model runs | When a session stops unnamed, and when today's Story opens with a qualifying session that has no cached result. Only one call at a time, and never on the 1 Hz ticker. After a relaunch it runs again once, when the Story opens. The notice asks again on a change to the session archive, the notes, the corrections (a rename on a card), the kept list or the day, and never on the minute-by-minute app-use checkpoint. |
| Ambiguous, no evidence, or no answer | That session shows no notice; the next one is tried. A session with no candidates but a note or app evidence is asked for a fresh name. |

## 4. Privacy

The facts (times, app names, the note, earlier names) go only to
`SystemLanguageModel.default` on the Mac, and only for a session about to be
offered. Nothing is stored except the threads kept as they are.

## 5. Checks

| Check | Fails when |
|---|---|
| Ranking | The order, the 0.3 threshold, the category bonus or the recency tie-break is wrong; generic auto names or category-spelled names count; the 60-day edge moves across time zones. |
| Audit | A digit, a quote, a bare category, a bare app name, more than 4 words or more than 30 characters passes. |
| Which sessions | A break, the running session, a session under 10 minutes, a named session or a kept one is offered; the order is not newest first; a session just after midnight lands on the wrong day. |
| Model answer | `1`–`3` alters the candidate's text; a fresh name matching an earlier one keeps the model's spelling; `none` or a timeout shows something; the model is asked with the switch off or with no evidence; a redraw calls it again; an ambiguous session is asked or offered; an earlier-name offer carries the AI caption, or a fresh one does not. |
| Actions | Name it does not rename, Undo does not restore, Keep as is is not remembered or not trimmed, or a session named on its card still shows. |
| Views | `--snapshot` of the notice breaks at 80% or 140% zoom, light or dark. |

**Live probe.** 20 hand-built sessions, each with the expected answer written
down first: clear repeats of an earlier name, new work with a telling note,
mixed apps, and no evidence. The target is at least 16 right-or-none, with 0
names that slipped past the audit. Smoke-test the model first with a 60 s
timeout. A miss is fixed in code (the ranking or the facts), never by
editing the prompt.

## 5a. Live probe

Run on 2026-10-12 on macOS 27.2 (build 26B5101f), with
`SystemLanguageModel.default` available. The smoke test (`Say OK`, 60 s
timeout) answered in 4.2 s. The probe ran `NameSuggester` with no responder
and a 60 s timeout, over one fixture: five earlier names (Daybook, Thesis,
Email triage, Release notes, Admin) of four sessions each, with distinct app
mixes, and 20 unnamed sessions. The expected answers were written before the
run. Each question took 0.9–2.2 s; none timed out or threw.

"Right" is the expected answer, or a stated alternative. "None" is nothing
offered where a name was expected: honest, and counted toward the target.
"Wrong" is a name that does not fit.

| # | Case | Apps and note | Expected | Model's `choice` / `name` | Offered | Verdict |
|---|---|---|---|---|---|---|
| 1 | repeat | Xcode 40m, Terminal 15m | Daybook | `1` | Daybook | right |
| 2 | repeat | Pages 35m, Safari 10m, Zotero 8m | Thesis | `Thesis` | nothing | none |
| 3 | repeat | Mail 25m, Calendar 5m | Email triage | `1` | Email triage | right |
| 4 | repeat | Notion 30m, Safari 15m, Terminal 5m | Release notes | `1` | Release notes | right |
| 5 | repeat | Numbers 20m, Preview 15m, Mail 10m | Admin | `deep work` / `budget review` | nothing | none (no candidate; see below) |
| 6 | repeat | Xcode 50m, Safari 10m | Daybook | `Daybook` | nothing | none |
| 7 | note | Safari 30m, Terminal 20m; "wrote the changelog and release summary for the new version" | Release notes | `1` | Release notes | right |
| 8 | note | Safari 25m, Terminal 20m, Xcode 5m; "fixed the crash in the session engine tests" | Daybook | `Release notes` / `Crash fix in session engine` | nothing | none |
| 9 | note | Safari 20m, Pages 10m, Terminal 10m; "drafted the methods chapter for my dissertation" | Thesis | `Thesis` | nothing | none |
| 10 | note | Mail 20m, Numbers 15m; "filed receipts and updated the household budget sheet" | Admin | `Email triage` | nothing | none (no candidate; see below) |
| 11 | fresh | Figma 40m, Safari 5m; "designed the onboarding screens for the landing page" | a landing-page or onboarding name | `design onboarding screens` / `landing page UX` | nothing | none |
| 12 | fresh | Logic Pro 50m; "mixed the podcast episode and cut the intro" | a podcast name | `mix intro podcast` / `Podcast Intro Edit` | nothing | none |
| 13 | fresh | Zoom 30m, Slack 10m; "interviewed candidates for the design role" | an interviews or hiring name | `interviewed candidates for the design role` / `design role interviews` | nothing | none |
| 14 | fresh | Blender 45m; "modelled the chair for the furniture scene" | a 3D or chair name | `modelled the chair` / `furniture scene` | nothing | none |
| 15 | mixed | Xcode 15m, Pages 15m, Mail 15m | none | `Daybook` | nothing | right |
| 16 | mixed | Safari 20m, Terminal 15m, Slack 10m | none, or Release notes | `Release notes` | nothing | right |
| 17 | mixed | Notion 15m, Numbers 15m, Preview 10m | none, or Admin | `1` | Release notes | wrong |
| 18–20 | no evidence | no apps, no note | never asked | not asked | nothing | right |

**Counts.** 9 right, 10 none, 1 wrong. Right-or-none is 19 of 20 against a
target of 16, and 0 offered names failed `NameAudit`: the target is met.

**The wrong row.** #17: the model answered `1` and Release notes was offered
for a session that was a third Notion and two thirds Numbers and Preview. The
candidate scored 0.375 shared time plus the category bonus, over the 0.3
threshold. Its one strong app is the session's biggest, but the rest of the
mix does not fit, and the facts cannot say so.

**What the target hides.**
- Admin is a category's name, so it is never an earlier name (§2). The fixture
  made it one anyway, and #5 and #10 had no candidate to reach. That is a
  fault in the fixture, not in the code; the rows are scored as none.
- The model did not follow the form of the answer. In 12 of the 17 questions
  its `choice` was an earlier name's text or the work in its own words, not
  `1`, `2`, `3`, `new` or `none`. `NameSuggester.choice` reads all of those as
  none. Three of those were the right earlier name (#2, #6, #9). So 10 of the
  14 rows that expected a name gave none, and no fresh name was ever offered
  (#11–#14 held sensible names in the `name` field).
- Reading such a `choice` as the earlier name it spells is not a safe fix on
  its own. It would also have offered Release notes for #8, Email triage for
  #10 and Daybook for #15, all wrong. The strict reading is what kept those
  three off the screen. A fix belongs in the answer's shape: a closed set for
  `choice` (an enum), not a tolerant reading of free text. It changes the
  schema the model sees, so it is a decision for a later pass, not made here.

### Second run (after constraining the answer)

Run on 2026-10-12, same machine and model, after `choice` was constrained to
`1`, `2`, `3`, `new` and `none` (ruling S12). The fixture changed in one
way: the earlier name "Admin", which spells a category and so is never a
candidate, became "Invoices" with the same app mix. The expectations for the
rows it touches were written before the run: #5 Invoices; #10 Invoices, with
none acceptable and Email triage wrong; #17 none, with Invoices acceptable.
Smoke test 3.7 s. Each question took 0.9–1.2 s except one at 4.1 s; none
timed out or threw.

| # | Case | Expected | Model's `choice` / `name` | Offered | Verdict |
|---|---|---|---|---|---|
| 1 | repeat | Daybook | `1` / Daybook | Daybook | right |
| 2 | repeat | Thesis | `1` / Thesis | Thesis | right |
| 3 | repeat | Email triage | `1` / Email triage | Email triage | right |
| 4 | repeat | Release notes | `1` / Release notes | Release notes | right |
| 5 | repeat | Invoices | `1` / Invoices | Invoices | right |
| 6 | repeat | Daybook | `1` / Daybook | Daybook | right |
| 7 | note | Release notes | `1` / Release notes | Release notes | right |
| 8 | note | Daybook | `1` / Release notes | Release notes | wrong |
| 9 | note | Thesis | `1` / Dissertation methods | Thesis | right |
| 10 | note | Invoices, or none | `1` / Invoices | Invoices | right |
| 11 | fresh | a landing-page or onboarding name | `1` / designed onboarding screens | nothing | none |
| 12 | fresh | a podcast name | `1` / Mixed intro | nothing | none |
| 13 | fresh | an interviews or hiring name | `1` / design candidate interview | nothing | none |
| 14 | fresh | a 3D or chair name | `1` / modeled chair for furniture | nothing | none |
| 15 | mixed | none | `1` / Daybook | Daybook | wrong |
| 16 | mixed | none, or Release notes | `1` / Release notes | Release notes | right |
| 17 | mixed | none, or Invoices | `1` / Invoices | Invoices | right |
| 18–20 | no evidence | never asked | not asked | nothing | right |

(The `name` shown is what the model wrote beside `choice`; it is read only
with `new`.)

**Counts.** 14 right, 4 none, 2 wrong. Right-or-none is 18 of 20 against a
target of 16, and 0 offered names failed `NameAudit`: the target is met.

**What changed.** `choice` was a valid value in 17 of 17 questions, against 5
of 17 before, and 10 of the 14 rows that expected a name now get one (4
before). The cost is that the model answered `1` every time. It never
declined and never said `new`, in either run: the free text in the first run
was already candidate 1 on every row that had a candidate. The constraint
also cost the fresh-name path, which the first run had in mind for #5 and
#11–#14. So:
- The four fresh rows (#11–#14) get nothing. With no candidate, `1` resolves
  to no name, which is safe, but a fresh name is still never offered.
- Whether a name is offered now rests on the ranking alone. Where a candidate
  existed, the model took it. That is right when the apps fit (#1–#7, #9,
  #10) and wrong when they do not: #8 (the note says session engine tests;
  Release notes ranked above Daybook) and #15 (an even three-way split
  offered Daybook).
- #16 and #17 passed on the stated alternatives, not because the model
  declined.

The two wrong rows led to the third run: a margin rule for close earlier
names, and a second question for sessions with none.

### Third run (after the second question and the margin rule)

Run on 2026-10-12, same machine, model and fixture as the second run
(including "Invoices"), after two changes (fix round 2, ruling S13):
- When the best earlier name leads the second by less than 0.1, the session
  is not asked about and nothing is offered.
- A session with no candidates is asked a second question whose `choice` is
  `new` or `none`.

The expectations were written before the run, from hand-computed scores.
Four rows were expected to be ambiguous and so not asked: #8, #9, #10 and #15.
The earlier runs expected Daybook, Thesis and Invoices for the first three;
they are now none by rule, not by the model's choice. Smoke test 3.3 s; each
question took 0.8–1.0 s.

| # | Case | Candidates (score) | Expected | Model's `choice` / `name` | Offered | Verdict |
|---|---|---|---|---|---|---|
| 1 | repeat | Daybook 1.02 | Daybook | `1` / Daybook | Daybook | right |
| 2 | repeat | Thesis 1.03 | Thesis | `1` / Thesis | Thesis | right |
| 3 | repeat | Email triage 0.97 | Email triage | `1` / Email triage | Email triage | right |
| 4 | repeat | Release notes 0.98 | Release notes | `1` / Release notes | Release notes | right |
| 5 | repeat | Invoices 0.96 | Invoices | `1` / Invoices | Invoices | right |
| 6 | repeat | Daybook 0.87 | Daybook | `1` / Daybook | Daybook | right |
| 7 | note | Release notes 0.53, Daybook 0.41 | Release notes | `1` / Release notes | Release notes | right |
| 8 | note | Release notes 0.53, Daybook 0.51 | none, ambiguous | not asked | nothing | right |
| 9 | note | Thesis 0.61, Release notes 0.53, Daybook 0.41 | none, ambiguous | not asked | nothing | right |
| 10 | note | Invoices 0.64, Email triage 0.57 | none, ambiguous | not asked | nothing | right |
| 11 | fresh | none | a landing-page or onboarding name | `new` / landing page design | landing page design | right |
| 12 | fresh | none | a podcast name | `new` / Intro edit | Intro edit | right |
| 13 | fresh | none | an interviews or hiring name | `new` / design candidate interview | design candidate interview | right |
| 14 | fresh | none | a 3D or chair name | `new` / modeled chair for scene | modeled chair for scene | right |
| 15 | mixed | Daybook 0.43, Thesis 0.43, Email triage 0.33 | none, ambiguous | not asked | nothing | right |
| 16 | mixed | Release notes 0.59, Daybook 0.41 | none, or Release notes | `1` / Release notes | Release notes | right |
| 17 | mixed | Invoices 0.62, Release notes 0.47 | none, or Invoices | `1` / Invoices | Invoices | right |
| 18–20 | no evidence | none | never asked | not asked | nothing | right |

**Counts.** 20 right, 0 none, 0 wrong, 0 offered names failed `NameAudit`.
Read with care: 4 of the 20 are nothing offered by rule (#8, #9, #10, #15),
which the earlier runs would have scored as none for #8–#10; and #16 and #17
are right only as their stated alternatives. Against the earlier
expectations, the count is 17 right, 3 none, 0 wrong.

**Did the model ever decline?** No. On the 9 questions about a candidate
(#1–#7, #16, #17) it answered `1` every time: never `none`, `2` or `3`. Both
sessions where the right answer was arguably none (#16, #17) were given the
top name. The model confirms the ranking; it does not judge it. What stops a
wrong earlier name is the margin rule, which would not have caught a session
with one candidate that fits badly.

**Fresh names.** All four sessions with no candidate got a fresh name (`new`)
and all four fit: "landing page design", "Intro edit" (the podcast intro),
"design candidate interview" and "modeled chair for scene". Two are loose
("Intro edit" drops the podcast), but none misstates the work.

**Caption.** Because the model never declined or picked another name when it
had candidates, an earlier-name offer is the ranking's, not the model's. The
notice says so: "From your earlier names", no sparkles mark. Only the four
fresh names above are the model's own wording.

## 6. Hand checks

| # | Step | Passes when |
|---|---|---|
| 1 | Stop an unnamed 15-minute session that used the apps of an earlier named one | The notice offers that earlier name |
| 2 | Name it, then Undo | The Story shows "Named … · Undo"; Undo leaves the session unnamed |
| 3 | Keep as is | The next unnamed session is offered; the kept one never returns |
| 4 | Turn "Use on-device AI" off | No notice is drawn |
| 5 | Stop an unnamed 15-minute session in apps no earlier name used, with a note that says what the work was | The notice offers a fresh name under "Suggested by on-device AI" with the sparkles mark |
| 6 | Stop an unnamed session whose apps fit two earlier names about equally | No notice is drawn for it |

## Out of scope

- Unnamed sessions older than yesterday (project 4, tidy suggestions).
- Renaming sessions that already have a name, including generic auto names.
- Suggesting a category.
- Suggestions on Macs without the model.
