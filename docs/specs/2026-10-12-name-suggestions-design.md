# Name suggestions for unnamed sessions

Date: 2026-10-12
Status: design approved 2026-10-12 in chat; written spec awaiting review

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
| Approach | Code ranks earlier names by shared app time and category, and offers the top 3. The on-device model picks one of them, words a fresh name, or declines. Code checks any fresh name before it is shown. |
| Rejected: code alone for earlier names | Cannot read the note, and it would put a non-AI suggestion on every Mac. |
| Rejected: the model reads every name | Hard to check, likely to pick a plausible wrong name, and against the shared rule that code offers the candidates. |
| Which sessions | Ended focus sessions from today and yesterday whose name is empty, focused for at least 10 minutes, and not kept as they are. A session is one thread's stretches on one day, as History shows one card; its day is the day it started, in `periodCalendar`. |
| Rejected: any day you open | Older guesses are harder to judge; tidying older history is project 4. |
| Cadence | One suggestion at a time, newest first: today's sessions, then yesterday's. |
| Rejected: a batch with "Name all" | One wrong guess rides along with the right ones. |
| Form | A Story rail notice in the `NameCategoryNotice` pattern: one action ("Name it"), "Keep as is", and Undo through the Story's existing saved-action row. |
| Wording | "On-device AI", never "Apple Intelligence", and the `sparkles` mark. Sir decided this app-wide on 2026-10-12; a separate PR renames the shipped wording. `apple.intelligence` is reserved for naming Apple Intelligence itself. |
| Shared rules | On-device only (`SystemLanguageModel.default`); `ModelGate.modelAvailable` and the "Use on-device AI" switch; nothing drawn on Macs that cannot run it; never on the 1 Hz ticker; no history change until the person accepts. |

## 1. Parts

| Layer | File | Responsibility |
|---|---|---|
| Core | `Sources/Core/NameCandidates.swift` (new) | Pure. From one session's app minutes and category, and every named session in the last 60 days grouped by name, returns earlier names ranked by shared app time (§2). |
| Core | `Sources/Core/NameAudit.swift` (new) | Pure. Accepts or rejects a fresh name (§2). |
| App | `Sources/App/SessionStore+NameSuggestion.swift` (new) | Which sessions to offer, in order (§3); their facts; "Name it" through `renameSession`; "Keep as is". |
| App | `Sources/App/NameSuggester.swift` (new) | `@MainActor` and `ObservableObject`, in the `NoteWriter` shape: one greedy `LanguageModelSession` call per session, a 10 s timeout, cancellation, a `responder` seam for checks, and an in-memory cache keyed by the session's thread ID, end time, category and note. |
| App | `Sources/App/MainWindowModel.swift` | `nameSuggester`, built on first read like `notes`. |
| Surfaces | `Sources/Surfaces/Story/NameSuggestionNotice.swift` (new) | The notice in today's rail tile, under `NameCategoryNotice` when both show. |

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

A session with no app evidence and no note is not sent to the model and
gets no suggestion.

**The model's answer.** A `@Generable` choice of `1`, `2`, `3`, `new` or `none`, plus a name that is used only with `new`. The call is greedy and runs once.

**What code accepts.**

| Answer | Result |
|---|---|
| `1`–`3` | That candidate's exact text; the model cannot alter it. |
| `new` | Only if `NameAudit` passes: 1–4 words, at most 30 characters, no digits, no quotes, not a category name, not just an app's name. A fresh name equal to any earlier name, ignoring case, takes the earlier spelling. |
| `none`, a failed audit, an error or the timeout | No suggestion for this session; the next session is tried. |

## 3. The notice

**Shape.**

```text
✦ Name this morning's 1h 20m session “Daybook”?
  Suggested by on-device AI
  [Name it]   [Keep as is]
```

- The opening follows the session: "this morning's", "this afternoon's", "this evening's", "yesterday evening's", using `SessionStore.timeOfDay` and the focused time from `DurationText`.
- VoiceOver reads the mark as "Suggested by on-device AI".

**Behaviour.**

| Case | Behaviour |
|---|---|
| Name it | `renameSession`, an ordinary correction. The Story's saved-action row shows "Named … · Undo". The notice moves on to the next session. |
| Undo | The session's name is empty again. It is offered again only after a relaunch or a change to its facts. |
| Keep as is | The thread is remembered in `fc.nameSuggestionKept`, trimmed to threads that ended in the last two days, and the next session is shown. |
| Named on its card | The session drops out. |
| Switch off, or model unusable | Nothing is drawn, and a call in flight is cancelled. |
| Model runs | When a session stops unnamed, and when today's Story opens with a qualifying session that has no cached result. Only one call at a time, and never on the 1 Hz ticker. After a relaunch it runs again once, when the Story opens. |
| No candidates, no evidence, or no answer | That session shows no notice; the next one is tried. |

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
| Model answer | `1`–`3` alters the candidate's text; a fresh name matching an earlier one keeps the model's spelling; `none` or a timeout shows something; the model is asked with the switch off or with no evidence; a redraw calls it again. |
| Actions | Name it does not rename, Undo does not restore, Keep as is is not remembered or not trimmed, or a session named on its card still shows. |
| Views | `--snapshot` of the notice breaks at 80% or 140% zoom, light or dark. |

**Live probe.** 20 hand-built sessions, each with the expected answer written
down first: clear repeats of an earlier name, new work with a telling note,
mixed apps, and no evidence. The target is at least 16 right-or-none, with 0
names that slipped past the audit. Smoke-test the model first with a 60 s
timeout. A miss is fixed in code (the ranking or the facts), never by
editing the prompt.

## 6. Hand checks

| # | Step | Passes when |
|---|---|---|
| 1 | Stop an unnamed 15-minute session that used the apps of an earlier named one | The notice offers that earlier name |
| 2 | Name it, then Undo | The Story shows "Named … · Undo"; Undo leaves the session unnamed |
| 3 | Keep as is | The next unnamed session is offered; the kept one never returns |
| 4 | Turn "Use on-device AI" off | No notice is drawn |

## Out of scope

- Unnamed sessions older than yesterday (project 4, tidy suggestions).
- Renaming sessions that already have a name, including generic auto names.
- Suggesting a category.
- Suggestions on Macs without the model.
