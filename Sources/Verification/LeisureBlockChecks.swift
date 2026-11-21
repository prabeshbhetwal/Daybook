import Foundation

/// Watching or listening outside a session (plan Phase B Task 7, ruling B14): found from beats once a run
/// ends, written once to `leisure.json`, shown on the day's timeline, and read by nothing that totals focus,
/// goals, streaks or breaks.
enum LeisureBlockChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Ten minutes of watching outside a session make one block, a second less makes none", tenMinutes),
        ("A run inside a session, or with automatic mode off, or still going, makes no block", noBlock),
        ("A block is cut clear of a session, and one a later backdated session covers is trimmed or dropped", trimmed),
        ("A block is written once, survives a relaunch, shows on the timeline and moves no figure", storeWritesOnce),
        ("An unreadable leisure file is set aside, a newer one is left alone, an impossible block is dropped, and a past day redraws",
         fileSafety),
    ]

    private static func fileSafety() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let start = SelfTest.base
            let block = LeisureBlock(id: UUID(), start: start, end: start.addingTimeInterval(900), bundleID: player,
                                     activity: .media)
            func folder(_ text: String) -> URL {
                let directory = SelfTest.scratchDirectory()
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? Data(text.utf8).write(to: directory.appendingPathComponent(LeisureStore.fileName))
                return directory
            }
            let corrupt = folder("{ not json")
            let reopened = LeisureStore(directory: corrupt, now: start)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: corrupt.path)) ?? []
            expect(reopened.failure == nil && reopened.blocks.isEmpty && names.contains { $0.hasPrefix("leisure-corrupt-") },
                   "an unreadable file was not set aside: \(names)", &problems)
            expect(reopened.add([block]) == nil && LeisureStore(directory: corrupt).blocks == [block],
                   "a fresh file was not written after the unreadable one", &problems)

            let newer = folder(#"{"version":2,"blocks":[]}"#)
            let bytes = try? Data(contentsOf: newer.appendingPathComponent(LeisureStore.fileName))
            let held = LeisureStore(directory: newer)
            expect(held.failure != nil && held.add([block]) != nil
                   && (try? Data(contentsOf: newer.appendingPathComponent(LeisureStore.fileName))) == bytes,
                   "a newer file was not left exactly as it was", &problems)

            let backwards = #"{"version":1,"blocks":[{"id":"\#(UUID().uuidString)","start":1000,"end":10,"bundleID":"x","activity":"media"}]}"#
            let impossible = LeisureStore(directory: folder(backwards))
            expect(impossible.failure == nil && impossible.blocks.isEmpty, "a backwards block was kept: \(impossible.blocks)", &problems)

            // A day already drawn and cached gains a block written for it later.
            guard let r = ActivityEvidenceStoreChecks.rig(session: false, auto: true) else {
                return problems + ["could not create isolated preferences"]
            }
            defer { r.close() }
            let calendar = Calendar.current
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: r.clock.value),
                  let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: yesterday) else {
                return problems + ["no yesterday"]
            }
            func drawn() -> Bool {
                r.store.storyDayProjection(on: yesterday).chronology.contains { $0.id.hasPrefix("leisure-") }
            }
            expect(!drawn(), "yesterday showed leisure before any was kept", &problems)
            r.store.leisureStore.add([LeisureBlock(id: UUID(), start: noon, end: noon.addingTimeInterval(1_200),
                                                   bundleID: player, activity: .media)])
            expect(drawn(), "yesterday, drawn before, did not gain its block", &problems)
            return problems
        }
    }

    static let player = ActivityTraces.mediaPlayer

    /// `minutes` of hands-off watching from `start`, with the player holding the screen awake.
    static func watching(_ minutes: Double, from start: Date) -> [Beat] {
        BeatTrace.beats([ActivityTraces.step(player, minutes, .none, holder: player)], from: start)
    }

    private static func find(_ beats: [Beat], sessions: [DateInterval] = [], auto: Bool = true,
                             now: Date? = nil) -> [LeisureBlock] {
        let end = beats.map(\.end).max() ?? SelfTest.base
        return LeisureFinder.blocks(beats: beats, sessions: sessions, autoModeOn: auto, after: .distantPast,
                                    now: now ?? end.addingTimeInterval(120))
    }

    private static func tenMinutes() -> [String] {
        var problems: [String] = []
        let start = SelfTest.base
        let ten = find(watching(10, from: start))
        expect(ten.count == 1 && ten.first?.start == start && ten.first?.end == start.addingTimeInterval(600)
               && ten.first?.bundleID == player && ten.first?.activity == .media, "ten minutes gave \(ten)", &problems)
        let short = find(watching(599.0 / 60, from: start))
        expect(short.isEmpty, "9 min 59 s gave \(short)", &problems)
        return problems
    }

    private static func noBlock() -> [String] {
        var problems: [String] = []
        let start = SelfTest.base
        let beats = watching(20, from: start)
        let whole = DateInterval(start: start.addingTimeInterval(-60), end: start.addingTimeInterval(1_260))
        expect(find(beats, sessions: [whole]).isEmpty, "a run inside a session made a block", &problems)
        expect(find(beats, auto: false).isEmpty, "a run with automatic mode off made a block", &problems)
        expect(find(beats, now: start.addingTimeInterval(1_200 + 30)).isEmpty, "a run still going made a block", &problems)
        return problems
    }

    private static func trimmed() -> [String] {
        var problems: [String] = []
        let start = SelfTest.base
        let at = { (minutes: Double) in start.addingTimeInterval(minutes * 60) }
        // A session over its last five minutes: the block is the fifteen before it.
        let cut = find(watching(20, from: start), sessions: [DateInterval(start: at(15), end: at(25))])
        expect(cut.count == 1 && cut.first?.start == start && cut.first?.end == at(15), "the cut block is \(cut)", &problems)
        // Written first, then an automatic session backdated over part of it.
        let block = LeisureBlock(id: UUID(), start: start, end: at(20), bundleID: player, activity: .media)
        let kept = LeisureFinder.visible([block], beside: [DateInterval(start: at(10), end: at(30))])
        expect(kept.count == 1 && kept.first?.start == start && kept.first?.end == at(10) && kept.first?.id == block.id,
               "the block beside a later session shows as \(kept)", &problems)
        let dropped = LeisureFinder.visible([block], beside: [DateInterval(start: at(9), end: at(30))])
        expect(dropped.isEmpty, "nine minutes left of a block still showed: \(dropped)", &problems)
        return problems
    }

    private static func storeWritesOnce() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = ActivityEvidenceStoreChecks.rig(session: false, auto: true) else {
                return ["could not create isolated preferences"]
            }
            defer { r.close() }
            // A session in the morning, so the figures have something to keep.
            let record = SessionRecord(name: "Write", workType: .deepWork, start: r.clock.value,
                                       end: r.clock.value.addingTimeInterval(1_800), workSeconds: 1_800,
                                       detectedApp: nil, threadID: UUID(), isAuto: false, pausedSpans: [])
            _ = r.engine.archive.append(record)
            let start = record.end.addingTimeInterval(600)
            for beat in watching(25, from: start) { try? r.evidence.archive.append(beat) }
            r.clock.value = start.addingTimeInterval(25 * 60 + 120)
            r.store.refresh()
            let sessionsFile = r.engine.archive.dataDirectoryURL.appendingPathComponent("sessions.json")
            let bytes = try? Data(contentsOf: sessionsFile)
            let before = SplitStoreChecks.figures(r.store, r.clock, withGoal: false)
            let day = r.store.storyDayProjection(on: r.clock.value)

            r.store.recordLeisure()
            r.store.recordLeisure()
            expect(r.store.leisureStore.blocks.count == 1 && r.store.leisureStore.blocks.first?.start == start,
                   "the store kept \(r.store.leisureStore.blocks)", &problems)
            // A relaunch reads the file and adds nothing.
            r.evidence.leisure = nil
            r.store.recordLeisure()
            expect(r.store.leisureStore.blocks.count == 1, "a relaunch added \(r.store.leisureStore.blocks)", &problems)
            expect((try? Data(contentsOf: sessionsFile)) == bytes, "sessions.json changed", &problems)

            r.store.refresh()
            expect(SplitStoreChecks.figures(r.store, r.clock, withGoal: false) == before, "a figure moved", &problems)
            let after = r.store.storyDayProjection(on: r.clock.value)
            expect(after.focused == day.focused && after.tracked == day.tracked && after.goalCredit == day.goalCredit
                   && after.recordedBreakSeconds == day.recordedBreakSeconds,
                   "the day's figures moved: \(day.focused) \(after.focused), breaks \(after.recordedBreakSeconds)", &problems)
            let shown = r.store.storyMoments(on: r.clock.value).contains {
                if case .leisure(let block) = $0 { return block.start == start }
                return false
            }
            expect(shown, "the block is not on the timeline", &problems)
            return problems
        }
    }
}
