# FocusContinuity Premium Interface Design System

**Date:** 2026-08-30  
**Status:** Implemented and verified — headless suite green, visual matrix rendered and inspected
**Scope:** Main checkout only. This document defines the visual and interaction system for every FocusContinuity surface. It does not change time-accounting semantics, persistence, or historical evidence.  
**Supersedes:** The visual-system and Review-routing portions of `2026-08-29-interface-redesign-design.md`. The five-tab product architecture, its privacy constraints, and its truthfulness requirements remain in force.

## 1. Executive decision

FocusContinuity will be a calm, native-feeling macOS application for understanding and acting on personal focus continuity. It must feel designed as one product, not as a collection of cards, charts, and controls added at different times.

The chosen interaction model is **Review as a workbench**:

- Selecting a bar or History row keeps the user in Review.
- The selected date opens an inline **day detail** directly beneath the trend, retaining period context.
- `Open in Today` is a visible, explicit action in that detail. It is never an invisible side effect of selecting data.
- A permanent inspector is deliberately rejected: at the supported 980-point minimum window width, it reduces the chart and table to the point where both become less readable.

The visual language is **warm precision**: quiet warm-neutral surfaces, a cool blue focus signal, stable semantic colours, system typography, deliberate empty space, and native macOS interaction behaviour. “Premium” here means that every element has a clear job, a predictable visual state, an aligned position, and an evidence-based reason to exist. It does **not** mean adding gradients, excessive glass, ornamental motion, or a card around every piece of text.

## 2. Purpose, outcomes and guardrails

### 2.1 User outcomes

| User need | Design outcome |
|---|---|
| Start or continue work quickly | Focus gives one clear primary action and no reporting clutter. |
| Understand a whole day honestly | Today tells one chronological day story: activity, focus, breaks, and supporting totals. |
| Compare days without losing context | Review moves from period summary to trend to selected-day detail in one stable workspace. |
| Find patterns without fabricated claims | Insights leads with short, evidence-backed findings and puts methodology on demand. |
| Adjust product behaviour with confidence | Settings uses familiar Mac hierarchy and only exposes controls backed by real settings. |

### 2.2 Non-negotiable guardrails

1. **Truth before visual appeal.** `Tracked`/`At the Mac`, `Focused`, rest, Watching, historical accuracy boundaries, pending persistence, and session semantics retain their current canonical meanings.
2. **No presentation-driven accounting.** Views consume store-provided canonical values. They do not recompute focus, tracked time, averages, or historical intervals.
3. **No third-party visual dependency.** Continue using SwiftUI, AppKit, Charts, SF Symbols, system fonts, macOS 13+, direct `swiftc`, and the existing one-second ticker.
4. **No new permission or network surface.** The redesign adds no telemetry, external service, account, package, or TCC permission.
5. **No fake configurability.** A control needs a persisted/observable effect, or it does not ship.
6. **No compulsory density.** Empty space may establish hierarchy and readability. It must not be filled with duplicate KPIs or decorative charts simply because a window is tall.
7. **No source-control pollution.** Generated bundles, snapshots, Finder metadata, and personal copies remain ignored. This specification is created in the main checkout but is not pushed until the user approves it.

## 3. Research basis and translation

The system adopts platform guidance rather than copying a generic web dashboard.

| Source | Principle | FocusContinuity translation |
|---|---|---|
| [Apple: Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars?changes=_2) | A toolbar or titlebar helps orientation, navigation, and action; it should not be overcrowded. | One unified window-chrome row: contextual title left, global navigation centred, live status right. |
| [Apple: Windows](https://developer.apple.com/design/human-interface-guidelines/windows) | Window controls occupy the leading edge; custom content must not collide with them. | Keep native traffic lights, reserve semantic leading clearance, and never place an important command underneath them. |
| [Apple: Charts](https://developer.apple.com/design/human-interface-guidelines/charts) | A chart needs a descriptive purpose, a clear hierarchy, and marks more prominent than axes. | Every chart has a plain-language title/takeaway; axes and gridlines are quiet; the actual data is dominant. |
| [Apple: Layout](https://developer.apple.com/design/human-interface-guidelines/layout?changes=la) | Reading order, alignment, and distinction between controls and content establish hierarchy. | Put the answer at the upper leading edge, align columns and cards, and use panels only for related evidence. |
| [Material date pickers](https://m3.material.io/components/date-pickers/overview) | Date selection is a contained interaction, not an always-visible data-entry mechanism. | Replace exposed History steppers with a single range-summary control that opens a focused calendar/date-entry popover. |
| [Carbon: dashboards](https://carbondesignsystem.com/data-visualization/dashboards/) | A dashboard should reduce complexity, prioritise data, and coordinate related views. | Review is a three-level sequence: period answer, selected-day context, and supporting evidence/log. |

The product deliberately remains macOS-first. It should feel closer to a disciplined Apple productivity utility than to a web-admin dashboard: restrained surfaces, predictable navigation, native controls, and progressive disclosure.

## 4. Information architecture

### 4.1 Top-level contract

Each global tab owns one question. Any element that does not answer that question belongs elsewhere or behind an explicit drill-down.

| Tab | Primary question | Dominant evidence | Must not become |
|---|---|---|---|
| Focus | What should I do now? | Current state, intent, timer, next action | A history report |
| Today | What happened on this calendar day? | Time ribbon | A goal-configuration page |
| Review | How did time change across a period? | Tracked-time trend | A live session controller |
| Insights | Which patterns are supported by enough local evidence? | A small set of findings | Generic motivation or predictions |
| Settings | How does FocusContinuity behave? | Selected setting group | A data dashboard |

### 4.2 Four evidence levels

Every screen follows the same reading sequence:

1. **Orientation** — where am I, what period/state is shown, and what can I change?
2. **Primary answer** — one leading timer, timeline, trend, finding, or setting group.
3. **Supporting evidence** — the numbers or breakdown that explain the primary answer.
4. **Detail on demand** — a selected-day panel, disclosure, inline expansion, or explicit route.

This prevents the present failure mode in which period summary, chart, session list, app list, work-type donut, and raw log all claim equal visual importance.

### 4.3 Deliberate whitespace

Whitespace is valid only when it does one of these jobs:

- separates distinct evidence groups;
- protects a readable text measure or chart plot area;
- centres a focused operational task;
- creates an intentional quiet empty state.

Whitespace is not valid when a small panel is stretched across a large empty canvas, a group is isolated without a relationship to nearby content, or a vertical gap makes the user scroll before seeing the next logical step. Panels may have a maximum reading measure; the canvas itself need not be fully occupied.

## 5. Foundation tokens

`Sources/Design/DesignTokens.swift` remains the sole owner of visual values. Product views may select a semantic token or a documented component variant; they must not introduce local hex colours, arbitrary spacing, ad-hoc radii, or one-off font sizes.

### 5.1 Colour roles

| Token | Light | Dark | Purpose | Never use for |
|---|---:|---:|---|---|
| `ground` | `#F7F6F3` | `#1C1919` | Window canvas | Interactive selected state |
| `surface` | `#FFFFFF` | `#272222` | Primary grouped evidence | Every isolated text line |
| `elevated` | `#F0EEEA` | `#332C2D` | Quiet wells, tab rail, selected field backing | Primary call to action |
| `line` | black 8% | white 10% | Hairline boundaries and separators | High-emphasis decoration |
| `hover` | black 4% | white 7% | Hover/pressed context | Persistent selection |
| `focus` | `#3478F6` | `#82AEFF` | Primary action, selected navigation, active focus state | Unrelated chart series |
| `progress` | `#238D7A` | `#52C3AC` | Verified positive progress | General decoration |
| `attention` | `#B9721F` | `#E3A34F` | Integrity qualification or action required | Ordinary warnings or labels |
| `danger` | system red | system red | Destructive/irreversible action | Stop, pause, or neutral emphasis |

Stable app and work-type palettes retain their current meanings. A colour dot, app icon, or chart mark must use the same identity on Today, Review, and Insight evidence. The selected-tab blue is a navigation signal, not an app/time category.

### 5.2 Typography

System typography is the brand. No custom font, all-caps visual noise, or decorative numeral style is introduced.

| Role | Token/current style | Rules |
|---|---|---|
| Live timer | `liveTimer`: SF Rounded, 46 pt semibold, tabular digits | Focus hero only; never a list or chart label. |
| Page title | `pageTitle`: SF Pro, 26 pt semibold | One per canvas; concise noun or direct date. |
| Section title | `sectionTitle`: SF Pro, 17 pt semibold | Starts an evidence group; no redundant “overview” suffix. |
| Metric value | `metricValue`: SF Rounded, 28 pt semibold, tabular digits | Summary bands and selected-day figures only. |
| Row title | `rowTitle`: SF Pro, 14 pt medium | List identity, settings labels, session names. |
| Tab label | `tabLabel`: SF Pro, 13 pt medium | Global and segmented navigation only. |
| Metadata | `metadata`: SF Pro, 12 pt regular | Time range, method qualifier, source, and secondary context. |

Numbers representing time, counts, averages, and percentages use `.monospacedDigit()` to prevent visual jitter. Metadata stays readable at the supported minimum width; it may wrap where comprehension needs it and should only truncate when a row has a disclosure for the full text.

### 5.3 Spacing, radius and measure

| Token | Value | Use |
|---|---:|---|
| `xs` | 4 pt | Label-to-value and icon-to-text micro gaps |
| `s` | 8 pt | Compact control internals, dense-row spacing |
| `m` | 12 pt | Normal control padding and related-field gaps |
| `l` | 16 pt | Standard section/panel padding in comfortable density |
| `xl` | 24 pt | Distinct evidence groups |
| `xxl` | 32 pt | Canvas edge padding at comfortable desktop width |
| `xxxl` | 48 pt | Reserved for deliberately spacious empty/focus states |

Primary panels use a 16-point continuous radius. Nested wells use 12 points. Capsules are reserved for navigation, filter chips, and compact state controls. Charts use a 3-point bar radius and timelines use a 5-point segment radius. No other radius is introduced without a token.

Maximum measures are purposeful:

- Focus operational canvas: 760 pt.
- Narrative/empty state: 620 pt.
- Settings control column: 720 pt.
- Full analytical canvas: available width, capped by the window instead of artificially narrowed.
- A data table keeps numeric columns fixed and lets identity/context take remaining width.

### 5.4 Density

The existing persisted density preference is a layout choice, not a second visual language.

| Context | Comfortable | Compact | Constraint |
|---|---:|---:|---|
| Interactive row | 52 pt | 44 pt | Never below the practical 28-point target requirement; 44 remains the default minimum for repeatedly clicked rows. |
| Panel inset | 16 pt | 12 pt | Section grouping remains visible in both. |
| Inter-panel gap | 24 pt | 16 pt | Does not collapse into a card wall. |
| Canvas edge | 32 pt | 16–24 pt | The selected surface stays readable at 980 pt. |

### 5.5 Iconography, motion and state

- Use SF Symbols with hierarchical rendering; real app icons remain real app icons.
- Icons explain a familiar action or category. They do not repeat text that is already obvious.
- Buttons, rows, charts, and tabs expose normal, hover, pressed, disabled, selected, and keyboard-focus states.
- Native focus behaviour must remain accessible without a conspicuous blue rectangular outline around the entire tab rail. The focused subcontrol is indicated by its platform-appropriate focus treatment, while the selected route continues to use `focus` fill.
- Motion is 160–200 ms, interruptible, and only explains a state change, selected data, or live progress. Respect Reduce Motion. No decorative entrance, pulse, parallax, bounce, or perpetual animation.

## 6. Component system

### 6.1 Window chrome and navigation

The macOS titlebar is visually integrated with the app chrome. It contains three stable zones:

```text
[native traffic-light clearance | contextual title + subtitle] [global tabs] [literal live status]
```

- The title is the selected mode (`Focus`, `Today`, `Review`, `Insights`, `Settings`), not the app name alone.
- `FocusContinuity` remains a quiet subtitle for orientation, not a competing page heading.
- Status uses literal language, e.g. `Focus active · 45m` or `Today · 2h 5m focused`.
- The tab rail is the only global route. `⌘1`–`⌘5` and arrow movement retain parity with pointer navigation.
- The traffic-light clearance is semantic, tested, and leaves every live window control unobscured.
- At narrow supported widths, tabs may reduce decoration before labels. Global navigation must never become ambiguous.

### 6.2 Surface panels

`SurfacePanel` is used for a coherent evidence group, not as default page background.

| Use a panel when | Do not use a panel when |
|---|---|
| A title, primary evidence, and related supporting values form one unit | A page title or date header already has enough separation from the canvas |
| A timeline, chart, detail panel, or setting group needs a shared boundary | A simple status line, hint, or single action is being isolated merely for decoration |
| The content can be scanned as one card-sized composition | It would create nested cards inside nested cards without a new interaction boundary |

Panel anatomy is: optional section title/trailing qualifier, primary content, then internal hairline separators only between repeated rows. Do not apply multiple borders, shadows, tinted backgrounds, or different radii to the same group.

### 6.3 Buttons, menus and segmented controls

| Type | Use | Visual rule |
|---|---|---|
| Primary button | One obvious next step, such as Start focus or Pause | Filled `focus` token; one per operational region. |
| Secondary button | Stop, Away, Open in Today, reveal data folder | Quiet native-like background or borderless action; never competes with primary. |
| Destructive button | Reset or irreversible data action | System red, confirmation where the existing product requires it. |
| Icon button | Previous/next date or period, close selection | SF Symbol, explicit help/accessibility label, predictable 28+ pt hit target. |
| Menu | App/work-type filter, compact setting choices | Shows current selection in its label; menu items use human names. |
| Segmented control | Peer modes with a shared canvas: Week/Month/History and This week/This month | One selected item, no duplicate global navigation, equal-height targets. |

Controls must have a stable label. Avoid unlabeled glyph-only controls except universally understood, help-labelled actions such as a chevron or close button.

### 6.4 Filters and date range control

History replaces exposed `NSDatePicker` steppers with one compact range-summary control:

```text
Search history     [calendar  12 Aug – 30 Aug  ▾]     [All apps ▾] [All work types ▾]
```

Selecting the range control opens a popover containing:

1. `All dates` reset action;
2. a concise start/end calendar entry surface, using native controls where practical;
3. clear selected-range text; and
4. an Apply action only when a staged custom calendar requires it. Native immediate controls may update directly.

The popover is a temporary choice surface, not another dashboard. It normalises start/end order, respects the available local-history bounds, preserves the existing local-calendar interpretation, and does not invent a server-side filter or mutate history.

App and work-type filters remain adjacent secondary controls. Search is visually the leading filter because it is the broadest query. `Clear filters` appears only when a non-default filter is active.

### 6.5 Metric bands

Metric bands contain a fixed small set of values answering the same question. They are not generic KPI tiles.

- Values align vertically and use tabular digits.
- A label may appear once as a column header when all subsequent rows share the same metric.
- A footnote only clarifies a meaningful qualifier; it does not repeat the value.
- A metric band cannot mix unrelated concepts such as tracked time, focus quality, and settings state.

### 6.6 Tables and lists

Lists support scanning and drill-in; they do not make every row a miniature card.

**History table anatomy**

```text
Day and context                         Tracked     Focused    Sessions
Sunday 30 August · Deep work · Xcode      5h 30m      11m          1       ›
Saturday 29 August · Meetings · Chrome    1h 26m      19m          1       ›
```

- The header row states `Tracked`, `Focused`, and `Sessions` once.
- Numeric columns are right-aligned with stable widths.
- The day/context column expands; metadata may truncate only after retaining date identity.
- A selected row receives a quiet selected background and opens the inline Review detail. It does not navigate to Today.
- `Open in Today` exists within the selected detail, is plainly named, and has keyboard/VoiceOver parity.
- Dividers separate rows; row backgrounds do not alternate unless a future accessibility appearance requires it.

Session and app lists use the same grammar: identity on the leading edge, context below, measurement on the trailing edge, and a disclosure only if it has an actual destination or expansion.

### 6.7 Charts

Every chart must answer one question in its title before the user reads an axis.

**Period tracked-time chart**

- Title: `Tracked by day`.
- Supporting takeaway: `Average active day: 2h 20m`, or a neutral empty-state sentence when no evidence exists.
- Bars encode exact canonical tracked time only. Work-type composition remains a separate donut/list because it answers a different question.
- Vertical scale begins at zero and uses short, leading-axis labels in the same unit stated by the title/legend. Do not duplicate the axis label on the trailing edge.
- The x-domain includes at least one full bar-width of leading and trailing calendar padding. The first and final bars must never crop at the plot frame.
- Gridlines are light and sparse. No more lines than interpretation requires.
- The active-day average is a thin dashed rule with an unobtrusive, in-plot annotation that cannot collide with axis labels or the last bar.
- Hover/focus names the literal local date and exact tracked value. A selected bar gains a clear but restrained state and opens inline Review detail.
- All-zero periods use a useful empty state rather than an empty coordinate system.

Other charts must follow the same rules: one canonical series per primary encoding, stable colours, a text alternative, and no interaction that silently changes the current tab.

### 6.8 Empty, loading and integrity states

Empty states are part of the product, not a missing screen.

- Explain what is absent and what will make the state useful, without blame or fabricated recommendations.
- Keep empty-state content centred within its evidence group; do not stretch a small message into a huge card merely to occupy a window.
- Integrity notices precede the figures they qualify, use the attention token, and provide exact read-only language.
- A legacy-accuracy note never disappears solely because a design is sparse.

## 7. Surface specifications

### 7.1 Focus — operational instrument

Focus is intentionally the least analytical surface.

| State | Primary content | Supporting content | Excluded content |
|---|---|---|---|
| Idle | Intent, work type, `Start focus` | Goal context and up to three useful continuations/quick starts | Charts, multi-value dashboard grids, full history |
| Running | Large timer, intent, work type, `Pause` | Away/Stop, goal progress, quiet break status | Redundant tracked/focused/session cards |
| Paused | Quiet timer, `Resume`, `Stop` | Current intent and exact paused context | Motivational prose or an unrelated report |
| Watching | Honest explanation that productive time is not advancing | Relevant state action when evidence permits | A visual treatment implying it is active work |
| Awaiting decision | Existing honest gap decision and time range | Direct explanation that the gap is not counted | Modal-like decorative error styling |

The operational canvas remains centred at its 760-point measure. The quiet space around it supports concentration; it is intentional and should not be filled with secondary charts.

### 7.2 Today — one calendar-day story

Today is the canonical day record, including past-day browsing.

1. **Header:** selected day title, direct subtitle (`Sunday 30 August · 2h 5m focused · 1 session`), and date navigation. A past day exposes a clear `Today` reset action.
2. **Primary visual:** time ribbon across the full content width. It shows app stretches, breaks/gaps, focus brackets, labels, hover, and selected state.
3. **Selected detail:** clicking a ribbon segment, session, or app opens a lightweight inspector directly below the ribbon. Escape clears only inspection; it does not change the selected day.
4. **Supporting evidence:** two aligned groups: `Sessions` and `At the Mac`.
5. **Recap:** one compact band with Focused, At the Mac, Sessions, Longest, and the lead canonical SummaryText sentence where available. Remaining canonical day-summary sentences appear in a compact `More about this day` disclosure.

The recap consumes the existing selected-day SummaryText output. It does not recalculate a parallel narrative or permanently duplicate a generic Insight card. SummaryText's internal bold markers are stripped with SummaryText.plain before a sentence reaches SwiftUI Text: 12-point secondary recap copy remains plain, not Markdown-rendered.

The time ribbon stays dominant. Supporting cards use equal top alignment, but they must not visually rival the timeline. Named break time stays visibly separate from focus; unknown inactivity never resembles productive time.

### 7.3 Review — analytical workbench

Review explains a selectable period, not an individual day by default.

```text
Review / 24–30 August 2026 / Week | Month | History
  ↓
Period answer: tracked total, active days, active-day average, longest focus stretch
  ↓
Tracked-by-day trend
  ↓
Selected-day detail (only after a bar or History row is selected)
  ↓
Supporting evidence: top apps, work-type composition, focus sessions, full activity log
```

#### Period sections

1. **Period header:** Review label, short canonical summary, Week/Month/History segmented control, previous/next period controls.
2. **Period answer band:** exactly four related values: Tracked, Active days, Average / active day, Longest focus stretch.
3. **Trend:** the tracked-by-day chart described in section 6.7.
4. **Selected-day detail:** appears only after selection, immediately after the trend. It contains selected date, tracked/focused/sessions, a concise app/session breakdown, and explicit `Open in Today`. App evidence is complete for the selected local day even when the period's chronological log is display-capped; focus ranges and durations are clipped to that day before display. It has a clear close action and preserves the selected period/filter state.
5. **Supporting breakdowns:** top apps and work-type composition. Their titles state what they measure; the work-type donut is never presented as tracked-time comparison.
6. **Evidence lists:** Focus sessions and the full activity log appear after interpretation. Large lists are collapsible or grouped with a literal row count, but never silently discarded.

#### History section

History is a chronological record embedded in Review, not a hidden navigation launchpad.

1. `History filters` groups search, range, app, work type, and active-filter summary.
2. `Days` uses the labelled table from section 6.6, ordered newest first.
3. Selecting a row opens the same selected-day detail pattern. No tab change occurs.
4. The selected detail uses the filtered day’s exact values; filters do not semantically alter those values.
5. If the user wants the day narrative, `Open in Today` sends the literal selected date to Today. This is the only cross-tab route.

#### Review route contract

The current `ReviewDayRoute` changes `selectedTab` to `.today`; this behaviour is removed. A replacement review-selection action must:

```text
set selected Review date
retain Review tab, section, period, and History filters
refresh/reveal inline detail
```

The explicit Today action is the only route allowed to call the existing `openToday(date:)` path. Tests must change from asserting implicit Today navigation to asserting Review remains selected and the literal date is selected in Review.

### 7.4 Insights — evidence with restraint

Insights stays sparse, but its cards become easier to scan.

- A card has category icon/title, one clear conclusion, and a short confidence/source qualifier.
- Detailed methodology moves into an in-card disclosure (`How this is calculated`) instead of permanently consuming half the card.
- Findings appear in the natural order: pace, rhythm, focus quality, continuity. Missing evidence removes a finding; it does not create zero-valued cards.
- Week/month control appears only when both ranges earn it.
- A finding is never a button unless it has an explicit, useful drill-down destination. A conclusion cannot quietly alter date/tab state.

The grid uses two columns when each card can retain a comfortable reading measure; it stacks when it cannot. Empty lower canvas is acceptable once the available verified findings are shown.

### 7.5 Settings — native configuration hierarchy

Settings remains a recognisable Mac split view.

- The sidebar groups persisted settings by user intention: General, Focus sessions, Away and breaks, Automatic and rewards, Tracking and apps, Appearance, Data and privacy, Advanced.
- Search spans the top of the settings canvas and filters the sidebar, without opening an unrelated results page.
- The selected group title and its real rows occupy a readable 720-point control measure. Controls align on a trailing accessory axis.
- A small group is allowed to be small. It should not become a full-window card to conceal the fact that it has one setting.
- Explanatory copy is directly beneath a setting label, not detached in a far-off help card.
- Data/privacy language distinguishes passive monitoring from entered focus-session content and keeps the data-folder action discoverable but secondary.

## 8. Responsive and accessibility requirements

### 8.1 Supported layout states

| Window width | Required behaviour |
|---|---|
| 980–1,079 pt | Minimum production canvas: global chrome remains intact; Review uses one column below the trend; Settings swaps sidebar for its group menu; tables retain headers and stable numeric columns. |
| 1,080–1,199 pt | Settings may use sidebar; Today/Review supporting groups choose the clearer of two columns or stacked layout. |
| 1,200 pt and above | Two-column supporting groups are permitted where they preserve equal visual weight and no card becomes a sparse billboard. |

Content may scroll inside the selected surface. Global chrome remains fixed. A chart may not force the persistent title/navigation band off the rendered view.

### 8.2 Accessibility contract

- Use semantic labels for every chart, bar, row, date control, icon-only button, disclosure, and selected state.
- Keyboard access mirrors pointer behaviour: tab selection, Review day selection, explicit `Open in Today`, date navigation, row expansion, and Escape to clear a transient inspection.
- Focus styles must be visible, but not rely on a rectangular focus ring around an entire composite control.
- Verify light, dark, Increase Contrast, Reduced Motion, VoiceOver ordering, literal time alternatives, and practical targets.
- Every chart has a spoken/text representation with local date and exact canonical values.
- Avoid colour-only meaning: app icon/name, label, and/or symbol accompanies a colour key.

## 9. Data presentation rules

1. **Name the metric as the user should understand it.** Use `At the Mac` for day narrative and `Tracked` for period/accounting comparison only when the accompanying context makes that meaning clear.
2. **Do not mix measures.** A tracked-time chart displays tracked time; focus composition lives elsewhere; a goal reflects focused-active time only.
3. **Preserve scope.** Selected-day data is clipped to the selected local day; period evidence is clipped to its calendar interval; cross-midnight records must not visually bleed outside their day.
4. **Qualify historical accuracy.** Pre-accuracy app usage is preserved and visibly qualified; no visual smoothing or retrospective repair is attempted.
5. **Prefer direct labels over a legend when few marks exist.** Use a compact legend only for reusable, stable app/work-type colour mappings.
6. **Do not repeat a label whose column header already supplies it.** This is mandatory for History’s Tracked, Focused, and Sessions values.
7. **Use disclosure for detail, not navigation surprise.** A selected item reveals evidence in context; cross-surface navigation is named.

## 10. Engineering ownership and interfaces

The redesign preserves the existing boundary:

| Layer | Responsibility during redesign |
|---|---|
| Core | Pure records, date clipping, chart points, statistics, accessibility text helpers. No SwiftUI import or presentation state. |
| App | `SessionStore` read models, Review selected-day state, navigation routing, published visible state, persisted existing preferences. |
| Design | Tokens, component grammar, visual-state contracts, accessibility/size primitives. |
| Surfaces | Layout and local interaction composition. They do not compute raw time or rewrite history. |

The required new presentation state is intentionally narrow:

- Review owns a selected date/detail state separate from `Today`’s selected date/inspector state.
- It identifies one literal local day and is cleared by a close/Escape action or when its backing filter/period no longer contains the date.
- The state is not persisted as historical data and does not mutate session or app-usage records.
- `MainWindowModel.openToday(date:)` remains for the explicit action only.

## 11. Quality bar and rejection criteria

A change is rejected if any of the following is true:

- a chart bar, axis label, tooltip, or selection is clipped at the canvas edge;
- an interaction changes tabs without an explicit label/action saying it will do so;
- a title, panel, card, or chart cannot state the question it answers;
- a list repeats labels that are already supplied by a stable table header;
- an element uses an unapproved local colour, spacing, radius, type size, or visual state;
- a screen fills empty space by duplicating metrics or unrelated charts;
- a meaningful data qualification is visually hidden, truncated without disclosure, or omitted in compact/dark mode;
- a setting does not produce an observable product effect;
- the minimum 980-point canvas loses persistent chrome, table comprehension, or critical controls;
- a visual improvement changes canonical accounting, historical records, or the privacy boundary.

## 12. Verification matrix

### 12.1 Automated checks

- Headless tests for Review selection: a period bar and History row select the literal date while `selectedTab == .review`; only explicit `Open in Today` routes to Today.
- Tests for history column/header semantics and accessible row labels.
- Tests for chart domain padding/axis configuration helpers where pure extraction is possible.
- Tests that filters/period changes clear an out-of-range selected Review day rather than showing stale detail.
- Existing canonical accounting, date clipping, chart-point, accuracy-warning, keyboard, density, and colour-token tests remain green.
- `./build.sh --check`, `./build.sh --test`, code-signature verification, and `git diff --check` remain mandatory.

### 12.2 Visual checks

Render and inspect, in both light and dark appearances:

1. Focus: first run, idle, running, paused, watching, awaiting decision.
2. Today: empty/current/past day, selected app, selected session, named break, legacy accuracy notice.
3. Review: Week and Month with zero, sparse, and dense data; first/last chart bar; selected bar; History filters; selected History row; explicit `Open in Today`.
4. Insights: sufficient week/month, partial evidence, and no evidence.
5. Settings: every group, sidebar layout, narrow group-menu layout, search result, data/privacy actions.
6. Global chrome: 980-point minimum, comfortable width, light/dark, normal/Increase Contrast, keyboard traversal.

Snapshot rendering is evidence, not the sole authority for native controls. Native date controls, titlebar/traffic lights, scroll behaviour, keyboard focus, and accessibility must also be inspected in the running application.

## 13. Implementation order (design-level)

The later implementation plan must sequence work as follows:

1. Establish any missing/revised semantic tokens and shared components with tests and component-gallery evidence.
2. Correct Review selection/navigation semantics before visual detail work, so every later surface uses the right route.
3. Fix the chart layout contract and History range/table anatomy.
4. Build the Review information hierarchy and selected-day detail.
5. Apply the same component grammar to Today, Focus, Insights, Settings, and global chrome without redesigning Core semantics.
6. Finish with the full visual/accessibility matrix, a fresh build, and a source-control audit.

No implementation starts from this specification until the user has reviewed it and the detailed execution plan has been written and approved.

## 14. Decisions intentionally deferred

- New user-configurable dashboard layouts, export, sharing, cloud sync, onboarding, data editing, or account features are outside this redesign.
- A custom multi-month range calendar is allowed only if native macOS date controls cannot meet the contained range-popover design at macOS 13. It must not add a dependency or reduce keyboard/VoiceOver behaviour.
- Additional chart types require a separate question, canonical measure, and specification; a chart is not added merely to populate open space.
