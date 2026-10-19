import Foundation

/// The reminder log: every reminder shown, what became of it, and the rhythm
/// in force each day, kept in its own file for the analytics to read later.
enum BreakLogChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The reminder log keeps prompts and their outcomes across a reload", logRoundTrip),
        ("A day's rhythm is written once and replaced when it changes", rhythmUpsert),
        ("The reminder log forgets entries older than 400 days", logRetention),
        ("An unreadable reminder log is never overwritten", logLoadFailureBlocks),
    ]

    private static let base = SelfTest.base
    private static let calendar = Calendar.current

    private static func daysBefore(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: base)!
    }

    private static func entry(shown: Date, kind: BreakPromptKind = .main) -> BreakPromptEntry {
        BreakPromptEntry(id: UUID(), kind: kind, due: shown.addingTimeInterval(-60), shown: shown)
    }

    private static func logRoundTrip() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        let log = BreakLog(directory: directory)
        let shown = entry(shown: base)
        expect(log.recordShown(shown) == nil, "a shown reminder is saved", &problems)
        expect(log.noteLater(for: shown.id, at: base.addingTimeInterval(30)) == nil,
               "Later is saved", &problems)
        expect(log.setOutcome(.skipped, for: shown.id, at: base.addingTimeInterval(700)) == nil,
               "an outcome is saved", &problems)

        let reloaded = BreakLog(directory: directory).prompts
        expect(reloaded.count == 1, "one prompt is reloaded, got \(reloaded.count)", &problems)
        let back = reloaded.first
        expect(back?.id == shown.id && back?.kind == .main, "the same reminder comes back", &problems)
        expect(back?.laterCount == 1, "the Later count survives, got \(String(describing: back?.laterCount))", &problems)
        expect(back?.outcome == .skipped, "the outcome survives, got \(String(describing: back?.outcome))", &problems)
        expect(back?.outcomeAt == base.addingTimeInterval(700), "the outcome time survives", &problems)
        expect(BreakPromptKind.of(.micro) == .eyes && BreakPromptKind.of(.cognitive) == .main
                && BreakPromptKind.of(.ultradian) == .stretchGuard,
               "tiers map to prompt kinds", &problems)
        return problems
    }

    private static func rhythmUpsert() -> [String] {
        var problems: [String] = []
        var writes = 0
        let log = BreakLog(directory: SelfTest.scratchDirectory(),
                           writeOverride: { _ in writes += 1; return nil })
        let a = BreakRhythmSnapshot.fromTiers([.cognitive])
        let b = BreakRhythmSnapshot.fromTiers([.micro, .cognitive])
        log.noteRhythm(a, on: base)
        log.noteRhythm(a, on: base)
        expect(log.days.count == 1, "one day after the same rhythm twice, got \(log.days.count)", &problems)
        expect(writes == 1, "the same rhythm is written once, got \(writes) writes", &problems)
        log.noteRhythm(b, on: base.addingTimeInterval(3_600))
        expect(log.days.count == 1, "a change on the same day keeps one day, got \(log.days.count)", &problems)
        expect(log.days.first?.rhythm == b, "the day holds the new rhythm", &problems)
        expect(log.days.first?.day == calendar.startOfDay(for: base), "the day is keyed by its start", &problems)
        expect(writes == 2, "the change is written, got \(writes) writes", &problems)
        expect(BreakRhythmSnapshot.fromTiers([.cognitive, .ultradian]) ==
               BreakRhythmSnapshot(workMinutes: 50, breakMinutes: 5, eyes: false, guardMinutes: 90, override: nil),
               "tiers map as the spec's migration table", &problems)
        log.noteEyesPrompt(at: base)
        log.noteEyesPrompt(at: base.addingTimeInterval(1_200))
        expect(log.days.first?.eyesPrompts == 2, "eyes prompts are counted per day", &problems)
        return problems
    }

    private static func logRetention() -> [String] {
        var problems: [String] = []
        let log = BreakLog(directory: SelfTest.scratchDirectory())
        let old = entry(shown: daysBefore(401))
        let recent = entry(shown: daysBefore(399))
        log.recordShown(old)
        log.noteRhythm(BreakRhythmSnapshot.fromTiers([.micro]), on: daysBefore(401))
        log.recordShown(recent)
        log.noteRhythm(BreakRhythmSnapshot.fromTiers([.micro]), on: daysBefore(399))
        // Retention counts from the moment of the write, so today's write is
        // what lets the 401-day-old entries go.
        log.noteRhythm(BreakRhythmSnapshot.fromTiers([.micro]), on: base)
        expect(log.prompts.map(\.id).contains(old.id) == false,
               "a prompt 401 days old is dropped on the next write", &problems)
        expect(log.prompts.map(\.id).contains(recent.id), "a prompt 399 days old is kept", &problems)
        expect(log.days.map(\.day) == [daysBefore(399), base].map { calendar.startOfDay(for: $0) },
               "the 401-day-old day is dropped and the 399-day-old day kept, got \(log.days.count) days", &problems)
        return problems
    }

    private static func logLoadFailureBlocks() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(BreakLog.fileName)
        let garbage = Data("not json".utf8)
        try? garbage.write(to: file)
        let log = BreakLog(directory: directory)
        expect(log.recordShown(entry(shown: base)) != nil, "a write over an unreadable log is refused", &problems)
        expect(log.noteRhythm(BreakRhythmSnapshot.fromTiers([.micro]), on: base) != nil,
               "a rhythm write over an unreadable log is refused", &problems)
        expect((try? Data(contentsOf: file)) == garbage, "the unreadable file is unchanged", &problems)
        return problems
    }
}
