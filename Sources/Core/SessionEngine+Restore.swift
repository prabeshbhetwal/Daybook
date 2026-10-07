import Foundation

extension SessionEngine {
    /// What a cold launch restores: the preference snapshot, or — when
    /// preferences hold none, set aside as unreadable or out of reach of a
    /// process launched from a sandboxed shell — the correction journal's own
    /// checkpoint. Reconciled first, so a journal whose only transaction is
    /// still pending yields that transaction's state. Starting blank beside the
    /// journal left the engine generations behind it, and the next answer
    /// swapped the journal's checkpoint in under the live stretch.
    func launchSnapshot() -> PersistedState? {
        if let saved = store.loadState() { return saved }
        _ = decisionHistory.reconcile(archive: archive)
        return decisionHistory.document.checkpoint
    }

    /// Restores a snapshot and resolves the gap since it was written through the
    /// same away path a live lock/wake would take (D14).
    /// - Parameter awayAtLaunch: whether nobody is here *now*, at launch — the
    ///   screen is locked or the display is asleep. Relaunched like that — a
    ///   crash, an update, a kill while the user is away — nobody has come back
    ///   yet: the absence stays open from where the snapshot puts it and the
    ///   unlock or wake resolves all of it. Resolving the gap at launch measured
    ///   only up to the launch and then forgot the lock, which is how a
    ///   40-minute absence was recorded as a 6-minute break.
    func restore(from original: PersistedState, awayAtLaunch: Bool = false) {
        var snapshot = original
        snapshot.liveCorrectionGeneration = liveGeneration(of: original)
        if let error = decisionHistory.reconcile(archive: archive) { awayDecisionError = error }
        if let saved = decisionHistory.document.checkpoint,
           liveGeneration(of: saved) > liveGeneration(of: snapshot) {
            let receipts = decisionHistory.metadata?.awayDecisions ?? saved.awayDecisions ?? []
            let replaySavedInitial = original.kind == .awaiting && receipts.contains(where: {
                $0.id == original.pendingDecisionID && $0.isResolved && $0.decision != .mergeTime
            })
            if saved.savedAt >= snapshot.savedAt && !replaySavedInitial { snapshot = saved }
            else {
                // A newer ordinary snapshot owns its live transition. It has
                // already superseded this earlier correction authority.
                snapshot.liveCorrectionGeneration = liveGeneration(of: saved)
            }
        }
        if let metadata = decisionHistory.metadata, metadata.generation >= (snapshot.correctionGeneration ?? 0) {
            snapshot = metadata.applying(to: snapshot)
        }
        store.sessionName = snapshot.name
        sessionStartDate = snapshot.sessionStart
        totalPausedDuration = snapshot.totalPaused
        pausedSpans = snapshot.pausedSpans ?? []
        pauseStartDate = snapshot.pauseStart
        currentAppName = snapshot.lastApp
        currentAppBundleID = snapshot.lastAppBundleID
        decisionStartDate = snapshot.decisionStarted
        activeThreadID = snapshot.threadID ?? UUID()
        activeRecordID = snapshot.activeRecordID ?? legacyActiveRecordID(for: snapshot,
            pendingDecisionID: original.pendingDecisionID)
        activeWorkType = snapshot.activeWorkType ?? .deepWork
        activeIsAuto = snapshot.isAuto ?? false
        activeAutomaticAction = snapshot.automaticActivityAction
        awayDecisions = snapshot.awayDecisions ?? snapshot.awayDecision.map { [$0] } ?? []
        correctionGeneration = snapshot.correctionGeneration ?? 0
        liveCorrectionGeneration = liveGeneration(of: snapshot)
        // From the preference snapshot itself: a correction checkpoint is not
        // where refused rests are kept, and one already saved is skipped by id.
        pendingRests = original.pendingRests ?? []
        pendingDecisionID = nil
        workBeforePendingAway = nil
        awayInterval = nil
        shadowAway = 0
        let receiptReconciled = decisionHistory.metadata == nil ? reconcileAwayReceipt() : false

        // Stop saves the record first and the idle state second. Killed
        // between the two, the snapshot still said running, and every later
        // Stop, Reset or Start failed on the record it had already saved, so
        // the session could never end. The saved record is the ending: finish it.
        if snapshot.kind == .running || snapshot.kind == .paused,
           archive.records.contains(where: { $0.id == activeRecordID }) {
            activeIsAuto = false
            activeAutomaticAction = nil
            pauseStartDate = nil
            decisionStartDate = nil
            awayReturnedAt = nil
            state = .idle
            persist()
            onStateChanged?(state)
            return
        }

        // Closed past the cap, the stretch ended where it was left, whatever
        // the snapshot says it was doing. Only a running one used to be
        // measured, through `resolve`. A pause or a question left up carried
        // the whole gap into a stretch that stayed open, and one resume or
        // answer the next morning made a record of the night. Nobody has been
        // here since the earliest of the pause, an absence still open at the
        // write, and the write, except that a break app or a video the user
        // was present for says nothing about when they left. The work stopped
        // where any pause began.
        let presentWhilePaused = snapshot.kind == .paused
            && !Self.pauseMeansNobodyHere(snapshot.restoredPauseReason)
        let absentSince = [presentWhilePaused ? nil : snapshot.pauseStart, snapshot.awayStart, snapshot.savedAt]
            .compactMap { $0 }.min() ?? snapshot.savedAt
        let left = min(snapshot.pauseStart ?? absentSince, absentSince)
        let leftPastCap = snapshot.kind != .idle && interval(from: absentSince) >= store.longAwayCap
        // A saved answer to the question is replayed below first, so its
        // records stand, and its successor is ended after it.
        let answerSaved = snapshot.kind == .awaiting && archive.records.contains {
            $0.id == snapshot.pendingDecisionID || $0.id == activeRecordID
        }
        if leftPastCap, !answerSaved {
            shadowAway = snapshot.shadowAway ?? 0
            endStretch(leftAt: left)
            persist()
            onStateChanged?(state)
            return
        }

        switch snapshot.kind {
        case .idle:
            state = .idle
            if receiptReconciled { persist() }
            return
        case .paused:
            if awayAtLaunch, let began = snapshot.awayStart {
                awayInterval = (start: began, trigger: snapshot.awayTrigger ?? .screenLock)
            }
            state = .paused(reason: snapshot.restoredPauseReason)
            if receiptReconciled { persist() }
            return
        case .awaiting:
            // The app was not running, so none of this gap was observed work.
            // Nothing else subtracts it: deliberation is ordinary time now, and
            // without this a card left up over a weekend would come back as two
            // days of focus. Measured from the start of any second absence that
            // was still open when the snapshot was written, not from the
            // write: a lock the card sat through and a quit while locked are
            // one absence. Shadow already banked for closed second absences is
            // settled here too, onto the session that lived through them —
            // `apply` would otherwise hand it to a successor that starts after
            // they happened and whose span cannot contain them.
            // A question held at a second absence past the cap stopped the
            // stretch at its `pauseStart`; the gap runs from there instead.
            totalPausedDuration += (snapshot.shadowAway ?? 0)
                + interval(from: snapshot.pauseStart ?? snapshot.awayStart ?? snapshot.savedAt)
            pauseStartDate = nil
            pausedSpans = []
            // `?? 0`, never the threshold: `.mergeTime` subtracts this from the
            // paused total, and a fabricated value would subtract time that was
            // never added — inventing work out of a missing field.
            state = .awaitingUserDecision(away: snapshot.pendingAway ?? 0,
                                          lastApp: snapshot.lastApp)
            // Re-stamped so the gap just excluded is not excluded a second time
            // when the decision lands. The range keeps the real return moment.
            awayReturnedAt = snapshot.awayReturnedAt ?? snapshot.decisionStarted ?? now()
            decisionStartDate = now()
            pendingDecisionID = snapshot.pendingDecisionID ?? UUID()
            let beforeSpan = max(0, (awayReturnedAt ?? now())
                .addingTimeInterval(-(snapshot.pendingAway ?? 0)).timeIntervalSince(snapshot.sessionStart))
            let totalAtSnapshot = max(0, snapshot.savedAt.timeIntervalSince(snapshot.sessionStart)
                - snapshot.totalPaused)
            let afterReturnAtSnapshot = max(0, snapshot.savedAt.timeIntervalSince(awayReturnedAt ?? snapshot.savedAt))
            workBeforePendingAway = snapshot.workBeforePendingAway
                ?? min(beforeSpan, max(0, totalAtSnapshot - afterReturnAtSnapshot))
            // A completed initial break may already be in the archive while
            // the last preference snapshot still describes its pending card.
            // Replay only that proven answer; stable effect IDs prevent inserts.
            if let id = pendingDecisionID, let range = pendingAwayRange,
               let recordedBreak = archive.records.first(where: { $0.id == id }),
               recordedBreak.workType == .breakTime, recordedBreak.threadID == id,
               recordedBreak.start == range.start, recordedBreak.end == range.end {
                pendingAwayLabel = recordedBreak.name
                apply(.tookBreak)
            }
            if awayAtLaunch {
                // Offline time was already excluded above. The Mac remains
                // unattended after relaunch, including when recovery completed
                // a saved answer and opened its successor. Only real return
                // may close this new tail; replay is not a presence signal.
                awayInterval = (start: now(), trigger: snapshot.awayTrigger ?? .screenLock)
            }
            if leftPastCap, state == .running {
                // The replayed successor began at the return and was left with
                // the app. Its gap, banked above, becomes the closing pause.
                totalPausedDuration = max(0, totalPausedDuration - interval(from: left))
                endStretch(leftAt: left)
            }
        case .running:
            state = .running
            let began = snapshot.awayStart ?? snapshot.savedAt
            if original.kind == .awaiting && snapshot.kind != original.kind {
                // A committed initial live answer is proof of the answer, not
                // proof of presence while the app was closed afterwards.
                totalPausedDuration += interval(from: began)
                pausedSpans = []
                if awayAtLaunch { awayInterval = (start: now(), trigger: snapshot.awayTrigger ?? .screenLock) }
                break
            }
            if awayAtLaunch {
                awayInterval = (start: began, trigger: snapshot.awayTrigger ?? .screenLock)
            } else {
                // With its start, so the gap is kept as a pause span. Without
                // it the spans no longer added up to the paused total, and the
                // record lost every exact pause it had, not just this one.
                resolve(away: interval(from: began), startedAt: began)
            }
        }

        persist()
        onStateChanged?(state)
        if case .awaitingUserDecision(let away, let app) = state {
            onNeedsDecision?(away, app)
        }
    }

    /// Stable migration for snapshots written before `activeRecordID`. A
    /// pending answer already reserved the predecessor effect identity; every
    /// other legacy live stretch derives one from persisted, repeatable fields.
    func legacyActiveRecordID(for snapshot: PersistedState,
                                      pendingDecisionID: UUID? = nil) -> UUID {
        if snapshot.kind == .awaiting,
           let decisionID = snapshot.pendingDecisionID ?? pendingDecisionID {
            return AwayDecisionReceipt.precedingRecordID(for: decisionID)
        }
        var input = Array((snapshot.threadID?.uuidString ?? "legacy").utf8)
        input.append(contentsOf: String(snapshot.sessionStart.timeIntervalSinceReferenceDate.bitPattern).utf8)
        func digest(seed: UInt64) -> UInt64 {
            input.reduce(seed) { value, byte in (value ^ UInt64(byte)) &* 1_099_511_628_211 }
        }
        let high = digest(seed: 14_695_981_039_346_656_037)
        let low = digest(seed: 10_995_116_282_11) ^ 0x9e3779b97f4a7c15
        let bytes = (0..<16).map { index -> UInt8 in
            let value = index < 8 ? high : low
            return UInt8(truncatingIfNeeded: value >> UInt64((index % 8) * 8))
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
