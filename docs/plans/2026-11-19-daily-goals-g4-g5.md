# Daily goals G4 and G5: activity limits and site-kind limits

Spec: `docs/specs/2026-11-18-daily-goals-design.md`. Prerequisites: G4 waits on
activity-aware Phase B (PR 93), G5 on Phase D (PR 94). Each ships as its own PR.

## Findings from the prerequisite code

- The code-derived activity label is `AppPurpose` (on main since Phase A):
  coding, writingAI, design, communication, research, media, utility.
  `isFocused` splits it: coding, writingAI and design are focus; the rest are not.
- Purpose seconds come from `ActivityCredit.credit(CreditInput)` over beats,
  then `ActivityDerivation.purposeSeconds`. Credit is restricted to
  `CreditInput.counted`, so a day reading must pass the whole day's recorded
  foreground spans, not only session spans.
- Phase D adds `SiteKind` (video, documentation, codeHost, social, shopping,
  mail, aiChat, meeting; `isLeisure` for video, social, shopping), stored on
  `BeatSlice.site`. No address or site name is ever kept, so a named-site limit
  ("YouTube") is impossible by design: the limit is on a kind.
- `SignalGate.passing` is empty on every macOS, so no slice carries a site
  today. G5 must say "Not available yet" rather than show "0m of 2h".

## G4: activity limits

1. `DailyGoalTarget.requiredKind`: `.activity(raw)` is `.limit` when `raw` is an
   `AppPurpose` that is not focused, `.target` otherwise (kept labels, Phase C).
   Saved items keep decoding; an existing activity target on a non-focused
   purpose becomes unusable rather than silently changing kind (check).
   No build has offered activity goals yet, so none should exist; the rule
   still covers a hand-edited or future file.
2. Day reading: one Core function, `DayActivityUse.read(beats:counted:overrides:signals:)
   -> (purpose: [AppPurpose: TimeInterval], site: [SiteKind: TimeInterval])`,
   reusing `ActivityCredit.credit` so the numbers match the session report.
   `SessionStore` calls it with the day's beats over the day's recorded
   foreground spans, cached per refresh like `storyRailDay`. Limits count all
   use, in or out of sessions. G4 ships the purpose half; G5 fills the site half.
3. `GoalDayResults.close` takes purpose use beside app use; a day without beats
   (evidence off) leaves activity limits unjudged, not "kept".
4. Card: a limit row like the app limit row, named by `displayName`, symbol by
   `symbolName`. Settings "Daily goals" panel offers non-focused purposes as
   limits. Awards name activity goals by `displayName`.
5. Checks: requiredKind table, day reading equals the History/report accounting
   for the same beats, close() with and without beats, Settings offers only
   non-focused purposes. `fix-reviewer` on the result storage change.

## G5: site-kind limits

1. Target `.site(SiteKind.rawValue)`, kind `.limit` (already the required kind).
   An unknown raw value stays as stored and is never counted.
2. Use per kind: seconds of credited slices whose `site` is that kind, over the
   same day reading as G4 (one pass returns both maps).
3. Availability: `SignalGate.isOn(.siteKind, macOSMajor:)` and the site signal
   setting on. While off, Settings lists the kinds disabled with "Not available
   yet", the card row reads "Not available yet", and close() leaves the goal
   unjudged so it can never break a Perfect day.
4. Checks: gate closed gives unavailable on card, settings and results; gate
   opened in a check (injected availability, not by editing `passing`) counts a
   fixture's video slices; an unknown kind round-trips.

## G5 as built (19 Nov 2026)

Beats are recorded only while a session runs, but a limit counts the whole day,
so no source for whole-day site use exists yet, gate or no gate. G5 therefore
ships the unavailable state only: a stored site limit shows on the card as "Not
available yet", is named by its kind in Settings and awards, is never judged
(so it never keeps or breaks a Perfect day), and the Add Goal row says site
limits are not available yet. No site limit can be added. Counting (steps 2 and
the gate-open half of 3 and 4) waits for the gate and for site kinds read
outside sessions; `DailyGoalList+Site.swift` carries the shortcut note.

## Panel review (19 Nov 2026)

Two of three reviewers approved; the third could not read the file. Adopted:
one API for both maps (above), an explicit rule for existing activity items.

## Open questions for review

- Should leisure site kinds also be addable while the gate is closed (stored,
  shown unavailable) or hidden entirely? Plan: shown disabled, not addable.
- Research is not focused but is often work. Plan: offered as a limit like the
  rest; revisit if the owner objects.
