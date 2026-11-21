import Foundation

/// The person's answers to what Apple Intelligence said (Phase C, rulings C13, C14 and C25), for the session
/// report to call. On an AI pick: Keep makes it theirs; Change is the ordinary picker (`setWorkType(_:for:)`),
/// which remembers the pick as vetoed (B6). On an AI-made label: Keep, or Rename, makes it one of their
/// categories under the same id; Merge Into and Remove give every session carrying it a category of theirs, or
/// Unsorted, as one undo step, and its name is never proposed again. Use takes a shadow-mode suggestion. Each is
/// counted in the tally, as is a category change made any other way (`tallyChoices`).
extension SessionStore {
    /// Keep on an AI pick: the session's AI-filed stretches become the person's, as they stand. One undo step.
    @discardableResult
    func keepAIPick(_ session: DaySession) -> Bool {
        // A label the person's categories hold is theirs, as the report reads it (`aiReport`).
        let unkept = Set(activityEvidence.aiLabels?.book.labels.map(\.id) ?? []).subtracting(engine.store.workTypeDefinitions.map(\.id))
        let ids = Set(session.recordIDs)
        let picked = engine.archive.records.filter {
            ids.contains($0.id) && $0.categorySource == .ai && !unkept.contains($0.workType.rawValue)
        }
        guard !picked.isEmpty else { return false }
        return rewrite(picked.map { var kept = $0; kept.categorySource = .user; return kept })
    }

    /// Keep, or Rename with `typed`: the label becomes one of the person's categories under its own id, so the
    /// records carrying it are left as they are and a kept suggestion counts as a match (C25).
    @discardableResult
    func keepAILabel(_ labelID: String, as typed: String? = nil) -> Bool {
        // One the person merged or removed is not brought back: its name stays removed. One archived for age is (C32).
        guard let book = activityEvidence.aiLabels?.book, let label = book.labels.first(where: { $0.id == labelID }),
              !(label.archived && book.removedNames.contains(label.name)) else { return false }
        let name = WorkTypeDefinition.normalisedName((typed ?? label.name).trimmingCharacters(in: .whitespacesAndNewlines))
        guard !name.isEmpty else {
            publishCorrectionError("Enter a name for the category.")
            return false
        }
        var kept = label.hiddenDefinition
        kept.isUnkeptAILabel = false
        kept.name = name
        let carriers = engine.archive.records.filter { $0.workType.rawValue == labelID }
        let before = engine.store.workTypeDefinitions
        // The person's categories take it before the label leaves its file: a crash between leaves both holding the
        // id, which the launch settles (`installCategoryAssistant`), where the other order left neither and its
        // records read "Other". A save refused there takes the category back, so it keeps nothing.
        guard keepCategory(kept) else { return false }
        if let why = updateAILabels({ book in
            book.labels.removeAll { $0.id == labelID }
            carriers.forEach { book.recordChoice(recordID: $0.id, chosen: labelID) }
        }) {
            engine.store.workTypeDefinitions = before
            publishCorrectionError(why)
            correctionRetry = nil
            return false
        }
        refresh()
        return true
    }

    /// Merge Into: every session carrying the label takes `type` as the person's, as one undo step.
    @discardableResult
    func mergeAILabel(_ labelID: String, into type: WorkType) -> Bool {
        guard WorkType.startable.contains(type) else { return false }
        return retireAILabel(labelID, giving: type)
    }

    /// Remove: every session carrying the label becomes Unsorted as the person's, as one undo step (C12).
    @discardableResult
    func removeAILabel(_ labelID: String) -> Bool { retireAILabel(labelID, giving: .unsorted) }

    /// Use on a shadow-mode suggestion (C8, C9): a pick files the stretches it was offered for; a label, or a new
    /// one proposed, is kept first, so they are filed under a category of the person's. Refused, with the reason
    /// shown, when what is offered now is not `shown`, the suggestion the open report drew: it may have lapsed since.
    @MainActor @discardableResult
    func useAISuggestion(_ shown: AISessionReport.Suggestion, for session: DaySession) -> Bool {
        guard let assistant = activityEvidence.categoryAssistant,
              let answer = offeredAIAnswer(for: session, in: records(of: session)),
              AISessionReport.Suggestion(answer) == shown else {
            publishCorrectionError("That suggestion is no longer offered. Open the report again to see what is.")
            // An older action's Retry must not run in this one's place, as `canRewrite` says.
            correctionRetry = nil
            return false
        }
        // The stretches whose own suggestion is what Use takes, worked out before keeping changes what one comes to.
        // Only they are filed: another stretch of the session keeps its category and its own offer.
        let took = session.recordIDs.filter { offeredAIAnswer(for: $0, assistant) == answer }
        let stretches = { self.engine.archive.records.filter { took.contains($0.id) } }
        // Filing's own refusals come before a category is kept, so a refused Use leaves none behind.
        guard let offering = took.first, canRewrite(stretches()) else { return false }
        let chosen: String, categories = engine.store.workTypeDefinitions, book = activityEvidence.aiLabels?.book
        switch answer {
        case .pick(let id): chosen = id
        // Live: `offeredAIAnswer` offers one kept since as a pick, and one retired or aged out not at all.
        case .label(let id): guard keepAILabel(id) else { return false }; chosen = id
        case .proposed(let id, let name): guard keepProposal(id, name, from: offering) else { return false }; chosen = id
        case .none: return false
        }
        // True once the records landed, their journal save refused or not, so what follows is never skipped.
        guard fileStretches(stretches(), as: WorkType(rawValue: chosen)) else {
            if case .pick = answer { return false }
            // Nothing landed: the category kept for it goes again, so the offer stays as it was. The label file
            // first, as Keep's order reversed: refused, the category stays and the label is the person's.
            let why = correctionError
            if case .label(let id) = answer, let book, let label = book.labels.first(where: { $0.id == id }) {
                // Only what Keep changed: the label and its carriers' choices. An answer saved since stays.
                let carriers = Set(engine.archive.records.filter { $0.workType.rawValue == id }.map(\.id))
                let undone = updateAILabels { now in
                    if !now.labels.contains(where: { $0.id == id }) {
                        now.labels.insert(label, at: min(book.labels.firstIndex { $0.id == id } ?? 0, now.labels.count))
                    }
                    for entry in book.tally where carriers.contains(entry.recordID) {
                        guard let index = now.tally.firstIndex(where: { $0.recordID == entry.recordID }) else { continue }
                        now.tally[index].chosen = entry.chosen
                    }
                }
                guard undone == nil else { return false }
            }
            engine.store.workTypeDefinitions = categories
            refresh()
            publishCorrectionError(why)
            correctionRetry = nil
            return false
        }
        // The tally holds each stretch's answer as first given; Use took what it comes to now (a proposal a
        // category took since is a pick of it), so that is what those stretches' choice is compared with.
        updateAILabels { book in took.forEach { book.retallyAnswer(chosen, recordID: $0) } }
        assistant.withdraw(took)
        return true
    }

    /// The tally's hook in the person's own category change (C14), whichever path made it: the card's picker,
    /// Change, Use, a tidy-up. Counted once the records landed, their journal save refused or not, as `rewrite` does.
    func tallyChoices(of correction: SessionCorrection, _ records: [SessionRecord]) {
        guard case .workType = correction, !records.isEmpty, records.allSatisfy(engine.archive.records.contains) else { return }
        updateAILabels { book in records.forEach { book.recordChoice(recordID: $0.id, chosen: $0.workType.rawValue) } }
    }

    /// Undo of a rewrite put `records` back: a label they carry that Merge Into or Remove retired is in use again
    /// and its name may be proposed again, unless another retired label still holds it. The tally keeps the choice
    /// made; forgotten answers stay forgotten. One whose name a category of the person's has taken since stays
    /// archived, its name removed: the records read it archived (C32). Nil when saved or nothing changed, else why
    /// the file was not saved.
    @discardableResult
    func aiLabelsFollowUndo(of records: [SessionRecord]) -> String? {
        let ids = Set(records.map(\.workType.rawValue)), categories = WorkTypeCatalog.namedDefinitions(besides: [])
        return updateAILabels { book in
            var back: Set<String> = []
            for index in book.labels.indices where book.labels[index].archived && ids.contains(book.labels[index].id)
                && WorkTypeDefinition.nameProblem(book.labels[index].name, for: book.labels[index].id, among: categories) == nil {
                book.labels[index].archived = false
                back.insert(book.labels[index].name)
            }
            let held = Set(book.labels.filter(\.archived).map(\.name))
            book.removedNames.removeAll { back.contains($0) && !held.contains($0) }
        }
    }

    // MARK: - Private

    /// Archived rather than deleted, so a record an Undo brings back still reads the label (`aiLabelsFollowUndo`).
    /// Archived, it is never reused, offered or counted toward the limits (C15).
    private func retireAILabel(_ labelID: String, giving type: WorkType) -> Bool {
        guard let labels = activityEvidence.aiLabels, labels.book.labels.contains(where: { $0.id == labelID }) else { return false }
        let changed = engine.archive.records.filter { $0.workType.rawValue == labelID }.map { record -> SessionRecord in
            var next = record
            next.workType = type
            next.categorySource = .user
            return next
        }
        // Every refusal comes before the label goes, so a refused action leaves the label as it was.
        guard canRewrite(changed) else { return false }
        // No running stretch carries one: a start from idle falls back to a startable category (`beginFreshSession`).
        // The label goes first, so a write refused here leaves no record changed, and records that then fail to
        // change still read it, retired: done again, this passes the guard above.
        var book = labels.book
        if let index = book.labels.firstIndex(where: { $0.id == labelID }) {
            book.labels[index].archived = true
            if !book.removedNames.contains(book.labels[index].name) { book.removedNames.append(book.labels[index].name) }
        }
        book.forget(labelID: labelID)
        if let why = labels.save(book, at: now()) {
            publishCorrectionError(why)
            return false
        }
        return rewrite(changed)
    }

    /// The refusals `rewriteRecords` would make before its write, made first, with the reason shown. No Retry is
    /// kept for a rewrite: an older action's is cleared, so it cannot run in this one's place.
    private func canRewrite(_ changed: [SessionRecord]) -> Bool {
        guard !changed.isEmpty else { return true }
        let running = engine.state != .idle && changed.contains { $0.id == engine.activeRecordID }
        let why: String? = hasUnresolvedAwayDecision ? "Answer the away question first."
            : engine.archive.isReadOnly ? "Session history couldn't be read or set aside, so it isn't being changed. "
                + "Reveal Data Folder in Settings, Privacy & Data shows where it is."
            : running ? "Those sessions changed since. Reopen the day and try again."
            : engine.prepareCorrection() ? nil : engine.awayDecisionError
        guard let why else { return true }
        publishCorrectionError(why)
        correctionRetry = nil
        return false
    }

    /// Writes `changed` over the records of the same ids as one undo step, then counts each as the person's
    /// choice. False, with the reason shown, when the records did not change. `filings`: what the change taught
    /// the remembered choices, kept with it so its Undo takes them back.
    private func rewrite(_ changed: [SessionRecord], remembering filings: [RememberedFiling] = []) -> Bool {
        if !changed.isEmpty {
            guard canRewrite(changed) else { return false }
            let done = engine.rewriteRecords(changed, remembering: filings)
            publishCorrectionError(done ? nil : engine.awayDecisionError)
            correctionRetry = nil
            // Landed with only the journal save refused: the change stands and the error says so.
            guard done || changed.allSatisfy({ engine.archive.records.contains($0) }) else { return false }
            publishCanUndoCorrection(!corrections.isEmpty || engine.canUndoAwayDecision)
            refresh()
        }
        updateAILabels { book in changed.forEach { book.recordChoice(recordID: $0.id, chosen: $0.workType.rawValue) } }
        return true
    }

    /// Use's filing: `records` alone become the person's under `type`, as one undo step, and what that teaches of
    /// each kind of stretch is remembered as Change remembers it (B6), the AI's answer kept and the app's own
    /// vetoed, and taken back by its Undo. True once the records landed.
    private func fileStretches(_ records: [SessionRecord], as type: WorkType) -> Bool {
        let filing = categoryFiling(of: records, as: type)
        let filings = rememberedFilings(filing)
        let changed = records.map { record -> SessionRecord in
            var next = record
            next.workType = type
            next.categorySource = .user
            return next
        }
        guard rewrite(changed, remembering: filings) else { return false }
        if !filings.isEmpty { keepFiling(filing, shown: correctionError == nil) }
        return true
    }

    /// A new label kept from a suggestion, drawn as the dominant activity of the stretch that proposed it says (C16).
    private func keepProposal(_ id: String, _ name: String, from recordID: UUID) -> Bool {
        guard let credited = metadataArchive.metadata(for: recordID)?.activityShape?.credited,
              let top = AITrigger.ranked(credited).first, let dominant = AppPurpose(rawValue: top.key) else { return false }
        let look = LabelLook.look(for: dominant)
        return keepCategory(WorkTypeDefinition(id: id, name: name, symbolName: look.symbolName, hue: look.hue,
                                               countsTowardFocus: dominant.isFocused))
    }

    /// Into the person's own categories, replacing one of the same id, once its name is free (`nameIsFree`).
    @discardableResult
    private func keepCategory(_ definition: WorkTypeDefinition) -> Bool {
        guard nameIsFree(definition) else { return false }
        engine.store.workTypeDefinitions = engine.store.workTypeDefinitions.filter { $0.id != definition.id } + [definition]
        return true
    }

    /// The category editor's rule (`nameProblem`), with the reason shown when it refuses, against Break and Unsorted
    /// too and every live label: one aged out may share a name with a category or label made since (C32), and two
    /// proposals may share one.
    private func nameIsFree(_ definition: WorkTypeDefinition) -> Bool {
        let live = activityEvidence.aiLabels?.book.liveLabels(now: now()) ?? []
        guard let problem = WorkTypeDefinition.nameProblem(definition.name, for: definition.id,
                                                           among: WorkTypeCatalog.namedDefinitions(besides: live)) else { return true }
        publishCorrectionError(problem)
        // An older action's Retry must not run in this one's place, as `canRewrite` says.
        correctionRetry = nil
        return false
    }

    /// One change to the label file, saved, and the catalogue told when the labels moved. Nil when saved, when the
    /// store has no assistant or when nothing changed; else why the file was not saved, which is logged.
    @discardableResult
    func updateAILabels(_ change: (inout AILabelBook) -> Void) -> String? {
        guard let labels = activityEvidence.aiLabels else { return nil }
        var book = labels.book
        change(&book)
        let before = labels.book
        guard book != before else { return nil }
        if let why = labels.save(book, at: now()) {
            Diagnostics.log("ai-labels.json not saved: \(why)")
            return why
        }
        if labels.book.labels != before.labels { WorkTypeCatalog.shared.install(aiLabels: labels.book.labels) }
        return nil
    }
}
