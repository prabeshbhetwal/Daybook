# Type audit

Date: 2026-10-06. Base: `d4afc08`. Read-only: nothing was changed.

## Summary

| Measure | Count |
|---|---|
| `.font(...)` calls under `Sources/` | 385 |
| …using a `Tokens.Typography` font | 361 |
| …adding an ad-hoc `.weight(...)` to a token | 81 (54 on the 12pt `metadata`) |
| …raw `.system(size:)` or system text styles (`.title3`, `.callout`…) | 21, plus 3 in the debug Gallery |
| Sizes in `Typography.Size` | 11 (9, 10, 11, 12, 13, 14, 15, 19, 22, 24, 36) |
| Text sizes actually drawn | 12 (the scale plus `StoryStyle.headline` at 20) |

The tokens are sizes with a default weight, not roles. Each view then picks a
weight, so one role lands at different sizes and weights in different areas.
`metadata` (12pt) is used 170 times plain and 54 times reweighted. It does the
work of body text, captions, row figures, card labels and text buttons.

## The same role, set differently

| Role | Where | Now |
|---|---|---|
| Card title | History month card `HistoryPeriodCard.swift:34` | **19 bold**, a raw size. No other card title is above 15. |
| | Day-story entry card `DayStory.swift:505` | 14 medium |
| | History search card `HistorySessionCard.swift:38` | 14 semibold |
| | Rail tile `StoryRail.swift:650` | 12 bold, secondary |
| Card's main figure | Rail goal `StoryRail.swift:337`, session tile `HistoryJournalRail.swift:306`, Awards streak `AwardsView.swift:141` | 24 semibold rounded |
| | Month card total `HistoryPeriodCard.swift:46` | 19 semibold rounded |
| | Report stats `SessionReportView.swift:265` | 15 semibold |
| | "On this Mac" `StoryRail.swift:455`, app total `HistorySearchRail.swift:46` | 14 semibold |
| | App detail total `StoryAppDetail.swift:89` | 14 medium |
| Row duration | Dashboard session `DayStory.swift:595` | 12 regular (semibold when live) |
| | History search card `HistorySessionCard.swift:44`, `HistorySearchList.swift:91` | 12 semibold |
| | History tree facts `HistoryTreeRow.swift:158`, breaks `StoryBreakRow.swift:82` | 12 regular |
| List group header | Search day header `HistorySearchList.swift:58` | 14 bold |
| | Tree day row `HistoryTreeRow.swift:152` | 12 bold |
| | Tree month/year row, same line | 14 medium |
| | Search month header `HistorySearchList.swift:51` | 12 bold |
| Small heading / label | "Each day" `HistoryDayChart.swift:59`, "This month so far" `HistoryJournalRail.swift:273` | 12 bold |
| | "How this is measured" `AwardsView.swift:48`, onboarding eyebrow `WelcomeCoach.swift:193` | 12 semibold |
| | Story eyebrow `StoryColumns.swift:102` | 10 bold capitals |
| Prompt title | Away prompt `AwayAnswers.swift:220` | `.title3` semibold (15) / `.headline` (13 bold) |
| | Everywhere else | `sectionTitle` (15 semibold) / `rowTitle` (14) |
| Headline sentence | `StoryStyle.headline` | 20, off the scale. The scale's 19 step serves only the strip clock and the month card. |

## Raw sizes that bypass the tokens

Text:

- `HistoryPeriodCard.swift:34` — `.system(size: Size.headline, weight: .bold)`
- `AwayAnswers.swift:98, 131, 180, 220, 225` — `.callout`, `.body`, `.caption`, `.headline`, `.title3`
- `DashboardCharts.swift:18, 48` — `.callout`, `.caption2`
- `DayPickerCalendar.swift:88` — `.caption.weight(.medium)`
- `StoryRail.swift:355` — ring label `.system(size: 12, weight: .bold, design: .rounded)`; the ring's own default is 11 semibold
- `AppIcon.swift:95`, `Cards.swift:52` — monogram letters at `size * 0.55`
- `GalleryView.swift:406, 417, 443` — debug catalogue only

Symbols sized as fonts:

- `SurfacePrimitives.swift:59` (18), `:88` (12)
- `SettingsSidebar.swift:226` (12), `CategoryEditorPanel.swift:161` (11)
- `CategoriesView.swift:609` (15 or 19), `DayStory.swift:561` (12 or 15)
- `Components.swift:307` (`size * 0.45`), `GoalRing.swift:37` (`diameter * 0.3`)
- `MenuBarGlyph.swift:25, 29` (7, 6.5): drawn into the menu-bar icon, not text

## Deliberate choices to keep

These read as drift but are commented decisions:

- Onboarding eyebrow in sentence case, not capitals (`WelcomeCoach.swift:190`).
- Onboarding paragraph at 13 in primary ink, for reading (`WelcomeCoach.swift:278`).
- Away answer buttons in the rounded face, so one glyph reads whole (`AwayAnswers.swift:90-99`).
- Compact surfaces step each title down one level (`FocusHero.swift:449`, `Components.swift:19`).
- The menu-bar title uses the system menu font (`Tokens.Typography.menuBar`).

## Documentation drift

`DESIGN.md` says card labels are "the small-label size in capitals". The code
sets them at 12 bold in sentence case, and lists the scale without the 20pt
headline it names two lines earlier.

## Outcome

Applied the same day after approval. Type is now set by 15 roles in
`Sources/Design/Typography.swift`, and `build.sh` fails a raw size, a system
text style or a reweighted role. On this audit's base the guard reports 115
lines; after the change it reports none. The month card is set at the row
role (14 medium), by the owner's choice over the 15pt heading that was
proposed. `DESIGN.md` carries the role table.
