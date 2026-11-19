import Foundation

/// What a file this build reads back may hold: a newer build's remembered site is kept when another is
/// changed, a beat line that no recorder could have written is passed over, and a stored summary with an
/// impossible credit is dropped without the note beside it. Fakes and scratch folders only.
enum StoredEvidenceBoundsChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Changing one remembered site keeps kinds a newer version saved", changingOneSiteKeepsNewerKinds),
        ("A beat line of impossible length is passed over", impossibleBeatLineIsPassedOver),
        ("A stored summary with impossible credit is dropped, the note kept", impossibleSummaryIsDropped),
    ]

    private static func changingOneSiteKeepsNewerKinds() -> [String] {
        var problems: [String] = []
        let name = "fc-selftest-stored-sites"
        guard let defaults = MemoryDefaults.suite(named: name) else { return ["no scratch preferences"] }
        defer { MemoryDefaults.remove(named: name) }
        let settings = SiteSignalSettings(defaults: defaults)
        settings.setRemembers(true)
        let newer = ["example.com": "documentation", "newer.example": "futureKind"]
        func stored() -> [String: String]? { defaults.dictionary(forKey: SiteSignalSettings.sitesKey) as? [String: String] }
        defaults.set(newer, forKey: SiteSignalSettings.sitesKey)
        settings.forget("example.com")
        expect(stored() == ["newer.example": "futureKind"], "forgetting one site left \(String(describing: stored()))", &problems)
        settings.remember("docs.example.org", as: .documentation)
        expect(stored() == ["newer.example": "futureKind", "docs.example.org": "documentation"],
               "remembering one site left \(String(describing: stored()))", &problems)
        expect(settings.rememberedSites == ["docs.example.org": .documentation], "the read still shows only kinds this build knows", &problems)
        return problems
    }

    private static func beatLine(_ slice: String, offset: Int? = nil) -> String {
        let start = Int(Beat.gridStart(for: SelfTest.base).timeIntervalSinceReferenceDate)
        let shift = offset.map { ",\"f\":\($0)" } ?? ""
        return "{\"v\":1,\"t\":\(start)\(shift),\"s\":[\(slice)],\"p\":\"input\"}"
    }

    private static func slice(d: Int = 30, k: Int = 1, c: Int = 0, w: Int = 0) -> String {
        "{\"a\":\"com.example.editor\",\"d\":\(d),\"k\":\(k),\"c\":\(c),\"w\":\(w)}"
    }

    private static func decodes(_ line: String) -> Bool {
        (try? JSONDecoder().decode(Beat.self, from: Data(line.utf8))) != nil
    }

    private static func impossibleBeatLineIsPassedOver() -> [String] {
        var problems: [String] = []
        let impossible: [(String, String)] = [
            ("a slice of 2^62 seconds", beatLine(slice(d: 4_611_686_018_427_387_904))),
            ("an offset and slices over 30 seconds", beatLine(slice(d: 25), offset: 10)),
            ("a negative slice", beatLine(slice(d: -5))),
            ("an offset past its cell", beatLine(slice(d: 0), offset: 31)),
            ("more clicks than a counter holds", beatLine(slice(c: Int(UInt32.max) + 1))),
            ("a negative key count", beatLine(slice(k: -1))),
        ]
        expect(decodes(beatLine(slice(d: 20, k: 4, c: Int(UInt32.max)), offset: 10)), "a line filling its cell no longer decodes", &problems)
        for (what, line) in impossible { expect(!decodes(line), "a line with \(what) decoded", &problems) }
        let directory = SelfTest.scratchDirectory()
        let start = Beat.gridStart(for: SelfTest.base)
        let before = Beat(start: start, slices: [BeatSlice(app: "com.example.editor", seconds: 30, keys: 12, clicks: 0, scrolls: 0)],
                          presence: .input)
        let after = Beat(start: start.addingTimeInterval(60), slices: before.slices, presence: .input)
        try? BeatArchive(directory: directory, calendar: .current).append(before)
        guard let file = BeatArchiveChecks.dayFile(directory) else { return problems + ["no day file was written"] }
        BeatArchiveChecks.appendRaw(beatLine(slice(d: 25), offset: 10) + "\n", to: file)
        try? BeatArchive(directory: directory, calendar: .current).append(after)
        let read = BeatArchive(directory: directory, calendar: .current)
            .beats(in: DateInterval(start: start.addingTimeInterval(-60), end: start.addingTimeInterval(600)))
        expect(read == [before, after], "the two good beats did not both return around the impossible line, got \(read.count)", &problems)
        return problems
    }

    private static func impossibleSummaryIsDropped() -> [String] {
        var problems: [String] = []
        let bounds = DateInterval(start: SelfTest.base, duration: 600)
        func shape(_ credited: [String: TimeInterval], counted: TimeInterval = 600) -> SessionActivityShape {
            ActivitySnapshotChecks.shape(.activity(.media), credited: credited, over: bounds, counted: counted)
        }
        func reread(_ shape: SessionActivityShape) -> SessionMetadata? {
            var entry = SessionMetadata(recordID: UUID(), note: "kept")
            entry.activityShape = shape
            entry.headSummary = shape
            return (try? JSONEncoder().encode(entry)).flatMap { try? JSONDecoder().decode(SessionMetadata.self, from: $0) }
        }
        let broken: [(String, SessionActivityShape)] = [
            ("credit of 1e300", shape(["media": 1e300])),
            ("counted time beyond its span", shape(["media": 100], counted: 900)),
            ("credit beyond its span in all", shape(["media": 400, "coding": 400])),
            ("a negative credit", shape(["media": -5])),
        ]
        for (what, impossible) in broken {
            let entry = reread(impossible)
            expect(entry?.note == "kept", "a summary with \(what) lost the note too", &problems)
            expect(entry?.activityShape == nil && entry?.headSummary == nil, "a summary with \(what) was kept", &problems)
        }
        let nonFinite = shape(["media": .nan])
        expect(!nonFinite.isPlausible && !shape(["media": .infinity]).isPlausible, "a non-finite credit counted as plausible", &problems)
        let fine = shape(["media": 300, "coding": 300])
        expect(reread(fine)?.activityShape == fine && reread(fine)?.headSummary == fine, "a plausible summary did not survive", &problems)
        return problems
    }
}
