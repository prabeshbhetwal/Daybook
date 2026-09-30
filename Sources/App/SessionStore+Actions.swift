import SwiftUI
import AppKit
import Combine

extension SessionStore {
    // MARK: - Actions

    /// The sole start/stop route for the global shortcut. An unresolved Away
    /// question is evidence awaiting classification, not a running state the
    /// shortcut may stop. The coordinator uses the returned route to re-present
    /// the existing answer surface; no second decision UI is introduced.
    @discardableResult
    func performSessionHotKeyAction() -> SessionHotKeyActionResult {
        guard !hasUnresolvedAwayDecision else { return .showAwayDecision }
        if engine.state == .idle {
            // The category the picker shows, as the Start button would use.
            guard replaceSession(workType: workType, intent: "") else { return .saveFailed }
            refresh()
            return .started
        }
        let origin = (engine.activeThreadID, engine.sessionStartDate)
        let stopped = engine.stop()
        let finalisationPending = stopped && engine.awayDecisionError != nil
        if !stopped || finalisationPending { retainEndingRetry(origin: origin) }
        refresh()
        return stopped ? (finalisationPending ? .stoppedPendingFinalisation : .stopped) : .saveFailed
    }

    /// Pressing Start continues a session already running on the same kind of
    /// work — including one the app started by itself — and only begins a new
    /// one when the work type differs. Background recording is unaffected
    /// either way: app usage is captured all day regardless of sessions.
    func start() {
        guard !hasUnresolvedAwayDecision else { return }
        if engine.wouldAdopt(workType: workType, intent: intent) {
            engine.adopt(intent: intent)
        } else {
            guard replaceSession(workType: workType, intent: intent) else { return }
        }
        engine.store.rememberActivity(name: intent, workType: workType)
        // Remember the pairing of the app in front and the category chosen,
        // so starting from that app next time suggests this category.
        engine.store.rememberCategoryChoice(workType, for: tracker?.currentBundleID)
        intent = ""
        refresh()
    }

    func startQuick(_ quick: QuickStart) {
        guard !hasUnresolvedAwayDecision else { return }
        workType = quick.workType
        if engine.wouldAdopt(workType: quick.workType, intent: quick.name) {
            engine.adopt(intent: quick.name)
        } else {
            guard replaceSession(workType: quick.workType, intent: quick.name) else { return }
        }
        engine.store.rememberActivity(name: quick.name, workType: quick.workType)
        intent = ""
        refresh()
    }

    /// Drives the Start button's label, so the button says what it will do.
    var startWouldContinue: Bool { engine.wouldAdopt(workType: workType, intent: intent) }

    // MARK: - Saved activities

    /// Recent names not already pinned, for the menu's second group.
    var recentActivities: [QuickStart] {
        SavedActivities.recents(quickStarts, excluding: savedActivities)
    }

    /// Whether one more can be pinned.
    var canPinActivity: Bool { savedActivities.count < SavedActivities.limit }

    /// Adds or updates a pinned activity. A matching id replaces in place; a
    /// new one goes at the end. False when the list is full or the name is
    /// blank or already pinned under another id.
    @discardableResult
    func saveActivity(_ activity: SavedActivity) -> Bool {
        var items = engine.store.savedActivities
        let name = SavedActivities.normalisedName(activity.name)
        guard !name.isEmpty, activity.workType.countsAsFocus else { return false }
        let taken = items.contains { $0.id != activity.id && SavedActivities.key($0.name) == SavedActivities.key(name) }
        guard !taken else { return false }
        if let index = items.firstIndex(where: { $0.id == activity.id }) {
            items[index] = SavedActivity(id: activity.id, name: name, workType: activity.workType)
        } else {
            guard items.count < SavedActivities.limit else { return false }
            items.append(SavedActivity(id: activity.id, name: name, workType: activity.workType))
        }
        engine.store.savedActivities = items
        savedActivities = engine.store.savedActivities
        return true
    }

    /// Pins a recent name as it was last used.
    @discardableResult
    func pinActivity(_ quick: QuickStart) -> Bool {
        saveActivity(SavedActivity(name: quick.name, workType: quick.workType))
    }

    func removeSavedActivity(id: UUID) {
        engine.store.savedActivities = engine.store.savedActivities.filter { $0.id != id }
        savedActivities = engine.store.savedActivities
    }

    /// Moves one row up or down by one place.
    func moveSavedActivity(id: UUID, up: Bool) {
        var items = engine.store.savedActivities
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let target = up ? index - 1 : index + 1
        guard items.indices.contains(target) else { return }
        items.swapAt(index, target)
        engine.store.savedActivities = items
        savedActivities = engine.store.savedActivities
    }

    /// Fills the field from a pinned activity. Never starts anything.
    func chooseActivity(_ activity: SavedActivity) {
        intent = activity.name
        workType = activity.startableWorkType
    }

    func stop() {
        guard !hasUnresolvedAwayDecision else { return }
        let thread = engine.activeThreadID, start = engine.sessionStartDate
        engine.stop()
        if let error = engine.awayDecisionError {
            publishCorrectionError(error)
            correctionRetry = .ending(threadID: thread, sessionStart: start)
        } else {
            publishCorrectionError(nil)
            correctionRetry = nil
        }
        refresh()
    }

    private func retainEndingRetry(origin: (threadID: UUID, sessionStart: Date)) {
        publishCorrectionError(engine.awayDecisionError)
        correctionRetry = .ending(threadID: origin.threadID, sessionStart: origin.sessionStart)
    }

    /// Every app-level replacement retains the originating save action before
    /// changing live identity. Callers perform their existing eligibility gate
    /// first, and only activate apps/clear drafts/backdate after true success.
    @discardableResult
    func replaceSession(workType: WorkType, intent: String, threadID: UUID = UUID(), isAuto: Bool = false) -> Bool {
        let origin = (engine.activeThreadID, engine.sessionStartDate)
        let started = engine.start(workType: workType, intent: intent, threadID: threadID, isAuto: isAuto)
        let retry = SessionCorrectionRetry.ending(threadID: origin.0, sessionStart: origin.1)
        let unfinishedEnding = engine.awayDecisionError != nil
            && engine.decisionHistory.document.pending.map { retry.matches($0) } == true
        if !started || unfinishedEnding { retainEndingRetry(origin: origin) }
        if !started { refresh() }
        return started
    }

    func togglePause() {
        guard !hasUnresolvedAwayDecision else { return }
        let resumable = !engine.state.isRunning && engine.state != .idle
        engine.transition(on: resumable ? .manualResume : .manualPause)
        _ = applyLongAwayResult()
    }

    // MARK: - Presentation helpers

    var activeIntent: String {
        engine.sessionName.isEmpty ? "Focus session" : engine.sessionName
    }

    var isIdle: Bool { state == .idle }
    var isPaused: Bool { state.isPaused }
}
