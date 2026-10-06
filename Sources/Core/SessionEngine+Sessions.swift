import Foundation

extension SessionEngine {
    func archiveCurrentSession(endingAt endMoment: Date? = nil) -> Bool {
        guard state != .idle else { return true }
        // A start immediately followed by a stop is a misclick, not a session.
        // Nine such records sit in the shipped archive inflating the day's
        // session count and the quick-start tallies.
        // A question held at a second absence past the cap already stopped
        // the stretch there; Stop or Reset must not stretch it to now.
        let held = isAwaitingCorrection ? pauseStartDate : nil
        let end = min(max(endMoment ?? held ?? now(), sessionStartDate), now())
        let record: SessionRecord? = elapsed < store.minimumRecordedSession ? nil : SessionRecord(id: activeRecordID,
                                     name: sessionName,
                                     workType: activeWorkType,
                                     start: sessionStartDate,
                                     // Clamped both ways. `endingAt` comes from
                                     // the detector, which can be told a moment
                                     // that predates this session entirely; an
                                     // unclamped value writes end < start and
                                     // lands the record on the wrong day.
                                     end: end,
                                     workSeconds: elapsed,
                                     detectedApp: activeDetectedApp,
                                     threadID: activeThreadID,
                                     isAuto: activeIsAuto,
                                     pausedSpans: trustedPausedSpans(until: end))
        let additions = record.map { [$0] } ?? []
        if decisionHistory.requiresTerminalCheckpoint || awayDecisions.contains(where: {
            $0.creditedSeconds > 0 && $0.threadID == activeThreadID && $0.sessionStart == sessionStartDate
        }) || !archive.capacityRetirements(adding: additions).isEmpty {
            let before = snapshot()
            linkCreditRecords(additions)
            // End owns this idle checkpoint, including uncredited endings that
            // retire older history. The generic Away/Watching append handler
            // remains metadata-only and never assumes that work is ending.
            var after = snapshot()
            after.kind = .idle
            after.pauseStart = nil
            after.awayStart = nil
            after.awayTrigger = nil
            after.decisionStarted = nil
            after.pendingAway = nil
            after.awayReturnedAt = nil
            after.pendingDecisionID = nil
            after.workBeforePendingAway = nil
            after.shadowAway = 0
            after.isAuto = false
            after.correctionGeneration = correctionGeneration + 1
            after.liveCorrectionGeneration = after.correctionGeneration
            let result = decisionHistory.commit(before: before, after: after, adding: additions,
                archive: archive, allowsEviction: true, operation: .endStretch)
            awayDecisionError = result.error
            guard result.didCommit else {
                awayDecisions = before.awayDecisions ?? []
                return false
            }
            correctionGeneration += 1
            liveCorrectionGeneration = correctionGeneration
            synchroniseCommittedCorrectionMetadata()
        } else if let record, let error = archive.append(record) {
            awayDecisionError = error
            return archive.records.contains(record)
        }
        // A rest refused earlier is retried with each stretch archived here.
        saveRests()
        return true
    }

    // MARK: - Discrete sessions

    /// Begins a session. Any running session is stopped and archived first, so
    /// starting is always safe and never silently discards work.
    /// True when pressing Start would continue what is already running rather
    /// than replace it: same kind of work, already in progress.
    func wouldAdopt(workType: WorkType) -> Bool {
        state != .idle && activeWorkType == workType
    }

    /// An explicit different name is a different activity even where the work
    /// type happens to match. An empty intent is the existing deliberate
    /// "continue what is running" affordance, so it keeps its prior behaviour.
    func wouldAdopt(workType: WorkType, intent: String) -> Bool {
        guard wouldAdopt(workType: workType) else { return false }
        let trimmed = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || ContinuationPolicy.activityKey(name: trimmed, workType: workType)
            == ContinuationPolicy.activityKey(name: sessionName, workType: activeWorkType)
    }

    /// Claims the running session as the user's own without disturbing its
    /// clock. Pressing Start while already doing this kind of work should name
    /// the work, not chop the afternoon into two records with a seam where the
    /// user happened to reach for the menu bar.
    func adopt(intent: String) {
        guard state != .idle else { return }
        let trimmed = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { store.sessionName = trimmed }
        // A deliberate act. From here the app must not end this session itself.
        activeIsAuto = false
        activeAutomaticAction = nil
        if state.isPaused { transition(on: .manualResume) }
        persist()
    }

    @discardableResult
    func start(workType: WorkType, intent: String, threadID: UUID = UUID(),
               isAuto: Bool = false) -> Bool {
        if state != .idle, !stop() { return false }
        activeWorkType = workType
        activeDetectedApp = currentAppBundleID
        activeThreadID = threadID
        activeIsAuto = isAuto
        activeAutomaticAction = nil
        store.sessionName = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        transition(on: .launch)
        return true
    }

    /// The thread an automatic session for `action` should continue, if any.
    ///
    /// A rule switching back to its app resumes the stretch it left — Coding,
    /// then a few minutes in the browser, then Coding again is one piece of
    /// work, not two records with a seam where the reader happened to check
    /// something. Eligibility is the Continue affordance's own rule: the
    /// latest stretch of that activity, ended within its window. Only threads
    /// the app itself made qualify. A stretch the user started, or adopted as
    /// their own, is theirs, and a rule never extends it.
    func continuedThread(for action: ActivityAutomaticAction, at moment: Date) -> UUID? {
        let index = ContinuationPolicy.Index(records: archive.records)
        let key = ContinuationPolicy.activityKey(name: action.ruleName, workType: action.workType)
        guard let latest = index.latestByActivity[key], latest.isAuto,
              index.isEligible(latest, active: nil, now: moment) else { return nil }
        return latest.threadID
    }

    @discardableResult
    func startAutomatically(action: ActivityAutomaticAction) -> Bool {
        let evidence = action.evidence
        guard state == .idle, evidence.duration.isFinite, evidence.duration >= 0,
              evidence.start <= evidence.end, evidence.end <= now() else { return false }
        // Time already written to a record is owned. An evidence window that
        // begins inside archived work would credit those seconds twice, so it
        // is refused outright rather than trimmed — a trimmed window would
        // claim a dwell the app never observed.
        if let lastEnd = archive.records.map(\.end).max(), evidence.start < lastEnd {
            return false
        }
        activeWorkType = action.workType
        activeDetectedApp = currentAppBundleID
        let continued = continuedThread(for: action, at: evidence.start)
        activeThreadID = continued ?? UUID()
        activeThreadWasContinued = continued != nil
        activeRecordID = UUID()
        activeIsAuto = true
        activeAutomaticAction = action
        store.sessionName = action.ruleName
        sessionStartDate = evidence.start
        totalPausedDuration = max(0, now().timeIntervalSince(evidence.end))
        pausedSpans = totalPausedDuration > 0 ? [DateInterval(start: evidence.end, end: now())] : []
        pauseStartDate = nil
        awayInterval = nil
        shadowAway = 0
        decisionStartDate = nil
        awayReturnedAt = nil
        pendingDecisionID = nil
        workBeforePendingAway = nil
        state = .running
        persist()
        onStateChanged?(state)
        return true
    }
}
