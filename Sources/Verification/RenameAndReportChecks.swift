import Foundation

/// Naming a session says so once, at the moment it happened: a rename in the
/// session's card claims an automatic session, the automatic row's button
/// says what it will do, the rename notice stands at the time of the rename,
/// and the session report does not list every quick app switch as a gap.
enum RenameAndReportChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Renaming the running automatic session claims it, so Name stops asking", renameClaimsAutomatic),
        ("The automatic row's button says Save exactly when it renames in place", saveLabelMatchesAction),
        ("A rename's notice stands at the moment of the rename", noticeAtRenameTime),
        ("The session report lists no gap shorter than a minute", reportSkipsSwitchGaps),
        ("A break's notice, which stands in place of the break, keeps the break's span", breakNoticeKeepsSpan),
    ]

    @MainActor
    private static func make(automatic: Bool) -> (store: SessionStore, clock: TestClock, suite: String) {
        let suite = "fc-selftest-rename-\(UUID().uuidString)"
        let clock = TestClock(SelfTest.anchoredNow())
        let archive = SessionArchive(directory: SelfTest.scratchDirectory(), now: { clock.value })
        let persistence = PersistenceStore(defaults: MemoryDefaults.suite(named: suite) ?? .standard)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence, archive: archive, ownBundleID: "com.test",
                                   schedulesDwell: false, now: { clock.value })
        engine.start(workType: .deepWork, intent: "Detected work", isAuto: automatic)
        clock.advance(20 * 60)
        if automatic {
            // The persisted ownership is what marks the stretch automatic.
            var snapshot = engine.snapshot()
            snapshot.isAuto = true
            engine.restore(from: snapshot)
        }
        return (SessionStore(engine: engine, now: { clock.value }), clock, suite)
    }

    @MainActor
    private static func running(_ store: SessionStore, at moment: Date) -> DaySession {
        let engine = store.engine
        return DaySession(id: UUID(), threadID: engine.activeThreadID, name: engine.sessionName,
                          workType: engine.activeWorkType, start: engine.sessionStartDate, end: moment,
                          worked: moment.timeIntervalSince(engine.sessionStartDate), stretches: 1,
                          spans: [DateInterval(start: engine.sessionStartDate, end: moment)], isRunning: true)
    }

    private static func renameClaimsAutomatic() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = make(automatic: true)
            defer { MemoryDefaults.remove(named: suite) }
            expect(store.isAutoSession, "the fixture starts automatic", &problems)
            store.isNamingAutomaticSession = true
            let saved = store.renameSession(running(store, at: clock.value), to: "Job application")
            expect(saved, "the rename saved: \(store.correctionError ?? "no reason")", &problems)
            expect(store.engine.sessionName == "Job application",
                   "the running session carries the new name, got \(store.engine.sessionName)", &problems)
            expect(!store.isAutoSession, "a renamed session is still marked automatic", &problems)
            expect(!store.focusSurfaceComposition.showsAutomaticSessionControls,
                   "Name still asks to name a session that has a name", &problems)
            expect(!store.isNamingAutomaticSession,
                   "the Name row left open still holds the update back", &problems)

            // The goal tile's tidy-up changes the field, not who owns the session.
            let tidied = make(automatic: true)
            defer { MemoryDefaults.remove(named: tidied.suite) }
            if let other = WorkType.startable.first(where: { $0 != .deepWork }) {
                expect(tidied.store.setWorkType(other, threadID: tidied.store.engine.activeThreadID),
                       "the tidy-up saved: \(tidied.store.correctionError ?? "no reason")", &problems)
                expect(tidied.store.isAutoSession, "a tidy-up claimed the automatic session", &problems)
            }
            return problems
        }
    }

    private static func breakNoticeKeepsSpan() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = make(automatic: false)
            defer { MemoryDefaults.remove(named: suite) }
            let start = store.engine.sessionStartDate
            let session = running(store, at: clock.value)
            store.stop()
            clock.advance(60 * 60)
            expect(store.setWorkType(.breakTime, for: session),
                   "the correction saved: \(store.correctionError ?? "no reason")", &problems)
            store.refresh()
            let notices = store.storyTimelineItems(on: start).compactMap { item -> DateInterval? in
                if case .correction(_, let title, let range) = item,
                   title.lowercased().contains("recorded as a break") { return range }
                return nil
            }
            expect(notices.count == 1, "one break notice, got \(notices.count)", &problems)
            if let range = notices.first {
                // It stands in place of the break's row, so it is the break's time.
                expect(range.start == start && range.duration > 0,
                       "the break notice keeps the break's span from \(DateFormats.clockTime(start)); it reads "
                       + "\(DateFormats.clockTime(range.start)) for \(Int(range.duration)) s", &problems)
            }
            return problems
        }
    }

    private static func saveLabelMatchesAction() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // A new name in the same category renames this session in place.
            let renamed = make(automatic: true)
            defer { MemoryDefaults.remove(named: renamed.suite) }
            let thread = renamed.store.engine.activeThreadID
            renamed.store.intent = "Job application"
            expect(renamed.store.automaticCorrectionAdopts,
                   "a new name in the same category reads Start new over a rename", &problems)
            renamed.store.applyAutomaticSessionCorrection()
            expect(renamed.store.engine.activeThreadID == thread
                   && renamed.store.engine.sessionName == "Job application",
                   "Save renamed in place, got \(renamed.store.engine.sessionName) on "
                   + (renamed.store.engine.activeThreadID == thread ? "the same" : "a new") + " thread",
                   &problems)

            // Another category is another session.
            let moved = make(automatic: true)
            defer { MemoryDefaults.remove(named: moved.suite) }
            let movedThread = moved.store.engine.activeThreadID
            guard let other = WorkType.startable.first(where: { $0 != .deepWork }) else {
                return problems + ["no second startable category to move to"]
            }
            // A name spelled like a category is that category.
            moved.store.intent = other.displayName
            expect(!moved.store.automaticCorrectionAdopts,
                   "the name \(other.displayName) reads Save over a new \(other.displayName) session", &problems)
            moved.store.intent = "Job application"
            moved.store.workType = other
            expect(!moved.store.automaticCorrectionAdopts,
                   "another category reads Save over a new session", &problems)
            moved.store.applyAutomaticSessionCorrection()
            expect(moved.store.engine.activeThreadID != movedThread,
                   "Start new kept the same session", &problems)
            return problems
        }
    }

    private static func noticeAtRenameTime() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = make(automatic: false)
            defer { MemoryDefaults.remove(named: suite) }
            let start = store.engine.sessionStartDate
            clock.advance(70 * 60)
            let renamedAt = clock.value
            expect(store.renameSession(running(store, at: renamedAt), to: "Job application"),
                   "the rename saved: \(store.correctionError ?? "no reason")", &problems)
            clock.advance(15 * 60)
            store.refresh()
            let notices = store.storyTimelineItems(on: start).compactMap { item -> DateInterval? in
                if case .correction(_, "Session renamed", let range) = item { return range }
                return nil
            }
            expect(notices.count == 1, "one rename notice, got \(notices.count)", &problems)
            if let range = notices.first {
                expect(range.start == renamedAt && range.duration == 0,
                       "the notice stands at the rename, \(DateFormats.clockTime(renamedAt)); it reads "
                       + "\(DateFormats.clockTime(range.start)) for \(Int(range.duration)) s", &problems)
            }
            return problems
        }
    }

    private static func reportSkipsSwitchGaps() -> [String] {
        var problems: [String] = []
        let base = SelfTest.base
        func segment(_ name: String, _ from: TimeInterval, _ to: TimeInterval) -> TimelineSegment {
            TimelineSegment(id: UUID(), bundleID: "test." + name.lowercased(), appName: name,
                            start: base.addingTimeInterval(from), end: base.addingTimeInterval(to), colorIndex: 0)
        }
        // A 3 s switch to an app too brief to record, then four minutes untouched.
        let activity = RecordedActivity(
            segments: [segment("ChatGPT", 0, 100), segment("ChatGPT", 103, 200), segment("Claude", 440, 600)],
            spans: [DateInterval(start: base, end: base.addingTimeInterval(600))])
        let gaps = activity.intervals.filter(\.isGap).map(\.duration)
        expect(gaps.count == 2, "the fixture has two gaps, got \(gaps)", &problems)
        let listedGaps = SessionReport.listing(activity.intervals).filter(\.isGap).map(\.duration)
        expect(listedGaps == [240], "only the four-minute gap is listed, got \(listedGaps)", &problems)
        expect(SessionReport.listing(activity.intervals).filter { !$0.isGap }.count == 3,
               "every visit is still listed", &problems)
        return problems
    }
}
