import Foundation

/// "Split here?" and what a tail begins as: who is offered the cut, what Keep Together remembers, and that
/// Daybook never files time that is not clearly focused work under a category by its own choice (plan Task 6,
/// rulings B5, B8, B9, B10, B11).
enum SplitOfferChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A tail is Daybook's to file only when its dominant purpose is focused work; otherwise the person picks",
         tailChoice),
        ("A tail is named for what it was when its head's name was Daybook's, and keeps a name the person gave",
         tailNames),
        ("A manual session and a rule's are offered the cut, an automatic one is not, until the person makes it theirs",
         whoIsOffered),
        ("Keep Together hides the offer for that moment, after a relaunch too, and an offer changes nothing by itself",
         keepTogetherIsRemembered),
        ("Taking an offer whose tail is not clearly focused writes the category the person picked as theirs",
         pickedCategoryIsTheirs),
    ]

    typealias Rig = SplitStoreChecks.Rig

    private static func tailChoice() -> [String] {
        var problems: [String] = []
        let head = WorkType.deepWork
        func decide(_ label: ActivityLabel?, remembered: WorkType? = nil, suggested: WorkType? = nil) -> SplitTailChoice {
            .decide(label: label, remembered: remembered, suggested: suggested, head: head)
        }
        expect(decide(.activity(.coding), remembered: .admin, suggested: .learning) == .chosen(.admin, .correction),
               "a remembered category did not come first", &problems)
        expect(decide(.activity(.design), suggested: .learning) == .chosen(.learning, .builtIn),
               "the built-in pick was not used", &problems)
        expect(decide(.activity(.writingAI)) == .ask(head), "a focused tail with nothing to go on was filed anyway", &problems)
        for label in [ActivityLabel.activity(.media), .activity(.research), .activity(.communication),
                      .activity(.utility), .mixed, .unsorted] {
            expect(decide(label, remembered: .admin, suggested: .learning) == .ask(head),
                   "\(label) was filed under a focus category by Daybook", &problems)
        }
        expect(decide(nil, remembered: .admin, suggested: .learning) == .ask(head), "no evidence still filed a tail", &problems)
        expect(decide(.activity(.coding), remembered: .breakTime, suggested: .breakTime) == .ask(head),
               "a break was offered as a tail's category", &problems)
        return problems
    }

    private static func tailNames() -> [String] {
        var problems: [String] = []
        var head = SplitRecordChecks.original()
        func name(of head: SessionRecord, _ purpose: AppPurpose?, _ app: String?) -> SplitTail {
            SplitTail(after: head, workType: .learning, source: .builtIn, purpose: purpose, topApp: app)
        }
        let coding = name(of: head, .coding, "com.apple.dt.Xcode")
        expect(coding.name == "Coding" && coding.nameByApp && coding.detectedApp == "com.apple.dt.Xcode",
               "an app-named head's tail is \(coding)", &problems)
        let browsing = name(of: head, .research, ActivityTraces.browser)
        expect(browsing.name == "Browsing" && browsing.nameByApp, "a browser tail is \(browsing)", &problems)
        let media = name(of: head, .media, ActivityTraces.mediaPlayer)
        expect(media.name == "" && !media.nameByApp, "a tail with no name of its own is \(media)", &problems)
        expect(name(of: head, nil, nil).name == "" && !name(of: head, nil, nil).nameByApp,
               "a tail with no evidence took its head's app-chosen name", &problems)
        head.nameByApp = false
        let theirs = name(of: head, .coding, "com.apple.dt.Xcode")
        expect(theirs.name == head.name && !theirs.nameByApp, "the person's own name did not carry over: \(theirs)", &problems)
        return problems
    }

    /// The record shape a session with one candidate has: the work, then `tail` for good from `cut`.
    @MainActor
    static func keepShape(_ record: SessionRecord, in store: SessionStore, cutAfter cut: TimeInterval = 2_400,
                          tail: AppPurpose = .media) {
        let moment = record.start.addingTimeInterval(cut)
        let phases = [SessionPhase(start: record.start, end: moment, activity: .purpose(.coding), counted: true,
                                   credited: [AppPurpose.coding.rawValue: 1_800]),
                      SessionPhase(start: moment, end: record.end, activity: .purpose(tail), counted: true,
                                   credited: [tail.rawValue: 1_200])]
        store.metadataArchive.saveActivityShape(
            SessionActivityShape(algorithmVersion: ActivityConstants.algorithmVersion, fidelity: .beats,
                                 bounds: DateInterval(start: record.start, end: record.end), countedSeconds: 3_000,
                                 signals: [], phases: phases, depth: nil, label: .activity(.coding),
                                 credited: [AppPurpose.coding.rawValue: 1_800, tail.rawValue: 1_200], fingerprint: nil,
                                 splitCandidates: [moment]), for: record.id)
    }

    private static func whoIsOffered() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            /// The offer a session of this kind gets, in a store of its own.
            @MainActor func offer(shape: Bool = true, _ make: (Rig) -> SessionRecord) -> SplitOffer? {
                let rig = SplitStoreChecks.rig()
                defer { MemoryDefaults.remove(named: rig.suite) }
                let record = make(rig)
                SplitStoreChecks.seed(rig, [record])
                if shape { keepShape(record, in: rig.store) }
                return rig.store.splitOffer(for: SplitStoreChecks.row(record))
            }
            for (label, origin) in [("manual", SessionOrigin.manual), ("rule", .rule)] {
                let made = offer { SplitStoreChecks.ended($0, origin: origin) }
                expect(made?.choice == .ask(.deepWork), "a \(label) session was not offered a cut: \(String(describing: made))", &problems)
            }
            expect(offer { SplitStoreChecks.ended($0, origin: .automatic) } == nil,
                   "an automatic session of Daybook's own was offered a cut", &problems)
            expect(offer { var record = SplitStoreChecks.ended($0, origin: .automatic); record.nameByApp = false; return record } != nil,
                   "an automatic session the person renamed was not offered a cut", &problems)
            expect(offer { var record = SplitStoreChecks.ended($0, origin: .automatic); record.categorySource = .user; return record } != nil,
                   "an automatic session the person filed was not offered a cut", &problems)
            expect(offer(shape: false) { SplitStoreChecks.ended($0, origin: .manual) } == nil,
                   "a session with no candidate was offered a cut", &problems)
            // A candidate the record's own pauses rule out is not a moment a cut may land on.
            expect(offer { var record = SplitStoreChecks.ended($0, origin: .manual)
                record.pausedSpans = [DateInterval(start: record.start.addingTimeInterval(2_100), duration: 600)]
                return record } == nil, "a candidate inside a pause was offered", &problems)
            return problems
        }
    }

    private static func keepTogetherIsRemembered() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let rig = SplitStoreChecks.rig()
            defer { MemoryDefaults.remove(named: rig.suite) }
            let store = rig.store
            let record = SplitStoreChecks.ended(rig, origin: .manual)
            SplitStoreChecks.seed(rig, [record])
            keepShape(record, in: store)
            let row = SplitStoreChecks.row(record)
            let revision = store.engine.archive.revision
            guard let offer = store.splitOffer(for: row) else { return ["no offer was made"] }
            store.refresh()
            expect(store.engine.archive.revision == revision && store.engine.archive.records == [record]
                   && store.corrections.isEmpty, "an offer changed a record or made a correction", &problems)
            expect(SessionReport.make(for: row, store: store).split == offer, "the report did not carry the offer", &problems)
            store.declineSplit(offer)
            expect(store.splitOffer(for: row) == nil && SessionReport.make(for: row, store: store).split == nil,
                   "the offer stayed after Keep Together", &problems)
            expect(store.engine.archive.records == [record] && store.corrections.isEmpty,
                   "Keep Together changed a record or made a correction", &problems)
            let again = SplitStoreChecks.rig(directory: rig.directory, suite: rig.suite, clock: rig.clock)
            expect(again.store.splitOffer(for: row) == nil, "the offer came back after a relaunch", &problems)
            // A moment further on is a different cut, still the person's to decline.
            keepShape(record, in: again.store, cutAfter: 3_000)
            expect(again.store.splitOffer(for: row)?.at == record.start.addingTimeInterval(3_000),
                   "a different moment was hidden by the first answer", &problems)
            return problems
        }
    }

    private static func pickedCategoryIsTheirs() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let rig = SplitStoreChecks.rig()
            defer { MemoryDefaults.remove(named: rig.suite) }
            let store = rig.store
            let record = SplitStoreChecks.ended(rig, origin: .manual)
            SplitStoreChecks.seed(rig, [record])
            keepShape(record, in: store)
            let row = SplitStoreChecks.row(record)
            guard let offer = store.splitOffer(for: row), case .ask(let preset) = offer.choice else {
                return ["the offer did not ask for a category"]
            }
            expect(preset == record.workType && offer.purpose == .media, "the offer began at \(preset) for \(String(describing: offer.purpose))", &problems)
            expect(store.acceptSplit(offer, as: .learning), "the split was refused: \(store.correctionError ?? "")", &problems)
            guard let halves = SplitStoreChecks.halves(of: record, in: store) else { return problems + ["no halves"] }
            expect(halves.tail.workType == .learning && halves.tail.categorySource == .user && halves.tail.origin == .manual,
                   "the tail is \(halves.tail)", &problems)
            expect(halves.head.workType == record.workType && halves.head.categorySource == record.categorySource,
                   "the head changed", &problems)
            expect(store.canMergeBack(recordID: halves.tail.id), "the tail did not offer Merge Back", &problems)
            expect(SessionReport.make(for: SplitStoreChecks.row(halves.tail), store: store).mergeBack
                   == MergeBackOffer(tailID: halves.tail.id, headName: record.name), "the tail's report has no Merge Back", &problems)
            // The day says so, with Undo, as it does of any correction; a merge then takes the split's place.
            @MainActor func notices() -> [String] {
                store.storyTimelineItems(on: record.start).compactMap {
                    if case .correction(_, let title, _) = $0 { return title } else { return nil }
                }
            }
            expect(notices() == ["Session split"], "the day's notice for a split is \(notices())", &problems)
            expect(store.mergeBack(tailID: halves.tail.id) && store.engine.archive.records == [record]
                   && notices() == ["Sessions merged"], "Merge Back gave \(notices())", &problems)
            expect(store.undoLastCorrection() && store.undoLastCorrection() && store.engine.archive.records == [record],
                   "two Undos did not give back the one record", &problems)
            // Taking the preset is the person's choice too.
            if let again = store.splitOffer(for: row) {
                expect(store.acceptSplit(again), "the preset was refused", &problems)
                expect(SplitStoreChecks.halves(of: record, in: store)?.tail.categorySource == .user,
                       "a preset the person accepted is not theirs", &problems)
            } else { problems.append("the offer did not return after Undo") }
            return problems
        }
    }
}
