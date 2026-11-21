import Foundation

/// An automatic session whose activity names no category starts as Unsorted, which never counts as focus;
/// focused work still starts as Deep work, and a person's own start never lands in Unsorted.
enum UnsortedStartChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Automatic mode files a session it cannot place as Unsorted, and focused work as before", detectorGuess),
        ("An automatic Unsorted session runs and is written as Unsorted, never counted as focus", engineKeepsUnsorted),
        ("A session the person starts, or begins afresh with Reset, never begins as Unsorted", manualNeverUnsorted),
    ]

    /// The detector's start decision for a run led by `purpose`, after the dwell.
    private static func guess(for purpose: AppPurpose) -> WorkType? {
        var detector = AutoSessionDetector(autoSessionPauseLimit: 600)
        let score = SelfTest.makeFocusScore(0.8, purpose: purpose)
        _ = detector.evaluate(score: score, at: SelfTest.base, sessionRunning: false,
                              sessionWasAutoStarted: false, enginePaused: false)
        let decision = detector.evaluate(score: score, at: SelfTest.base.addingTimeInterval(FocusConstants.autoStartDwell),
                                         sessionRunning: false, sessionWasAutoStarted: false, enginePaused: false)
        if case .start(let workType, _, _, _) = decision { return workType }
        return nil
    }

    private static func detectorGuess() -> [String] {
        var problems: [String] = []
        for purpose in AppPurpose.allCases {
            let expected: WorkType = purpose.isFocused ? .deepWork : .unsorted
            let got = guess(for: purpose)
            expect(got == expected, "\(purpose) should start as \(expected.rawValue), got \(String(describing: got))",
                   &problems)
        }
        return problems
    }

    private static func engineKeepsUnsorted() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .unsorted, intent: "", isAuto: true)
        expect(engine.activeWorkType == .unsorted,
               "the running automatic session should be Unsorted, got \(engine.activeWorkType.rawValue)", &problems)
        clock.advance(900)
        expect(engine.stop(), "the automatic session should end", &problems)
        let record = engine.archive.records.last
        expect(record?.workType == .unsorted && record?.categorySource == .builtIn,
               "the record should be Unsorted from the app, got \(String(describing: record))", &problems)
        expect(record.map { !$0.workType.countsAsFocus } == true, "an Unsorted record never counts as focus", &problems)
        return problems
    }

    private static func manualNeverUnsorted() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .unsorted, intent: "Write")
        expect(engine.activeWorkType == .fallbackStartable,
               "a person's start should fall back to \(WorkType.fallbackStartable.rawValue), got \(engine.activeWorkType.rawValue)",
               &problems)
        // Reset over an automatic Unsorted session begins a fresh one of the person's own.
        let reset = SelfTest.makeEngine(clock)
        reset.start(workType: .unsorted, intent: "", isAuto: true)
        clock.advance(900)
        reset.transition(on: .resetSession)
        expect(reset.state.isRunning && reset.activeWorkType == .fallbackStartable,
               "Reset should begin under \(WorkType.fallbackStartable.rawValue), got \(reset.state) \(reset.activeWorkType.rawValue)",
               &problems)
        return problems
    }
}
