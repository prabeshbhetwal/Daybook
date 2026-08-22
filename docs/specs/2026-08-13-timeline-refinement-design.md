# Timeline Refinement and Memory Budget — Design Spec

**Date:** 2026-08-13
**Status:** Approved for planning
**Extends:** `2026-08-12-dashboard-design.md`

---

## 1. Goal

Make the day timeline readable at the hour and inspectable to the minute, surface when
each app's stretches actually happened, replace the dead space under Insights with app
history, scale date navigation past two days, and bring memory back under control.

## 2. Defects being fixed

| # | Defect | Evidence | Cause |
|---|---|---|---|
| D-1 | "1 session today" beside "No sessions yet today" | Screenshot, same screen | `sessionsToday` counts the running session; `FocusQuality.sessionCount` counts only completed records |
| D-2 | Apps show "0m" at 17% and 3% | Screenshot, Top apps | `Tokens.duration` floors below a minute; timeline stretches are often seconds |
| D-3 | 4 minutes of data renders as one block on a 12am–1am axis | Screenshot | The window adapts to data with no minimum span and no hour snapping |
| D-4 | Memory grew 17 MB → 49 MB (peak 53) | `footprint` | Unbounded cache of multi-representation `NSImage` icons; see §6 |

## 3. Timeline

### 3.1 Hour grid

The band is divided into uniform hour columns with a hairline at each boundary. Labels
appear every hour, or every second hour when the window would produce more than twelve
labels. The window snaps outward to whole hours and enforces a **minimum span of four
hours**, so a short day does not render as one fat block against a one-hour axis.

### 3.2 Hover

`onContinuousHover` over the `Canvas` maps the pointer's x to a time, then to the segment
covering it. A floating label shows the app icon, name, clock range and duration. Leaving
the band clears it. The hovered segment id is a single `UUID?` on the store — nothing
allocates per frame.

### 3.3 Expand to minutes

Clicking a segment selects it. An inline detail row appears beneath the axis listing that
app's individual stretches within the selected segment's hour, each as
`2:13 – 2:41 pm · 28m`. Clicking the same segment again, clicking empty band, or pressing
Escape clears the selection. Only the selected segment's detail renders, so the cost is
bounded by one app's stretches in one hour rather than by the size of the day.

## 4. Durations

`Tokens.preciseDuration(_:)` replaces `Tokens.duration` everywhere a tracked stretch is
shown:

| Input | Output |
|---|---|
| < 60 s | `45s` |
| < 1 h | `12m` |
| ≥ 1 h | `2h 13m` |

`Tokens.duration` stays for session-length figures, where sub-minute precision is noise.

## 5. Sections

### 5.1 Top apps

Each row gains the day span of that app beneath its name — `9:02 am – 4:41 pm` — computed
from its first and last stretch. A disclosure triangle expands the row to list every
stretch with clock range and duration. Collapsed is the default; expansion state is a
`Set<String>` of bundle ids on the store.

### 5.2 Earlier today

New section in the right column, **above** Insights, filling the dead space. Every app with
usage today that is not currently running, each with icon, name, total, and its stretches
listed individually. An app used three times shows three lines. Ordered by most recent
stretch first, capped at the same count as the menu bar setting so the column cannot grow
without bound.

Apps still running stay in Running Now and are not repeated here.

### 5.3 Date stepper

`‹ Wed 13 Aug ›` replaces the Today/Yesterday segmented control. Back is disabled at the
earliest record in either archive; forward is disabled at today. Left and right arrow keys
step. A `Today` button appears only when the selected day is not today.

## 6. Memory budget

Measured: 49 MB with the dashboard open, peak 53 MB, of which `Malloc Small` is 25 MB.

**Cause.** `NSWorkspace.icon(forFile:)` returns an `NSImage` with **32 representations up
to 2048×2048** — roughly 53 MB if fully decoded, per icon. `AppIconProvider` caches those
whole, unbounded.

**Fix 1 — rasterise at display size.** Cache a single bitmap at the size actually drawn
(20pt at 2× = 40px, so 40×40×4 ≈ 6.4 KB) and discard the multi-representation original.

**Fix 2 — one pass per refresh.** `clippedUsage(for:)` is currently recomputed inside
`trackedTotal`, `rankedApps`, `timeline` and `focusQuality` — four full scans of the usage
array plus their transient tuple arrays on every refresh. `DashboardStats` computes the
day slice once in `init` and shares it.

**Target:** ≤ 35 MB with the dashboard open. Measured before and after and reported
either way, including if the target is missed.

## 7. Verification

- Headless tests for: hour snapping and the four-hour minimum, hover hit-testing
  (time → segment), stretch grouping per app, `preciseDuration` boundaries at 59/60/3599/3600
  seconds, date-stepper bounds, and D-1's consistency (session counts agree).
- `--snapshot` fixtures gain a short day (minutes only), a dense day, and a
  navigated-to-yesterday state.
- Memory measured with `footprint` before and after, dashboard open, after 60 s idle.

## 8. Out of scope

Week and month views, editing or deleting usage records, per-app detail windows, and
export. The 7-day stacked timeline remains deferred.
