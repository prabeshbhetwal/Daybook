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

    // MARK: - Collaborators

    let store: PersistenceStore
    let categories: CategoryManager
    let archive: SessionArchive

    // MARK: - State

    private(set) var state: SessionState = .idle
    private(set) var sessionStartDate: Date
    private(set) var totalPausedDuration: TimeInterval = 0
    private(set) var currentAppName: String = "—"
    private(set) var currentAppBundleID: String?

    private var pauseStartDate: Date?
    private var awayInterval: (start: Date, trigger: AwayTrigger)?
    /// Absence that ended while the away card was up. D10 records but never
    /// resolves an away interval during a decision, and `apply` used to drop it
    /// — so a second lock while the card sat unanswered dissolved into the
    /// successor session as work. Banked here and handed to whichever session
    /// survives the decision.
    private var shadowAway: TimeInterval = 0
    private var pendingDwell: DispatchWorkItem?
    /// When the extended-break alert was raised. Time spent deciding is never work.
    private var decisionStartDate: Date?

    private let now: () -> Date
    private let ownBundleID: String?
    /// Disabled in the self-test so no work items outlive the process.
    private let schedulesDwell: Bool

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
    private(set) var activeWorkType: WorkType = .deepWork
    /// Frontmost bundle id captured when the session started, informational only.
    private(set) var activeDetectedApp: String?
    /// The thread the running session belongs to. A fresh session gets a fresh
    /// thread; continuing adopts an existing one.
    private(set) var activeThreadID = UUID()
    /// Whether the running session was started by the detector rather than the
    /// user. Only the app's own guesses may be undone automatically.
    private(set) var activeIsAuto = false

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
         now: @escaping () -> Date = Date.init) {
        self.store = store
        self.archive = archive ?? SessionArchive(now: now)
        self.categories = CategoryManager(store: store)
        self.ownBundleID = ownBundleID
        self.schedulesDwell = schedulesDwell
        self.now = now
        self.sessionStartDate = now()
    }

    deinit {
        pendingDwell?.cancel()
    }

    // MARK: - Derived values (D1, D2)

    /// `elapsed = (now - sessionStart) - totalPaused - currentPauseSoFar`.
    /// The in-flight pause is subtracted live; it only lands in
    /// `totalPausedDuration` on exit from the paused state.
    var elapsed: TimeInterval {
        let gross = interval(from: sessionStartDate)
        let live = pauseStartDate.map { interval(from: $0) } ?? 0
        return max(0, gross - totalPausedDuration - live)
    }

    /// Counts the running session. Showing "42m focused" beside "0 sessions" is
    /// two truths on one screen.
    var sessionsToday: Int {
        archive.sessionsToday() + (state == .idle ? 0 : 1)
    }

    /// The longest session today, running one included.
    var longestToday: TimeInterval {
        max(archive.longestToday(), elapsedToday())
    }

    /// Today's completed work plus the part of the running session that happened
    /// today.
    var todayTotal: TimeInterval {
        archive.todayTotal() + elapsedToday()
    }

    /// The running session's work that belongs to today. A session begun before
    /// midnight must not donate last night's hours to this morning's goal bar —
    /// that is how a session left open across a night showed "18h 51m of 4h,
    /// goal met" before anyone had done a minute's work.
    /// The running session's span, for figures that intersect it with something
    /// else. Nil when idle.
    var runningSpan: (start: Date, end: Date)? {
        state == .idle ? nil : (start: sessionStartDate, end: now())
    }

    func elapsedToday(calendar: Calendar = .current) -> TimeInterval {
        guard state != .idle else { return 0 }
        let moment = now()
        let dayStart = calendar.startOfDay(for: moment)
        guard sessionStartDate < dayStart else { return elapsed }
        let span = moment.timeIntervalSince(sessionStartDate)
        guard span > 0 else { return 0 }
        let todayShare = moment.timeIntervalSince(dayStart) / span
        return elapsed * min(1, max(0, todayShare))
    }

    /// Wall-clock interval with backwards-skew clamping (D1).
    private func interval(from date: Date) -> TimeInterval {
        let raw = now().timeIntervalSince(date)
        if raw < 0 {
            Diagnostics.log("clock skew: negative interval \(raw)s clamped to 0")
            return 0
        }
        return raw
    }

    // MARK: - Transition table (§3.1)

    func transition(on event: SessionEvent) {
        let previous = state
        var forceEmit = false

        switch (state, event) {

        // .idle
        case (.idle, .launch):
            beginFreshSession()
        case (.idle, .appActivated(let bundleID, let name)):
            recordApp(bundleID: bundleID, name: name)
            if categories.category(for: bundleID) == .work { beginFreshSession() }
        case (.idle, .resetSession):
            beginFreshSession()
            forceEmit = true
        case (.idle, .markedAway), (.idle, .idleObserved):
            break // nothing to pause; the coordinator still stops recording
        case (.idle, _):
            break // documented no-op: nothing runs before the session starts

        // .running
        case (.running, .awayBegan(let trigger)):
            recordAway(trigger)
        case (.running, .awayEnded):
            resolveAway()
        case (.running, .appActivated(let bundleID, let name)):
            if isSelf(bundleID) { break }   // our own alert must not cancel a dwell
            recordApp(bundleID: bundleID, name: name)
            cancelDwell()
            if categories.category(for: bundleID) == .breakTime, let bundleID {
                scheduleDwell(for: bundleID)
            }
        case (.running, .dwellExpired(let bundleID)):
            if currentAppBundleID == bundleID,
               categories.category(for: bundleID) == .breakTime {
                enterPause(reason: .distractionApp(bundleID: bundleID))
            }
        case (.running, .overrideApplied(let bundleID)):
            if currentAppBundleID == bundleID,
               categories.category(for: bundleID) == .breakTime {
                cancelDwell()
                enterPause(reason: .distractionApp(bundleID: bundleID))
            }
        case (.running, .manualPause):
            enterPause(reason: .manual)
        case (.running, .markedAway):
            enterPause(reason: .away)
        case (.running, .idleObserved(let seconds)):
            if seconds >= FocusConstants.idlePauseThreshold {
                enterPause(reason: .idle, at: now().addingTimeInterval(-seconds))
            }
        case (.running, .resetSession):
            archiveCurrentSession()
            beginFreshSession()
            forceEmit = true
        case (.running, .launch), (.running, .manualResume), (.running, .decision):
            break // documented no-op: already running

        // .paused
        case (.paused(let reason), .appActivated(let bundleID, let name)):
            if isSelf(bundleID) { break }
            recordApp(bundleID: bundleID, name: name)
            cancelDwell()
            if reason == .idle {
                // Any activation is input, and input is the user back. An idle
                // pause is the app's own observation rather than the user's
                // act, so its end is resolved like any absence the app
                // observed: ended past the cap, asked about past the
                // threshold, resumed quietly below it. Touching a work app
                // after the cap starts a fresh one, as it does from `.idle`.
                if absenceOutgrewCap() {
                    endAbsentSession()
                    if categories.category(for: bundleID) == .work { beginFreshSession() }
                } else {
                    endIdlePause()
                }
            } else if categories.category(for: bundleID) == .work {
                if absenceOutgrewCap() {
                    // Coming back to work after an absence past the cap: the
                    // old session ended where they left, and touching a work
                    // app is the same signal that starts one from `.idle`. The
                    // thread carries over, exactly as answering "I was away"
                    // would keep it.
                    endAbsentSession()
                    beginFreshSession()
                } else {
                    leavePause()
                }
            }
            // .neutral and .breakTime leave a deliberate pause untouched (D5)
        case (.paused, .overrideApplied(let bundleID)):
            if currentAppBundleID == bundleID,
               categories.category(for: bundleID) == .work {
                leavePause()
            }
        case (.paused, .manualResume):
            if absenceOutgrewCap() {
                endAbsentSession()
                beginFreshSession()
            } else {
                leavePause()
            }
        case (.paused, .awayBegan(let trigger)):
            recordAway(trigger)
        case (.paused(let reason), .awayEnded):
            // Already paused, so the away time is accounted for by the pause
            // itself — drop the interval rather than double-counting it.
            awayInterval = nil
            // Unless the pause is an unattended one that the lock has now run
            // past the cap. That is the ordinary overnight: input stops, the
            // session pauses itself, the display sleeps and locks, and the
            // next event is this unlock in the morning. Left to the ticker,
            // the first sample after waking already sees fresh input — the
            // unlock itself — and would merge the whole night back into a
            // surviving session. Same rule as the lock path in `resolve`:
            // ended where input stopped.
            if absenceOutgrewCap() {
                endAbsentSession()
            } else if reason == .idle {
                // Unlocking is the user back. The idle pause ends the way an
                // observed absence does — asked about past the threshold.
                endIdlePause()
            }
        case (.paused, .resetSession):
            archiveCurrentSession()
            beginFreshSession()
            forceEmit = true
        case (.paused, .markedAway):
            // Already stopped, but the reason matters: it changes what the menu
            // bar says and, through the coordinator, whether the background
            // recorder keeps running. Restamping `pauseStartDate` via
            // `enterPause` would silently turn the pause so far back into work.
            cancelDwell()
            state = .paused(reason: .away)
        case (.paused(let reason), .idleObserved(let seconds)):
            // The cap is judged first, whatever this sample says. By the time
            // the first sample after a long absence arrives the user has
            // usually already touched the machine — that is often what woke
            // the ticker — so a "they are back, resume" rule evaluated first
            // folded the whole absence into a surviving session. The absence
            // is measured from the pause's own start, and past the cap the
            // session ended where input stopped, as the lock path rules in
            // `resolve(away:)`. This is also the lid-open overnight: no lock,
            // no wake event, only samples.
            if absenceOutgrewCap() {
                endAbsentSession()
            } else if reason == .idle, seconds < FocusConstants.idlePauseThreshold {
                // Only an idle pause lifts itself. A pause the user pressed
                // stays pressed until they say otherwise — the app must not
                // overrule a deliberate act just because a key was struck.
                endIdlePause()
            }
        case (.paused, .launch), (.paused, .manualPause),
             (.paused, .dwellExpired), (.paused, .decision):
            break // documented no-op

        // .awaitingUserDecision — record, never transition (D10)
        case (.awaitingUserDecision, .decision(let decision)):
            apply(decision)
        case (.awaitingUserDecision, .resetSession):
            archiveCurrentSession()
            beginFreshSession()
            forceEmit = true
        case (.awaitingUserDecision, .appActivated(let bundleID, let name)):
            if isSelf(bundleID) { break }
            recordApp(bundleID: bundleID, name: name)
        case (.awaitingUserDecision, .awayBegan(let trigger)):
            recordAway(trigger)
        case (.awaitingUserDecision, .awayEnded):
            // The card owns the pending question, but a second absence that
            // ends while it is up is a fact about time, not about the question
            // — bank it so `apply` can exclude it from whichever session
            // continues.
            if let interval = awayInterval {
                shadowAway += self.interval(from: interval.start)
                awayInterval = nil
                persist()
            }
        case (.awaitingUserDecision, .markedAway):
            // Saying "I am away" answers the pending question in the same breath:
            // the gap was a break, and this one is too.
            apply(.continueSession)
            enterPause(reason: .away)
        case (.awaitingUserDecision, .manualResume):
            // Manual escape hatch: if the alert was suppressed (D10) or dismissed
            // without an answer, the menu must still be able to free the session.
            // Resuming by hand is the conservative reading — the break is discarded.
            apply(.continueSession)
        case (.awaitingUserDecision, .launch),
             (.awaitingUserDecision, .dwellExpired), (.awaitingUserDecision, .manualPause),
             (.awaitingUserDecision, .idleObserved),
             (.awaitingUserDecision, .overrideApplied):
            break // documented no-op: the alert owns the next transition
        }

        if state != previous || forceEmit {
            persist()
            onStateChanged?(state)
        }
        if case .awaitingUserDecision(let away, let app) = state, state != previous {
            onNeedsDecision?(away, app)
        }
    }

    // MARK: - Side effects

    private func beginFreshSession() {
        // A session begun by activation is the user's, not the app's guess.
        activeIsAuto = false
        cancelDwell()
        sessionStartDate = now()
        totalPausedDuration = 0
        pauseStartDate = nil
        awayInterval = nil
        shadowAway = 0
        decisionStartDate = nil
        state = .running
    }

    /// - Parameter moment: when the pause really began. Idle pauses are
    ///   backdated to the last keypress, so the interval that proves the user is
    ///   gone is excluded along with the rest of the absence. Clamped forward to
    ///   `now()` so a bad sample can never place a pause in the future.
    private func enterPause(reason: PauseReason, at moment: Date? = nil) {
        cancelDwell()
        pauseStartDate = min(moment ?? now(), now())
        state = .paused(reason: reason)
    }

    private func leavePause() {
        if let start = pauseStartDate {
            totalPausedDuration += interval(from: start)
        }
        pauseStartDate = nil
        state = .running
    }

    /// Ends an idle pause because input has returned.
    ///
    /// An idle pause is the app's own observation, not the user's act, so its
    /// end is resolved the way any observed absence is — through
    /// `resolve(away:)`: excluded either way, asked about past `breakThreshold`,
    /// ended past the cap (callers judge the cap first). It used to resume
    /// silently at any length, so a forty-minute absence with the screen never
    /// locked was never asked about while the same forty minutes behind a lock
    /// was — and the settings explainer promised the question for both. The
    /// live pause is lifted *without* banking it: `resolve` banks the same
    /// seconds itself.
    private func endIdlePause() {
        guard let began = pauseStartDate else {
            state = .running
            return
        }
        let absence = interval(from: began)
        pauseStartDate = nil
        state = .running
        resolve(away: absence)
    }

    /// True when an unattended pause has outgrown `longAwayCap`. Only the two
    /// reasons that mean "nobody is here" qualify: a `.manual` pause is a
    /// deliberate act about a session the user is still sitting in front of,
    /// and overruling it would be the app un-pressing their button.
    private func absenceOutgrewCap() -> Bool {
        guard case .paused(let reason) = state,
              reason == .idle || reason == .away,
              let began = pauseStartDate else { return false }
        return interval(from: began) >= store.longAwayCap
    }

    /// Ends a session whose absence outgrew the cap, archived where the absence
    /// began — the same shape as the lock path in `resolve(away:)`. `elapsed`
    /// already subtracts the live pause, so the record's work is exactly what
    /// was done before they left.
    private func endAbsentSession() {
        let began = pauseStartDate
        archiveCurrentSession(endingAt: began)
        cancelDwell()
        pauseStartDate = nil
        awayInterval = nil
        shadowAway = 0
        decisionStartDate = nil
        activeIsAuto = false
        state = .idle
    }

    private func isSelf(_ bundleID: String?) -> Bool {
        guard let bundleID, let ownBundleID else { return false }
        return bundleID == ownBundleID
    }

    private func recordApp(bundleID: String?, name: String) {
        if isSelf(bundleID) { return }
        currentAppBundleID = bundleID
        currentAppName = name.isEmpty ? "—" : name
        // Neither field changes `state`, so the emit block will not persist for
        // us — write through here or the snapshot goes stale between transitions.
        persist()
    }

    /// D8 — the first away event wins; later ones are ignored while one is open.
    private func recordAway(_ trigger: AwayTrigger) {
        guard awayInterval == nil else { return }
        awayInterval = (start: now(), trigger: trigger)
        // Persist immediately so a power loss while locked still knows when the
        // away interval began, rather than falling back to the last transition.
        persist()
    }

    /// D7/D8/D9 — idempotent resolution of a single away interval.
    private func resolveAway() {
        guard let interval = awayInterval else { return }
        awayInterval = nil
        resolve(away: self.interval(from: interval.start))
    }

    private func resolve(away: TimeInterval) {
        if away < FocusConstants.awayDebounce { return }
        // Excluded the instant it is noticed, whether or not anyone answers.
        // Leaving it in the total until the card was dismissed meant an
        // overnight sleep read as nine hours of work on the goal bar — the
        // flattering direction, and the one an unanswered question must never
        // drift towards. `.mergeTime` is what adds it back.
        totalPausedDuration += away
        if away < breakThreshold {
            persist()
            return
        }
        cancelDwell()

        // An absence this long was not a break inside a session, it was the end
        // of one. Keeping the session open across it is what produced records
        // spanning thirty-two hours, and a record that covers two nights has to
        // guess which day its work belongs to no matter how the guess is made.
        // There is also nothing to ask: nobody answers "was that a break?" about
        // a night's sleep with "I was working".
        if away >= store.longAwayCap {
            archiveCurrentSession(endingAt: now().addingTimeInterval(-away))
            activeIsAuto = false
            pauseStartDate = nil
            decisionStartDate = nil
            state = .idle
            persist()
            return
        }

        decisionStartDate = now()
        state = .awaitingUserDecision(away: away, lastApp: currentAppName)
    }

    private func apply(_ decision: UserDecision) {
        guard case .awaitingUserDecision(let away, _) = state else { return }
        // An absence still open when the answer lands is closed here: answering
        // is proof the user is back. Together with the banked shadow this is
        // every second of any *second* absence the card sat through.
        if let interval = awayInterval {
            shadowAway += self.interval(from: interval.start)
        }
        awayInterval = nil
        let shadow = shadowAway
        shadowAway = 0
        // `decisionStartDate` is stamped the moment the away ended, so it is
        // when the user came back — and the away began exactly `away` before it.
        let returnedAt = decisionStartDate
        let awayStarted = returnedAt?.addingTimeInterval(-away)
        // Deliberately not subtracted from work. That rule was written for the
        // blocking alert this card replaced: with a modal in the way, time spent
        // deciding really was not work. The card blocks nothing, so the minutes
        // that pass while it sits there are ordinary minutes — usually spent
        // working, which is why the user reported the session "not starting"
        // until they answered.
        decisionStartDate = nil

        switch decision {
        case .mergeTime:
            totalPausedDuration -= away   // it was work after all (D12)
            // "I was working" answered the *first* gap. A second absence the
            // card sat through was never part of the question and stays
            // excluded.
            totalPausedDuration += shadow
            state = .running

        case .continueSession, .tookBreak, .resetTimer:
            // The session ended when they walked away. Holding it open across
            // the gap made one record span an afternoon, so its elapsed figure
            // measured the span of the work rather than any stretch worked —
            // which is how the hero timer came to read 5h 57m.
            if decision == .tookBreak, let awayStarted,
               away >= FocusConstants.minimumRecordedSession {
                // A break leaves a record so the timeline can say "Break 33m"
                // where it would otherwise show a gap and the day would look
                // abandoned. Its own thread: rest is not a segment of the work
                // it interrupts.
                archive.append(SessionRecord(name: "Break",
                                             workType: .breakTime,
                                             start: awayStarted,
                                             end: awayStarted.addingTimeInterval(away),
                                             workSeconds: away,
                                             threadID: UUID()))
            }
            // The minutes since they got back belong to the session starting
            // now, so they must come off the one that is closing — otherwise it
            // is archived with more work than its own span.
            if let returnedAt { totalPausedDuration += interval(from: returnedAt) }
            let thread = activeThreadID
            // Ends where they left, not where they answered. Stamping it `now()`
            // drew a record straight through the gap on the day timeline.
            archiveCurrentSession(endingAt: awayStarted)
            beginFreshSession()
            // Same work, resumed — unless they said it was something else.
            // `Continue Today` groups by thread, so this is what keeps an
            // afternoon split by lunch reading as one job.
            activeThreadID = decision == .resetTimer ? UUID() : thread
            // Answering is not the start of the work — coming back was.
            if let returnedAt { sessionStartDate = returnedAt }
            // A second absence between coming back and answering belongs to
            // this new session's span, and it was not work.
            totalPausedDuration += shadow
        }
    }

    private func archiveCurrentSession(endingAt endMoment: Date? = nil) {
        guard state != .idle else { return }
        // A start immediately followed by a stop is a misclick, not a session.
        // Nine such records sit in the shipped archive inflating the day's
        // session count and the quick-start tallies.
        guard elapsed >= FocusConstants.minimumRecordedSession else { return }
        archive.append(SessionRecord(name: sessionName,
                                     workType: activeWorkType,
                                     start: sessionStartDate,
                                     // Clamped both ways. `endingAt` comes from
                                     // the detector, which can be told a moment
                                     // that predates this session entirely; an
                                     // unclamped value writes end < start and
                                     // lands the record on the wrong day.
                                     end: min(max(endMoment ?? now(), sessionStartDate),
                                              now()),
                                     workSeconds: elapsed,
                                     detectedApp: activeDetectedApp,
                                     threadID: activeThreadID,
                                     isAuto: activeIsAuto))
    }

    // MARK: - Discrete sessions

    /// Begins a session. Any running session is stopped and archived first, so
    /// starting is always safe and never silently discards work.
    /// True when pressing Start would continue what is already running rather
    /// than replace it: same kind of work, already in progress.
    func wouldAdopt(workType: WorkType) -> Bool {
        state != .idle && activeWorkType == workType
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
        if state.isPaused { transition(on: .manualResume) }
        persist()
    }

    func start(workType: WorkType, intent: String, threadID: UUID = UUID(),
               isAuto: Bool = false) {
        if state != .idle { stop() }
        activeWorkType = workType
        activeDetectedApp = currentAppBundleID
        activeThreadID = threadID
        activeIsAuto = isAuto
        store.sessionName = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        transition(on: .launch)
    }

    /// Ends the running session, writes its record, and returns to `.idle`.
    /// `endingAt` exists for automatic ends: the detector notices a session is
    /// over only after the break has run its course, and the record must say
    /// when the work stopped, not when the app worked it out.
    func stop(endingAt endMoment: Date? = nil) {
        guard state != .idle else { return }
        archiveCurrentSession(endingAt: endMoment)
        // Must not survive into the next session: `beginFreshSession` can start
        // one without going through `start(_:)`, and it would inherit this flag
        // and be treated as the app's own guess.
        activeIsAuto = false
        cancelDwell()
        pauseStartDate = nil
        awayInterval = nil
        shadowAway = 0
        decisionStartDate = nil
        state = .idle
        persist()
        onStateChanged?(state)
    }

    /// Moves a running session's start earlier, crediting work that happened
    /// before the app noticed it. Only ever earlier: moving a start forward
    /// would erase real work, so a later date is refused rather than clamped
    /// silently to something the caller did not ask for.
    func backdate(to moment: Date) {
        guard state != .idle, moment < sessionStartDate else { return }
        sessionStartDate = moment
        persist()
    }

    /// Ends a session without writing a record. Used only to undo the app's own
    /// automatic start — a guess the user rejected is not history, and keeping
    /// it would put a session in the archive that never happened.
    func discard() {
        guard state != .idle else { return }
        cancelDwell()
        pauseStartDate = nil
        awayInterval = nil
        shadowAway = 0
        decisionStartDate = nil
        totalPausedDuration = 0
        activeIsAuto = false
        state = .idle
        persist()
        onStateChanged?(state)
    }

    // MARK: - Dwell guard (D6)

    private func scheduleDwell(for bundleID: String) {
        guard schedulesDwell else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.pendingDwell = nil
            self?.transition(on: .dwellExpired(bundleID: bundleID))
        }
        pendingDwell = item
        DispatchQueue.main.asyncAfter(deadline: .now() + FocusConstants.distractionDwell,
                                      execute: item)
    }

    private func cancelDwell() {
        pendingDwell?.cancel()
        pendingDwell = nil
    }

    // MARK: - Overrides

    /// D4/§5 — an explicit override is evaluated immediately against the current
    /// state rather than waiting out a fresh dwell.
    func applyOverride(_ category: AppCategory, to bundleID: String) {
        categories.setOverride(category, for: bundleID)
        let previous = state
        transition(on: .overrideApplied(bundleID: bundleID))
        // The transition emits on a real change; refresh the menu otherwise so
        // the new checkmark and category row are picked up.
        if state == previous { onStateChanged?(state) }
    }

    // MARK: - Persistence (D14)

    func persist() {
        store.saveState(snapshot())
    }

    func snapshot() -> PersistedState {
        PersistedState(state: state,
                       name: sessionName,
                       sessionStart: sessionStartDate,
                       totalPaused: totalPausedDuration,
                       pauseStart: pauseStartDate,
                       away: awayInterval,
                       lastApp: currentAppName,
                       lastAppBundleID: currentAppBundleID,
                       decisionStarted: decisionStartDate,
                       savedAt: now(),
                       threadID: activeThreadID,
                       isAuto: activeIsAuto,
                       shadowAway: shadowAway)
    }

    /// Restores a snapshot and resolves the gap since it was written through the
    /// same away path a live lock/wake would take (D14).
    func restore(from snapshot: PersistedState) {
        sessionStartDate = snapshot.sessionStart
        totalPausedDuration = snapshot.totalPaused
        pauseStartDate = snapshot.pauseStart
        currentAppName = snapshot.lastApp
        currentAppBundleID = snapshot.lastAppBundleID
        decisionStartDate = snapshot.decisionStarted
        activeThreadID = snapshot.threadID ?? UUID()
        activeIsAuto = snapshot.isAuto ?? false
        awayInterval = nil
        shadowAway = 0

        switch snapshot.kind {
        case .idle:
            state = .idle
            return
        case .paused:
            state = .paused(reason: snapshot.restoredPauseReason)
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
            totalPausedDuration += (snapshot.shadowAway ?? 0)
                + interval(from: snapshot.awayStart ?? snapshot.savedAt)
            // `?? 0`, never the threshold: `.mergeTime` subtracts this from the
            // paused total, and a fabricated value would subtract time that was
            // never added — inventing work out of a missing field.
            state = .awaitingUserDecision(away: snapshot.pendingAway ?? 0,
                                          lastApp: snapshot.lastApp)
            // Re-stamped so the gap just excluded is not excluded a second time
            // when the decision lands.
            decisionStartDate = now()
        case .running:
            state = .running
            let gap = interval(from: snapshot.awayStart ?? snapshot.savedAt)
            resolve(away: gap)
        }

        persist()
        onStateChanged?(state)
        if case .awaitingUserDecision(let away, let app) = state {
            onNeedsDecision?(away, app)
        }
    }
}
