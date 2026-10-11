# Plain-language History search

Date: 2026-10-11
Status: design approved 2026-10-11 in chat; written spec awaiting review

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
| Core | `Sources/Core/SearchQuery.swift` (new) | `SearchQuery.parse(_ text:, now:, calendar:, apps:, categories:) -> ParsedSearch`. Finds phrases (§2) by longest match, left to right, skipping quoted text. Returns `span: DateInterval?`, `weekdays: Set<Int>?`, `minLength`/`maxLength: TimeInterval?`, `appBundleID`, `workType`, `leftover: String` and `phrases: [SearchPhrase]` (text range, kind, chip label). Periods go through `AskRange.resolving`; number words through `NoteNumberWords`. Pure; no App types. |
| Core | `Sources/Core/HistoryStats.swift` | `HistoryFilter` gains `span`, `weekdays`, `minLength`, `maxLength`; `isActive` counts them; `apply(to:)` honours span and weekdays for the map. |
| App | `Sources/App/SessionStore+HistoryFind.swift` | `historySearchHits(matching:)` applies span (`holds` on the session-day), weekdays (of the session-day) and length (the session-day's focused seconds, pauses excluded, as its card shows). The empty-filter guard becomes "no filter active". |
| App | `Sources/App/SessionStore+Review.swift` | `setHistoryQuery(_:)` keeps the raw text in a published `historySearchText`, parses it, and sets the filter (leftover words into `query`; app and category into the same state the menus set). |
| App | `Sources/App/SearchRescue.swift` (new) | On Return: if `ModelGate.modelAvailable`, the switch is on, leftover words remain and hits are zero, one greedy `LanguageModelSession` call returns `@Generable struct RescuedPhrases { phrases: [String] }` for the leftover words. Each phrase is parsed on its own; only phrases the parser accepts as a single phrase are kept. Accepted phrases replace the leftover words in the field (one undoable change); the chip is marked as from Apple Intelligence. `responder` seam for checks. |
| Surfaces | `Sources/Surfaces/History/HistorySearchChips.swift` (new) | The chips row under the search field: label, × button, the app icon or category colour, the Apple Intelligence mark on rescued chips. |
| Surfaces | the History search field's view | Binds to `historySearchText`, submits Return to `SearchRescue`, places the chips row. |

Rules kept: views never parse or compute; the 1 Hz ticker never runs the
parser or the model; files under 300 lines; lengths are tokens or `.zoomed`;
`Sources/App/ModelGate.swift` stays byte-identical (another branch copies it).

## 2. Grammar

Case-insensitive, English, any order, mixed with free words.

| Kind | Phrases | Chip |
|---|---|---|
| Period | today, yesterday; this/last week, month, year; the week/month before last; N days/weeks/months ago; last N days/weeks; a month name with or without a year ("September", "Sept 2025"); a day and month with or without a year ("3 October", "3 Oct 2025"); a year ("2025") | `Last week · 6–12 Oct`: the label plus the exact dates |
| Weekdays | a plural weekday ("Mondays"), "on Mondays", "Mondays and Fridays", "weekends", "weekdays" | `Mondays`, `Weekends` |
| Length | over / longer than / more than / at least D; under / shorter than / less than / at most D; between D and D. D: 1h, 1 h, 1 hour, 90m, 90 min, 1h 30m, 1.5h, "an hour", number words | `Over 1h`, `30m–1h` |
| App | the exact name of an app with recorded use (`historySortedUsage`), multi-word names included | the app's name with its icon |
| Category | the exact name of a category | the category's name with its colour |

- A single weekday ("Monday") is not a phrase: it already matches every
  Monday as a word.
- A named month or day without a year means the most recent one that is
  not in the future.
- Text in double quotes is never parsed: `"Xcode"` searches the word.
- Several periods intersect; if they do not overlap the chip reads
  "No overlap" and the list is empty.
- Spans and weekdays use the calendar History builds its places with, and
  `DateInterval.holds` (half-open).

## 3. Behaviour

| Case | Behaviour |
|---|---|
| Only phrases, no words | Every session matching the filters is listed. |
| Length filter | Focus sessions only; breaks join only through words or the Break category, as now. |
| Running session | Its focused time so far counts for length. |
| Chip × | Removes the phrase's text range from the field; the filter follows. |
| Typed app or category | Sets the menu's state; × on its chip clears it. Choosing a different app or category in the menu removes the typed phrase from the field, so the text and the menu never disagree. |
| AI rescue accepted | The leftover words become the accepted phrase text in the field, as one undoable change; ⌘Z restores the original. The chip carries the Apple Intelligence mark. |
| AI rescue rejected, failed or model unusable | Nothing changes; no message. |
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
| Single weekday | "Monday" becomes a filter |
| Zones and DST | A span or weekday shifts in `TZ=Europe/Berlin` or across a daylight-saving week (fixtures built through the calendar) |
| List and map agree | `historySearchHits` and `HistoryFilter.apply` disagree on span or weekdays |
| Phrases only | "last week" lists nothing |
| Length | Pauses count toward length, or breaks pass a length filter |
| Typed app | A typed app name and the app menu set different state |
| Rescue | An accepted phrase does not rewrite the text or lacks the mark; a rejected one changes anything; the model is called with hits, with the switch off, or with no leftover words |
| Views | `--snapshot` with chips breaks at 80% or 140% zoom, light or dark |

Live probe: 20 phrasings outside the grammar ("fortnight before last",
"first week of September", "the last three Mondays", …) through the rescue.
Target: at least 18 rescued to the right filter, every rescue visible as a
marked chip, none accepted that the parser rejected.

## 6. Hand checks

| # | Step | Passes when |
|---|---|---|
| 1 | Type "last week" | Chip shows last week's exact dates; list shows only those sessions |
| 2 | Type "Thesis on Mondays over 1h" | Three chips; only Monday Thesis sessions over 1h |
| 3 | Press × on one chip | Its phrase leaves the field; the list widens |
| 4 | Type `"Xcode"` with quotes | Word search, no app chip |
| 5 | Type "fortnight before last" and press Return (AI Mac) | Field becomes a parser phrase with a marked chip; ⌘Z restores |
| 6 | Turn the switch off, repeat 5 | Nothing changes on Return |

## Out of scope

- Phrases for notes, power or automatic sessions beyond today's word match.
- Future periods ("next week") and open ranges ("since March").
- Saving searches.
