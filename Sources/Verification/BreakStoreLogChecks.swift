import Foundation

/// The reminder side of `BreakStoreChecks`: what is logged for a reminder, what
/// Later and Skip do to the clock, and nothing being due during a break.
extension BreakStoreChecks {
    /// A store with 55 minutes of use behind it, so a main break is due now.
    @MainActor
    static func makeDue(prepare: (SessionEngine, TestClock) -> Void = { _, _ in }) -> Fixture? {
        guard let f = make(prepare: prepare) else { return nil }
        f.work(-55, 0)
        return f
    }

    static func actionsAreLogged() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = makeDue() else { return ["could not create isolated preferences"] }
            defer { f.close() }
            var shown: [BreakPrompt] = []
            f.store.onBreakDue = { shown.append($0); return true }
            f.store.refresh()
            guard let prompt = shown.first else { return ["no reminder was raised"] }
            let entry = f.store.breakLog.prompts.first { $0.id == prompt.id }
            expect(shown.count == 1 && prompt.tier == .cognitive, "one main reminder is raised", &problems)
            expect(entry?.kind == .main && entry?.shown == f.clock.value,
                   "it is logged as shown now, under its own id", &problems)

            f.store.laterBreak(prompt)
            let later = f.store.breakLog.prompts.first { $0.id == prompt.id }
            expect(later?.laterCount == 1 && later?.outcome == .later, "Later is counted against it", &problems)
            expect(f.persistence.breakClock.snooze?.count == 1, "and held back on the clock", &problems)

            // A reminder that may not be put off again is not put off.
            var spent = prompt
            spent.canLater = false
            f.store.laterBreak(spent)
            expect(f.store.breakLog.prompts.first { $0.id == prompt.id }?.laterCount == 1
                   && f.persistence.breakClock.snooze?.count == 1,
                   "a third Later is refused", &problems)

            f.store.skipBreak(prompt)
            let skipped = f.store.breakLog.prompts.first { $0.id == prompt.id }
            expect(skipped?.outcome == .skipped && skipped?.laterCount == 1,
                   "Skip is logged and the Laters stay counted", &problems)
            expect(f.persistence.breakClock.floors[.cognitive] == f.clock.value
                   && f.persistence.breakClock.snooze == nil,
                   "Skip restarts that reminder and ends its Later", &problems)

            f.store.breakPromptUnanswered(prompt)
            expect(f.store.breakLog.prompts.first { $0.id == prompt.id }?.outcome == .skipped,
                   "a reminder already answered is not marked unanswered", &problems)
            return problems
        }
    }

    static func quietDuringBreak() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // Without a break the reminder is raised; that is what the rest is measured against.
            guard let control = makeDue() else { return ["could not create isolated preferences"] }
            defer { control.close() }
            var controlled = 0
            control.store.onBreakDue = { _ in controlled += 1; return true }
            control.store.refresh()
            expect(controlled == 1 && control.store.isBreakDue, "a break is due without one running", &problems)

            guard let f = makeDue() else { return problems + ["could not create isolated preferences"] }
            defer { f.close() }
            var raised = 0
            f.store.onBreakDue = { _ in raised += 1; return true }
            f.store.startBreak()
            f.store.refresh()
            f.clock.advance(120)
            f.store.refresh()
            expect(raised == 0, "no reminder is raised on a break, got \(raised)", &problems)
            expect(!f.store.isBreakDue && f.store.nextBreakTier == nil && f.store.breakCountdown == 0,
                   "nothing shows as due on a break", &problems)
            expect(f.persistence.lastBreakNotice == nil, "and no notice is written", &problems)
            return problems
        }
    }

    static func laterCountRestarts() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = make() else { return ["could not create isolated preferences"] }
            defer { f.close() }
            var shown: [BreakPrompt] = []
            f.store.onBreakDue = { shown.append($0); return true }

            // Put off twice while the work goes on; the third showing may not be.
            f.work(0, 55); f.go(toMinute: 55); f.store.refresh()
            guard let first = shown.last else { return ["no first reminder"] }
            f.store.laterBreak(first)
            f.work(55, 65); f.go(toMinute: 65); f.store.refresh()
            guard shown.count == 2, let second = shown.last else { return ["no second reminder"] }
            expect(second.canLater, "the second reminder may be put off", &problems)
            f.store.laterBreak(second)
            f.work(65, 75); f.go(toMinute: 75); f.store.refresh()
            expect(shown.count == 3 && shown.last?.canLater == false, "the third may not", &problems)

            // A rest nobody pressed Take a break for, then a new run that is due.
            f.go(toMinute: 90); f.store.refresh()
            f.work(90, 145); f.go(toMinute: 145); f.store.refresh()
            guard shown.count == 4, let fourth = shown.last else { return problems + ["no reminder in the new run"] }
            expect(fourth.canLater, "the new run's reminder may be put off", &problems)
            f.store.laterBreak(fourth)
            expect(f.persistence.breakClock.snooze?.count == 1,
                   "its first Later counts as one, got \(String(describing: f.persistence.breakClock.snooze?.count))",
                   &problems)
            f.work(145, 155); f.go(toMinute: 155); f.store.refresh()
            expect(shown.count == 5 && shown.last?.canLater == true,
                   "and it comes back with one Later still to give", &problems)

            let log = f.store.breakLog.prompts
            expect(log.count == 5 && Set(log.map(\.id)).count == 5,
                   "every showing is its own entry, got \(log.count)", &problems)
            expect(log.first { $0.id == first.id }?.laterCount == 1
                   && log.first { $0.id == fourth.id }?.laterCount == 1,
                   "each entry keeps the Later pressed on it", &problems)

            // A rest that is taken restarts the count the same way.
            f.store.startBreak(length: 300)
            f.clock.advance(300)
            f.store.endBreak()
            expect(f.persistence.breakClock.snooze == nil, "a taken break clears any Later", &problems)
            return problems
        }
    }

    static func loggingFollowsDelivery() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // Raised but not shown (the screen was out of reach): not logged, and not
            // written down as said either, so it is asked again.
            guard let missed = makeDue() else { return ["could not create isolated preferences"] }
            defer { missed.close() }
            missed.store.onBreakDue = { _ in false }
            missed.store.refresh()
            expect(missed.store.breakLog.prompts.isEmpty, "a reminder that did not reach the screen is not logged", &problems)
            expect(missed.persistence.lastBreakNotice == nil,
                   "and it is not the last thing said", &problems)

            guard let seen = makeDue() else { return problems + ["could not create isolated preferences"] }
            defer { seen.close() }
            seen.store.onBreakDue = { _ in true }
            seen.store.refresh()
            let entry = seen.store.breakLog.prompts.first
            expect(seen.store.breakLog.prompts.count == 1 && entry?.kind == .main, "a shown reminder is logged", &problems)
            expect(entry.map { $0.shown.timeIntervalSince($0.due) } == 300,
                   "with the moment it fell due, five minutes before", &problems)
            expect(seen.store.breakLog.days.first?.rhythm == BreakPlan(tiers: Set(BreakTier.allCases)).snapshot,
                   "and the day's rhythm", &problems)

            // Eyes are counted by day, not listed.
            guard let eyes = make(prepare: { engine, _ in
                // Only Eyes on: the guard off and no main rhythm on any weekday.
                engine.store.breakEyes = true
                engine.store.breakGuardEnabled = false
                engine.store.breakSchedule.weekdays = Array(repeating: .off, count: 7)
            }) else {
                return problems + ["could not create isolated preferences"]
            }
            defer { eyes.close() }
            eyes.work(-25, 0)
            eyes.store.onBreakDue = { _ in true }
            eyes.store.refresh()
            expect(eyes.store.breakLog.prompts.isEmpty && eyes.store.breakLog.days.first?.eyesPrompts == 1,
                   "an eyes prompt is counted for the day and not listed", &problems)
            expect(eyes.store.breakLog.days.first?.rhythm == BreakPlan(tiers: [.micro]).snapshot, "under the rhythm then in force", &problems)
            return problems
        }
    }
    static func startAnswersReminder() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            func raise(_ f: Fixture) -> BreakPrompt? {
                var shown: BreakPrompt?
                f.store.onBreakDue = { shown = $0; return true }
                f.store.refresh()
                return shown
            }
            func outcome(_ f: Fixture, _ prompt: BreakPrompt) -> BreakPromptOutcome? {
                f.store.breakLog.prompts.first { $0.id == prompt.id }?.outcome
            }

            // Pressing Start break on the reminder.
            guard let f = makeDue(), let prompt = raise(f) else { return ["no reminder was raised"] }
            defer { f.close() }
            f.store.startBreak(from: prompt)
            expect(outcome(f, prompt) == .started, "Start break answers its reminder", &problems)
            expect(f.store.activeBreak?.plannedLength == 300, "a main break is five minutes", &problems)

            // Starting by hand soon after one that went unanswered.
            guard let g = makeDue(), let unanswered = raise(g) else { return problems + ["no reminder was raised"] }
            defer { g.close() }
            g.store.breakPromptUnanswered(unanswered)
            expect(outcome(g, unanswered) == .unanswered, "an ignored reminder is marked so", &problems)
            g.clock.advance(120)
            g.store.startBreak()
            expect(outcome(g, unanswered) == .started, "a break begun by hand soon after answers it", &problems)

            // Not one from long before.
            guard let h = makeDue(), let old = raise(h) else { return problems + ["no reminder was raised"] }
            defer { h.close() }
            h.clock.advance(700)
            h.store.startBreak()
            expect(outcome(h, old) == nil, "but not one from over ten minutes ago", &problems)

            // The long-stretch reminder asks for fifteen.
            guard let k = make() else { return problems + ["could not create isolated preferences"] }
            defer { k.close() }
            k.work(-95, 0)
            guard let guardPrompt = raise(k) else { return problems + ["no long-stretch reminder"] }
            k.store.startBreak(from: guardPrompt)
            expect(guardPrompt.tier == .ultradian && k.store.activeBreak?.plannedLength == 900,
                   "its break is fifteen minutes, got \(String(describing: k.store.activeBreak?.plannedLength))",
                   &problems)
            return problems
        }
    }
}
