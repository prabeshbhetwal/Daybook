import Foundation

/// What a split writes for the tail: the name and category it begins under, and where each came from.
struct SplitTail: Equatable {
    var name: String
    var workType: WorkType
    var source: DecisionSource
    var nameByApp: Bool
    var detectedApp: String? = nil
}

/// One ended record cut in two, and two cut records joined again (spec section 4). Pure: the work is
/// divided by counted time exactly as a day's share of a record is (`workSeconds(in:)`), so the halves
/// always add up to the record and no total, goal or streak can move.
extension SessionRecord {
    /// The head, which keeps this record's id, thread, name, category and source and now ends at `moment`,
    /// and the tail, a new record from `moment` to the end under `choice` with the head's origin. Nil unless
    /// `moment` is strictly inside the record and clear of every paused span, edges included: a cut at a
    /// pause would leave one half starting or ending on time that does not count.
    func split(at moment: Date, tail choice: SplitTail, tailID: UUID = UUID(),
               tailThread: UUID = UUID()) -> (head: SessionRecord, tail: SessionRecord)? {
        guard workType.countsAsFocus, breakOrigin == nil, start < moment, moment < end,
              !(pausedSpans ?? []).contains(where: { $0.start <= moment && moment <= $0.end }) else { return nil }
        let headWork = max(0, min(workSeconds, workSeconds(in: (start: start, end: moment))))
        var head = self
        head.end = moment
        head.workSeconds = headWork
        head.pausedSpans = pausedSpans.map { $0.filter { $0.end <= moment } }
        let tail = SessionRecord(id: tailID, name: choice.name, workType: choice.workType, start: moment, end: end,
                                 workSeconds: workSeconds - headWork, detectedApp: choice.detectedApp,
                                 threadID: tailThread, isAuto: isAuto,
                                 pausedSpans: pausedSpans.map { $0.filter { $0.start >= moment } },
                                 origin: origin, originRuleID: originRuleID, originRuleName: originRuleName,
                                 categorySource: choice.source, nameByApp: choice.nameByApp)
        return (head, tail)
    }

    /// `head` and `tail` as the one record: the head's identity and fields, running to the tail's end, with
    /// both halves' work and pauses. Nil unless they touch, in that order, and are both work.
    static func merged(head: SessionRecord, tail: SessionRecord) -> SessionRecord? {
        guard head.id != tail.id, head.end == tail.start, head.workType.countsAsFocus, tail.workType.countsAsFocus,
              head.breakOrigin == nil, tail.breakOrigin == nil else { return nil }
        var joined = head
        joined.end = tail.end
        joined.workSeconds = head.workSeconds + tail.workSeconds
        if head.pausedSpans != nil || tail.pausedSpans != nil {
            joined.pausedSpans = (head.pausedSpans ?? []) + (tail.pausedSpans ?? [])
        }
        return joined
    }
}
