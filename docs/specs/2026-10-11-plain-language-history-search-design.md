# Plain-language History search

Date: 2026-10-11
Status: built; hand checks pending (2026-10-12). Weekday days added 2026-10-12 (§7).

## Why

History's search box matches every word of what is typed against a
session's names, notes, apps, date text, time of day and power source. That
finds "Thesis", "Monday" or "October", but "last week", "on Mondays" or
"over 1h" find nothing, because no session's text holds those words.

This is project 2 of the Apple Intelligence roadmap
(`docs/specs/2026-10-10-apple-intelligence-notes-design.md`, "Projects, in
order"). Ask v2 already answers questions with links into History; this
project makes the search box itself read the phrases people type, on every
Mac, and uses the on-device model only to rescue phrasings code cannot read.

## Decisions

| Question | Decision |
|---|---|
| Job | The search box reads dates, recurring weekdays, length and exact app or category names out of the typed text and turns them into filters. Leftover words search as today. |
| Rejected: full model search | Hidden on Macs without the model, about 3 s a search, and a model misreading becomes a silent wrong filter. |
| Rejected: fold into Ask v2 | Ask answers questions; the search box lists sessions. Both are wanted. |
| Approach | A pure Core parser handles every phrase kind on every Mac. On an Apple Intelligence Mac, the model runs only when Return is pressed, words are left over, and nothing matched; it proposes phrases, and the parser must accept each one. |
| Rejected: parser only | Works everywhere, but phrasings outside the grammar stay unread. |
| Display | Chips under the search field, one per understood phrase, with exact dates on period chips. × on a chip removes that phrase from the field text. |
| Rejected: one summary line; silent filtering | A summary line cannot drop one part; silent filtering hides a misread. |
| Source of truth | The field's text. Chips and filters are derived from it on every change. |
| Shared rules | The roadmap's rules hold: on-device only, `ModelGate` plus the "Use Apple Intelligence" switch, nothing drawn for AI on Macs that cannot run it, the Apple Intelligence mark on anything the model produced. |

## 1. Parts

| Layer | File | Responsibility |
|---|---|---|
| Core | `Sources/Core/SearchQuery.swift`, `SearchQueryGrammar.swift`, `SearchQueryPeriods.swift`, `SearchQueryTokens.swift` (new) | `SearchQuery.parse(_ text:, now:, calendar:, apps:, categories:) -> ParsedSearch`. Finds phrases (§2) by longest match, left to right, skipping quoted text. Returns `span: DateInterval?`, `weekdays: Set<Int>?`, `minLength`/`maxLength: TimeInterval?`, `appBundleID`, `workType`, `leftover: String` and `phrases: [SearchPhrase]` (text range, kind, chip label). Named months, days and years go through `AskRange.resolving`; the relative periods (today, last week, N days ago, past weekends, …) are built directly from the period calendar in `SearchQueryPeriods.swift`. Number words go through `NoteNumberWords`. Pure; no App types. |
| Core | `Sources/Core/HistoryStats.swift` | `HistoryFilter` gains `span`, `weekdays`, `minLength`, `maxLength`; `isActive` counts them; `apply(to:)` honours span and weekdays for the map. |
| App | `Sources/App/SessionStore+HistoryFind.swift` | `historySearchHits(matching:)` applies span (`holds` on the session-day), weekdays (of the session-day) and length (the session-day's focused seconds, pauses excluded, as its card shows). The empty-filter guard becomes "no filter active". |
| App | `Sources/App/SessionStore+HistoryQuery.swift` | `setHistoryQuery(_:)` and the menu state live here, not in `+Review`. It keeps the raw text in a published `historySearchText`, parses it, and sets the filter (leftover words into `query`; a typed app or category name is held beside the menus' own picks, `historyMenuApp` and `historyMenuWorkType`, and the typed name wins while it is in the text). |
| App | `Sources/App/SearchRescue.swift` (new) | On Return: if `ModelGate.modelAvailable`, the switch is on, leftover words remain and hits are zero, one greedy `LanguageModelSession` call returns `@Generable struct RescuedSearch { phrases: [String]; keep: [String] }` for the leftover words: phrases in the forms the instructions list, and the typed words worth keeping as search words. Each phrase is parsed on its own; only a phrase the parser reads as exactly one period, weekday or length phrase is kept (an app or category is never taken). Kept words must be a subset of the leftover words: the model can drop words, never add them. Accepted phrases replace the leftover words in the field, beside the kept words (one undoable change); the chip is marked as from Apple Intelligence. A reply with no accepted phrase changes nothing. The wait ends after about 10 s (a sleeping timer, so a model that ignores cancellation cannot hold it), leaving the text untouched and the spinner cleared; editing the text cancels it, and a late reply changes nothing. The rebuilt text is parsed again with the store's own reading and committed only if it reads as the phrases already there, then the model's, then the kept words, so no chip the model made lacks its mark. `responder` seam for checks. |
| Surfaces | `Sources/Surfaces/History/HistorySearchChips.swift` (new) | The chips row under the search field: label, × button, the app icon or category colour, the Apple Intelligence mark on rescued chips. |
| Surfaces | the History search field's view | Binds to `historySearchText`, submits Return to `SearchRescue`, places the chips row. |

Rules kept: views never parse or compute; the 1 Hz ticker never runs the
parser or the model; files under 300 lines; lengths are tokens or `.zoomed`;
`Sources/App/ModelGate.swift` stays byte-identical (another branch copies it).

## 2. Grammar

Case-insensitive, English, any order, mixed with free words. The one exception is an app or category name, which is read only when typed with its own leading capital.

| Kind | Phrases | Chip |
|---|---|---|
| Period | today, yesterday; this/last week, month, year; the week/month before last; N days/weeks/months ago ("back" reads as "ago": "three weeks back"); last N days/weeks; a fortnight (two weeks): last/past fortnight (the 14 days ending today), "a fortnight ago" and "N fortnights ago" (the calendar week 2N weeks back), the fortnight before last (the 14 days before those); past weekends: last weekend, this/the past weekend, the weekend before last (Saturday to Sunday, Monday weeks); a month name with or without a year ("September", "Sept 2025"); a day and month with or without a year ("3 October", "3 Oct 2025"); a year ("2025"); one weekday as a day (§7): last Tuesday, (this, the) past Tuesday, this Tuesday, the Tuesday before last, Tuesday or on Tuesday; a day as the search text writes it, `d/M/yyyy` ("31/8/2026") | `Last week · 6–12 Oct`, `Last Tuesday · Tue 6 Oct`: the label plus the exact dates |
| Weekdays | a plural weekday ("Mondays"), "on Mondays", "Mondays and Fridays", "weekends", "weekdays" | `Mondays`, `Weekends` |
| Length | over / longer than / more than / at least D; under / shorter than / less than / at most D; between D and D. D: 1h, 1 h, 1 hour, 90m, 90 min, 1h 30m, 1.5h, "an hour", "half an hour", "an hour and a half", "two and a half hours", number words | `Over 1h`, `30m–1h` |
| App | the exact name of an app with recorded use (`historySortedUsage`), multi-word names included, typed with its leading capital ("Notes" is the Notes app; "notes" is a word) | the app's name with its icon |
| Category | the exact name of a category, typed with its leading capital | the category's name with its colour |

- "Weekends" alone is still the weekday set (Saturdays and Sundays of any
  week); "last weekend" and the other weekend phrases above are periods.
  Future weekends ("this weekend", "next weekend") are not phrases.
- A lone weekday ("Monday", "on Monday") is the latest Monday up to today,
  inside the other periods when the text has any (§7). Until 2026-10-12 it
  was not a phrase and searched as a word, which matched every Monday;
  "Mondays" says that now.
- A named month or day without a year takes its year from the other period
  phrases in the text when they pin one (the latest such occurrence inside
  their intersection that is not in the future); otherwise it is the most
  recent one not in the future. "September last year" is September of last
  year; "September" alone is the latest September.
- Month names are periods in any case: "may" and "march" read as months.
  Quote the word to search it.
- Text in double quotes is never parsed: `"Xcode"` searches the word.
- Several periods intersect; if they do not overlap the list is empty and
  "No overlap" shows as a caption after the chips.
- Length bounds are inclusive: a session of exactly the bound passes "over"
  and "under". The chips still read "Over" and "Under".
- Weekday phrases anywhere in the text union ("Mondays ... Fridays" lists
  both). Several length phrases combine as the strictest.
- Spans and weekdays use the calendar History builds its places with, and
  `DateInterval.holds` (half-open).

## 3. Behaviour

| Case | Behaviour |
|---|---|
| Only phrases, no words | Every session matching the filters is listed. |
| Length filter | Focus sessions only; breaks join only through words or the Break category, as now. |
| Running session | Search has never listed the running session, and still does not; it joins the results, length filter included, once it ends. |
| Chip × | Removes the phrase's text range from the field; the filter follows. |
| Typed app or category | The effective filter is the typed name if one is typed, otherwise the menu's pick; the menus keep their own choice. × on its chip removes the name from the field. Choosing in a menu removes any typed name of that kind from the field, so the text and the menu never disagree. |
| AI rescue accepted | Only a period, weekday or length phrase is accepted. The leftover words become the accepted phrase text, plus the words the model kept (a subset of the typed ones), in the field, as one undoable change; ⌘Z restores the original. The chip carries the Apple Intelligence mark. |
| AI rescue rejected, failed or model unusable | Nothing changes; no message. |
| Typed text read again | The filter is read again from the text, not only when it is typed: when History opens, when the day or the time zone changes (the tree's top moves and History reconciles), and when app names load. So a typed "yesterday" or "this week" follows the clock, and an app name typed before the names loaded becomes a chip. Nothing is published when the reading is unchanged, and the 1 Hz ticker never does it. |
| Model chooses a valid but wrong phrase | Not detectable by the parser; the chip's exact dates and mark make it visible. Measured by the live probe. |

## 4. Privacy

The leftover words go only to `SystemLanguageModel.default` on the Mac,
only on Return. Nothing is stored.

## 5. Checks

| Check | Fails when |
|---|---|
| Grammar | Any row of §2 is not read, or reads the wrong span, weekdays, length, app or category |
| Leftovers and quotes | Free words are lost, or quoted text is parsed |
| Longest match | "the week before last" reads as "last week" plus words |
| Intersection | "September last year" is not September of last year; disjoint periods do not read "No overlap" |
| Weekday days | "last Tuesday", "Tuesday", "this Tuesday" or "Tuesday before last" reads the wrong day on any weekday, in any zone or across a daylight-saving day, or "Tuesdays" stops being every Tuesday (§7) |
| Zones and DST | A span or weekday shifts in `TZ=Europe/Berlin` or across a daylight-saving week (fixtures built through the calendar) |
| List and map agree | `historySearchHits` and `HistoryFilter.apply` disagree on span or weekdays |
| Phrases only | "last week" lists nothing |
| Length | Pauses count toward length, or breaks pass a length filter |
| Typed app | A typed name does not win over the menu's pick, or a menu pick leaves the typed name in the field |
| Rescue | An accepted phrase does not rewrite the text or lacks the mark; a rejected one changes anything; the model is called with hits, with the switch off, or with no leftover words |
| Views | `--snapshot` with chips breaks at 80% or 140% zoom, light or dark |

Live probe: 20 phrasings outside the grammar ("fortnight before last",
"first week of September", "the last three Mondays", …) through the rescue.
Target: at least 18 rescued to the right filter or honestly left alone, every
rescue visible as a marked chip, none accepted that the parser rejected.
Results: §5a (first run 18 of 20; second run, after the grammar additions,
20 of 20).

## 5a. Live probe

### First run

Run 2026-10-12 on macOS 27.2 (build 26B5101f), a MacBook Pro with an Apple M1 Pro,
through `SearchRescue`'s live path: the real `SystemLanguageModel.default`,
the Apple Intelligence switch on, no `responder`. The store is the rescue
checks' fixture (Wed 15 Nov 2023, Monday weeks, three sessions). Each phrasing
was typed, Return pressed once, and the field read afterwards. A second run
gave identical replies (greedy). A rescue took 0.9–1.5 s; the model answered a
bare "Say OK" in 3.9 s. "Model said" is the phrases the model returned; the
parser took only those under "Taken".

| # | Typed | Model said | Taken | Field after Return | Verdict |
|---|---|---|---|---|---|
| 1 | fortnight before last | two months ago | two months ago | two months ago fortnight (Two months ago · 1–30 Sep) | wrong: a fortnight is two weeks, not two months |
| 2 | first week of september | first week of | none | unchanged (the parser read "september") | nothing |
| 3 | the last three mondays | last 3 | none | unchanged (the parser read "mondays") | nothing |
| 4 | past fortnight | two weeks ago | two weeks ago | two weeks ago (Two weeks ago · 30 Oct – 5 Nov) | wrong: one week two weeks back, not the last 14 days |
| 5 | a month ago | not asked | none | unchanged (the parser read it: A month ago · 1–31 Oct) | nothing |
| 6 | this past weekend | last weekend | none | unchanged | nothing |
| 7 | three weeks back | three weeks ago | three weeks ago | three weeks ago (Three weeks ago · 23–29 Oct) | right |
| 8 | early october | early | none | unchanged (the parser read "october") | nothing |
| 9 | since monday | since Monday | none | unchanged | nothing |
| 10 | the 1st | 1st | none | unchanged | nothing |
| 11 | longer than an hour and a half | and a half | none | unchanged (the parser read "longer than an hour" as Over 1h) | nothing |
| 12 | quick ones under ten minutes | quick ones | none | unchanged (the parser read Under 10m) | nothing |
| 13 | mornings last week | this week mornings | none | unchanged (the parser read Last week) | nothing |
| 14 | xmas | this time of year | none | unchanged | nothing |
| 15 | new year's day | a year; 1 january | 1 january | 1 january (Sun 1 Jan 2023) | right: the latest New Year's Day |
| 16 | q3 | q3 | none | unchanged | nothing |
| 17 | the weekend before last | last weekend | none | unchanged | nothing |
| 18 | last tuesday's sessions | last tuesday's sessions | none | unchanged | nothing |
| 19 | two months back | last 2 months ago | none | unchanged | nothing |
| 20 | parser stuff from last fortnight | last fortnight | none | unchanged | nothing |

Counts: right 2, nothing 16, wrong 2, accepted but rejected by the parser 0.
Right or honestly nothing: 18 of 20, which meets the target of 18 and no more.
The rescue changed the field on 4 of 20 phrasings, and 2 of those 4 were wrong.

Valid but wrong, both visible as a marked chip with exact dates:

- "fortnight before last" became "two months ago" (September); the person
  meant the two weeks before last week.
- "past fortnight" became "two weeks ago" (30 Oct – 5 Nov); the person meant
  the last 14 days, which "last 2 weeks" would have said.

What the first run also showed:

- The model often names the right period in words the grammar lacks ("last
  weekend", "since Monday", "last fortnight"); the parser rejects those, and
  the field stays as typed. "Fortnight", "last weekend", "since" and quarters
  are not in the grammar.
- Rows 2, 3, 8, 11, 12 and 13 had a phrase the parser already read, with
  other words left over and no hits. The rescue found nothing to add and left
  the field alone. Row 11 stays at "Over 1h" for "longer than an hour and a
  half" because the parser, not the rescue, read "an hour" first.
- Row 5 was read by the parser alone and lists a session, so the model is not
  asked.
- The first run's hand check 5 used "three weeks back" because "fortnight
  before last" was rescued wrongly; the second run moved it (§6).

### Second run (after the grammar additions)

Run 2026-10-12 on the same Mac and the same fixture, with the same twenty
phrasings, after the parser learned fortnights, "back", past weekends and
half hours (§2). A phrasing the parser now reads in full never reaches the
model ("not asked" in the Model column); the verdict then judges the parser's
chip. The model was asked on the other twelve: 0.9–1.4 s each, median 1.0 s;
the bare "Say OK" took 3.4 s.

| # | Typed | Parser reads | Model said | Field after Return | Verdict |
|---|---|---|---|---|---|
| 1 | fortnight before last | Fortnight before last · 19 Oct – 1 Nov | not asked | unchanged | right (parser) |
| 2 | first week of september | September 2023, "first week of" left | first week of | unchanged | nothing |
| 3 | the last three mondays | Mondays, "the last three" left | last 3 | unchanged | nothing |
| 4 | past fortnight | Past fortnight · 2–15 Nov | not asked | unchanged | right (parser) |
| 5 | a month ago | A month ago · 1–31 Oct | not asked | unchanged | right (parser; the spec's calendar-month meaning) |
| 6 | this past weekend | This past weekend · 11–12 Nov | not asked | unchanged | right (parser) |
| 7 | three weeks back | Three weeks back · 23–29 Oct | not asked | unchanged | right (parser) |
| 8 | early october | October 2023, "early" left | early | unchanged | nothing |
| 9 | since monday | nothing | since Monday | unchanged | nothing |
| 10 | the 1st | nothing | 1st | unchanged | nothing |
| 11 | longer than an hour and a half | Over 1h 30m | not asked | unchanged | right (parser) |
| 12 | quick ones under ten minutes | Under 10m, "quick ones" left | quick ones | unchanged | nothing |
| 13 | mornings last week | Last week · 6–12 Nov, "mornings" left | this week mornings | unchanged | nothing |
| 14 | xmas | nothing | this time of year | unchanged | nothing |
| 15 | new year's day | nothing | a year; 1 january | 1 january (Sun 1 Jan 2023) | right (model: the latest New Year's Day) |
| 16 | q3 | nothing | q3 | unchanged | nothing |
| 17 | the weekend before last | Weekend before last · 4–5 Nov | not asked | unchanged | right (parser) |
| 18 | last tuesday's sessions | nothing | last tuesday's sessions | unchanged | nothing |
| 19 | two months back | Two months back · 1–30 Sep | not asked | unchanged | right (parser) |
| 20 | parser stuff from last fortnight | Last fortnight · 2–15 Nov, "parser stuff from" left | "parser" | unchanged | nothing |

Counts: right 9 (parser 8, model 1), nothing 11, wrong 0, accepted but
rejected by the parser 0. Right or honestly nothing: 20 of 20, against 18 of
20 before. The rescue changed the field on 1 of 12 phrasings it was asked,
and that one was right. The wrong rescues of the first run (rows 1 and 4)
are gone because the parser reads both phrasings before the model is asked.

What this run shows:

- Of the nine phrasings that ended with a right filter, eight came from the
  parser alone. Teaching the parser the words the model had been rewriting
  into ("fortnight", "back", "last weekend", "an hour and a half") did more
  than the rescue did; the rescue now earns its keep on phrasings like "new
  year's day" that need a date looked up.
- Rows 2, 3, 8, 12, 13 and 20 still have a phrase the parser read and some
  other words left over, no hits, and nothing the model can add; the field
  stays as typed. "Since Monday", "early October", "first week of", "q3",
  "xmas" and "the 1st" remain outside the grammar and the model proposes
  nothing the parser accepts.

## 6. Hand checks

| # | Step | Passes when |
|---|---|---|
| 1 | Type "last week" | Chip shows last week's exact dates; list shows only those sessions |
| 2 | Type "Thesis on Mondays over 1h" | Three chips; only Monday Thesis sessions over 1h |
| 3 | Press × on one chip | Its phrase leaves the field; the list widens |
| 4 | Type `"Xcode"` with quotes | Word search, no app chip |
| 5 | Type "new year's day" and press Return (AI Mac) | Field becomes "1 january" with a marked chip (Sun 1 Jan of the latest year); ⌘Z restores (a phrasing only the model rescues, §5a) |
| 6 | Turn the switch off, repeat 5 | Nothing changes on Return |
| 7 | Type "last Tuesday longer than an hour" | Two chips, `Last Tuesday · <its date>` and `Over 1h`; the list shows that Tuesday's sessions over an hour (§7) |

## 7. Weekday days

Added 2026-10-12. On the live app, "last Tuesday longer than an hour" read
as one chip, "Over 1h", and left "last Tuesday" as words, which no session
holds, so History said "No matching sessions" over a week with Tuesday
sessions. The grammar read "last" only before week, month, year,
fortnight, weekend and a count of days or weeks, and no single weekday at
all. A Core probe (now Monday 12 October 2026, Sydney) read the text as
span nil, chips `["Over 1h"]`, leftover "last Tuesday"; "Tuesday", "on
Tuesday", "this tuesday" and "tuesday before last" were all left as words.

| Question | Decision |
|---|---|
| "last Tuesday", "(this, the) past Tuesday" | The latest Tuesday strictly before today: on a Tuesday, a week ago; on a Wednesday, yesterday. Chip `Last Tuesday · Tue 6 Oct`. |
| "Tuesday", "on Tuesday" | The latest Tuesday up to today, today included: on a Tuesday it is today, as Ask's `AskRange.resolving("tuesday")` reads it. Chip `Tuesday · Tue 13 Oct`. |
| A lone weekday beside other periods | It falls inside them: the latest such day they hold, once a month or day typed without a year has taken its year. "Tuesday last week" is last week's Tuesday, "Monday 5 October" the 5th, "on Monday October" the last Monday of October. With none inside ("Tuesday 5 October", a Monday) the periods do not overlap. |
| "this Tuesday" | This week's Tuesday. Weeks run from Monday, as History's do, so this Sunday is still to come during the week and lists nothing until it has passed. |
| "Tuesday before last" | The Tuesday a week before last Tuesday; "the" may lead. |
| Numeric dates | `d/M/yyyy` ("31/8/2026"), the form History's search text already holds for each day, is that day, chip `Mon 31 Aug 2026`. Before, it matched as a word; now a weekday beside it falls on it, so "monday 31/8/2026" finds that Monday in any later week. A date the calendar lacks ("31/2/2026") or another order ("8/31/2026") stays a word. |
| Abbreviations | After "last" or "this" and before "before last", three letters name the weekday ("last tue", "this thurs"). Alone only the whole name does: "wed", "sat" and "sun" stay ordinary words, and "tues" and "thurs", like "Tuesdays", stay every Tuesday or Thursday. "Tuesday's" reads as Tuesday, so the live probe's row 18 (§5a) now gives a chip. |
| Recurring weekdays | Unchanged: "Tuesdays", "on Tuesdays" and "Mondays and Fridays" are weekday sets, not days. |
| How a day is found | The calendar day holding noon that many days away, so a 23- or 25-hour day keeps its length and a clock change at midnight cannot move it. |
| Empty search | When the periods do not overlap, the hint under "No matching sessions" says so: The dates in the chips do not overlap, so no session fits them all. Remove one of them. Otherwise, with chips shown and leftover words that find nothing, it names the words: “banana split” was searched as words, and no session that fits the chips has them. Remove them, or say them another way. Without chips, or with no leftover words, the hint is as before. |
| Rescue | Unchanged. It still runs on Return when words are left over and nothing is listed; a weekday phrase the parser reads leaves no words for it. |

What changes for a typed word: a lone weekday used to search as a word and
matched every session on a day of that name. It is a day now; "Mondays"
lists every Monday, and `"Monday"` in quotes searches the word.

Not done:

- "next Tuesday" (future periods stay out of scope): "next" stays a word
  beside the latest Tuesday, and the empty search names it. "since Tuesday"
  likewise.
- Two lone weekdays together: "Tuesday and Thursday" reads as two days that
  do not overlap.
- A date the grammar does not read stays as words: in "Monday 5th of
  October", "5th of" stays words and the Monday is October's latest.
- An app or category named like a weekday ("Monday") is read as the day, as
  a month name is read as the month; pick it from the menu instead.
- `d/M` without a year stays a word.
- The rescue's instructions still offer the model only plural weekdays, and
  the live probe (§5a) was not run again.

Checks: `HistorySearchWeekdayChecks`, six suites appended to
`registeredTests`, each failing on the parser before this change.
`HistorySearchChecks` "Search finds a session by every word…" also searches
"monday 31/8/2026 morning compiler" six weeks after the session, which a
lone weekday that ignored the date beside it would fail.
`HistorySearchQueryChecks` "Quoted words stay words" (formerly "Quoted words
and a single weekday stay words") lost its two rows that pinned a lone
weekday as a word.

## Out of scope

- Phrases for notes, power or automatic sessions beyond today's word match.
- Future periods ("next week") and open ranges ("since March").
- Saving searches.
