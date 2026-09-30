import Foundation

extension SessionEngine {
    /// Undo affects the absence classification only. The session already begun
    /// on return is kept; neither its elapsed work nor later sessions is rewound.
    var canUndoAwayDecision: Bool {
        guard lastAwayDecision?.isResolved == true else { return false }
        if case .awaitingUserDecision = state { return false }
        return true
    }

    func canUndoAwayDecision(expectedID: UUID) -> Bool {
        awayDecision(id: expectedID)?.isResolved == true && !isAwaitingCorrection
    }
    var isAwaitingCorrection: Bool {
        if case .awaitingUserDecision = state { return true }; return false
    }

    /// Names a recorded break after the fact. The receipt and its record move
    /// together, so the row reads by the new name and Undo still recognises
    /// the record as the one this decision wrote.
    @discardableResult
    func nameBreak(decisionID: UUID, to name: String) -> Bool {
        guard prepareCorrection(), !isAwaitingCorrection,
              let index = awayDecisions.firstIndex(where: { $0.id == decisionID }),
              awayDecisions[index].decision == .tookBreak,
              let inserted = awayDecisions[index].insertedRecord,
              let current = archive.records.first(where: { $0.id == inserted.id }),
              current == inserted else {
            awayDecisionError = awayDecisionError ?? "This break changed since it was recorded, so it cannot be renamed here."
            return false
        }
        var renamed = current
        renamed.name = name
        guard renamed != current else { return true }
        let before = snapshot()
        awayDecisions[index].insertedRecord = renamed
        return commitCorrection(before: before, removing: [current], adding: [renamed])
    }

    @discardableResult
    func undoAwayDecision(expectedID: UUID? = nil) -> Bool {
        guard prepareCorrection(), !isAwaitingCorrection,
              var receipt = expectedID.flatMap({ awayDecision(id: $0) }) ?? (expectedID == nil ? lastAwayDecision : nil),
              receipt.isResolved else { return false }
        let before = snapshot()
        var removals: [SessionRecord] = []
        var additions: [SessionRecord] = []
        var liveCredit: TimeInterval = 0
        if let record = receipt.insertedRecord {
            guard archive.records.contains(where: { $0.id == record.id }) else {
                awayDecisionError = "The original classified record is no longer available. Its correction history was preserved."
                return false
            }
            removals.append(record)
        }
        if let original = receipt.legacyOriginalRecord { additions.append(original) }
        if receipt.creditedSeconds > 0 {
            if state != .idle, activeThreadID == receipt.threadID, sessionStartDate == receipt.sessionStart {
                liveCredit = receipt.creditedSeconds
                guard elapsed + 0.001 >= liveCredit else {
                    awayDecisionError = "This session no longer contains the original away credit."
                    return false
                }
            } else {
                guard let expected = receipt.expectedCreditRecord,
                      let record = archive.records.first(where: { $0.id == expected.id }),
                      expected.workSeconds + 0.001 >= receipt.creditedSeconds else {
                    awayDecisionError = "The original saved session cannot be verified for Undo. Its record was preserved."
                    return false
                }
                // Name/type edits are independent fields, not a conflict with
                // subtracting this exact, journalled credit from its stretch.
                guard record.id == expected.id, record.start == expected.start, record.end == expected.end,
                      record.threadID == expected.threadID, record.workSeconds == expected.workSeconds else {
                    awayDecisionError = "This session changed since the action. Its newer evidence was preserved."
                    return false
                }
                var corrected = record
                corrected.workSeconds = max(0, expected.workSeconds - receipt.creditedSeconds)
                removals.append(record); additions.append(corrected)
            }
        }
        totalPausedDuration += liveCredit
        pausedSpans = []
        receipt.decision = nil
        // This is a new review action. Old buttons/retries must not target a
        // subsequent answer to the same physical interval.
        receipt.id = UUID()
        receipt.insertedRecord = nil
        receipt.creditedSeconds = 0
        if receipt.legacyOriginalRecord != nil {
            awayDecisions.removeAll { $0.id == expectedID || ($0.range == receipt.range
                && $0.legacyOriginalRecord?.id == receipt.legacyOriginalRecord?.id) }
        } else { lastAwayDecision = receipt }
        linkCreditRecords(additions)
        guard commitCorrection(before: before, removing: removals, adding: additions) else { return false }
        awayDecisionError = nil
        persist()
        onStateChanged?(state)
        return true
    }

    /// Re-answer an undone historical interval without replaying its original
    /// state transition or ending the work happening now.
    @discardableResult
    func reviseAwayDecision(_ decision: UserDecision, label: String? = nil, expectedID: UUID? = nil) -> Bool {
        guard prepareCorrection(),
              var receipt = expectedID.flatMap({ awayDecision(id: $0) }) ?? (expectedID == nil ? lastAwayDecision : nil),
              !receipt.isResolved else { return false }
        if case .awaitingUserDecision = state { return false }
        let before = snapshot()
        var record: SessionRecord?
        if decision == .mergeTime || decision == .tookBreak {
            let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            record = SessionRecord(id: receipt.id,
                name: decision == .mergeTime ? receipt.name : trimmed.isEmpty ? "Break" : trimmed,
                workType: decision == .mergeTime ? receipt.workType : .breakTime,
                start: receipt.range.start, end: receipt.range.end, workSeconds: receipt.range.duration,
                threadID: decision == .mergeTime ? receipt.threadID : receipt.id)
        }
        if let error = validateDecisionEffects(record.map { [$0] } ?? []) {
            awayDecisionError = error; return false
        }
        receipt.decision = decision
        receipt.insertedRecord = record
        lastAwayDecision = receipt
        let additions = record.map { archive.records.contains($0) ? [] : [$0] } ?? []
        guard commitCorrection(before: before, adding: additions) else { return false }
        awayDecisionError = nil
        persist()
        onStateChanged?(state)
        return true
    }

    /// A legacy break has no original away receipt. Reclassifying it records
    /// the real break as the reversible before-state, never invented work.
    @discardableResult
    func reclassifyLegacyBreak(recordID: UUID, decision: UserDecision, focusTargetID: UUID? = nil) -> Bool {
        guard prepareCorrection(), !isAwaitingCorrection,
              decision == .continueSession || decision == .mergeTime,
              let original = archive.records.first(where: { $0.id == recordID && $0.workType == .breakTime }),
              original.end > original.start,
              !awayDecisions.contains(where: { $0.insertedRecord?.id == recordID || $0.legacyOriginalRecord?.id == recordID })
        else { return false }
        let target = focusTargetID.flatMap { id in archive.records.first { $0.id == id && $0.workType.countsAsFocus } }
        if decision == .mergeTime && target == nil {
            awayDecisionError = "Choose a valid recorded focus session before counting this interval. Leave uncounted is still available."
            return false
        }
        let before = snapshot()
        let id = UUID()
        let focus: SessionRecord? = target.map {
            SessionRecord(id: id, name: $0.name, workType: $0.workType,
                start: original.start, end: original.end, workSeconds: original.end.timeIntervalSince(original.start),
                threadID: $0.threadID)
        }
        lastAwayDecision = AwayDecisionReceipt(id: id, range: DateInterval(start: original.start, end: original.end),
            name: target?.name ?? original.name, workType: target?.workType ?? original.workType,
            threadID: original.threadID, sessionStart: original.start, decision: decision,
            insertedRecord: decision == .mergeTime ? focus : nil, creditedSeconds: 0,
            legacyOriginalRecord: original)
        guard commitCorrection(before: before, removing: [original], adding: decision == .mergeTime ? focus.map { [$0] } ?? [] : []) else {
            return false
        }
        onStateChanged?(state)
        return true
    }

    /// An archive commit can outlive its preference receipt. Repeated writes
    /// recognise their stable effect IDs and exact accounting values; mixed or
    /// incompatible evidence is never overwritten as part of recovery.
    func validateDecisionEffects(_ records: [SessionRecord]) -> String? {
        let existing = records.compactMap { wanted in archive.records.first { $0.id == wanted.id } }
        guard !existing.isEmpty else { return nil }
        guard existing.count == records.count else {
            return "This interval's saved evidence has changed. No records were replaced."
        }
        for (saved, wanted) in zip(existing, records) {
            // Detected-app metadata can be unavailable on restore. Preserve
            // it verbatim, while requiring every identity and accounting field.
            guard saved.id == wanted.id, saved.name == wanted.name, saved.workType == wanted.workType,
                  saved.start == wanted.start, saved.end == wanted.end,
                  abs(saved.workSeconds - wanted.workSeconds) < 0.000_001,
                  saved.threadID == wanted.threadID, saved.isAuto == wanted.isAuto else {
                return "An incompatible answer is already saved for this interval. Its record was preserved."
            }
        }
        return nil
    }

    /// Reconcile only a demonstrable committed result. This updates the
    /// preference-side receipt; it never repairs or rewrites archive evidence.
    func reconcileAwayReceipt() -> Bool {
        guard var receipt = lastAwayDecision else { return false }
        if !receipt.isResolved,
           let record = archive.records.first(where: { $0.id == receipt.id }),
           record.start == receipt.range.start, record.end == receipt.range.end,
           record.workSeconds == receipt.range.duration {
            if record.workType == .breakTime, record.threadID == receipt.id {
                receipt.decision = .tookBreak
            } else if record.workType == receipt.workType, record.threadID == receipt.threadID {
                receipt.decision = .mergeTime
            } else { return false }
            receipt.insertedRecord = record
            lastAwayDecision = receipt
            return true
        }
        var completedUndo = false
        if receipt.isResolved, let record = receipt.insertedRecord,
           !archive.records.contains(where: { $0.id == record.id }) {
            completedUndo = true
        }
        if receipt.creditedSeconds > 0, let expected = receipt.expectedCreditRecord {
            var after = expected
            after.workSeconds = max(0, expected.workSeconds - receipt.creditedSeconds)
            completedUndo = archive.records.contains(after)
        }
        if completedUndo {
            receipt.id = UUID()
            receipt.decision = nil
            receipt.insertedRecord = nil
            receipt.creditedSeconds = 0
            lastAwayDecision = receipt
        }
        return completedUndo
    }
}
