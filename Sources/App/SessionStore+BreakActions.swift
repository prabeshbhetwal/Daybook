import SwiftUI
import AppKit
import Combine

extension SessionStore {
    // MARK: - Taking a break

    var isOnBreak: Bool { engine.activeBreak != nil }
    var activeBreak: ActiveBreak? { engine.activeBreak }

    /// Whether Take a break would begin one. The buttons and the Session menu
    /// offer it only then, so none is pressed to be refused in silence.
    var canTakeBreak: Bool { engine.canStartBreak && !hasUnresolvedAwayDecision }

    /// Begins a break. `length` defaults to the reminder's own, never less
    /// than five minutes; a break begun from the menu is five. Refused while
    /// the away question waits or the session is paused because nobody was
    /// here, as the engine refuses.
    func startBreak(length: TimeInterval? = nil, label: String? = nil, from prompt: BreakPrompt? = nil) {
        let planned = length
            ?? prompt.map { max($0.tier.breakLength, BreakLength.standard) }
            ?? BreakLength.standard
        guard engine.startBreak(length: planned, label: label) else { return }
        let moment = now()
        sustained.reset()
        breakEndRetryAfter = nil
        if let prompt { breakLog.setOutcome(.started, for: prompt.id, at: moment) }
        markRecentPromptStarted(except: prompt?.id, at: moment)
        publishBreakChange()
        onBreakBegan?()
    }

    /// End break, Resume and Done. The break is recorded at the length it had;
    /// `refresh` settles its end, like any other end of a break.
    func endBreak() {
        guard isOnBreak else { return }
        guard engine.endBreak() != nil else {
            // The stretch the break paused could not be saved; the break stands.
            publishCorrectionError(engine.awayDecisionError)
            return
        }
        publishBreakChange()
    }

    /// Every action that starts, stops or replaces a session ends the break
    /// first: the engine leaves one alone, and a session beside a running
    /// break, or a break with no session left, is not a state to be in.
    /// False when the break could not be ended; it and its error stay, and
    /// the caller does nothing more.
    @discardableResult
    func endBreakIfNeeded() -> Bool {
        guard isOnBreak else { return true }
        endBreak()
        return !isOnBreak
    }

    /// +5 min: five minutes more than there are left, and five from now when
    /// the break is already over by more than that.
    func extendBreak() {
        guard let brk = engine.activeBreak else { return }
        let overdue = min(brk.remaining(at: now()), 0)
        // The engine re-arms the break-over prompt itself.
        engine.extendBreak(by: BreakLength.extra - overdue)
        sustained.reset()
        publishBreakChange()
    }

    /// Put the reminder off. The third time is refused: `canLater` is the
    /// prompt's to say, and the clock does not count it.
    func laterBreak(_ prompt: BreakPrompt) {
        guard prompt.canLater else { return }
        let moment = now()
        engine.store.breakClock.later(prompt.tier, at: moment)
        breakLog.noteLater(for: prompt.id, at: moment)
        refreshBreak()
    }

    /// Not this one: that reminder starts again, and no rest is recorded.
    func skipBreak(_ prompt: BreakPrompt) {
        let moment = now()
        engine.store.breakClock.skip(prompt.tier, at: moment)
        breakLog.setOutcome(.skipped, for: prompt.id, at: moment)
        refreshBreak()
    }

    /// The reminder went away with no answer. One already answered stays so.
    func breakPromptUnanswered(_ prompt: BreakPrompt) {
        guard breakLog.prompts.first(where: { $0.id == prompt.id })?.outcome == nil else { return }
        breakLog.setOutcome(.unanswered, for: prompt.id, at: now())
    }

    // MARK: - From the ticker

    /// Once a tick, in this order: a break nobody came back to ends at its
    /// cap; the time left is published; the planned end is announced until it
    /// has reached the screen; and input after it, told apart from a glance,
    /// ends the break where that input began. An end that cannot be saved is
    /// reported, and tried again every few seconds rather than every second.
    func tickBreak() {
        guard let brk = engine.activeBreak else {
            syncBreakRemaining()
            return
        }
        let moment = now()
        let mayEnd = breakEndRetryAfter.map { moment >= $0 } ?? true
        if mayEnd, moment >= brk.capEnd(longAwayCap: engine.store.longAwayCap) {
            if engine.expireBreakIfOutgrown() != nil { publishBreakChange() }
            else { breakEndFailed(at: moment) }
            return
        }
        let remaining = brk.remaining(at: moment)
        breakRemaining = remaining
        guard remaining <= 0 else { return }
        // Neither the prompt nor input counts where no one could be: a wake
        // resets the idle clock with nobody there, and a locked screen has no
        // one in front of it.
        guard !screenLocked, !presenceGate.isAwaitingConfirmation else { return }
        if !brk.overNoticed, onBreakOver?(brk) == true {
            engine.markBreakOverNoticed()
            publishBreakChange()
        }
        guard mayEnd, idle.idleSeconds() <= 1,
              let began = sustained.record(activeAt: moment) else { return }
        // Reset only by an end that was saved: a refused one keeps the window
        // it met, and is tried again on the five-second gate.
        if engine.endBreak(at: began) != nil {
            sustained.reset()
            publishBreakChange()
        } else { breakEndFailed(at: moment) }
    }

    private func breakEndFailed(at moment: Date) {
        breakEndRetryAfter = moment.addingTimeInterval(TimeInterval(SessionStore.breakCheckSeconds))
        publishCorrectionError(engine.awayDecisionError)
    }

    // MARK: - After a break

    /// Runs once for each break that ends, whichever way it ended: here, on
    /// the ticker, or inside the engine (a session adopted by Start, a
    /// discarded one). `refresh` calls it, and so every path that ends a
    /// break and refreshes settles it.
    func settleEndedBreak() {
        guard let ended = engine.lastEndedBreak, ended.id != lastSettledBreak else { return }
        lastSettledBreak = ended.id
        afterBreakEnded(ended)
    }

    /// Only a rest that was recorded is a rest that counts: every reminder
    /// starts again from the end of a break that lasted long enough to be
    /// written down, and a glance at Start break and End break restarts none.
    func afterBreakEnded(_ ended: EndedBreak) {
        // A session that goes on is told where the person is. With none, there
        // is nothing to tell, and a work app in front must not start one.
        if engine.state == .running { feedFrontmostApplication() }
        if ended.end.timeIntervalSince(ended.start) >= engine.store.minimumRecordedSession {
            engine.store.breakClock.credit(at: ended.end)
        }
        sustained.reset()
        if breakEndRetryAfter != nil {
            breakEndRetryAfter = nil
            publishCorrectionError(nil)
        }
        resumeTrackingAfterBreak(ended)
        onBreakEnded?()
    }

    /// Recording starts again with the app in front. The person who ended the
    /// break is at the Mac, which is as good as an unlock. A break that ran out
    /// its cap, or was found past it at launch, ended with nobody there: the
    /// app waits, as after a wake, for the gate's own sign of a return.
    private func resumeTrackingAfterBreak(_ ended: EndedBreak) {
        if let front = frontmostApplication() {
            prepareTrackingResume(bundleID: front.bundleID, name: front.name)
        }
        if ended.byPerson { _ = confirmPresence(at: now()) }
    }

    /// The time left on the break under way, from the engine, wherever the
    /// store learns of it: a break restored at launch has some before the
    /// ticker's first second.
    func syncBreakRemaining() {
        let left = engine.activeBreak?.remaining(at: now()) ?? 0
        if breakRemaining != left { breakRemaining = left }
    }

    // MARK: - Private

    /// The engine's break methods save but do not announce, so the store does
    /// what it does for any change of state: mirror it and recompute.
    private func publishBreakChange() {
        apply(engine.state)
    }

    /// A reminder shown a moment ago and not answered or only put off, then a
    /// break begun by hand: the break is the answer.
    private func markRecentPromptStarted(except taken: UUID?, at moment: Date) {
        guard let recent = breakLog.prompts.last, recent.id != taken,
              moment.timeIntervalSince(recent.shown) <= Self.answeredWithin,
              recent.outcome == nil || recent.outcome == .unanswered || recent.outcome == .later
        else { return }
        breakLog.setOutcome(.started, for: recent.id, at: moment)
    }

    private static let answeredWithin: TimeInterval = 600

    /// Activations during a break are dropped by the engine, so the session
    /// that goes on would remember the app that was in front before the break.
    private func feedFrontmostApplication() {
        guard let front = frontmostApplication() else { return }
        engine.transition(on: .appActivated(bundleID: front.bundleID, name: front.name))
    }
}
