import Foundation

/// Everything the assistant needs to put one question about an ended session, worked out from the store:
/// the record as it ended, the question, and the names the model's answer is checked against.
struct CategoryAskTarget {
    /// The record exactly as it ended. An answer is written only while the archive still holds it so (C24).
    let record: SessionRecord
    let question: CategoryQuestion
    /// Every category that can be started, in catalogue order: the question offers the first 20, and a
    /// proposal naming a later one is none (C29).
    let startable: [(id: String, name: String)]
    /// The names of every other category that exists (Break, Unsorted, retired ones): never proposed.
    let unofferedNames: [String]
    /// The activity with most credited time: it draws a new label and says whether it counts as focus.
    let dominant: AppPurpose
}

/// The store's side of the category assistant (Phase C, Task 3): what a question is made of, whether an
/// answer may still be written, the write itself, and telling the assistant a session has ended.
extension SessionStore {
    /// The question for an ended record, or nil when the evidence is clear, the record is not one Daybook
    /// chose the category of, or there is nothing to describe (C2, C3). Built from the stored shape and the
    /// person's category names alone: the session's name, note, window titles, addresses and bundle
    /// identifiers have no way in (C5). `splitHeads`, from `splitHeads()`, spares a caller asking about many records
    /// one archive scan each.
    func categoryAskTarget(for recordID: UUID, splitHeads: Set<UUID>? = nil) -> CategoryAskTarget? {
        let moment = now()
        guard let record = engine.archive.records.first(where: { $0.id == recordID }), record.end <= moment,
              !isHeldByUndo(recordID, splitHeads: splitHeads),
              let shape = metadataArchive.metadata(for: recordID)?.activityShape, let fingerprint = shape.fingerprint,
              shape.bounds == DateInterval(start: record.start, end: record.end) else { return nil }
        let corrected = categoryCorrections.suggestion(for: fingerprint, now: moment) != nil
        guard AITrigger.shouldAsk(record: record, shape: shape, hasCorrection: corrected) else { return nil }
        let ranked = AITrigger.ranked(shape.credited)
        guard let dominant = ranked.first.flatMap({ AppPurpose(rawValue: $0.key) }) else { return nil }
        let activities = ranked.compactMap { entry -> (name: String, minutes: Int)? in
            let minutes = CategoryQuestion.minutes(fromSeconds: entry.value)
            return minutes > 0 ? AppPurpose(rawValue: entry.key).map { ($0.displayName, minutes) } : nil
        }
        let startable = WorkType.startable.map { (id: $0.rawValue, name: $0.displayName) }
        guard !activities.isEmpty, !startable.isEmpty else { return nil }
        let facts = CategoryQuestionFacts(
            activities: activities, depthWord: shape.depth?.rawValue,
            appNames: fingerprint.topApps.compactMap(appDisplayName),
            siteKind: activityEvidence.siteReader?.sharesKind == true ? SiteKind(rawValue: fingerprint.siteKind)?.rawValue : nil,
            categories: startable)
        let offered = Set(startable.map(\.id))
        let others = WorkTypeCatalog.shared.allDefinitions.filter { !offered.contains($0.id) }.map(\.name)
            + [WorkType.unsorted.displayName]
        return CategoryAskTarget(record: record, question: .make(facts: facts, fingerprint: fingerprint), startable: startable,
                                 unofferedNames: others, dominant: dominant)
    }

    /// An app's name as the usage record knows it. An app it has never heard of is left out, and so is one it
    /// holds under its bundle identifier (the tracker's fallback for an app with no name): the model must never
    /// see an identifier (C27).
    private func appDisplayName(_ bundleID: String) -> String? {
        bundleID.isEmpty ? nil : usage?.latestName(for: bundleID)
    }

    /// Whether an Undo or a Merge Back still holds the record by its exact value (C30): it is in a correction or
    /// an away answer's receipt, or is the head or the tail of a split whose link is still kept. An AI write is
    /// not in the correction journal, so it would make each of those refuse; the record is left as it is.
    private func isHeldByUndo(_ recordID: UUID, splitHeads: Set<UUID>? = nil) -> Bool {
        engine.retainedCorrectionRecordIDs.contains(recordID) || metadataArchive.metadata(for: recordID)?.splitFrom != nil
            || (splitHeads.map { $0.contains(recordID) } ?? hasLaterPart(of: recordID))
    }

    /// Whether an answer may still be written (C24): the record is exactly as the question found it, so
    /// nothing was renamed, filed, claimed, split, merged or removed since, no Undo holds it now, and no
    /// remembered correction now matches its kind of session. The caller checks the switches.
    func categoryAskIsCurrent(_ target: CategoryAskTarget) -> Bool {
        engine.archive.records.contains(target.record) && !isHeldByUndo(target.record.id)
            && categoryCorrections.suggestion(for: target.question.fingerprint, now: now()) == nil
    }

    /// Files the record under `type` as the AI's pick (C8). Not a correction and not an undo step: the AI mark
    /// is the way to change it. Compare-and-swap against the record as asked, so a change made at the same
    /// moment wins. False when nothing was written, which includes any moment a correction is pending: the
    /// journal would find the archive changed under it (C30).
    @discardableResult
    func writeAICategory(_ type: WorkType, to target: CategoryAskTarget) -> Bool {
        guard engine.decisionHistory.document.pending == nil else { return false }
        var changed = target.record
        changed.workType = type
        changed.categorySource = .ai
        guard engine.archive.edit(removing: [target.record], adding: [changed]) == nil else { return false }
        refresh()
        return true
    }

    // MARK: - Telling the assistant

    /// The assistant told of every session that ends. The evidence holder keeps it and its label file.
    /// A new one starts as at launch, with the first pass made now: it notes what is there and brings back its
    /// offers, so an idle launch that records no app use shows them without waiting for a session. A label the
    /// person's categories already hold is theirs (a Keep whose label file was not written) and leaves the file,
    /// with what lapsed, so answers past their time do not stay while no question is asked.
    @MainActor func installCategoryAssistant(_ assistant: CategoryAssistant) {
        activityEvidence.categoryAssistant = assistant
        activityEvidence.aiLabels = assistant.labels
        activityEvidence.assistantSeen = nil
        activityEvidence.assistantSince = nil
        let kept = Set(engine.store.workTypeDefinitions.map(\.id)), moment = now(), records = engine.archive.records
        updateAILabels { book in
            let settled = Set(book.labels.map(\.id)).intersection(kept)
            book.labels.removeAll { settled.contains($0.id) }
            // Counted as the Keep that crashed would have counted its records (`keepAILabel`).
            for record in records where settled.contains(record.workType.rawValue) {
                book.recordChoice(recordID: record.id, chosen: record.workType.rawValue)
            }
            book.archiveStale(now: moment)
        }
        noteEndedRecordsForAssistant()
    }

    /// Each refresh: on-device AI turned on since the last brings back the offers a launch with it off could not.
    func followAppleIntelligenceSwitch() {
        guard let assistant = activityEvidence.categoryAssistant else { return }
        MainActor.assumeIsolated { assistant.followSwitch() }
    }

    /// The app's own: its label file beside the sessions and the "assign" switch in the preferences `defaults`.
    func installCategoryAssistant(defaults: UserDefaults) {
        MainActor.assumeIsolated {
            let setting = AIAssignSetting(defaults: defaults)
            installCategoryAssistant(CategoryAssistant(
                store: self, labels: AILabelStore(directory: engine.archive.dataDirectoryURL), assigns: { setting.isOn }))
        }
    }

    /// After a sweep: each record it has finished with that was not there when the app opened and has not been
    /// told of is a session that ended, in the order they ended. The first pass of a launch only notes what is
    /// there and when, so nothing recorded before is ever asked about, not even under the new id a split, a
    /// merge or an Undo gives it later: only a record that ends after that moment is (C4).
    func noteEndedRecordsForAssistant() {
        let evidence = activityEvidence
        guard let assistant = evidence.categoryAssistant else { return }
        guard let seen = evidence.assistantSeen, let since = evidence.assistantSince else {
            evidence.assistantSeen = Set(engine.archive.records.map(\.id))
            evidence.assistantSince = now()
            // Shadow mode's offers are this run's only; the answers behind them are in the label file.
            MainActor.assumeIsolated { assistant.restoreSuggestions() }
            return
        }
        let unseen = evidence.settled.filter { !seen.contains($0.key) }
        guard !unseen.isEmpty else { return }
        evidence.assistantSeen = seen.union(unseen.keys)
        let ended = unseen.filter { $0.value.record.end > since }
            .sorted { $0.value.record.end < $1.value.record.end }.map { $0.key }
        MainActor.assumeIsolated { ended.forEach(assistant.sessionEnded) }
    }
}
