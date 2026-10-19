import SwiftUI
import AppKit
import Combine

extension SessionStore {
    // MARK: - Taking a break

    var isOnBreak: Bool { engine.activeBreak != nil }
    var activeBreak: ActiveBreak? { engine.activeBreak }

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
        if let prompt { breakLog.setOutcome(.started, for: prompt.id, at: moment) }
        markRecentPromptStarted(except: prompt?.id, at: moment)
        breakRemaining = engine.activeBreak?.remaining(at: moment) ?? 0
        publishBreakChange()
        onBreakBegan?()
    }

    /// End break, Resume and Done. The break is recorded at the length it had,
    /// and it is a rest that counts.
    func endBreak() {
        guard isOnBreak else { return }
        guard let end = engine.endBreak() else {
            // The stretch the break paused could not be saved; the break stands.
            publishCorrectionError(engine.awayDecisionError)
            publishBreakChange()
            return
        }
        afterBreakEnded(end)
    }

    /// Every action that starts, stops or replaces a session ends the break
    /// first: the engine leaves one alone, and a session beside a running
    /// break, or a break with no session left, is not a state to be in.
    func endBreakIfNeeded() {
        if isOnBreak { endBreak() }
    }

    /// +5 min.
    func extendBreak() {
        guard isOnBreak else { return }
        // The engine re-arms the break-over prompt itself.
        engine.extendBreak(by: BreakLength.extra)
        sustained.reset()
        breakRemaining = engine.activeBreak?.remaining(at: now()) ?? 0
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
    /// ends the break where that input began.
    func tickBreak() {
        guard let brk = engine.activeBreak else {
            if breakRemaining != 0 { breakRemaining = 0 }
            return
        }
        if let end = engine.expireBreakIfOutgrown() {
            afterBreakEnded(end)
            return
        }
        let moment = now()
        let remaining = brk.remaining(at: moment)
        breakRemaining = remaining
        guard remaining <= 0 else { return }
        if !brk.overNoticed, onBreakOver?(brk) == true {
            engine.markBreakOverNoticed()
            publishBreakChange()
        }
        // Input counts only where a person could have made it: a wake resets
        // the idle clock with nobody there, and a locked screen has no one in
        // front of it.
        guard !screenLocked, !presenceGate.isAwaitingConfirmation,
              idle.idleSeconds() <= 1,
              let began = sustained.record(activeAt: moment) else { return }
        sustained.reset()
        guard let end = engine.endBreak(at: began) else {
            publishBreakChange()
            return
        }
        afterBreakEnded(end)
    }

    /// A rest that counted: every reminder starts again from its end.
    func afterBreakEnded(_ end: Date) {
        // A session that goes on is told where the person is. With none, there
        // is nothing to tell, and a work app in front must not start one.
        if engine.state == .running { feedFrontmostApplication() }
        engine.store.breakClock.credit(at: end)
        sustained.reset()
        breakRemaining = 0
        publishBreakChange()
        onBreakEnded?()
    }

    // MARK: - Private

    /// The engine's break methods save but do not announce, so the store does
    /// what it does for any change of state: mirror it and recompute.
    private func publishBreakChange() {
        apply(engine.state)
    }

    /// A reminder shown a moment ago and left unanswered, then a break begun by
    /// hand: the break is the answer.
    private func markRecentPromptStarted(except taken: UUID?, at moment: Date) {
        guard let recent = breakLog.prompts.last, recent.id != taken,
              moment.timeIntervalSince(recent.shown) <= Self.answeredWithin,
              recent.outcome == nil || recent.outcome == .unanswered else { return }
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
