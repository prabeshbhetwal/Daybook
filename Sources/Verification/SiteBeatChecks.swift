import Foundation

/// Activity-aware sessions, phase D: the kind of site a browser showed, kept on the beat slice
/// it was read for. The recorder is driven as `BeatRecorderChecks` drives it; apps are fictional.
enum SiteBeatChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A read labels the slice it was asked for", readLabelsItsSlice),
        ("A changed tab splits the slice where the answer came", changedTabSplitsTheSlice),
        ("The next half-minute keeps the site until it is read again", nextHalfMinuteKeepsTheSite),
        ("A late answer never labels another app", lateAnswerNeverLabelsAnotherApp),
        ("A slice opened by an activation starts with no site", activationStartsWithNoSite),
        ("A beat with an unknown site kind still loads", unknownKindStillLoads),
        ("Two sites in one app stay two slices, and a flick takes its neighbour's site", flickTakesNeighboursSite),
    ]

    private typealias Rig = BeatRecorderChecks.Rig
    private static let browser = "com.example.browser"
    private static let editor = "com.example.editor"

    private static func slice(_ app: String, _ seconds: Int, _ site: SiteKind? = nil, keys: Int = 0) -> BeatSlice {
        BeatSlice(app: app, seconds: seconds, keys: keys, clicks: 0, scrolls: 0, site: site)
    }

    /// The answer for a read asked `askedAt` seconds into the cell arrives now.
    private static func read(_ rig: Rig, _ kind: SiteKind?, _ app: String = browser, askedAt: TimeInterval) {
        rig.recorder.site(kind, app: app, requestedAt: rig.at(askedAt), at: rig.clock.value,
                          counters: rig.counts, idleSeconds: rig.idle)
    }

    /// The browser in front from the cell's start and read as `kind` at once; the clock is 1 s in.
    private static func opened(_ kind: SiteKind?) -> Rig {
        let rig = Rig()
        rig.activate(browser)
        rig.tick()
        read(rig, kind, askedAt: 0)
        return rig
    }

    private static func readLabelsItsSlice() -> [String] {
        var problems: [String] = []
        let rig = opened(.video)
        rig.tick(30)
        expect(rig.beats.count == 1 && rig.beats.first?.slices == [slice(browser, 30, .video)],
               "one 30 s browser slice should carry the video kind, got \(rig.beats.map(\.slices))", &problems)
        return problems
    }

    private static func changedTabSplitsTheSlice() -> [String] {
        var problems: [String] = []
        let rig = opened(.video)
        rig.tick(11)
        rig.counts = CounterReading(keys: 7, clicks: 0, scrolls: 0)
        read(rig, .documentation, askedAt: 11)  // answered 1 s after it was asked
        rig.tick(19)
        expect(rig.beats.first?.slices == [slice(browser, 12, .video, keys: 7), slice(browser, 18, .documentation)],
               "video should hold to the second the answer came, with the 7 keys typed by then, got \(rig.beats.map(\.slices))", &problems)
        return problems
    }

    private static func nextHalfMinuteKeepsTheSite() -> [String] {
        var problems: [String] = []
        let kept = opened(.video)
        kept.tick(60)
        expect(kept.beats.map(\.slices) == [[slice(browser, 30, .video)], [slice(browser, 30, .video)]],
               "the second half-minute should carry video unread, got \(kept.beats.map(\.slices))", &problems)

        let reread = opened(.video)
        reread.tick(30)
        read(reread, nil, askedAt: 30)  // asked at the edge, so it labels the whole new slice
        reread.tick(30)
        expect(reread.beats.last?.slices == [slice(browser, 30)],
               "a read of nothing at the edge should clear the kind, got \(reread.beats.map(\.slices))", &problems)

        let other = opened(.video)
        other.tick(29)
        other.activate(editor)  // on the edge, so it opens in the next beat
        other.tick(31)
        expect(other.beats.map(\.slices) == [[slice(browser, 30, .video)], [slice(editor, 30)]],
               "another app should not inherit the kind, got \(other.beats.map(\.slices))", &problems)

        let slept = opened(.video)
        slept.tick(10)
        slept.clock.value = slept.at(3_610)
        slept.tick(21)
        expect(slept.beats.map(\.slices) == [[slice(browser, 10, .video)], [slice(browser, 20)]],
               "a kind should not carry across a gap, got \(slept.beats.map(\.slices))", &problems)
        return problems
    }

    private static func lateAnswerNeverLabelsAnotherApp() -> [String] {
        var problems: [String] = []
        let rig = Rig()
        rig.activate(browser)
        rig.tick(10)
        rig.activate(editor)
        rig.tick()
        read(rig, .video, askedAt: 0)  // the browser's answer, 1 s after the editor came forward
        rig.tick(20)
        expect(rig.beats.first?.slices == [slice(browser, 10), slice(editor, 20)],
               "neither slice should carry the browser's late answer, got \(rig.beats.map(\.slices))", &problems)

        let stopped = opened(.video)
        stopped.tick(4)
        _ = stopped.recorder.stop(at: stopped.clock.value, counters: stopped.counts, idleSeconds: stopped.idle)
        read(stopped, .documentation, askedAt: 4)  // arrives once recording has stopped
        stopped.tick(26)
        expect(stopped.beats.first?.slices == [slice(browser, 25)],
               "an answer after recording stopped should label nothing, got \(stopped.beats.map(\.slices))", &problems)
        return problems
    }

    private static func activationStartsWithNoSite() -> [String] {
        var problems: [String] = []
        let rig = opened(.video)
        rig.tick(9)
        rig.activate(editor)
        rig.tick(10)
        rig.activate(browser)
        rig.tick(11)
        expect(rig.beats.first?.slices == [slice(browser, 10, .video), slice(editor, 10), slice(browser, 10)],
               "the browser's second slice should start with no kind, got \(rig.beats.map(\.slices))", &problems)
        return problems
    }

    private static func unknownKindStillLoads() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        let start = Beat.gridStart(for: SelfTest.base)
        let first = Beat(start: start, slices: [slice(browser, 30, .video)], presence: .input)
        let third = Beat(start: start.addingTimeInterval(60), slices: [slice(browser, 30)], presence: .input)
        try? BeatArchive(directory: directory, calendar: .current).append(first)
        guard let file = BeatArchiveChecks.dayFile(directory) else { return ["no day file was written"] }
        let unknown = "{\"v\":1,\"t\":\(Int(start.addingTimeInterval(30).timeIntervalSinceReferenceDate)),"
            + "\"s\":[{\"a\":\"\(browser)\",\"d\":30,\"k\":0,\"c\":0,\"w\":0,\"y\":\"hologram\"}],\"p\":\"input\"}\n"
        BeatArchiveChecks.appendRaw(unknown, to: file)
        try? BeatArchive(directory: directory, calendar: .current).append(third)
        let loaded = BeatArchive(directory: directory, calendar: .current)
            .beats(in: BeatArchiveChecks.wide(around: start))
        expect(loaded.count == 3, "all three beats should load around an unknown kind, got \(loaded.count)", &problems)
        guard loaded.count == 3 else { return problems }
        expect(loaded[0] == first, "a kept kind should read back as written, got \(loaded[0].slices)", &problems)
        expect(loaded[1].slices == [slice(browser, 30)], "an unknown kind should read as none, got \(loaded[1].slices)", &problems)
        let lines = (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
        expect(lines.count == 3 && lines[0].contains("\"y\":\"video\"") && !lines[2].contains("\"y\""),
               "a kind is written as y, and a slice with none writes no y, got \(lines)", &problems)
        return problems
    }

    private static func flickTakesNeighboursSite() -> [String] {
        var problems: [String] = []
        let middle = opened(.video)
        middle.tick(11)
        read(middle, .documentation, askedAt: 11)
        middle.tick(3)
        read(middle, .video, askedAt: 14)
        middle.tick(16)
        expect(middle.beats.first?.slices == [slice(browser, 30, .video)],
               "video, 3 s of documentation, then video should be one video slice, got \(middle.beats.map(\.slices))", &problems)

        let leading = opened(.documentation)
        leading.tick(2)
        read(leading, .video, askedAt: 2)
        leading.tick(28)
        expect(leading.beats.first?.slices == [slice(browser, 30, .video)],
               "a 3 s lead of documentation should join the video after it, got \(leading.beats.map(\.slices))", &problems)
        return problems
    }
}
