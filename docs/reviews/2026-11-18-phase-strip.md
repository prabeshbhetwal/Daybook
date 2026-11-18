# Phase strip: design review

Date: 18 November 2026. Subject: commit 75017d5, Task 11 of the Phase A plan
(`docs/plans/2026-11-17-activity-aware-sessions-phase-a.md`).

Method: the controller read the rendered snapshots (traces b, d, e and lunch as
open cards, with trace b's report beside them) in light and dark at 80% and 160%
zoom. The `impeccable` skill was not run; this is a direct read of the renders
against the brief's visual treatment and the app strip's rules. Contrast figures
are the implementer's estimates, not measured by this review.

## What was checked

| Point | Finding |
|---|---|
| Reads as the app strip's sibling | Yes. One clipped band, proportional runs, 1 pt card-coloured dividers, no motion. |
| Counted, focused phase | Solid session colour with the purpose symbol; clear in light and dark. |
| Counted, not focused phase | Quieter fill with a full-colour 1 pt border; the search phase in trace b is visibly a different kind of time without being alarming. |
| Uncounted phase (film, away) | Dashed outline on a neutral fill, as the app strip draws gaps. Trace e's film and the lunch gap both read as "not counted" at a glance. |
| Phases above App use | The order answers "what was I doing" before "which app". The two bands use different hues (indigo, blue), so they do not merge. |
| Depth word | "Deep" and "Light" sit small beside the duration. Quiet enough. Trace e shows "20m Light" for a long session: the duration is counted time, which is the intended reading. |
| Accessibility | Label and value come from `SessionPhaseText`; the depth word is in the summary, not only on the title line. Colour is never the only carrier: symbol, outline and the spoken text each carry the meaning. |
| Zoom | At 160% the band, symbols and labels scale together with no clipping or wrapping beyond the existing card layout. |

## Findings

1. **Contrast below 3:1 for light category colours (Minor, accepted).** A
   yellow, green or teal category's solid fill is below 3:1 against the light
   card, and the quiet fill is below it for most colours. The category colour is
   the person's own choice and the app strip draws from the same palette, and the
   strip is never the only carrier of the information. No change in Phase A.
   Revisit if a UI for choosing colours ships.
2. **Wide uncounted run carries no symbol (Minor, accepted).** The lunch gap is
   half the strip and has no icon while the film in trace e does. This is
   intended: away has no activity of its own to symbolise.
3. **Running card has no phase strip (Minor, accepted).** Phases are read only
   for finished, open cards. A running session's evidence is still being
   recorded, so a strip would redraw every beat.
4. **Fixture artefacts (not a defect).** In the lunch trace the editor stays
   frontmost, so the app strip shows Code throughout; in trace e the film is one
   record with a pause where the engine would write a separate record.

## Outcome

No changes to the strip. Findings 1 to 3 are recorded as accepted for Phase A.
