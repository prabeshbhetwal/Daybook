import Foundation

/// What the summary a record keeps once its beats expire (`SessionActivityShape` in the sidecar) does across a
/// join. A cut leaves the head's covering its own part and the tail's the rest, and nothing rebuilds either
/// without beats; a head left as it was after the halves are joined again would read only its former half for
/// good, and the tail's, which nothing reads once the tail is gone, would be lost.
extension SessionStore {
    /// The halves are one record again (Merge Back, or Undo of the cut): the head's summary becomes the one of
    /// both, each cut to its half's own time so what one kept for the whole is not counted twice. With either
    /// half's missing there is none, and the session reads its app use, as two records do when only one kept one.
    /// A head summary that already covers the whole was never cut to its part, and stays. `keepingHead`: Merge
    /// Back sets the head's own aside on the tail, so Undo of the join gives it back.
    func joinSummaries(head: SessionRecord, tail: SessionRecord, keepingHead: Bool) {
        guard let own = metadataArchive.metadata(for: head.id)?.activityShape else { return }
        let whole = DateInterval(start: head.start, end: tail.end)
        guard !own.bounds.contains(whole.start) || !own.bounds.contains(whole.end) else { return }
        if keepingHead { logSidecar(metadataArchive.setAsideHeadSummary(own, on: tail.id), "head summary") }
        let joined = metadataArchive.metadata(for: tail.id)?.activityShape.flatMap {
            SessionActivityShape.joined([own.clipped(to: DateInterval(start: head.start, end: head.end)),
                                         $0.clipped(to: DateInterval(start: tail.start, end: tail.end))])
        }
        logSidecar(metadataArchive.replaceActivityShape(joined, for: head.id), "joined summary")
    }

    /// Undo of a cut or a join landed (`parts`: its head's id and tail record). A join gives the head its own
    /// summary back; a cut is a join of the halves again, from the records as the cut wrote them.
    func summariesFollowUndo(of state: SessionStoreCorrectionState, parts: (head: UUID, tail: SessionRecord)) {
        switch state.restructure {
        case .merge?:
            guard let own = metadataArchive.metadata(for: parts.tail.id)?.headSummary else { return }
            logSidecar(metadataArchive.replaceActivityShape(own, for: parts.head), "head summary")
            logSidecar(metadataArchive.setAsideHeadSummary(nil, on: parts.tail.id), "head summary")
        case .split?:
            guard let half = state.addedRecords?.first(where: { $0.id == parts.head }) else { return }
            joinSummaries(head: half, tail: parts.tail, keepingHead: false)
        case .removal?, nil:
            return
        }
    }
}
