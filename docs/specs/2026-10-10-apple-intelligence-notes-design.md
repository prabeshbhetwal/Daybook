# Apple Intelligence: review notes

Date: 2026-10-10
Status: built 2026-10-11; live probe and hand checks pending

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
| Storage | In memory, keyed by the period's place and the facts' text itself (no separate hash). Nothing is written to disk except the date the Yesterday notice was dismissed. |
| Tips | Built on one of the candidate observations code supplies. The model chooses and words it; it never states a pattern code did not measure. |

## 1. Parts

| Layer | File | Responsibility |
|---|---|---|
| Core | `Sources/Core/NoteFacts.swift` | The facts for one period as plain text: its label and dates, sessions in order (name, start, length), top apps, and candidate observations (a day's up to four: longest stretch, when focus began, change from the previous period, goal result and similar; a week's or month's up to five, §2). A day's observations that only the pattern may use, such as a drop in focus from the day before, are listed under "Context:" apart from the "Observations:" a tip may build on (`patternOnly`). Also `WrittenNote` (story, pattern, optional tip) and the inputs the facts are built from: `NoteDayInput` (which carries `sessionCount`, the sessions as History counts them, and `longestStretch`, the Story's own pause-aware figure as a `NoteStretch`) and `NotePeriodInput` (with the same `longestStretch` and a month's `busiestWeekday`). No `FoundationModels` import. |
| Core | `Sources/Core/NoteFactsBuilder.swift` | `NoteFacts.day` and `NoteFacts.period`, the wording and formats of the facts, and the app-rendered figures line. Lists are capped (a day names its top 8 sessions by time, in start order, and counts the rest; a week or month names its top 3 by time). A session left unnamed is called by its kind, as the Story titles it. Split from `NoteFacts` to keep each file under 300 lines. |
| Core | `Sources/Core/NoteAudit.swift`, `NoteFigure.swift`, `NotePiece.swift`, `NoteNumberWords.swift` | `passes(_ note:, facts:)`: every figure in the story, pattern and tip must appear among the facts' figures, compared by kind and value and not by digits (§2). `NotePiece` cuts a text into numbers, clock times and words; `NoteNumberWords` reads "forty-six" and "two thousand twenty-six"; `NoteFigure.read` types what remains. |
| App | `Sources/App/ModelGate.swift` | `modelAvailable`: macOS 26 and `availability == .available`, read on every call rather than kept from launch. `AskModel.canAsk` reads it too, so Ask is unchanged. The Settings switch is read by `NoteWriter.isUsable`. |
| App | `Sources/App/NoteWriter.swift` | `@MainActor ObservableObject`. Publishes each place's note state (writing, written, failed) and keeps the cache and the failed keys. One `LanguageModelSession` per note, with greedy sampling and a `@Generable` form for each kind (`GeneratedNote.swift`: a day's `GeneratedNote { story, pattern, tip }`, a week's or month's `GeneratedPeriodNote { story, pattern }`, with a `GeneratedSoloPeriodNote` and a `GeneratedPairPeriodNote` for facts that name one or two sessions, chosen by `PeriodForm`); the tip is kept on days only. Runs the audit, writes one note at a time, and has a `responder` seam for checks. `NoteWriter+Failure.swift` says which thrown errors would fail the same way again (§4). Remembers the key each published state was written for: `forgetIfStale(_:)` drops a note or failure whose facts have since changed, and `cancelAll()` stops the note being written and drops those waiting. |
| App | `Sources/App/SessionStore+Notes.swift` | Builds `NoteFacts` for a History place, for today and for yesterday from the read models those surfaces already publish, and answers whether Wrap up today or the Yesterday notice is offered. `noteEvidence` is the session archive's and the session metadata's revisions, read from `evidenceRevision`, and the daily goal: the cheap value a note on screen is checked against again (§3). The longest stretch of a day, week or month is `storyLongestFocusStretch`, the Story's own; a month's busiest weekday is summed from the per-day projections the period's session totals already read. It publishes no note state (only the redraw after the Yesterday notice is dismissed) and adds no stored property, so `SessionStore` gains no `keep_internals` entry. |
| App | `Sources/App/MainWindowModel.swift` | `notes`: builds the `NoteWriter` on first read. Today's rail reads it on every redraw, so every Mac that shows the rail holds one, whether or not a note is ever shown. Views reach the writer as `navigation.notes`. |
| App | `Sources/App/SettingsModel.swift` | `useAppleIntelligence` (default true). It and `yesterdayNoteDismissedDay` are stored in `PersistenceStore`. |
| Surfaces | `Sources/Surfaces/Story/PeriodNote.swift` | The note view used in every place: text, tip where a label is given, caption, "Writing…" line, failure line and the link for a note written on request. Its parent passes in `noteEvidence`. When the view appears, and again whenever that evidence changes, an automatic note is requested and an on-request note calls `forgetIfStale`; when the model becomes unusable it calls `cancelAll`. |
| Surfaces | `Sources/Surfaces/Story/YesterdayNotice.swift` | The Yesterday notice: figures line, note, Done. |
| Surfaces | `Sources/Surfaces/Story/TodayNotes.swift` | Places the Yesterday notice and Wrap up today at the top of Today's rail. The offers are built again when their cause changes; the cause includes `noteEvidence`, so a new daily goal or a correction to yesterday rebuilds the figures line. |
| Surfaces | `HistoryTreeRow.swift`, `StoryRail.swift`, Settings › Privacy | Place the views and the switch. |
| Surfaces | `SnapshotNotes.swift`, `Snapshotter.swift` | Two gallery scenarios (`reviewNotes`, `reviewNotesHistory`) that show fixed notes without a model. |
| Checks | `ReviewNoteFactsChecks`, `ReviewNoteGateChecks`, `ReviewNoteStoreChecks`, `ReviewNoteWriterChecks`, `ReviewNoteWriterFailureChecks`, `ReviewNoteWriterQueueChecks`, `ReviewNoteStoreEdgeChecks`, `ReviewNoteWriterStateChecks`, `ReviewNoteFreshnessChecks`, `ReviewNoteWordChecks`, `ReviewNoteFigureChecks`, `ReviewNoteStretchChecks`, `ReviewNoteGoalChecks`, `ReviewNoteTransientChecks`, `ReviewNotePeriodChecks` | Under `Sources/Verification/`; §6 lists what they guard. |

Rules kept:

- Views bind to the store and settings only; they never read storage or compute figures.
- Views gate on the switch and read no expensive store methods in a body that redraws every second. Today's rail holds its offers in state and builds them again only when their cause changes (the day turning over, a session starting, stopping or being added, the model becoming usable or not, and `noteEvidence`: a correction to yesterday or a new daily goal). Reading the model's availability costs about 215 µs of CPU, so the rail reads it once per redraw and passes it to the notes it places. `noteEvidence` is a few counter reads, with no projection, and is taken in the same redraws.
- Each new note file stays under 300 lines. `StoryRail.swift`, `SettingsModel.swift` and `MainWindowModel.swift` were already over it and received placement lines only.
- Lengths are design tokens or `.zoomed`, and text uses the type roles.
- `SessionEngine` and `SessionStore` internals are reached only through methods on their owners (`keep_internals`).

## 2. Writing a note

1. A view appears for a place, or the person presses "Write a note" or "Wrap up today".
2. The view asks `NoteWriter` for that place's note, and `NoteWriter` has `SessionStore+Notes` build the `NoteFacts`.
3. `NoteWriter` returns the cached note if the key (the place's id and the facts' text) matches. Otherwise it checks `ModelGate` and the switch, builds a session with the one instruction string (the same for every kind of period; a day and a week or month differ in the form asked for, `GeneratedNote` or `GeneratedPeriodNote`), and asks for a note from the facts.
4. The audit runs on story, pattern and tip together. A note that fails the audit, comes back blank or is refused is dropped and remembered as failed; an error that is the Mac's state is shown as a failure but not remembered (§4).
5. `NoteWriter` publishes the result and the view redraws. The store publishes no note state.

The instructions tell the model to use only the facts, to write every figure
in digits as the facts write it, never to total, average or compare figures
itself, and to write in plain Australian English in the second person. The
guides on `GeneratedNote` (a day) tell it to quote session names as written,
to build the pattern on one listed observation or context line, to stay
within two sentences for the story and one each for pattern and tip, and to
write the tip as one concrete action for the next day built on one of the
observations, never commenting on less focus or a missed goal. The guides on
`GeneratedPeriodNote` (a week or month, which has no tip) ask the story to name
up to three of the sessions that took the most time, as many as the facts name,
each with its duration in digits exactly as the facts write it, not in order
and not added together, and the pattern to state the first listed observation
with its figures as listed. That wording alone padded a period that names fewer
than three: a one-session week read "You spent 1h on Reading on Wednesday 29
July 2026 and 1h on Reading on Wednesday 29 July 2026.", and a two-session one
added "and 11h on Thesis again". Every rewording tried on the fixture still
padded (one sentence, "each once", "as many as are listed", an example), so the
facts count the sessions they name (`namedSessions`) and the model is asked for
a form that gives the sentence to fill: "You spent DURATION on NAME." for one,
"... and DURATION on NAME." for two, the three-session guide for three.

The tip guide is a deliberate exception to "fixes go in the facts, not the
prompt", because tone is wording and not a fact. The facts still do the
main work: a drop in focus from the day before is listed under "Context:",
not under "Observations:", so the tip has nothing to scold about. An
earlier version marked each usable observation "(usable for a tip)"; the
model parroted the mark ("Use the call to Mum for a tip"), so the facts split
the lists instead.

The audit weighs figures by kind and value, not by digits (`NoteFigure`):

| Kind | Reads as | Compared as |
|---|---|---|
| Duration | "1h 30m", "90 minutes", "1.5 hours", "one hour thirty minutes", "1-hour 30-minute" | seconds. Terms joined by a space, a comma or "and", each in a smaller unit than the one before, are one duration and are added: "2h, 30m" is 9000 s, and the facts must hold 9000 s as a single duration. A larger unit after a smaller ("30m, then 1h") or any other word between ("Xcode 1h, Safari 30m") starts a new figure |
| Clock time | "9:13 am", "9:13am", "9 pm", "21:13" | minute of the day; with no am or pm it reads both ways |
| Date | "14 November", "6th of October", "Tuesday 6 October 2026" | month and day; a weekday written touching the day ("Tuesday 7 October", "Tue, 7th Oct") is part of it and must be the weekday the facts give that date |
| Year | a four-digit number from 1900 to 2100 | the year |
| Count | a number before session(s), day(s), stretch(es), week(s), month(s) | number and noun, "three stretches" = "3 stretches" |
| Percentage | "40%", "40 percent" | the number |
| Bare number | any other: a session name's "Q4", "v2", "1.3", "3 of 7" | the number, against bare numbers only |
| Numberless amount | "an hour", "half an hour", "a couple of hours", "an hour and a half", "one and a half hours", "a quarter of an hour", "Thesis for hours", "a minute", "twice" | never: the words hour, minute (and their short forms), half, quarter, couple, twice and thrice left over with no number before them fail the note |

Every figure in the note must match one the facts hold, of the same kind and
value. So "9h" fails against a 9:13 start, "seventeen hours forty-one
minutes" fails against a session count and a duration that are both in the
facts, and a bare 30 does not pass because the facts hold 30m. A session
name's digits are facts, and pass when the note quotes the name.

The audit fails closed. A review found that an amount with no number in front
of it passed unchecked: with a 45m session in the facts, "an hour", "half an
hour", "a couple of hours", "an hour and a half" and "a quarter of an hour"
all passed, and "an hour" is the likeliest way for the model to invent a
duration. Such a wording is now a phrase no fact holds, and the note fails,
even when the facts hold a duration it could mean. The one excuse is a name:
the words hour, minute, half and the rest stand when the two words they sit in
(with the word before, or the word after) are in the facts, so a session
named "Office hours" or "Half marathon plan" is quoted freely. A weekday beside
a date was not compared either, so "Tuesday 7 October" passed against
Wednesday 7 October; it fails now, and a date with no weekday still matches
any weekday the facts give it.

Where the facts come from, as built:

- A day's facts, and the figures line on the Yesterday notice, read the Story day projection, which is always current. A day's longest stretch is the Story's own (`storyLongestFocusStretch`): the work of one recorded stretch with its pauses taken out, since a stretch's span from start to end counts a pause as focus (a 9 to 11 session with an hour paused read "2h", more than the day's focus). A session left unnamed is its kind's name in the facts, as in the Story.
- A week's or month's facts read History's index, which is refreshed only while History is open, so those notes are requested only from History. They name the top three sessions by time (naming more led the model to total "other sessions") and carry up to five observations, each a sentence a note can quote whole, in this order: the best day with its focus; a month's busiest weekday with its focus and number of days (left out when focus fell on one weekday only); the longest stretch with its day and start; the change from the period before; the goal days; and the top session's share when it is over 40%.
- A week or month is compared with the one before only when both are finished whole calendar periods and the one before lies wholly within the record, that is, begins on or after its first day. A running period, one cut short at the start of the record, or one whose predecessor was recorded only in part is not weighed against a whole one. A day is compared with the whole day before.
- A session carried on from the night before is not said to begin at midnight. The day's session is clipped to the day's start, so one starting exactly there is written "Focus carried on past midnight with …", "… from before midnight, 1h" in the session list and "from before midnight" on the longest stretch, never "12:00 am". A session that truly began at 00:00 reads the same, since only the clipped start is kept (`ponytail:` in `NoteFactsBuilder`).
- A day's session count is History's own: a session resumed after another on the same thread is one session, so "Focus: … over N sessions", the stretches observation and the figures line agree with the day's card. The "Sessions in order" list still names every row the Story shows.

## 3. Places

| Place | Position | Written | Shows |
|---|---|---|---|
| History day, past | Top of the opened day row, above the day's story; the same slot as a week's or month's note | On first open | Story, pattern |
| History week or month, past | Under its period card when open | On first open | Story, pattern |
| History day, current | Same slot as a past day's | On "Write a note", offered even while a session runs | Story, pattern |
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

History offers "Write a note" on a current day while a session runs, whereas
Today's rail offers "Wrap up today" only when none does. The difference is
kept: a current period is written on request, and the evidence check below
refreshes it as its figures change.

A note the writer holds for a place is shown whenever that place's view is
built again, so an on-request note stays shown after its view is recreated.
Its link shows only while there is nothing to show. A note written on request
for figures that have since changed (a session added to a running day or
week, a rename) counts as nothing: the writer forgets it when the view
appears, and the link returns.

A note already on screen checks its facts again when the session archive, the
session metadata or the daily goal changes (a rename, a correction, a
deletion, an edited session note, a session stopping, a new goal), through
the `noteEvidence` its parent
passes to `PeriodNote`: an automatic note is requested again and an on-request
note is forgotten if its facts changed. This holds in History, where a rename on
an opened day reaches the note above its story, and in the Yesterday notice,
where the note no longer lags the figures line above it when an away card is
answered after midnight. A day's facts and the Yesterday figures line both state
the goal and weigh the day against it, so the goal is part of the evidence;
before it was, a new goal left the note's old wording on screen. App use is
not part of that evidence: it moves every few seconds while you work, and would
send a Wrap up today note just written back to its link.

## 4. When it cannot write

| Case | Behaviour |
|---|---|
| Model unusable or switch off | No note, no link, no Yesterday notice. The note being written is cancelled and any waiting are dropped (`cancelAll`), so nothing is left showing "Writing…"; notes already written stay in memory, hidden. |
| No sessions in the period | No note and no link. |
| Audit fails, blank note, refusal, guardrail, unsupported language, context exceeded | Automatic notes show nothing. Requested notes show "Couldn't write a note for this period." No retry: greedy sampling would give the same result. These failures are remembered per place and facts for the session, so the model is not asked again until the facts change. The thrown ones are told by `NoteWriter.repeats(_:)`, named as `AskModel.notice(for:)` names them (macOS 26's `GenerationError` and macOS 27's `LanguageModelError`). |
| Any other error from the model (memory pressure, a model not ready, a rate limit, a timeout, an unknown error) | Shown as a failure like the above, but not remembered: it is the Mac's state and not the facts'. The next request for the place asks the model again, and an on-request note returns to its link when its view appears (`forgetIfStale`). The live probe was refused from its eleventh note on under memory pressure; before this the writer then never asked for those periods again. |
| Facts change (rename, correction, deletion, a session added) | The facts' text changes, and with it the cache key, so the note is written again, at once if it is on screen (the view checks again when `noteEvidence` moves, §3) and otherwise when next viewed. A note written on request returns to its link instead, since nothing writes it unasked. Changes in app use alone are not watched. |
| Midnight | Notes are keyed by period and the facts' text. A day's first fact line ends "(so far)" while it is current, so the text, and with it the key, always changes at midnight: today's wrap-up is never carried over, and the finished day's note, in History and in the Yesterday notice, is always written afresh. The Yesterday notice moves to the new yesterday. Done closes the day the notice showed, not whichever day is yesterday when it is pressed after midnight, so the new yesterday is still offered. |
| Several periods opened quickly | One call at a time. A newer request replaces the one running. A replaced period still on screen is written once the writer is idle; one whose view has closed is dropped. |
| Figures written as words | Read by the audit as the value they stand for, typed (§2): the probe found the model writing most of a week's or month's figures this way (§6a). A lone "one" counts before a unit or a thing counted ("one hour", "one session"). "Half", "quarter", "couple" and "twice" are not read as numbers but fail the note (§2); "dozen" and ordinals ("tenth") are still not read, and "and" ends a figure (`ponytail:` in `NoteNumberWords`). |

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
| Cache key | Same day before and after a rename | The rename leaves the facts' text, and so the key, as it was, or the model is not asked again (`renameRewrites`) |
| Cache | Stand-in responder counting calls | A second view of unchanged facts calls it again |
| Failed audit | Responder returns an invented figure | Any note is published |
| Gate | Switch off in `MemoryDefaults` | A note, link or Yesterday notice is published |
| Current period | Today and this week | A note is written without a request |
| Yesterday | Dismiss, then advance `TestClock` past midnight | The notice returns the same day, or fails to appear for the new yesterday |
| Done after midnight | Notice for Tuesday, clock moved to 00:30 on Thursday, Done pressed with Tuesday's place | Wednesday is recorded instead of Tuesday, or is not offered afterwards |
| Stale note | A note and a failure written on request, then a session renamed | Changed facts leave either on screen, unchanged facts forget it, or a note being written is forgotten |
| Cancel all | A note being written and one waiting, then `cancelAll` | A "Writing…" state is left, a late answer is published, or the waiting note is started again |
| Session count | A day with Parser, Mail, then Parser again on one thread | The facts or the figures line say 3 sessions where History counts 2 |
| Previous period | Months and weeks whose predecessor starts before, or after, the record's first day | A partly recorded period is compared, or a wholly recorded one is not |
| Evidence | A rename, an edited session note, a session running and stopping, and app use recorded | A rename, a session note or a stop leaves `noteEvidence` as it was, a running session moves it, or app use alone moves it |
| Carried over | A session from 10 pm on a Friday to 2 am on the Saturday | Saturday's facts name 12:00 am, or omit "carried on past midnight", "from before midnight" in the list and on the longest stretch; Friday's lose their 10:00 pm start |
| Spelled figures | Notes writing "forty-six", "two thousand twenty-six" and "five thirty" | A spelled number reads as other than its digits, a spelled figure the facts lack passes (the digits-only audit passed it), or one the facts hold, or a session name's, fails |
| Most-time list | A week whose sessions are "Budget, then notes" and "Release 1.3" | The list reads other than `name: duration` joined by semicolons, so a comma or a trailing number runs into the figures |
| Typed figures | Facts written by hand in the builder's wording; notes stating "9h" against a 9:13 start, "13 minutes", "9 sessions", "15 sessions" against a 15 November, "9:15 am", "9:13 pm", "40%", "2 days" against 2 sessions, "5 stretches" against 3, and "seventeen hours forty-one minutes" | A figure whose digits are elsewhere in the facts passes (`ReviewNoteFigureChecks`) |
| Same figures, other words | The facts' own durations, times, dates and counts in digits, as "1 hour 30 minutes", "90 minutes", "1.5 hours", "1-hour 30-minute", "one hour and thirty minutes", "09:13", "9:13am", "15th November" | A figure the facts hold fails |
| Duration reading | "1h 30m", "1 hour, 30 minutes", "1h30m", "90 minutes", "ninety minutes" all 5400 s, "2h, 30m" 9000 s; "Xcode 1h, Safari 30m" and "30m, then 1h" stay two figures | A duration with a word between its terms is summed, or one duration reads as two |
| Numberless amounts | Facts with a 45m and a 1h 30m session; notes saying "an hour", "half an hour", "a couple of hours", "an hour and a half", "one and a half hours", "a quarter of an hour", "hours on Thesis", "a few minutes", "a minute", "twice", "a couple of sessions", "the second half of the day" and "an hour" in the tip alone | Any of them passes (`ReviewNoteVagueChecks`) |
| Wording in the facts | Sessions named "Office hours", "Minute taking" and "Half marathon plan", quoted; the same notes with "an hour" or "half an hour" added | A quoted name fails, or an amount of the note's own is excused by a name |
| Weekday and date | A week's facts with Wednesday 7 and Tuesday 6 October; "Wednesday 7 October", "Wed 7 Oct", "Wednesday, 7th October", "7 October", "Tue 6 October 2026" pass; "Tuesday 7 October", "Tue 7 Oct", "Thursday, 7th October", "Monday 6 October" and "Tuesday 8 October" fail | A wrong weekday passes, or a right one, or a date without one, fails |
| Named sessions | A week naming 5, 3, 2 and 1 sessions | The facts name other than min(count, 3), or the form asked for is other than trio, trio, pair, solo |
| Bare numbers | Names "Q4 plan v2", "Sprint 42 review", "Release 1.3", "2026 tax return" quoted from the facts, against facts without them, and a bare 30 against facts that hold 30m | A name's digits fail when quoted, pass when the name is absent, or a bare number passes on a duration |
| Probe wording | The live run's week note with its invented total and its digit-named day, against the facts the app now writes | The invented total passes, or the digit-named day fails |
| Pause in a stretch | A session from 9 to 11 with an hour paused (1h of work), read from a store | The day's longest stretch reads 2h, or differs from the Story's `storyLongestFocusStretch` |
| Unnamed session | A session saved with a blank name | The facts list it blank where the Story titles it by kind |
| Context | A day 1h below the day before, and one 30m above | A drop is listed among the observations a tip may use, or a rise is kept from it |
| Goal evidence | `noteEvidence` before and after a new goal, a note written for one goal, and the offers' cause | A new goal leaves the evidence, a written note or the cause as it was; or setting the goal to what it was moves it |
| Correction to yesterday | A rename of yesterday's session, then `TodayNoteOffers.cause` | The cause stays as it was |
| Mac's state | A responder throwing rate-limited, assets-unavailable, a Cocoa error, the probe's unknown error and (macOS 27) a timeout | The second request does not ask the model again, or the writer does not recover when the Mac does |
| Facts' errors | A responder throwing context-exceeded, guardrail, refusal and unsupported-language errors (and macOS 27's) | One is asked for again |
| Link returns | An on-request note that failed for the Mac's state, one refused, and a day with no sessions, each `forgetIfStale` | The state failure stays where the link should return, or a refusal or a day with no facts is forgotten |
| Period facts | A month's input with five sessions, a best day, a busiest weekday, a longest stretch, a comparison and goal days; a week and a month on one weekday | More than three sessions are named, the observations are other than those five in order, a week names a busiest weekday, or a month on one weekday does |
| Period from the store | A session from 11 to 2 with an hour paused and no name, a week and a month | The longest stretch counts the pause, the unnamed session is blank in the list, or the month lacks its busiest weekday |
| Views | `--gallery` / `--snapshot` with fixed notes | Layout breaks at 80% and 140% zoom; VoiceOver labels missing |

Run in Sydney and with `TZ=Europe/Berlin`. Mutation test in a temporary tree
copy: let the audit accept every note; the failed-audit check must fail.

The fix wave's mutants, each put back by hand in a temporary tree copy, and
the check that caught it (checks are numbered by position; titles are in the
suites above):

| Old behaviour put back | Caught by |
|---|---|
| The longest stretch is the longest span, pause included | Pause in a stretch |
| A blank session name stays blank in a day's facts | Unnamed session |
| The first version's digits-only audit | Typed figures, Same figures in other words, Bare numbers, Probe wording |
| The goal is left out of `noteEvidence` | Goal evidence |
| The offers' cause leaves out `noteEvidence` | Correction to yesterday (and the goal assertion of Goal evidence) |
| Every thrown error is remembered | Mac's state, Link returns |
| Nothing thrown is remembered | Facts' errors |
| A failure that was not remembered stays on screen | Link returns |
| A drop in focus is offered to the tip | Context |
| Five sessions named in a week's or month's list | Period facts |
| The store gives no busiest weekday, or the builder leaves it out | Period facts, Period from the store |
| A blank session name stays blank in a period's totals | Period from the store |
| Numberless amounts are not read (fix round) | Numberless amounts |
| A date's weekday is dropped when read (fix round) | Weekday and date |
| Every period is asked for the three-session form (fix round) | Named sessions |

Live quality: Ask's probe harness gains a `--noteprobe` entry over 20 fixture
periods. Target: no audit failures, and Sir's read of tone and accuracy.

## 6a. Probe (2026-10-11)

Two runs are recorded. The first is kept as it was written, as evidence of
what the fix wave answered; the second, after the wave, follows it.

### First run (2026-10-11, before the fix wave)

After the Mac restarted, the on-device model wrote notes for 20 fixture
periods. **20 of 20 passed the audit.** No note stated a figure the facts
lack. Median 3.9 s a note, fastest 2.7 s, slowest 8.1 s (the day with nine
sessions), on a Mac that other builds were keeping at a load average of 12
to 90. Hand check 1's 3 s bar is therefore not met on a busy Mac. The notes
below, and a read of them, are for Sir's judgement of tone and truth.

How it ran. A temporary copy of the sources, outside the working tree, got a
`--noteprobe` entry that runs before anything touches live data. It calls
`NoteWriter`'s own generation and tidying code (the same instructions,
`GeneratedNote` and greedy sampling), applies `NoteAudit` itself so a failing
note's text can be read, then asks the real `NoteWriter` for the same place.
The writer's state matched the audit's verdict for all 20. The fixture is an
in-memory history from August to 10 October 2026:

- days with 1, 3 and 9 sessions, one named with digits ("Q4 plan v2",
  "Sprint 42 review", "2026 tax return"), one of two very short sessions, one
  with long names holding a comma and a dash, one after a very short day, one
  after a longer day, one with no focus the day before
- a session across midnight, read on both its days, and a running session
- weeks and months, finished with a whole previous period, current, and the
  first of the record

| Place | Audit | Story | Pattern | Tip |
|---|---|---|---|---|
| Wed 7 Oct, digit names | pass | You worked on Q4 plan v2 for 1 hour 30 minutes at 9:00 am, then Sprint 42 review for 1 hour at 11:00 am, and finally 2026 tax return for 2 hours at 2:00 pm. | The 2-hour stretch in 2026 tax return at 2:00 pm was the longest focus period of the day. | You spent 1 hour less focusing than the day before; consider adjusting your schedule for consistency. |
| Sat 10 Oct, so far, a session from the night before | pass | You worked on Release 1.3 from before midnight for 1h 15m, then Thesis at 9:10 am for 1h 50m, and Parser at 1:00 pm for 1h 30m. | The longest stretch of focus was 1h 50m in Thesis at 9:10 am. | You had 37 minutes less focus than the day before, so consider reviewing your priorities for the next day. |
| Mon 10 Aug, goal missed | pass | You worked on Thesis at 9:00 am for 1h 30m, then Parser at 2:00 pm for 54m, and finally Email at 4:30 pm for 30m. | The longest stretch of focus was 1h 30m in Thesis, from 9:00 am. | Next day, start with Thesis at 9:00 am to build momentum. |
| Fri 2 Oct, names with a comma and a dash | pass | You worked on Mum's birthday – planning at 9:00 am for 40 minutes, then reviewing the quarterly budget proposal with Priya and sending notes at 10:30 am for 1 hour 35 minutes. | The longest stretch of focus was 1 hour 35 minutes in reviewing the quarterly budget proposal with Priya, then sending notes, from 10:30 am. | You spent 1 hour 27 minutes less focused than the day before; consider reviewing priorities for the next session. |
| Week of 28 Sep | pass | You worked on reviewing the quarterly budget proposal with Priya and sending notes for one hour thirty-five minutes, then reading for one hour thirty minutes, then thesis for eleven hours, then parser for six hours thirty-six minutes, then email for two hours, and then other sessions for seventeen hours forty-one minutes over seven days. | You met your goal on three of seven days with focus. | not shown (tips appear on days only) |
| Week of 14 Sep | pass | You worked on Thesis for hours, Parser for hours and hours, and Email for hours over fourteen sessions spread across five days. | Tuesday 15 September 2026 had the most focus of the week at nine hours. | not shown |
| Week of 3 Aug | pass | You worked on Thesis for 7h 30m, Parser for 4h 30m, and Email for 2h 30m across 15 sessions over 5 days. | You met your goal on 0 of 5 days with focus. | not shown |
| September | pass | You worked on Thesis for a total of 68h, followed by Parser for 41h 48m, and Email for 10h 30m. | You met your goal of having focus every day on 22 of 22 days. | not shown |

Greedy sampling gave the same day notes word for word on every run.

### Read of tone and truth

Days (13 notes):

- Times, order and durations match the facts in every day story. One story
  misreads them: Sat 3 Oct (one session, Reading) says "then 1 hour 30 minutes
  in Books", taking the top-app line for a second block of work.
- Names are not always quoted as written: "Call Mum" became "called Mum", and
  the long name lost its capital, and its comma in the story (the pattern
  above keeps the comma).
- The three wording watch-points: a name ending in a number followed by its
  duration ("Release 1.3 for 2h 45m") read correctly everywhere; the
  overnight wording ("from before midnight") was used correctly on both days
  and nothing said a session began at midnight; a comma inside a name did
  not break a day, but did garble a week (below).
- No praise is shown anywhere. Tips are weaker than stories: 4 of 13 are sound
  advice built on the stretch or start time ("start with Thesis at 9:00 am to
  build momentum"); 2 restate an observation without advising; 5 turn the
  comparison with the day before into a mild reprimand ("consider adjusting
  your schedule for consistency"); 2 make no sense ("Next day, focus for 48
  minutes less than the day before", "aim to spend more time on calls than on
  apps"). One of the five reprimands, on the running day, also claims the
  person "carried focus into the morning", which the facts do not say.
- Days marked "so far" (and the current week and month) are written in the
  past tense, where the instructions ask for the present.

Weeks and months (7 notes), where the model is much less reliable:

- It wrote most of the figures as words in 4 of 7 ("five hours and forty-six
  minutes", "thirty-one hours thirty minutes"); in 2 it dropped them ("Thesis
  for hours"). The digits-only audit read none of the spelled ones. All
  pass now that it reads them, because each is in the facts.
- One note invents a total. The week of 28 Sep says "other sessions for
  seventeen hours forty-one minutes": it seems to have joined the week's 17
  sessions to its 23h 41m. Both numbers are in the facts, so the audit
  cannot see it. The audit checks that a figure exists in the facts, not what
  it stands for; this is the limit of the design, and why the instructions ask
  the model never to total.
- Every pattern line is true. Stories list sessions with "then", as if in
  order, though the list is by time spent.

### Changes the probe prompted

- The audit now reads numbers spelled out in words (see §4 and §6), as the
  spec foresaw. Passing was 20 of 20 before and after.
- A week's or month's most-time list is now "name: duration" joined by
  semicolons, like the day's session list. Before, a name with a comma ran
  into the figures in the week of 28 Sep ("Reviewing the quarterly budget
  proposal with Priya, then sending notes 1h 35m"), and the story repeated
  names.

Tried and rejected on the fixture, without rebuilding the app: calling the
top apps "apps in front during these sessions" (the tips then told the person
to spend less time in Mail); durations in words and a shorter list (the
period notes stayed erratic: some figures dropped, some spelled out). Facts
alone did not make the period notes dependable.

### For Sir

- Whether week and month notes ship as they are, given the dropped figures and
  the invented total; the day notes read well apart from some weak tips.
- A first run was refused from the eleventh note on, with the system's
  "not executed due to current system state: CriticalMemoryPressure, try
  again later" (error 1013), while other builds held the Mac at a load average
  near 80. That is the Mac, not the note, but `NoteWriter` treats any thrown
  error as a failed note and remembers the facts as failed for the session, so
  under memory pressure an automatic note is never tried again until its
  facts change. The probe waited and asked again; the app does not.
- Merge waits on Sir's read of the above, and on hand checks 1 to 6.

### Second run (2026-10-11, after the fix wave)

The same 20 periods through the same harness, rebuilt from the fixed sources.
The audit is the typed one (§2). The bar Sir set for the wave: no invented
figure anywhere; week and month notes as specific and readable as day notes,
and kept; no reprimanding or nonsensical tip.

| | First run | Second run |
|---|---|---|
| Audit, days | 13 of 13 (digits and words only) | 13 of 13 (typed figures) |
| Audit, weeks and months | 7 of 7, one with an invented total and four with figures in words | 7 of 7, every figure in digits, none dropped, none invented |
| Latency | median 3.9 s, fastest 2.7 s, slowest 8.1 s | median 4.8 s, fastest 3.1 s, slowest 7.6 s |
| Day tips: mild reprimands | 5 of 13 | 0 of 13 |
| Day tips: nonsense | 2 of 13 | 0 of 13 (one is vague: "Use the time spent in Numbers to organise the quarterly budget proposal notes.") |
| Thrown errors | 10 of 20 under memory pressure in the first attempt, then retried by the probe | 0 |

The writer's state matched the audit's verdict for all 20, and greedy sampling
gave the same note each time. Latency is on a Mac that another session's
builds kept at a load average of about 20 to 100, so Hand check 1's 3 s bar
is still not met on a busy Mac.

An intermediate run marked each observation a tip may use with "(usable for a
tip)". Tips then echoed the mark ("Use the call to Mum at 10:30 am for a
tip.", "The 2-hour stretch in 2026 tax return at 2:00 pm is usable for a tip.")
though none scolded. The facts now list a pattern-only observation under
"Context:" and the others under "Observations:", with no mark. Two further
variants were tried on the fixture with the model and left out: putting
"Most app time was in …" under Context as well and relabelling the apps line
"Apps in front during these sessions" (the tips then pointed at Xcode and
Mail), and a tip guide asking for "a session named in the observations" (the
tips all became "set a timer for …", two with a duration the facts do not
hold, which the audit would drop).

| Place | Story | Pattern | Tip |
|---|---|---|---|
| Wed 7 Oct, digit names | You worked on Q4 plan v2 for 1 hour 30 minutes at 9:00 am, then Sprint 42 review for 1 hour at 11:00 am, and finally 2026 tax return for 2 hours at 2:00 pm. | The longest focus stretch was 2 hours in 2026 tax return, from 2:00 pm. | Review the 2026 tax return notes before starting the next session. |
| Fri 9 Oct, yesterday on the Yesterday notice ("For today:"), runs past midnight | You worked on Thesis at 9:00 am for 2 hours, then Parser at 2:00 pm for 1 hour 12 minutes, Email at 4:30 pm for 30 minutes, and Release 1.3 at 10:30 pm for 1 hour 30 minutes. | The longest stretch of focus was 2 hours in Thesis at 9:00 am. | You could set a timer for 1 hour 30 minutes for Release 1.3 next time. |
| Week of 28 Sep | You spent 11h on Thesis, 6h 36m on Parser, and 2h on Email. | You had your best day on Monday 28 September 2026 with 5h 18m. | not shown |
| September | You spent 68h on Thesis, 41h 48m on Parser, and 10h 30m on Email. | You had your best day on Tuesday 15 September 2026 with 9h. | not shown |

What is still weak, honestly:

- Every week and month pattern restates the best day, because its guide asks for the first listed observation. The longest stretch, the busiest weekday, the comparison and the goal days are in the facts but not yet in a note. The earlier guide ("exactly one of the listed observations") picked the goal line every time, "You met your goal on 3 of 7 days", which is true and bland; the best day is the more specific of the two.
- A day with one session and a top app (Sat 3 Oct) still reads the apps line as a second block of work ("then 1 hour 30 minutes in Books"). The figure is in the facts, so the audit cannot see the misreading; the audit checks that a figure is held, not what it measures.
- Several day tips read "Start the next session with Thesis at 8:00 am for 5 hours": concrete and not a reprimand, but pushy about a duration.
- The typed audit cannot see a figure attached to the wrong thing, such as the best day's focus given to another day.

### Third run (2026-10-11, after the review's fix round)

The audit now fails closed on amounts with no number and on a weekday that
does not match its date (§2), and a twenty-first period joined the fixture: a
week with one session and one name. The same harness, the sources as fixed.

| | Result |
|---|---|
| Audit, days | 13 pass, 0 fail |
| Audit, weeks and months | 8 pass, 0 fail |
| Notes the stricter audit rejects | 0 of 21: the model wrote every duration in digits, so no numberless amount or wrong weekday reached it (the first run's "Thesis for hours" would be rejected now) |
| Latency | median 3.2 s, fastest 1.6 s, slowest 6.2 s, total 68 s for 21 notes |
| Day tips | 0 mild reprimands, 0 nonsense (the same 13 as before) |

The one-session week was the finding. With the three-session guide, reworded
five ways, the note padded itself ("You spent 1h on Reading on Wednesday 29
July 2026 and 1h on Reading on Wednesday 29 July 2026."), and a two-session
week added "and 11h on Thesis again". Giving the sentence's form fixed both:
"You spent 1h on Reading." and "You spent 11h on Thesis and 6h 36m on Parser."
A three-session form that gave the sentence to fill was worse than the guide
for three: it wrote "You spent 11h 41m on Thesis", a figure the facts do not
hold, which the audit would have dropped.

## 6b. A day's note without a tip (2026-10-12)

Sir's Yesterday card for Sun 11 Oct read "5h 40m focus · goal missed · 4
sessions", a story that retold the session list, and "For today: Keep Coding
sessions running past midnight." The tip came from the observation "Focus
carried on past midnight with Coding": a session crossing midnight, which is the
calendar's doing, handed to a guide that asked for "one concrete action" every
day. The audit had only ever checked figures; nothing checked whether a tip was
worth reading.

Live probe, five fixture days (Sir's 11 Oct rebuilt, an ordinary day, nine short
sessions, a release past midnight, two long sessions), greedy, macOS 27.2:

| Facts | Tips | Audit |
|---|---|---|
| As shipped (§2) | 5 of 5 useless: "You could use Coding at 11:07 pm to start a new session", "Start the next session with Thesis at 9:00 am for 2 hours" | 5 pass |
| Baseline facts, tip only from a daytime observation | 3 of 3 still invented: "Try using Xcode for 4 hours today", "Try using the hands-on app feature in Xcode" | 2 fail, both on the tip |
| Baseline facts, no tip (built) | none | 5 pass |

So a day's note is now a story and a pattern, as a week's is. The facts name
where the time went (busiest three, as a week's do) instead of listing the
sessions in order, and weigh the day against the person's own typical day: the
median focus of the days with focus among the 14 before (three at least, as the
goal's pace baseline), the part of the day that held the most focus, stretches
against the typical stretch, and the longest stretch unless it carried over. The
figures line shows what the goal counted when it was missed ("5h 40m focus ·
3h 59m towards 4h goal"): the goal counts focus with hands-on use only, and on
11 Oct that was 3h 59m (probed on a copy of the live data), so "goal missed"
was right but read as a fault. Checks 956–960.

## 7. Hand checks

Run on Sir's build with Apple Intelligence on, before merge and after the
probe in §6a. Record results here.

| # | Step | Passes when |
|---|---|---|
| 1 | Open yesterday in History | Note appears within 3 s; every figure matches the cards |
| 2 | Open today's main window | Yesterday notice shows; Done hides it until tomorrow |
| 3 | End all sessions, press Wrap up today | Note appears, with no tip (§6b) |
| 4 | Open this week, press Write a note | Note appears; reopening shows the same note |
| 5 | Turn the switch off | Every note, link and notice disappears at once |
| 6 | Rename a session from yesterday, reopen yesterday | Note mentions the new name |

## Out of scope

- Projects 2–5, each in its own spec.
- Editing or keeping notes on disk, and asking for a different note.
- Cloud models, Private Cloud Compute and notifications.
