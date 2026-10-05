import Foundation

/// The state machine and all time arithmetic. Owns `CategoryManager` and
/// `PersistenceStore`. Never calls `Date()` directly — everything goes through
/// the injected `now` closure so the logic is testable headlessly (§7).
final class SessionEngine {

    // MARK: - Outputs

    /// Emitted exactly once per real transition (and on session identity changes
    /// such as reset/rename), never on no-ops.
    var onStateChanged: ((SessionState) -> Void)?
    /// Raised when an extended break needs a user decision (D10/D11).
    var onNeedsDecision: ((TimeInterval, String) -> Void)?
    /// "Is this app part of the running work?" — supplied by the store, which
    /// knows the thread's apps from the usage archive; the engine knows only
    /// the app in front. Consulted when the user comes back from an absence in
    /// a different app than they left in. Nil keeps the thread, which is what
    /// every caller without usage data should get.
    var threadContextMatcher: ((String?) -> Bool)?

    // MARK: - Collaborators

    let store: PersistenceStore
    let categories: CategoryManager
    let archive: SessionArchive

    // MARK: - State

    var state: SessionState = .idle
    var sessionStartDate: Date
    var totalPausedDuration: TimeInterval = 0
    var pausedSpans: [DateInterval] = []
    var currentAppName: String = "—"
    var currentAppBundleID: String?

    var pauseStartDate: Date?
    var awayInterval: (start: Date, trigger: AwayTrigger)?
    /// Absence that ended while the away card was up. D10 records but never
    /// resolves an away interval during a decision, and `apply` used to drop it
    /// — so a second lock while the card sat unanswered dissolved into the
    /// successor session as work. Banked here and handed to whichever session
    /// survives the decision.
    var shadowAway: TimeInterval = 0
    var pendingDwell: DispatchWorkItem?
    /// When the extended-break alert was raised. Time spent deciding is never work.
    var decisionStartDate: Date?
    /// The app in front when the pending absence was noticed — before the user
    /// did anything on return. Same app on return, or one of the work's apps,
    /// means the same piece of work; a different one means new work, and the
    /// old thread is kept for Continue rather than stretched over it.
    var departureApp: String?
    /// A name for the break about to be recorded — "Dinner" — given with the
    /// answer. Consumed by the next `.tookBreak` and cleared with every
    /// decision, so a label never outlives the question it answered.
    var pendingAwayLabel: String?
    var awayDecisions: [AwayDecisionReceipt] = []
    /// Compatibility selection; changing selection never discards older rows.
    var lastAwayDecision: AwayDecisionReceipt? {
        get { awayDecisions.last }
        set {
            guard var receipt = newValue else { return }
            receipt.sequence = correctionGeneration + 1
            awayDecisions.removeAll { $0.id == receipt.id || ($0.range == receipt.range
                && $0.threadID == receipt.threadID && $0.sessionStart == receipt.sessionStart) }
            awayDecisions.append(receipt)
        }
    }
    let decisionHistory: DecisionHistory
    var correctionGeneration = 0
    var liveCorrectionGeneration = 0
    var transitionRevision: UInt64 = 0
    var lastLongAwayTransition: LongAwayTransitionResult?
    var decisionHistoryRevision: Int { correctionGeneration }
    var fieldCorrections: [SessionStoreCorrectionState] {
        if decisionHistory.pendingAfterIsCommitted(in: archive), let pending = decisionHistory.document.pending {
            return pending.fieldsAfter
        }
        return decisionHistory.document.fields
    }
    var retainedCorrectionRecordIDs: Set<UUID> {
        var ids = Set(awayDecisions.flatMap { receipt in
            [receipt.insertedRecord?.id, receipt.expectedCreditRecord?.id, receipt.legacyOriginalRecord?.id].compactMap { $0 }
        })
        for field in fieldCorrections { ids.formUnion(field.archiveRecordIDs) }
        if let pending = decisionHistory.document.pending {
            let pendingIDs = Set((pending.removed + pending.added).map(\.id))
            ids.formUnion(decisionHistory.pendingAfterIsCommitted(in: archive)
                ? pendingIDs.subtracting(pending.retiredRecordIDs ?? []) : pendingIDs)
        }
        return ids
    }
    func awayDecision(id: UUID) -> AwayDecisionReceipt? { awayDecisions.first { $0.id == id } }
    var awayDecisionError: String?
    var pendingDecisionID: UUID?
    var workBeforePendingAway: TimeInterval?
    /// When the user actually came back from the pending absence — what the
    /// card's range ends at. Usually the same instant as `decisionStartDate`,
    /// but a restore re-stamps that one to keep the arithmetic honest, and the
    /// absence did not move just because the app relaunched.
    var awayReturnedAt: Date?

    let now: () -> Date
    let ownBundleID: String?
    /// Disabled in the self-test so no work items outlive the process.
    let schedulesDwell: Bool

    /// The intent typed for the running session. May be empty — an empty intent
    /// never blocks a start.
    var sessionName: String {
        get { store.sessionName }
        set {
            store.sessionName = newValue
            persist()
            onStateChanged?(state)
        }
    }

    /// What kind of work the running session is.
    var activeWorkType: WorkType = .deepWork
    /// Frontmost bundle id captured when the session started, informational only.
    var activeDetectedApp: String?
    /// The thread the running session belongs to. A fresh session gets a fresh
    /// thread; continuing adopts an existing one.
    var activeThreadID = UUID()
    /// The identity under which this exact stretch will be archived.
    var activeRecordID = UUID()
    /// Whether the running session was started by the detector rather than the
    /// user. Only the app's own guesses may be undone automatically.
    var activeIsAuto = false
    var activeAutomaticAction: ActivityAutomaticAction?

    var breakThreshold: TimeInterval {
        get { store.breakThreshold }
        set {
            store.breakThreshold = newValue
            persist()
            onStateChanged?(state)
        }
    }

    init(store: PersistenceStore = PersistenceStore(),
         archive: SessionArchive? = nil,
         ownBundleID: String? = Bundle.main.bundleIdentifier,
         schedulesDwell: Bool = true,
         correctionWriteOverride: (() -> String?)? = nil,
         now: @escaping () -> Date = Date.init) {
        self.store = store
        self.archive = archive ?? SessionArchive(now: now)
        self.decisionHistory = DecisionHistory(directory: self.archive.dataDirectoryURL,
                                              writeOverride: correctionWriteOverride)
        self.categories = CategoryManager(store: store)
        self.ownBundleID = ownBundleID
        self.schedulesDwell = schedulesDwell
        self.now = now
        self.sessionStartDate = now()
        self.archive.capacityRetirementHandler = { [weak self] record in
            guard let self else { return "The correction journal owner is unavailable. No history was retired." }
            let before = self.snapshot()
            // Away and Watching also append here. Only correction metadata
            // changes; this handler must not end or replay the current stretch.
            return self.commitCorrection(before: before, adding: [record], allowsEviction: true, operation: .metadataOnly)
                ? nil : self.awayDecisionError
        }
    }

    deinit {
        pendingDwell?.cancel()
    }

    /// Starts one rule-owned thread from exact foreground evidence. A quiet
    /// choice may be answered after Daybook itself came forward; that
    /// control interval is represented as excluded pause time rather than
    /// silently credited.
    /// True while the running automatic session is a continuation of an
    /// earlier automatic stretch of the same rule, rather than a new thread.
    /// Transient: the notice that announces the session reads it, nothing
    /// persists it.
    var activeThreadWasContinued = false
}
