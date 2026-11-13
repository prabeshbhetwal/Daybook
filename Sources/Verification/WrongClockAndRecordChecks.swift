import Foundation

/// History that one bad input used to erase: a single save with the clock far
/// off, and a single unreadable record in the session archive.
enum WrongClockAndRecordChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A save with the clock a year ahead or decades behind keeps the reminder log", wrongClockKeepsBreakLog),    ]

    private static let base = SelfTest.base
    private static let calendar = Calendar.current

    private static func wrongClockKeepsBreakLog() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = BreakLog(directory: directory, calendar: calendar)
        for minutes in 0..<5 {
            let shown = base.addingTimeInterval(TimeInterval(minutes * 600))
            log.recordShown(BreakPromptEntry(id: UUID(), kind: .main, due: shown, shown: shown))
        }
        log.noteRhythm(.off, on: base)

        // The clock jumps 401 days ahead for a few saves, then comes back.
        let ahead = calendar.date(byAdding: .day, value: 401, to: base)!
        log.noteRhythm(BreakRhythmSnapshot(eyes: true), on: ahead)
        log.noteEyesPrompt(at: ahead.addingTimeInterval(60))
        let afterAhead = BreakLog(directory: directory, calendar: calendar)
        expect(afterAhead.prompts.count == 5,
               "five prompts survive saves with the clock 401 days ahead, got \(afterAhead.prompts.count)", &problems)

        // A clock decades behind: its entry lands first, and nothing goes.
        let behind = calendar.date(byAdding: .year, value: -30, to: base)!
        afterAhead.recordShown(BreakPromptEntry(id: UUID(), kind: .eyes, due: behind, shown: behind))
        afterAhead.noteRhythm(.off, on: behind)
        afterAhead.noteRhythm(BreakRhythmSnapshot(eyes: true), on: base.addingTimeInterval(3_600))
        let afterBehind = BreakLog(directory: directory, calendar: calendar)
        expect(afterBehind.prompts.count == 6,
               "saves with the clock 30 years behind keep all six prompts, got \(afterBehind.prompts.count)", &problems)
        return problems
    }
}
