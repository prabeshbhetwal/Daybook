import Foundation

/// An automatic session that ended with its work moved on to something that was not focused work splits
/// itself, and the tail is Unsorted from the app, which never counts as focus; the person's own offer still
/// asks them to pick.
enum UnsortedTailChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An automatic session's own cut files a tail that was not focused work as Unsorted; the person's offer still asks",
         ownCutChoice),
        ("An automatic session whose tail was a chat splits itself, the tail is Unsorted and leaves the focus total, and Undo joins it",
         chatTailIsUnsorted),
        ("Merge Back rejoins an Unsorted tail, a remembered category beats Unsorted, and a head that does not count stays whole",
         mergeAndRememberAndStayWhole),
    ]

    private static func ownCutChoice() -> [String] {
        var problems: [String] = []
        let head = WorkType.learning
        func decide(_ label: ActivityLabel?, suggested: WorkType? = .admin, ownCut: Bool = true) -> SplitTailChoice {
            .decide(label: label, remembered: nil, suggested: suggested, head: head, ownCut: ownCut)
        }
        for label in [ActivityLabel.activity(.media), .activity(.communication), .activity(.research),
                      .activity(.utility), .mixed, .unsorted] {
            expect(decide(label) == .chosen(.unsorted, .builtIn), "\(label) for a tail gave \(decide(label))", &problems)
            expect(decide(label, ownCut: false) == .ask(head), "the person's offer for \(label) did not ask", &problems)
        }
        let remembered = SplitTailChoice.decide(label: .activity(.communication), remembered: .admin, suggested: nil,
                                                head: head, ownCut: true)
        expect(remembered == .chosen(.admin, .correction), "the person's remembered category lost to \(remembered)", &problems)
        let rest = SplitTailChoice.decide(label: .activity(.media), remembered: .breakTime, suggested: nil,
                                          head: head, ownCut: true)
        expect(rest == .chosen(.unsorted, .builtIn), "a remembered category that cannot be started gave \(rest)", &problems)
        expect(decide(nil) == .ask(head), "a tail with no evidence was filed", &problems)
        expect(decide(.activity(.coding)) == .chosen(.admin, .builtIn), "a focused tail lost its pick", &problems)
        expect(decide(.activity(.coding), suggested: nil) == .ask(head),
               "focused work Daybook cannot place was filed as \(decide(.activity(.coding), suggested: nil))", &problems)
        return problems
    }

    private static func chatTailIsUnsorted() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = SplitAutomaticChecks.rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let record = SplitAutomaticChecks.ended(r, then: SplitAutomaticChecks.chat)
            // The whole session is the day's only focus. A refresh would already run the sweep that cuts it.
            let before = record.workSeconds
            r.store.writeActivitySnapshots()
            guard let halves = SplitStoreChecks.halves(of: record, in: r.store) else {
                return problems + ["the session did not split: \(r.engine.archive.records.count) records, \(r.store.correctionError ?? "no error")"]
            }
            let (head, tail) = (halves.head, halves.tail)
            expect(head.workType == .learning && head.categorySource == .builtIn && head.name == "Coding",
                   "the head changed: \(head)", &problems)
            expect(tail.workType == .unsorted && tail.categorySource == .builtIn && tail.origin == .automatic
                   && tail.name == "Catching up" && tail.nameByApp == true, "the tail is \(tail)", &problems)
            expect(r.store.canMergeBack(recordID: tail.id), "Merge Back is not offered on the tail", &problems)
            r.store.refresh()
            let after = r.store.todayTotal
            expect(tail.workSeconds > 0 && abs(after - (before - tail.workSeconds)) < 1,
                   "the focus total should lose the Unsorted tail's \(tail.workSeconds) s: \(before) s, then \(after) s", &problems)
            expect(r.store.undoLastCorrection() && r.engine.archive.records == [record],
                   "Undo did not give back the one record: \(r.store.correctionError ?? "")", &problems)
            r.store.refresh()
            expect(abs(r.store.todayTotal - before) < 1, "Undo should give the focus total back: \(r.store.todayTotal) s", &problems)
            r.store.writeActivitySnapshots()
            expect(r.engine.archive.records == [record], "the next sweep cut the session Undo had joined", &problems)
            return problems
        }
    }

    private static func mergeAndRememberAndStayWhole() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // Merge Back joins an Unsorted tail onto its head.
            guard let m = SplitAutomaticChecks.rig() else { return ["could not create isolated preferences"] }
            defer { m.close() }
            let record = SplitAutomaticChecks.ended(m, then: SplitAutomaticChecks.chat)
            m.store.writeActivitySnapshots()
            if let tail = SplitStoreChecks.halves(of: record, in: m.store)?.tail {
                expect(m.store.mergeBack(tailID: tail.id) && m.engine.archive.records.count == 1
                       && m.engine.archive.records.first?.workType == .learning
                       && abs((m.engine.archive.records.first?.workSeconds ?? 0) - record.workSeconds) < 0.5,
                       "Merge Back did not rejoin: \(m.engine.archive.records)", &problems)
            } else { problems.append("the chat tail did not split") }

            // The person's remembered category for that kind of stretch beats Unsorted.
            guard let r = SplitAutomaticChecks.rig() else { return problems + ["could not create isolated preferences"] }
            defer { r.close() }
            let chatted = SplitAutomaticChecks.ended(r, then: SplitAutomaticChecks.chat)
            if let at = r.store.splitMoment(in: chatted),
               let fingerprint = r.store.endedShape(of: chatted, within: DateInterval(start: at, end: chatted.end))?.fingerprint {
                _ = CorrectionsStore(directory: r.engine.archive.dataDirectoryURL)
                    .record(fingerprint: fingerprint, chosen: WorkType.admin.rawValue, vetoed: nil, at: r.clock.value)
                r.store.writeActivitySnapshots()
                let tail = SplitStoreChecks.halves(of: chatted, in: r.store)?.tail
                expect(tail?.workType == .admin && tail?.categorySource == .correction,
                       "the remembered tail is \(String(describing: tail))", &problems)
            } else { problems.append("no cut or no fingerprint for the chat tail") }

            // A head that does not count either stays whole: two Unsorted rows would change nothing.
            guard let u = SplitAutomaticChecks.rig() else { return problems + ["could not create isolated preferences"] }
            defer { u.close() }
            let unsorted = SplitAutomaticChecks.ended(u, then: SplitAutomaticChecks.chat, type: .unsorted)
            u.store.writeActivitySnapshots()
            expect(u.engine.archive.records == [unsorted], "an Unsorted session was cut into Unsorted halves", &problems)
            return problems
        }
    }
}
