# Ask Daybook v2, part 2: lookups for everything Daybook records

Date: 2026-10-11
Status: design approved section by section on 2026-10-11; written spec awaiting review

## Why

Part 1 (`docs/specs/2026-10-11-ask-daybook-v2-chat-design.md`) made Ask a chat
whose answers list their sources. Its five lookups read focus totals,
comparisons, best hours, sessions and app time. Everything else Daybook
records, stores and shows is out of reach: working stretches, breaks, answers
about time away, app use by hour, what the Mac did, notes, work types, the
daily goal, the streak and awards.

Out of reach is worse than unanswered. Asked 32 questions about those things
with only part 1's lookups (probe, 2026-10-11), the on-device model routed none
of them to a lookup that could answer and invented answers for most: "Your Mac
went to sleep on Friday at 9:00 am", "Your current streak is 2 days", "You
have focused on 52 days in a row", "Yes, you met your daily goal yesterday".
None of those came from any record.

Part 2 adds the lookups, each answering from the reader the screen that shows
the figure already uses, and each pointing to that screen. Insights (part 3)
and the user's own cloud key (part 4) are not part of it.

## Decisions

| Question | Decision |
|---|---|
| Shape of the catalogue | **One lookup per screen** (chosen): part 1's five, two of them saying what they now add, and three new ones that mirror the day story, the session report and the goal and awards tiles. Measured against the alternatives below. |
| Rejected: one lookup per kind of data | Fifteen tools take 2,325 of the model's 4,096 tokens before the first question; one full lookup result is about 436. Apple's guidance is three to five tools. |
| Rejected: one catch-all lookup with a `kind` argument | Fewer tokens (1,339), but the model reached the right data for 17 of 32 questions against 26 of 32 for one lookup per screen, filed battery questions under Mac events, and still invented ("Your longest streak ever was 152 days"). |
| Rejected: two passes, a family first | A second model pass per answer (1 to 2 s), or brittle keyword routing; the tools would change between follow-ups, rebuilding sessions. |
| The period guide | Part 1's wording, byte for byte, on every lookup. A shorter shared guide would have saved 230 tokens, but with it the model sent `all time` for "today", "this month" and "Friday", and answers on part 1's baseline went wrong ("You focused for 30 hours and 43 minutes today"). |
| Part 1's lookups | Names, parameters and the period guide unchanged. Two descriptions gain a sentence. Their facts may change wording (not figures); parity means every baseline answer is still right, not byte-identical. |
| Instructions and sampling | Unchanged, byte for byte. Misroutes are answered in the facts, not in the instructions. |
| Where a source opens | Where its figure is shown: History for days, sessions and periods, as in part 1; the Awards sheet for the streak and awards, which History does not show. |

## Evidence (2026-10-11)

The live on-device model (M1 Pro, macOS 27.2) in a temporary copy of the
tree with part 1's `--askprobe` entry and the fixture history of 1 August to
Saturday 10 October 2026 (clock 5:30 pm). New lookups were stubs returning
fixed facts, so these runs measure routing and parity, not the facts. Nothing
from the probe copies is committed.

### Token cost (`SystemLanguageModel.tokenCount`, context 4,096)

| | Tools | Tokens |
|---|---|---|
| Instructions | | 283 |
| Part 1's five | 5 | 1,131 |
| One lookup per kind (part 1's + ten) | 15 | 2,325 |
| One per screen, short period guide | 8 | 1,231 |
| One catch-all, short period guide | 6 | 1,065 |
| **One per screen, part 1's guide (chosen)** | 8 | **1,593** |
| One catch-all, part 1's guide | 6 | 1,339 |

One lookup result at the 1 KB cap is about 436 tokens. With the chosen
catalogue, 2,220 tokens remain for the chat after the instructions and tools
(part 1: 2,682); part 1's chat filled at turn 24, so about 19 or 20 turns are
expected before the carry-over (probe 3 measures it).

### Routing, 32 questions about the new data (3 or 4 for each kind)

| Catalogue | Right lookup reached | Right lookup first |
|---|---|---|
| Part 1's five | 0 | 0 |
| One per screen, short guide | 26 | 9 |
| One catch-all, short guide | 16 | 10 |
| **One per screen, part 1's guide** | **26** | **10** |
| One catch-all, part 1's guide | 17 | 8 |

With the chosen catalogue the model often looks up focus totals first and the
right lookup second (16 of the 26): one extra lookup, within the cap of five.
The six it missed, and where the facts answer them (section 2):

| Question | Lookup it chose | Answered by |
|---|---|---|
| How many days in a row have I focused? | `focusTotals`, all time | the all-time totals name the current streak |
| Did I write a note about the tokenizer? | `focusTotals`, words | totals for words name the note line that matched |
| Which hours was Safari in front yesterday? | `focusTotals`, words Safari | words that name an app bring its hours |
| When did I use Mail on Friday? | `findSessions`, words Mail | already answerable: the Email session's line, from 4:30pm, is when Mail was in front; probe 1 checks the answer |
| How did I answer when Daybook asked where I'd been yesterday? | `findSessions` | `dayEvents`' description names where the user was |
| Was I plugged in while working on the Parser on Friday? | `findSessions`, `appTime` | `sessionDetail`'s description names whether the Mac was plugged in |

"What notes did I write in September?" and "Show me my notes from last week."
reached `findSessions`, which today shows a note only when it holds the
searched words; each listed session now shows its note.

### Parity, part 1's 37 baseline questions

| Catalogue | Same lookups as part 1 | Same answer text |
|---|---|---|
| One per screen, short guide | 18 | 12, several wrong: today 30h 43m, Thesis this month 115h, "31 Feb" no longer refused |
| One catch-all, short guide | 17 | 10, wrong in the same way |
| **One per screen, part 1's guide** | **29** | **20**; every other answer has the same figures in other words ("60 hours and 54 minutes" for "60h 54m"), except "Is that true for Mondays too?", which became "You focused best from 9–11 am on 10 Oct" (part 1: "The strongest day was Tuesday, not Monday"), and "What did I do on 3 October?", which repeated the stub's fixed breaks |
| One catch-all, part 1's guide | 30 | 16 |

"What did I work on that day?" still reads Parser "2 hours" for a 4-hour
session that began at 2:00 pm, as in part 1; section 2's time wording answers it.

### Running the model beside other work

The on-device model refuses every request with `CriticalMemoryPressure` while
the Mac is short of memory; on 2026-10-11 runaway snapshot processes from
another branch held 11 to 22 GB each and one full run failed 207 of 207. The
probe asks a refused question again a few seconds later, and its logs record
how often. Probe results with refusals are not counted.

## 1. The catalogue

Part 1's five first, in their order, then the three new ones. Names,
parameters, parameter descriptions, optionality and the period guide of the
five are unchanged.

| # | Lookup | Description (what the model reads) | Parameters |
|---|---|---|---|
| 1 | `focusTotals` | Part 1's, then: "Also gives the time in each work type." | as part 1 |
| 2 | `compareFocus` | Part 1's | as part 1 |
| 3 | `bestHours` | Part 1's | as part 1 |
| 4 | `findSessions` | Part 1's | as part 1 |
| 5 | `appTime` | Part 1's, then: "Also gives the hours of the day it was in front." | as part 1 |
| 6 | `dayEvents` | "Lists what happened between sessions in a period: breaks, time away from the Mac with what the user said they were doing and whether it counted as focus, and what the Mac did, such as sleep, lock, restart or a crash, with their times." | `range` (required; part 1's guide) |
| 7 | `sessionDetail` | "Returns the detail of sessions in a period: each working stretch with its start and end, its note and its battery reading, such as whether the Mac was plugged in." | `range` (required; part 1's guide); `words` (optional): "Words from the session's name, such as thesis; leave out for every session" |
| 8 | `goals` | "Returns the daily goal, progress towards it today, the days a period met it, the current and longest streak, and the awards earned and still to earn." | `range` (optional): part 1's guide + "; leave out for all time" |

`AskRequest` gains `dayEvents(AskRange)`, `sessionDetail(AskRange, words:)`
and `goals(AskRange?)`, read through `AskRange.resolving` as part 1's are;
a period still to come is answered with part 1's "… is still to come." and a
date the calendar lacks with "There is no such date as …". Their provenance,
which the progress line shows: `what happened (Friday)`, `session detail
matching “thesis” (Friday)`, `goals (September 2026)`, `goals`.

## 2. The facts

Rules kept from part 1: `AskFacts` words every fact in code; each is held to
1 KB, cut at a line or `; ` with "…"; finished periods are spoken of in the
past tense; the model never adds, subtracts or averages. Every figure comes
from the reader the screen that shows it uses, so an answer cannot differ from
the screen.

Durations are written as everywhere in Daybook (`DurationText.compact`: 4h, 1h 12m, 45m).
New rule: a clock time is never written bare beside a duration. A start reads
"from 2:00pm", an end "to 3:12pm", an instant "at 11:48pm".

### `dayEvents`

Readers: Story's day projection (breaks), `storyTimelineItems(on:)` (answers
about time away and absences not yet answered, with the receipt's own title),
and `macAccount(on:)` (the "What the Mac did" card's rows and summary). Days
are walked in the store's period calendar.

One day, in time order:

```
Fri 9 Oct:
from 10:40am to 11:05am · away · answered “Meeting”: Counted as focus, 25m
from 12:25pm to 1:10pm · break “Lunch” · 45m
Mac locked from 12:25pm to 1:10pm
from 4:10pm to 4:30pm · away · answered “Coffee”: Recorded as a break
Mac asleep from 11:48pm until midnight
No restart or shut down was recorded.
No crash was recorded.
```

A longer period, one line per day with anything to tell, newest first:

```
Fri 9 Oct · 2 breaks, 1h · 2 answers about time away · Locked 45m · Asleep 7h 50m
Thu 8 Oct · 1 break, 15m · Mac off
Newest 2 of 9 days.
```

- A longer period lists whole days, newest first, as many as the 1 KB cap
  holds, and ends with "Newest N of M days." when it cannot hold them all.
  One day's lines, cut by the cap, end with "…" as part 1's facts do.
- An unnamed break reads "break". An absence not yet answered reads "away,
  not answered yet".
- Mac events exist from the event log's first day; a period that starts
  before it adds "The Mac's events are recorded from Thu 8 Oct 2026.", and one
  wholly before it says "No Mac events were recorded before Thu 8 Oct 2026."
- A Mac row leads with its title and words its times after it: `Mac locked
  from 12:25pm to 1:10pm`, `Mac asleep from 11:48pm until midnight`, and `Mac
  woke at 7:52am` for an instant. With the times first, the model read “from
  11:48pm to 12:00am · Mac asleep” as the Mac going to sleep at 12:00am. A
  day's own edges read `midnight` instead of 12:00am, “until midnight” for an
  end and “from midnight” for a start, for breaks and answers too.
- A crash or power loss is told as the card tells it, found at the next start,
  and keeps its own shape: `from 8:00am to 8:02am · Daybook crashed · some
  time in this window; found when Daybook opened at 8:02am`.
- A period the event log covers (from its first day on) ends, before any
  “Newest N of M days.”, with what the log did not record: “No restart or shut
  down was recorded.” when it holds no restart, shut down, restart or shut
  down not named, power-off not named, power loss, restart after a problem,
  start-up or macOS update, and “No crash was recorded.” when it holds no
  crash, force quit, power loss or restart after a problem. The model had read
  a list with no restart in it as a yes. A period wholly before the log, or no
  log at all, says neither.
- Nothing to tell: "No breaks, time away or Mac events recorded on Friday."

### `sessionDetail`

Reader: the journal's sessions for each day (Story's day projection, the
running session included), the session's saved stretches, and
`sessionMetadata(for:)` for each stretch's note and battery reading, worded as
the session report words its power line. Sessions matching `words` are found
the way part 1's search finds them, and only their days are read. Newest
first, at most ten.

```
Thesis · Fri 9 Oct · 2 stretches: from 9:00am to 10:40am, 1h 40m, battery 82% to 61%, note “chapter three, fixed citations”; from 11:05am to 12:25pm, 1h 20m, plugged in 61% to 88%
Parser · Fri 9 Oct · 1 stretch: from 2:00pm to 3:12pm, 1h 12m · no note · no battery reading
```

- More than ten sessions, or more than the 1 KB cap holds, ends with "Newest
  N of M." naming how many were listed.
- The running session reads "running from 1:00pm, 1h 30m so far".
- A session none of whose stretches has a note ends with " · no note", and
  one none of whose stretches has a battery reading ends with " · no battery
  reading" (both, in that order, when both are missing). The running stretch
  counts like any other. Silence read as a yes: asked whether it wrote notes
  or was plugged in, the model answered yes for sessions that had neither.
- No session: part 1's "No sessions match “…” on Friday." or "No sessions
  recorded on Friday."

### `goals`

Readers: the daily goal setting; goal credit for a day (focus during recorded
app use, the Story goal tile's figure); the days-met count History's goals
tile uses, against today's goal; the archive's current and best streak on the
store's clock (a day counts at the streak minimum, not the goal); the Awards
sheet's awards, by title and detail.

```
Daily goal: 4h of focus during recorded app use. Today so far: 3h 20m, 83%, not met yet.
September 2026: met on 14 of 30 days, against today's goal.
Current streak: 5 days with at least 1h of focus, since Mon 5 Oct. Longest: 12 days.
Awards earned: Goal, 10 days; Longest stretch. Still to earn: 500 hours focused, 312h so far.
```

- With no period, the second line is left out.
- A streak that ended yesterday is still current, as the archive counts it.

### Part 1's facts, extended

| Lookup | Adds |
|---|---|
| `focusTotals` | "By work type: Deep work 88h 30m, Admin 11h." from History's period categories. Words that name a work type ("deep work", "admin") already give that type's total: History's search matches a session by its work type's name. All time adds "The current streak is 5 days, since Mon 5 Oct." Words that name an app add that app's busiest hours, as `appTime` gives them. Words found in a note add the note's line. |
| `appTime` | A named app: its busiest hours over the period, from History's app lens: "most in front from 2pm to 3pm (31h 20m), then from 3pm to 4pm (24h 5m) and from 10am to 11am (6h 40m)". No app, one day: the rail's busiest hours that day. No app, a longer period: no hours, as no screen shows them. |
| `findSessions` | Lines read `Tue 15 Sep · Parser · from 2:00pm · 4h`. Each listed session shows its note's first line, not only a note that matched the words; a matching line still wins over the first. |

## 3. Sources

| Lookup | Sources, in this order (the first is the anchor) | Role |
|---|---|---|
| `dayEvents` | the period asked about; each day listed | What happened |
| `sessionDetail` | the period asked about; each session listed | Stretches |
| `goals` | today, or the period asked about; Awards | Daily goal; Streak and awards |
| `focusTotals`, `appTime` | as part 1 | as part 1 |

The picker of part 1 is unchanged apart from one naming rule: **Awards** is
named when the answer says "streak", "award", or an award's title, whole words,
ignoring case. Without it, an answer about the streak would list only today.

`AskLink.Target` gains `awards`. Following it opens the Awards sheet
(`open(tab: .awards)`): in the sheet placement the Ask sheet gives way to it
and ⌘K brings the chat back; in the panel placement it covers the window,
panel included, as Settings does, and closing it returns to the panel. Part 1's
rule "every source opens History" becomes: every source opens where its figure
is shown.

```
Sources
1  ▦  September 2026        Daily goal          ›    calendar glyph, opens History
2  ✪  Awards                Streak and awards   ›    rosette, opens Awards
```

- Glyph `rosette`, the one Awards already uses, in the supporting ink as
  the other glyphs; label and role as part 1's rows, the same height and target.
- VoiceOver: "Awards, streak and awards. Opens Awards."

## 4. Parts

| Layer | File | Change |
|---|---|---|
| Core | `AskFacts.swift` | The request cases and provenance; the time wording; `findSessions` lines. The new facts go to sibling files to keep each under 300 lines: `AskFacts+DayEvents.swift`, `AskFacts+SessionDetail.swift`, `AskFacts+Goals.swift`. |
| Core | `AskLink.swift` | `awards` target; roles What happened, Stretches, Daily goal, Streak and awards. |
| Core | `AskSourcePicker.swift` | The Awards naming rule. |
| App | `AskLookups.swift` | The three entries and the two description sentences. |
| App | `SessionStore+AskDayEvents.swift`, `+AskSessionDetail.swift`, `+AskGoals.swift` | Read the screens' readers into the new facts; no writes. |
| App | `SessionStore+Ask.swift`, `+AskClips.swift`, `+AskLinks.swift` | Dispatch; the extended facts; the Awards link. |
| App | `MainWindowModel+Ask.swift` | `follow` opens Awards for the Awards target. |
| Surfaces | `Ask/AskSourcesView.swift` | The rosette and the VoiceOver line. |
| Docs | `README.md` | Ask's paragraph names what it can answer. Privacy is unchanged: on-device, nothing sent. |

Rules kept: no lookup writes; views bind to `AskModel` and `MainWindowModel`
only; `AskModel` is built on the first ⌘K; lengths are tokens or `.zoomed`.

## 5. Proof

### Fixture

Part 1's history, plus, on Fri 9 Oct and the days around it: a Thesis session
of two stretches with notes and battery readings; breaks, one named Lunch;
three answers about time away (counted as focus, recorded as a break, left
uncounted) and one absence not yet answered; a Mac event log from Thu 8 Oct
with sleep, wake, lock, a restart and a crash found at the next launch; a 4h
goal; a streak; awards earned and still to earn. The probe and the checks
build it the same way.

### Live-model probes

In a temporary copy of the tree with the `--askprobe` entry, a watchdog on
every run and the memory-pressure retry; recorded in this spec before the pull
request.

| # | Probe | Passes when |
|---|---|---|
| 1 | The 32 questions about the new data and one question for each of the six misses, through the real lookups | At least 28 of 32 reach the right lookup; no answer states a figure, time, date or name the lookups did not return; each answer's sources include the place it names |
| 2 | Parity: the 37 baseline questions, three runs | Every answer right; "What did I work on that day?" gives Parser 4h |
| 3 | Depth: part 1's ten follow-ups, three times (30 turns) | The turn where the context fills is recorded; the carried turn is answered rightly |
| 4 | Speed, on a quiet machine | Median no more than 1 s over part 1's 3.7 s; no answer over 10 s; the share of answers with the extra first lookup recorded |

### Checks

New suites, appended at the end of `registeredTests`; numbers are assigned
when they merge. Each uses `TestClock`, `SelfTest.scratchDirectory()` and
`MemoryDefaults`, builds dates from the calendar the code uses, and runs under
`TZ=Europe/Berlin` too.

| Suite | Fails when |
|---|---|
| `AskDayEventsChecks` | lines are out of time order; a break, an answer (with its receipt title) or a Mac row is missed or misworded; a longer period is not one line per day, newest first, with "Newest N of M days."; the Mac log's first day is not said for a period that starts before it; sources miss the period or a day |
| `AskDayEventsAbsenceChecks` | a Mac row does not lead with its title; a day's edge reads 12:00am instead of midnight; a restart or crash the log holds is denied, or one it lacks is not said; a period before the log, or with no log, denies anything |
| `AskSessionDetailChecks` | a stretch's start, end or work is wrong; a battery reading or note is missed or worded unlike the report; a session lacking a note or a battery reading does not say so; the running session is not "running"; more than ten are listed without "Newest 10 of N." |
| `AskGoalsChecks` | progress is read from focus instead of goal credit; days met are not counted against today's goal; the streak is read from the wall clock instead of the store's; an award's title or detail differs from the Awards sheet; the Awards source is missing |
| `AskFactsExtensionChecks` | work types or a work-type total differ from History; app hours differ from the app lens or the rail; a clock time stands bare beside a duration; a listed session hides its note or battery reading; the all-time streak is missing; any new fact passes 1 KB |

Updated: `AskCatalogueChecks` (eight entries in order; part 1's five
byte-identical apart from the two exact sentences), `AskSourceOrderChecks`
(Awards named by "streak", "award" and a title, not by a word that only
contains one), `AskFollowChecks` (the Awards target opens Awards in both
placements and leaves the chat as part 1's sources do), `AskLookupLinkChecks`
(the new sources).

Mutations before commit, each in a temporary copy of the tree: the streak
read with the wall clock; the goal judged on focus; the Awards naming rule
removed. Each must fail a check.

`fix-reviewer` reviews the change before commit: it adds time arithmetic (day
walks, streak dates) and reads the goal setting.

### Snapshots and design review

`--snapshot` scenarios for an answer whose sources include a day, a session
and Awards, in the sheet and the panel; light and dark, at 80%, 100% and 140%.
The renders get a design critique before the pull request; fixes go in the
same pull request.

### Hand checks

Run by Claude on an isolated fixture app built with
`scripts/build-fixture-app.sh`, addressed by pid, never outside its window,
never the installed app:

| # | Do | Passes when |
|---|---|---|
| 1 | Ask one question for each new lookup | Each is answered from the fixture with its sources |
| 2 | Follow a day, a session and the Awards source, in the sheet and in the panel | Each opens its place; Awards opens the Awards sheet and closing it returns to the chat |
| 3 | Read the Awards row with the accessibility tree | "Awards, streak and awards. Opens Awards." and a press action |

## 6. Copy

| Element | Copy |
|---|---|
| Progress | Looking up what happened (Friday)…; Looking up session detail (Friday)…; Looking up goals… |
| Roles | What happened; Stretches; Daily goal; Streak and awards |
| Awards source | Awards |
| VoiceOver, Awards source | Awards, streak and awards. Opens Awards. |

## Working beside other projects

- Files are claimed on the sessions board before editing; the change ships by
  pull request after merging main, through the review session.
- Expected overlaps when merging main: the registry tail; `AskSourcesView`
  with any session changing supporting ink; `MainWindowModel` with History
  search work.

## Out of scope

- Insights, patterns, advice and explaining a day (part 3); cloud models and
  keys (part 4).
- New data: Ask reads only what Daybook already records.
- Settings and activity rules as answers ("which apps start Coding?").
- Instruction changes; the model writing anything.
