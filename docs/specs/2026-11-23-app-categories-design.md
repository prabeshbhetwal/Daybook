# App categories: show what kind of work a session was

Status: draft for review, 23 November 2026. Nothing built.

## Why

Almost every session is called "Deep work", so the Today screen cannot tell a
morning of coding from a morning of chatting with AI and reading. Daybook
already knows: every app has a purpose (`AppPurpose`), and that purpose already
drives phases, focus credit and activity goals. The person never sees it, and
cannot fix it when it is wrong.

This feature shows each app's category in plain words, lets anyone correct it
in one click, and lets the on-device model suggest a category for apps the
built-in rules do not know. Categories set the tone of the app: every screen
should look sorted.

## What already exists and is reused

| Need | Exists | Use |
|---|---|---|
| A purpose per app | `AppPurpose` (7 cases), `PurposeMap.rules` | Unchanged set. Only display names change (below) |
| Apps the rules do not know | `PurposeMap.categoryFallback` reads `LSApplicationCategoryType` | Unchanged. WhatsApp (`social-networking`) already lands in Communication; Muse (`com.meta.endo`, `productivity`) in Writing & AI |
| Per-app correction | `PersistenceStore.purposeOverrides` (`fc.purposeOverrides`), top precedence in `PurposeMap.purpose` | Stored and read everywhere, but **nothing in the UI writes it**. This feature is its first editor |
| Re-deriving after a correction | `SessionActivityShape.digest(overrides)` is part of the activity cache key | A correction re-derives cards, phases and goal totals with no new plumbing |
| On-device model, gates, AI mark | `ModelGate`, the Phase C sparkle and "assigned by AI" label | Reused for app suggestions |
| Session card sections | `DayStory` "Apps in this stretch", `SessionEntryCard+Activity` "Phases" | Regrouped, not replaced |

## Goals

1. Every app row anywhere in Daybook shows its category as a coloured pill.
2. The open session card groups its apps by category, with a one-line summary
   ("Mostly Writing & AI") and a bar split by category.
3. The day column gains a "What you worked on" card: the day's focus split by
   category.
4. One click on a pill changes that app's category everywhere, past and future.
5. For an app with no rule and no useful declared category, the on-device model
   suggests one, shown with the AI mark until the person confirms it.
6. Someone non-technical understands every word without help.

## Non-goals

- Custom categories. The seven are fixed in this phase (see Open questions).
- Per-site categories for browsers. That is the opt-in site signal's job.
- Changing what counts as focus. `AppPurpose.isFocused` is unchanged.
- Renaming the person's session categories ("Deep work"). Those stay theirs;
  app categories describe the tools inside a session.

## Anti-goals (a failure even if it works)

- The model writes a `purposeOverrides` entry. Only the person does.
- An AI suggestion changes a goal result, a focus total or a phase before the
  person confirms it.
- A pill or bar whose colour is the only way to tell categories apart.
- A first-run sheet that blocks the app or must be finished.

## Design

### 1. Plain names

Display names only. `rawValue`s, stored data and the enum stay as they are.

| Case | Today | Proposed | Symbol (unchanged) |
|---|---|---|---|
| `coding` | Coding | Coding | `chevron.left.forwardslash.chevron.right` |
| `writingAI` | Writing & AI | Writing & AI | `sparkles` |
| `design` | Design | Design | `paintbrush.pointed.fill` |
| `communication` | Communication | Chat & email | `bubble.left.and.bubble.right.fill` |
| `research` | Research | Browsing & research | `magnifyingglass` |
| `media` | Media | Entertainment | `play.rectangle.fill` |
| `utility` | Utility | Everything else | `wrench.and.screwdriver.fill` |

`displayName` already feeds activity goals (`DailyGoalsPanel`,
`SessionStore+Goals`), app limits (`StoryRail`), phase text
(`SessionPhaseText`) and the split offer (`SplitOfferRow`, which lowercases it:
"mostly chat & email"). All follow the new names with no other change; read
each sentence once with the new words before shipping.

### 2. Colour

One colour per category in `Tokens.Palette` (new `purpose(_:)`), used
identically by pills, bars, the day card and the phase strip. Each meets 3:1
against the card in light and dark, and white pill text meets 4.5:1. Colour is
never alone: every pill carries its symbol and name, and every bar segment has
a VoiceOver label ("Writing & AI, 2 hours 40 minutes").

### 3. Session card

"Apps in this stretch" becomes category groups:

- Above the groups: a bar split by category (credited seconds, same source as
  the existing app list) and one summary line: "Mostly Writing & AI" when one
  category holds more than 50%; "Writing & AI and Browsing" when two together
  hold more than 80%; otherwise "A mix of 4 kinds of work".
- Each group: symbol, name, total, then its apps with their times, largest
  first. At most four groups. When there are more, the fourth slot becomes
  "Everything else" and absorbs the smaller groups plus the `utility` group,
  so that name never appears twice.
- The existing "more apps · See Full Report" behaviour is kept per card.
- Browsers carry their behaviour-decided category for the stretch, and their
  row says so: "Dia · follows what you do in it" on first appearance only.

### 4. Pill and picker

Every app row (session card, Full Report, Top apps, Settings) shows the pill.
Clicking it opens a menu of the seven categories, each with colour, symbol and
a one-line example ("Chat & email: WhatsApp, Slack, Mail"). Choosing one writes
`purposeOverrides[bundleID]` and shows an inline confirmation with Undo,
matching the existing "Counted as focus · Undo" banner:

> Claude is now Coding, here and in past days. Undo

Past goal results already recorded keep their outcome (section 9); the copy
does not promise more than that.

The last menu item, "Use Daybook's choice", appears only when an override
exists and removes it.

### 5. AI suggestions for unknown apps

Applies only when `PurposeMap.purpose` would fall through to `.utility` because
there is no override, no rule and no usable declared category.

- **When.** The first time an app reaches 10 credited minutes in a day, read
  from the day's existing usage totals (no new accumulator). Same gates as
  Phase C: `ModelGate`, Low Power Mode, thermal pressure, Apple Intelligence
  off.
- **State per app**, in Core, persisted with the suggestions:

  | State | Meaning | Next |
  |---|---|---|
  | (absent) | Never asked | Ask when the gate opens |
  | `blocked` | Gate was shut | Ask again on a later day; no limit |
  | `failed` | Call errored | Ask again after 7 days, at most 3 times |
  | `noAnswer` | Model returned none | Final; never asked again |
  | `suggested(purpose)` | Shown with the AI mark | Person confirms or dismisses |
  | `vetoed(purpose)` | Person dismissed | Final |

  Confirming removes the entry and writes the override.
- **Input.** App name and bundle identifier only. Never window titles, sites or
  content.
- **Output.** Constrained to one of the seven cases, or none. Validated.
- **Stored** as a suggestion (`purposeSuggestions[bundleID]`), separate from
  overrides. A suggestion does **not** feed `PurposeMap.purpose`: the app stays
  "Everything else" in totals, phases and goals.
- **Shown** where it is counted. The app stays in the "Everything else" group
  and its pill reads "Everything else", with a separate sparkle chip beside
  it: "Writing & AI?". The pill never shows a category the totals do not use. One click confirms it (it becomes an override, the mark
  goes); the menu offers the others. Dismissing it records the veto and the
  model is not asked about that app again.
- **No model:** no suggestion. The app stays "Everything else" with its pill
  clickable.

### 6. First run

After updating, the first time Today opens with at least three apps used this
week, a dismissible card at the top of the day column:

> **We sorted your apps.** Sorted on your Mac. Nothing leaves it.
> 6 apps sorted · 1 to check   [Review] [Looks good]

Review opens the Apps list (section 7) filtered to this week's apps, with
"to check" (AI suggestions) first. "Looks good" dismisses it; it never returns.
Nothing is confirmed by dismissing: suggestions stay suggestions.

### 7. Settings › Apps

A list of every app seen, grouped by category, each row with icon, name, the
pill, and a source word in secondary text: "Built in", "From the app",
"Your choice", "Suggested". Search field at the top. This is also where a
suggestion can be confirmed in bulk ("Accept all suggestions"). It sits on the
Settings page that hosts `DailyGoalsPanel`, since goals read these totals; the
builder confirms the exact page in the 7-page Settings layout.

### 8. Day column: "What you worked on"

Placed under the day's headline card. Bar plus one row per category with time,
largest first, at most five rows. A row opens the day's apps in that category.
The card hides on days under 15 minutes of focus.

### 9. Consequences the person must not be surprised by

- An override changes past days too, because shapes are derived. The
  confirmation text says so ("here and in past days").
- A stored goal result for a past day (`GoalDayResults`) is not rewritten; only
  live and future days recompute. To check against the goal-results migration
  decision before building.

## Constraints (from `CLAUDE.md`)

- Core stays UI-free: suggestion storage and precedence live in Core; the model
  call lives in App.
- Lengths are tokens or `N.zoomed`. Views read published models only; no timers.
- Checks use `MemoryDefaults`, `TestClock`, and hold in any time zone.
- A change to persistence (`purposeSuggestions`) runs `fix-reviewer` first.

## Checks to add

1. An override changes a past session's groups and today's goal total;
   removing it restores them. A stored past `GoalDayResults` outcome is
   unchanged either way.
2. A suggestion changes nothing in totals, phases or goals until confirmed,
   and the pill keeps showing "Everything else".
3. Each state in section 5's table moves only as the table says; `noAnswer`
   and `vetoed` are never asked again.
4. The model is never called for an app with a rule, an override or a usable
   declared category.
5. Display-name change leaves stored `rawValue`s and decoding untouched.
6. Summary line at exactly 50%, two-category 80%, and three-plus categories.
7. Every sentence built from `displayName` (goals, limits, phase text, split
   offer) reads correctly with each of the seven names.
8. The card never shows two "Everything else" groups.

## Phasing

| Phase | Ships | Needs |
|---|---|---|
| 1 | Names, colours, pills, picker with Undo, grouped session card, Settings › Apps | Nothing new in Core except the colour token |
| 2 | "What you worked on" day card | Phase 1 |
| 3 | AI suggestions and the first-run card | Phase 1, macOS 26 |

Phase 1 alone fixes the visible problem: every app correctly labelled and
correctable.

## Review log

23 November 2026, plan-reviewer panel. DeepSeek V4 Pro: approve with changes,
0.75. Second OpenRouter model: approve, 0.88. GPT did not receive the file;
Gemini timed out. Adopted: past-goal contradiction in the checks, the
suggestion state table, summary-line boundaries, pill shows only what is
counted, single "Everything else" group, display-name check, Settings anchor.

## Open questions

1. Custom categories later, or the fixed seven for good? Recommendation: fixed
   seven; corrections cover most needs and keep goals simple.
2. Should a browser's category be pinnable by the person (an override on Dia),
   given it then stops following behaviour? Recommendation: yes, with the menu
   saying "Always Writing & AI (stops following what you do)".
3. Past goal results: recompute or keep as recorded? Recommendation: keep, per
   section 9.
