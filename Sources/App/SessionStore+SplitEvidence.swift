import Foundation

/// What the two sides of a cut were, read from the evidence that is there: the basis of both the offer to
/// split and an automatic session's own split. Reads only; nothing here writes a record.
extension SessionStore {
    /// `record` over `span` (the whole record when nil): worked out from the beats while they cover it, else
    /// the part of the summary the record kept. Nil with neither.
    func endedShape(of record: SessionRecord, within span: DateInterval? = nil) -> SessionActivityShape? {
        let bounds = span ?? DateInterval(start: record.start, end: record.end)
        guard bounds.duration > 0 else { return nil }
        let evidence = activityEvidence
        if evidence.enabled, evidence.archive.covers(from: bounds.start) {
            let beats = evidence.archive.beats(in: bounds)
            // As the summary sweep counts it: the record's own pauses when they say exactly, else the beats.
            let paused = record.exactPausedSpans.map { $0.filter { $0.start >= bounds.start && $0.end <= bounds.end } }
            let counted = CountedTime.spans(records: [(bounds: bounds, paused: paused)], beats: paused == nil ? beats : [])
            if !beats.isEmpty, ActivityDerivation.recordsWhole(counted, beats: beats) {
                return ActivityDerivation.derive(DerivationInput(
                    credit: CreditInput(beats: beats, counted: counted, signals: [],
                                        purposeOverrides: engine.store.purposeOverrides),
                    bounds: bounds, countsWhileWatching: record.workType.countsWhileWatching,
                    isRunning: false, now: now()))
            }
        }
        return metadataArchive.metadata(for: record.id)?.activityShape?.clipped(to: bounds)
    }

    /// The first moment inside `record` where its evidence says the work ended for good, that the cut may
    /// land on and the person has not turned down.
    func splitMoment(in record: SessionRecord) -> Date? {
        endedShape(of: record)?.splitCandidates.first {
            record.canSplit(at: $0) && !metadataArchive.hasDeclinedSplit(at: $0, for: record.id)
        }
    }

    /// What cutting `record` at `moment` would make of its tail, and why: the part of the evidence after the
    /// cut decides whether Daybook may pick the tail's category (ruling B8) and from what.
    func tailProposal(for record: SessionRecord, at moment: Date) -> SplitOffer {
        let shape = endedShape(of: record, within: DateInterval(start: moment, end: record.end))
        let topApp = shape?.fingerprint?.topApps.first.flatMap { $0.isEmpty ? nil : $0 }
        let remembered = shape?.fingerprint.flatMap { categoryCorrections.suggestion(for: $0, now: now()) }
            .map { WorkType(rawValue: $0) }
        let suggested = topApp.map { engine.categories.suggestedWorkType(for: $0) }
        var purpose: AppPurpose?
        if case .activity(let found)? = shape?.label { purpose = found }
        return SplitOffer(recordID: record.id, at: moment,
                          choice: .decide(label: shape?.label, remembered: remembered, suggested: suggested,
                                          head: record.workType),
                          purpose: purpose, topApp: topApp)
    }
}
