# Apple Intelligence: review notes

Date: 2026-10-10
Status: design approved 2026-10-10 in chat; written spec awaiting review

## Why

Ask Daybook (`docs/specs/2026-10-09-ask-daybook-design.md`) showed that
Apple's on-device model can phrase Daybook's figures well when code computes
them first. The aim now is to use that model wherever it helps, while a Mac
that cannot run it behaves exactly as it does today.

This spec sets the rules every AI project follows and designs the first one:
a short written note about a day, week or month.

## Shared rules for every AI project

| Question | Decision |
|---|---|
| Model | `SystemLanguageModel.default`, on the Mac only. |
| Rejected: Private Cloud Compute (macOS 27) | Larger context and more reasoning, but session names and notes would leave the Mac, which breaks the README's privacy statement. |
| Minimum macOS for AI | 26, the release that added `FoundationModels`, the same gate as Ask. The app's own minimum stays 14. |
| Model unusable (macOS 14–25, Mac not eligible, Apple Intelligence off, model still downloading) | New AI features are not drawn at all. Ask keeps its current notices, including the button that opens Apple Intelligence settings. |
| Off switch | One switch, "Use Apple Intelligence", in Settings › Privacy, on by default. Off hides every new AI feature and cancels any note being written. Ask stays on ⌘K either way, since it runs only when asked. The switch is hidden when the model is unusable. |
| Who computes figures | Code. The model only words facts it is given or chooses among candidates code offers. |
| Writes | No AI output changes history unless the person accepts it. |
| Forms | Only two. A **note** is text to read, with no action. A **suggestion** is a Story rail notice in the `NameCategoryNotice` pattern: one action, Undo, Keep as is. |
| Rejected: AI notifications | Notifications are kept for break reminders that come due while nobody is at the screen (`Notifier`). |
| Rejected: popover cards | The popover has no notice cards today; adding a second pattern breaks consistency. |
| When the model runs | On a person's action, or the first time a past period is opened. Never on the 1 Hz ticker. Idle CPU stays at its 0.1% baseline. |
| Label | Every AI note carries the caption "Apple Intelligence · on this Mac". |

### Projects, in order

Each gets its own spec, plan and build.

| # | Project | Writes? |
|---|---|---|
| 1 | Review notes (this spec). Also builds `ModelGate`, which the others reuse. | No |
| 2 | Plain-language History search, mapped onto History's search and `AskRange.resolving` | No |
| 3 | Name suggestion when a session ends unnamed | One session, on accept |
| 4 | Tidy suggestions: merge near-duplicate names, suggest categories, extending `NameCategoryNotice` | Several records, on accept, with Undo |
| 5 | Siri and Shortcuts through App Intents. Needs no model, so it can be built in parallel. | Start and stop only |

Considered and dropped: narrating Insights (repeats the charts), pre-filling
the away prompt (the app asks instead of deciding), image input (the app has
nothing to look at).

## Decisions (review notes)

| Question | Decision |
|---|---|
| Places | History (each day, week and month), Today ("Wrap up today") and a Yesterday notice. |
| Content by place | History: story and one pattern. Totals stay on the cards beside it, so each fact is shown once. Today: story, pattern and a tip for tomorrow. Yesterday: an app-rendered figures line, story, pattern and a tip for today. |
| Approach | Code builds the facts, one model call returns a structured note, and an audit drops any note that states a figure missing from the facts. |
| Rejected: the model rewords `SummaryText`'s template | Exact, but it cannot choose a pattern or write a tip. |
| Rejected: the model gathers facts with Ask's tools | Several calls, and choosing tools caused most of Ask's wrong answers (§8 of the Ask spec). |
| When | Past periods are written the first time they are opened. Current periods (today, this week, this month) are written only on request, because their figures change every second. |
| One note per period | A day's note is written once, with story, pattern and tip; weeks and months get story and pattern. Each place shows the parts it needs, so History, Today and the Yesterday notice never tell one day two ways. The tip's label ("For tomorrow:", "For today:") is app-rendered. |
| Storage | In memory, keyed by period and a fingerprint of the facts. Nothing is written to disk except the date the Yesterday notice was dismissed. |
| Tips | Built on one of the candidate observations code supplies. The model chooses and words it; it never states a pattern code did not measure. |

## 1. Parts

| Layer | File | Responsibility |
|---|---|---|
| Core | `Sources/Core/NoteFacts.swift` | The facts for one period: its label and dates, sessions in order (name, start, length), top apps, peak hour, longest stretch, switches per stretch, change from the previous period, goal result and 2–4 candidate observations. Also the set of figures in the formats the facts use, and a fingerprint. Built from `DaySummaryInput` and `PeriodSummaryInput`. Lists are capped (top 8 sessions by time, plus counts). No `FoundationModels` import. |
| Core | `Sources/Core/NoteAudit.swift` | `passes(_ text:, facts:)`: every run of digits in the text must appear among the facts' figures. |
| App | `Sources/App/ModelGate.swift` | `isUsable`: macOS 26, `availability == .available` and the Settings switch, read on every call rather than kept from launch. `AskModel.canAsk` uses the availability part only, so Ask is unchanged. |
| App | `Sources/App/NoteWriter.swift` | `@MainActor`. One `LanguageModelSession` per note, with greedy sampling and `@Generable struct WrittenNote { story, pattern, tip? }`; the tip is asked for on days only. Runs the audit, keeps the cache, cancels an older request when a newer visible one starts, and has a `responder` seam for checks. |
| App | `Sources/App/SessionStore+Notes.swift` | Builds `NoteFacts` for a History place, for today and for yesterday from the read models those surfaces already publish, and publishes each note's state (none, writing, written, failed). |
| App | `Sources/App/SettingsModel.swift` | `useAppleIntelligence` (default true) and `yesterdayNoteDismissedDay`. |
| Surfaces | `Sources/Surfaces/Story/PeriodNote.swift` | The note view used in every place: text, caption, "Writing…" line, failure line. |
| Surfaces | `Sources/Surfaces/Story/YesterdayNotice.swift` | The Yesterday notice: figures line, note, Done. |
| Surfaces | `StoryRail.swift`, `HistoryTreeRow.swift`, Settings › Privacy | Place the views and the switch. |

Rules kept:

- Views bind to the store and settings only; they never read storage or compute figures.
- Each file stays under 300 lines.
- Lengths are design tokens or `.zoomed`, and text uses the type roles.
- `SessionEngine` and `SessionStore` internals are reached only through methods on their owners (`keep_internals`).

## 2. Writing a note

1. A view appears for a place, or the person presses "Write a note" or "Wrap up today".
2. `SessionStore+Notes` builds `NoteFacts` and asks `NoteWriter` for that period's note.
3. `NoteWriter` returns the cached note if the key matches. Otherwise it checks `ModelGate`, builds a session with the instructions for the period's kind (day, or week and month), and asks for a `WrittenNote` from the facts.
4. The audit runs on story, pattern and tip together. A note that fails is dropped.
5. The store publishes the result and the view redraws.

Instructions tell the model to use digits for every figure, to quote session
names as written, to build the pattern and tip on one listed observation, and
to stay within two sentences for the story and one each for pattern and tip.

## 3. Places

| Place | Position | Written | Shows |
|---|---|---|---|
| History day, past | Top of that day's Story rail | On first open | Story, pattern |
| History week or month, past | Under its period card when open | On first open | Story, pattern |
| History week or month, current | Same | On "Write a note" | Story, pattern |
| Today | Top of today's Story rail | On "Wrap up today", offered once today has a session and none is running | Story, pattern, tip for tomorrow |
| Yesterday | Top of today's Story rail, above the backup offer | When yesterday had a session and the notice has not been dismissed for that date | Figures line, story, pattern, tip for today |

```
┌ Yesterday ─────────────────────────────┐
│ 4h 10m focus · goal met · 3 sessions   │  app-rendered
│ Morning went to Daybook haptics, then  │
│ History search after lunch. Your       │
│ longest stretch, 1h 40m, began at 9.   │  model-written, audited
│ For today: start with the hardest      │
│ task at 9, when you're most focused.   │
│ Apple Intelligence · on this Mac  Done │
└────────────────────────────────────────┘
```

The figures line uses the same figures and formatting as the History card
for that day.

## 4. When it cannot write

| Case | Behaviour |
|---|---|
| Model unusable or switch off | No note, no link, no Yesterday notice. A note being written is cancelled. |
| No sessions in the period | No note and no link. |
| Audit fails, refusal, guardrail, unsupported language, context exceeded | Automatic notes show nothing. Requested notes show "Couldn't write a note for this period." No retry: greedy sampling would give the same result. |
| Facts change (rename, correction, deletion) | The fingerprint changes and the note is written again when next viewed. |
| Midnight | Notes are keyed by period, so today's wrap-up becomes yesterday's History note and Yesterday notice while its facts are unchanged, and is written again if they changed. The Yesterday notice moves to the new yesterday. |
| Several periods opened quickly | One call at a time; the newest visible request wins. |
| Figures written as words | Not caught by the audit. Marked `ponytail:` in `NoteAudit`; widen to number words if the probe finds any. |

## 5. Privacy

Facts go only to `SystemLanguageModel.default` on the Mac. Notes live in
memory. The README's privacy paragraph gains one sentence: review notes are
written by the same on-device model as Ask, and nothing is sent anywhere.

## 6. Checks

New suites appended at the end of `registeredTests`. No check calls the live
model.

| Check | Fixture | Fails when |
|---|---|---|
| Audit | Notes with matching, missing and reformatted figures | A figure missing from the facts passes, or a matching one fails |
| Facts | Day built from `SelfTest.base` with the app's calendar | Sessions out of order, observations missing, caps not applied |
| Fingerprint | Same day before and after a rename | Fingerprint unchanged |
| Cache | Stand-in responder counting calls | A second view of unchanged facts calls it again |
| Failed audit | Responder returns an invented figure | Any note is published |
| Gate | Switch off in `MemoryDefaults` | A note, link or Yesterday notice is published |
| Current period | Today and this week | A note is written without a request |
| Yesterday | Dismiss, then advance `TestClock` past midnight | The notice returns the same day, or fails to appear for the new yesterday |
| Views | `--gallery` / `--snapshot` with fixed notes | Layout breaks at 80% and 140% zoom; VoiceOver labels missing |

Run in Sydney and with `TZ=Europe/Berlin`. Mutation test in a temporary tree
copy: let the audit accept every note; the failed-audit check must fail.

Live quality: Ask's probe harness gains a `--noteprobe` entry over 20 fixture
periods. Target: no audit failures, and Sir's read of tone and accuracy.

## 7. Hand checks

Run on Sir's build with Apple Intelligence on, before merge. Record results here.

| # | Step | Passes when |
|---|---|---|
| 1 | Open yesterday in History | Note appears within 3 s; every figure matches the cards |
| 2 | Open today's main window | Yesterday notice shows; Done hides it until tomorrow |
| 3 | End all sessions, press Wrap up today | Note with a tip for tomorrow appears |
| 4 | Open this week, press Write a note | Note appears; reopening shows the same note |
| 5 | Turn the switch off | Every note, link and notice disappears at once |
| 6 | Rename a session from yesterday, reopen yesterday | Note mentions the new name |

## Out of scope

- Projects 2–5, each in its own spec.
- Editing or keeping notes on disk, and asking for a different note.
- Cloud models, Private Cloud Compute and notifications.
