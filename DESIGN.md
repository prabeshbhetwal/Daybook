# FocusContinuity Story design system

## Authority

The final **Focus Continuity - Day as a Story.dc.html** in the supplied research
handoff is the visual reference. Earlier prototypes are alternatives. Native
macOS behaviour, accessible contrast and truthful recorded evidence take priority
over unsupported sample content. This document records the implemented remediation
language; the [verification report](docs/superpowers/reviews/2026-08-31-story-remediation-verification.md)
records the tested behaviour and remaining manual-verification limits.

## Composition

A persistent native chrome row holds Day / Week / Month, period navigation and
session controls. A readable Story column sits beside a 336-point supporting rail.
The canvas is warm off-white (`#FBFAF8`) with white entry cards; the rail is a
subtle neutral layer over the warm base. Dark appearance retains the same
hierarchy, without putting white labels on insufficiently dark fills.

Column insets: 26 top, 30 horizontal, 34 bottom. Rail insets: 22 top, 20 horizontal,
30 bottom, with 14-point tile gaps. These are reference-specific tokens, not a
reason to change every legacy surface's spacing.

## Type and colour

Use the native system typeface. Story headline: 25-point semibold, maximum
560-point reading width. Row titles: 14 points; secondary metadata: 12 points.
Values use monospaced digits. Prose wraps; diagnostics never truncate silently.

Focus identity is indigo, separate from blue action. The reference's `#4E4CCC`
is used for light-appearance emphasis; dark-appearance text uses `#B6B3FF`
to stay readable on dark cards instead of copying a low-contrast saturated fill
into small labels. Action blue is `#0071E3` / `#75B5FF`. Work types retain stable
identities; app colours are consistent within
the selected scope. Colour never implies goal credit where only focused duration
is known. Native controls preserve visible keyboard focus.

## Components

- Scope control: rounded rectangle, radius 9, neutral selected thumb radius 7.
- Entry cards: radius 13, 13-point vertical / 15-point horizontal padding,
  subtle hairline and shadow. The entire header toggles detail.
- Rail tiles: radius 14, 15-point vertical / 16-point horizontal padding.
- App row: icon, name and duration on one line; thin full-width share bar below.
- Entry detail: apps and coverage beside one another where space permits,
  stacked when narrow. No fabricated activity waveform or typing claims.
- Month: responsive square cells, 8-point gaps, 62-point weekly totals column,
  date and duration together. Intensity is relative focused duration, not goal
  attainment. Foreground is selected from resolved-fill contrast.
- Preferences: compact bounded native sheet with five groups, backed controls
  and contextual search. Native modal sheets block parent interaction and Escape
  dismisses. History remains searchable and opens historical stories explicitly.

## Measurement language

Focused means credited session work. Tracked / On this Mac means observed app
use. Goal credit is their qualifying intersection. Missing recording coverage
is a separate limitation, never added to observed use. Period bars and their
average remain tracked; focus headlines and averages use focused days only.
Integrity notices precede the figures they qualify.

## Interaction and motion

Inline disclosures stay visually joined to their headers. Editing receives
keyboard focus and exposes save errors. Undo remains available after changing a
focus session to Break. Hover and press feedback are restrained; reveal/selection
transitions respect Reduce Motion. Do not choreograph everyday page loading.

## Verification

Use isolated fixtures and inspect actual rendered content in both appearances at
980 and 1,160 points. Include native sheet Escape/focus, Light → System and
Dark → System, historical drill-in, live period totals, sparse recording and long
labels. A passing image-generation command is not a visual acceptance result.
