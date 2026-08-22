# Elided Timeline, Clearer Insights, Honest Running List — Design Spec

**Date:** 2026-08-13
**Status:** Approved for planning

---

## 1. Goal

Stop spending the timeline's width on time when nothing happened, say what an insight
actually means, and stop listing processes that never stop running.

## 2. Defects

| # | Defect | Evidence |
|---|---|---|
| E-1 | Yesterday's band spends 8pm–11pm on nothing and crushes an hour of real activity into a smear | Screenshot: three empty hour columns, then every app compressed into the last hour |
| E-2 | "Longest stretch / Claude, 10m" does not say what it measures or when it happened | Screenshot |
| E-3 | "50m less / tracked than yesterday" gives a delta with no baseline | Screenshot |
| E-4 | Finder is listed under Running Now, where it is permanently and uninformatively present | Screenshot |

## 3. The elided timeline

### 3.1 Clusters

Usage is grouped into **activity clusters**: runs of segments separated by gaps of less
than `gapThreshold` (20 minutes). A gap at or over the threshold ends a cluster.

The band's width is divided between clusters **in proportion to their duration**, with a
fixed 26pt separator for each elided gap. Overnight stops costing three quarters of the
band; the 11pm–12am burst gets most of it and becomes readable.

### 3.2 What a gap looks like

A narrow hatched separator with the elided duration beneath it: `No activity · 8h 12m`.
This is deliberately not blank — you can still see that a break happened and how long it
was, which is part of reading your own day. Only the pixels are reclaimed, not the fact.

### 3.3 Hours inside clusters

Within a cluster, hour boundaries are drawn as before and the axis labels real clock
times. This is what reconciles "represent every hour" with "do not waste space on empty
hours": hours stay uniform where there is data, and only wholly-empty stretches collapse.

A cluster shorter than 15 minutes is still given a readable minimum width so a two-minute
burst does not vanish between two separators.

### 3.4 Mapping

Hit-testing, hover and the focus-session brackets all go through one function, so the
band, the axis and the pointer can never disagree:

```swift
/// Fraction across the band (0...1) for an instant, or nil when the instant
/// falls inside an elided gap.
func fraction(for date: Date) -> Double?
/// The instant at a fraction across the band, for hover.
func date(at fraction: Double) -> Date?
```

Both live in `TimelineLayout`, computed from the clusters, and are unit-tested.

## 4. Insight copy

Insights state the measure, the value and the evidence. No bare deltas.

| id | Headline | Detail |
|---|---|---|
| `longest-stretch` | `Longest unbroken stretch` | `10m in Claude, 11:04 – 11:14 pm` |
| `inside-session` | `62% of tracked time was in a focus session` | `1h 18m of 2h 6m tracked` |
| `vs-yesterday` | `50m less than yesterday` | `1h 15m today, 2h 5m yesterday` |

Rules: the headline names what is being measured, never just a number; the detail carries
the evidence — a clock range, or both sides of a comparison. A delta without its baseline
is not an insight.

## 5. Running Now

Apps that report **no launch date** are excluded. Finder is the confirmed case: it is
started by the system at login, runs permanently, and the row can only ever read "since
login", which tells you nothing.

This is a principled rule rather than a name blocklist: if we cannot say when it started,
we cannot say anything useful about it, so we do not list it. The count in the section
header reflects what is shown.

## 6. Architecture

```
Core/TimelineLayout.swift   NEW. Clusters, widths, and the two mapping functions.
                            Pure — no SwiftUI, fully testable.
Core/DashboardStats.swift   Serves the layout; insight copy rewritten
Surfaces/.../DayTimelineView Draws clusters and separators through the layout
Surfaces/.../DashboardSections  Running Now filter
```

`TimelineLayout` owns every coordinate decision. The view asks it where things go and
never computes a position itself — that is what stops the axis, the segments and the
hover from drifting apart.

## 7. Verification

- Clustering: a 25-minute gap splits; a 15-minute gap does not; one continuous run is one
  cluster; an empty day is no clusters.
- Width allocation: two clusters of equal duration get equal width; separators take a
  fixed share; the total is 1.
- Mapping round-trip: `date(at: fraction(for: t)) == t` inside a cluster; `fraction` is nil
  inside an elided gap.
- Minimum width: a two-minute cluster beside a four-hour one is still visible.
- Insight copy: each insight's detail is non-empty and contains its evidence.
- Running Now excludes an input with no launch date.

## 8. Out of scope

Zooming into an elided gap, per-cluster collapse toggles, and week views.
