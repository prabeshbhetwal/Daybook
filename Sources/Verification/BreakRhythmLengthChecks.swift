import Foundation

/// The length Take a break shows and Start break plans. It is the rhythm's own
/// in every state the reminders can be in, never under the shortest recorded
/// session, and never raised past the longest that setting offers.
enum BreakRhythmLengthChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Take a break starts at the rhythm's length while reminders are quiet", suggestionHoldsWhenQuiet),
        ("A stored shortest session cannot stretch a break past the picker's longest", storedMinimumIsCapped),
        ("The length the button shows is the length that starts", buttonAgreesWithStart),
        ("Take a break names its length with the article it needs", startPhraseReadsRight),
    ]

    /// What Take a break shows and Start break plans after a refresh under `change`, with
    /// `work` minutes of use behind it at 10:00 on Wednesday 21 October 2026, Berlin.
    @MainActor
    static func begin(_ change: (inout BreakSchedule) -> Void, work: Double = 0, minimumSession: TimeInterval? = nil,
                      length: TimeInterval? = nil, reminders: Bool = true, meeting: Bool = false)
        -> (shown: TimeInterval, planned: TimeInterval?)? {
        let moment = BreakRhythmStoreChecks.oct(21, 10, 0)
        guard let f = BreakRhythmStoreChecks.make(at: moment) else { return nil }
        defer { f.close() }
        BreakRhythmStoreChecks.save(f, change)
        if let minimumSession { f.persistence.minimumRecordedSession = minimumSession }
        f.persistence.remindersEnabled = reminders
        if meeting { f.engine.start(workType: .meetings, intent: "Standup") }
        if work > 0 {
            BreakRhythmStoreChecks.use(f, from: moment.addingTimeInterval(-work * 60), to: moment)
        }
        f.store.refresh()
        let shown = f.store.suggestedBreakLength
        f.store.startBreak(length: length)
        return (shown, f.store.activeBreak?.plannedLength)
    }

    private static func suggestionHoldsWhenQuiet() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let off = begin({ $0.rhythm = .flow }, work: 40, reminders: false)
            expect(off?.shown == 480 && off?.planned == 480,
                   "Flow after 40 minutes with reminders off offers 8, got \(String(describing: off))", &problems)
            let closed = begin({ $0.rhythm = .flow; $0.workingHours = WorkingHours(fromMinute: 12 * 60, toMinute: 18 * 60) },
                               work: 40)
            expect(closed?.shown == 480 && closed?.planned == 480,
                   "and outside the working hours, got \(String(describing: closed))", &problems)
            let meeting = begin({ $0.rhythm = .flow }, work: 40, meeting: true)
            expect(meeting?.shown == 480 && meeting?.planned == 480,
                   "and in a category that asked for quiet, got \(String(describing: meeting))", &problems)
            return problems
        }
    }

    private static func storedMinimumIsCapped() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let huge = begin({ _ in }, minimumSession: 1e9)
            expect(huge?.planned == 300, "a stored minimum of a billion seconds still plans 5 minutes, got "
                   + "\(String(describing: huge?.planned))", &problems)
            let unbounded = begin({ _ in }, minimumSession: .infinity)
            expect(unbounded?.planned == 300 && unbounded?.shown == 300,
                   "and an infinite one starts the break all the same, got \(String(describing: unbounded))", &problems)
            return problems
        }
    }

    private static func buttonAgreesWithStart() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let tiny = begin({ $0.rhythm = .custom; $0.custom.breakMinutes = 1 }, minimumSession: 300)
            expect(tiny?.shown == 300 && tiny?.planned == 300,
                   "a 1-minute rhythm under a 5-minute shortest session shows 5 and starts 5, got "
                   + "\(String(describing: tiny))", &problems)
            return problems
        }
    }

    private static func startPhraseReadsRight() -> [String] {
        var problems: [String] = []
        let expected: [(Int, String)] = [(1, "a 1-minute"), (5, "a 5-minute"), (8, "an 8-minute"),
                                         (11, "an 11-minute"), (18, "an 18-minute"), (30, "a 30-minute")]
        for (minutes, phrase) in expected {
            expect(BreakChoice.startPhrase(minutes: minutes) == phrase,
                   "\(minutes) minutes reads \"\(phrase)\", got \"\(BreakChoice.startPhrase(minutes: minutes))\"",
                   &problems)
        }
        return problems
    }
}
