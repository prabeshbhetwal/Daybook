import Foundation
import AppKit

/// How a session began, said quietly on its row and in its report (spec section 4, "Origin is shown,
/// quietly"): the owner's words for each origin, a rule by the name it has now, the app's own name for
/// the session until the person edits it, an away answer that carried the work on, and the report's
/// contradiction line, which only the person's and a rule's labels earn.
enum OriginMarkChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A session says how it began in the owner's words, for each origin and for records from before it was stored",
         wordsForEachOrigin),
        ("A rule's name reads as it is now, else as stored at the start, else as just a rule", ruleNames),
        ("Name chosen by Daybook goes when the person renames, and nothing else the person does adds or removes a line",
         nameFollowsTheApp),
        ("Carried on after you were away is read from an \"I was working\" answer inside the session, and from nothing else",
         carriedOnReadsTheAnswer),
        ("A running session reads from the engine, and a session nothing says anything about has no mark",
         runningAndUnknown),
        ("The mark is spoken as the full sentence, never by its symbol alone, and the row redraws when it changes",
         spokenAndRedrawn),
        ("The report carries the mark, and the contradiction line only for a label the person or a rule chose",
         reportCarriesBoth),
    ]

    private typealias Rig = CorrectionsStoreChecks

    private static func words(_ text: OriginText?) -> [String]? { text?.lines.map(\.text) }

    private static func provenance(_ origin: SessionOrigin, ruleID: UUID? = nil, ruleName: String? = nil,
                                   nameByApp: Bool = false) -> SessionProvenance {
        SessionProvenance(origin: origin, ruleID: ruleID, ruleName: ruleName,
                          categorySource: origin == .manual ? .user : .builtIn, nameByApp: nameByApp)
    }

    @MainActor
    private static func ruled(_ id: UUID, _ name: String, at clock: TestClock) -> (SessionEngine) -> Void {
        { _ = $0.startAutomatically(action: ActivityAutomaticAction(
            ruleID: id, ruleName: name, workType: .deepWork,
            evidence: DateInterval(start: clock.value.addingTimeInterval(-300), end: clock.value),
            reason: "Coding evidence", ruleVersion: 1, generation: 1, expectedRecordID: nil)) }
    }

    private static func wordsForEachOrigin() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = Rig.make()
            defer { MemoryDefaults.remove(named: suite) }
            let ruleID = UUID()
            store.engine.store.activityRules = [ActivityRule(id: ruleID, name: "Coding", workType: .deepWork,
                                                             bundleIDs: ["com.apple.dt.Xcode"])]
            guard let manual = Rig.ended(store, clock, begin: { $0.start(workType: .deepWork, intent: "Mine") }),
                  let automatic = Rig.ended(store, clock, begin: Rig.automatic("Parser")),
                  let byRule = Rig.ended(store, clock, begin: ruled(ruleID, "Coding", at: clock)) else {
                return ["no sessions were made"]
            }
            expect(words(store.originText(for: manual)) == ["Started by you"],
                   "a manual start read \(String(describing: words(store.originText(for: manual))))", &problems)
            expect(words(store.originText(for: automatic)) == ["Started automatically", "Name chosen by Daybook"],
                   "an automatic start read \(String(describing: words(store.originText(for: automatic))))", &problems)
            expect(words(store.originText(for: byRule)) == ["Started by rule ‘Coding’"],
                   "a rule's start read \(String(describing: words(store.originText(for: byRule))))", &problems)

            // Records from before the origin was stored say what their ownership flag did.
            let base = clock.value
            let old = [true, false].map { auto in
                SessionRecord(name: "Old", workType: .deepWork, start: base, end: base.addingTimeInterval(600),
                              workSeconds: 600, threadID: UUID(), isAuto: auto)
            }
            old.forEach { store.engine.archive.append($0) }
            expect(old.map { words(store.originText(for: ActivitySnapshotChecks.daySession([$0]))) }
                    == [["Started automatically"], ["Started by you"]],
                   "records from before the origin was stored read otherwise", &problems)
            return problems
        }
    }

    private static func ruleNames() -> [String] {
        var problems: [String] = []
        let id = UUID()
        func first(_ stored: String?, rules: [ActivityRule]) -> String? {
            OriginText.make(provenance(.rule, ruleID: id, ruleName: stored), rules: rules, carriedOn: false)
                .lines.first?.text
        }
        let renamed = ActivityRule(id: id, name: "Deep coding", workType: .deepWork, bundleIDs: ["a.b"])
        let other = ActivityRule(name: "Other", workType: .deepWork, bundleIDs: ["c.d"])
        expect(first("Coding", rules: [renamed]) == "Started by rule ‘Deep coding’",
               "a renamed rule read \(String(describing: first("Coding", rules: [renamed])))", &problems)
        expect(first("Coding", rules: []) == "Started by rule ‘Coding’", "a deleted rule lost its stored name", &problems)
        expect(first("Coding", rules: [other]) == "Started by rule ‘Coding’", "another rule's name was used", &problems)
        expect(first(nil, rules: []) == "Started by a rule", "a rule with no name read \(String(describing: first(nil, rules: [])))",
               &problems)
        expect(first("  ", rules: []) == "Started by a rule", "a blank stored name was shown", &problems)
        return problems
    }

    private static func nameFollowsTheApp() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = Rig.make()
            defer { MemoryDefaults.remove(named: suite) }
            guard let session = Rig.ended(store, clock, begin: Rig.automatic("Parser")) else { return ["no session was made"] }
            expect(words(store.originText(for: session))?.last == "Name chosen by Daybook",
                   "the app's own name was not marked", &problems)
            expect(store.setWorkType(.learning, for: session), "the category change was refused", &problems)
            expect(words(store.originText(for: session)) == ["Started automatically", "Name chosen by Daybook"],
                   "a category change moved the origin or the name line: \(String(describing: words(store.originText(for: session))))",
                   &problems)
            expect(store.renameSession(session, to: "Mine"), "the rename was refused", &problems)
            expect(words(store.originText(for: session)) == ["Started automatically"],
                   "a renamed session read \(String(describing: words(store.originText(for: session))))", &problems)
            return problems
        }
    }

    private static func carriedOnReadsTheAnswer() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let carried = "Carried on after you were away (your answer)"
            @MainActor
            func answered(_ answer: UserDecision) -> (store: SessionStore, session: DaySession?, suite: String) {
                let (store, clock, suite) = Rig.make()
                let engine = store.engine
                engine.start(workType: .deepWork, intent: "Mine")
                clock.advance(600)
                engine.transition(on: .awayBegan(trigger: .screenLock))
                clock.advance(1_320)
                engine.transition(on: .awayEnded)
                engine.transition(on: .decision(answer))
                clock.advance(300)
                _ = engine.stop()
                clock.advance(1_800)
                let focus = engine.archive.records.filter(\.workType.countsAsFocus)
                return (store, focus.isEmpty ? nil : ActivitySnapshotChecks.daySession(focus), suite)
            }
            let worked = answered(.mergeTime), away = answered(.continueSession)
            defer { [worked.suite, away.suite].forEach { MemoryDefaults.remove(named: $0) } }
            guard let counted = worked.session, let left = away.session else { return ["no sessions were made"] }
            expect(words(worked.store.originText(for: counted)) == ["Started by you", carried],
                   "\"I was working\" read \(String(describing: words(worked.store.originText(for: counted))))", &problems)
            expect(words(away.store.originText(for: left)) == ["Started by you"],
                   "\"I was away\" read \(String(describing: words(away.store.originText(for: left))))", &problems)
            // A later session of the same day is not carried on by an answer that lies before it.
            let begin = counted.end.addingTimeInterval(3_600)
            let later = SessionRecord(name: "Later", workType: .deepWork, start: begin,
                                      end: begin.addingTimeInterval(600), workSeconds: 600, threadID: UUID())
            worked.store.engine.archive.append(later)
            expect(words(worked.store.originText(for: ActivitySnapshotChecks.daySession([later]))) == ["Started by you"],
                   "an answer outside the session marked it as carried on", &problems)
            // An overlapping session of another thread does not borrow the answer.
            let other = SessionRecord(name: "Other", workType: .deepWork, start: counted.start, end: counted.end,
                                      workSeconds: 600, threadID: UUID())
            worked.store.engine.archive.append(other)
            expect(words(worked.store.originText(for: ActivitySnapshotChecks.daySession([other]))) == ["Started by you"],
                   "another thread's session borrowed the answer", &problems)
            return problems
        }
    }

    private static func runningAndUnknown() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = Rig.make()
            defer { MemoryDefaults.remove(named: suite) }
            store.engine.start(workType: .deepWork, intent: "Parser", isAuto: true, nameByApp: true)
            clock.advance(300)
            @MainActor
            func row(thread: UUID, running: Bool) -> DaySession {
                DaySession(id: UUID(), threadID: thread, name: "Parser", workType: .deepWork, start: clock.value,
                           end: clock.value, worked: 300, stretches: 1, spans: [], recordIDs: [UUID()], isRunning: running)
            }
            expect(words(store.originText(for: row(thread: store.engine.activeThreadID, running: true)))
                    == ["Started automatically", "Name chosen by Daybook"],
                   "a running session did not read the engine's provenance", &problems)
            expect(store.originText(for: row(thread: UUID(), running: false)) == nil,
                   "a session nothing says anything about got a mark", &problems)
            expect(store.originText(for: row(thread: UUID(), running: true)) == nil,
                   "another thread's running row read the engine's provenance", &problems)
            return problems
        }
    }

    private static func spokenAndRedrawn() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let text = OriginText.make(provenance(.automatic, nameByApp: true), rules: [], carriedOn: true)
            expect(OriginMark(text: text).spoken == "Started automatically. Carried on after you were away (your answer). Name chosen by Daybook",
                   "the mark spoke \(OriginMark(text: text).spoken)", &problems)
            let symbols = OriginText.Kind.allCases.map(OriginMark.symbol(for:))
            expect(Set(symbols).count == symbols.count, "two kinds share a symbol", &problems)
            expect(symbols.allSatisfy { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil },
                   "a symbol is not in this system's set: \(symbols)", &problems)
            expect(text.lines.allSatisfy { !$0.text.isEmpty }, "a line has no words", &problems)

            @MainActor
            func card(_ origin: OriginText?) -> StableSessionCard {
                let session = DaySession(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                                         threadID: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
                                         name: "Parser", workType: .deepWork, start: SelfTest.base,
                                         end: SelfTest.base.addingTimeInterval(600), worked: 600, stretches: 1,
                                         spans: [], isRunning: false)
                let signature = SessionCardSignature(
                    session: session, apps: [], shape: nil, shapeCaption: nil, activity: nil,
                    canContinue: false, canStartNewSession: false, isOpen: false, clock: nil, liveStatus: nil,
                    power: nil, recordIDs: [], notes: [], editorsOpen: [], metadataError: nil, isHistory: false,
                    canRemove: true, removeBlockReason: nil, pauseTitle: "Pause", canControl: false,
                    minimumRecorded: 30, origin: origin)
                return StableSessionCard(signature: signature, card: { fatalError("a check does not draw") })
            }
            let manual = OriginText.make(provenance(.manual), rules: [], carriedOn: false)
            expect(card(manual) == card(manual), "a card changed with nothing about it changed", &problems)
            expect(card(manual) != card(text) && card(manual) != card(nil),
                   "a card did not redraw when how it began changed", &problems)
            return problems
        }
    }

    private static func reportCarriesBoth() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = Rig.make()
            defer { MemoryDefaults.remove(named: suite) }
            // 29% coding, 61% media: what a "Deep work" label does not say.
            @MainActor
            func session(_ begin: (SessionEngine) -> Void) -> DaySession? {
                guard let made = Rig.ended(store, clock, shape: nil, begin: begin),
                      let record = Rig.record(made, in: store) else { return nil }
                let bounds = DateInterval(start: record.start, end: record.end)
                store.metadataArchive.saveActivityShape(
                    ActivitySnapshotChecks.shape(.activity(.media), credited: [
                        AppPurpose.coding.rawValue: 174, AppPurpose.media.rawValue: 366,
                        AppPurpose.utility.rawValue: 60], over: bounds), for: record.id)
                return made
            }
            let ruleID = UUID()
            guard let manual = session({ $0.start(workType: .deepWork, intent: "Mine") }),
                  let automatic = session(Rig.automatic("Parser")),
                  let byRule = session(ruled(ruleID, "Coding", at: clock)) else { return ["no sessions were made"] }
            let line = "Mostly entertainment: 6 of 10 minutes"
            expect(SessionReport.make(for: manual, store: store).contradiction == line,
                   "the person's label got \(String(describing: SessionReport.make(for: manual, store: store).contradiction))",
                   &problems)
            expect(SessionReport.make(for: byRule, store: store).contradiction == line, "a rule's label got no line", &problems)
            expect(SessionReport.make(for: automatic, store: store).contradiction == nil,
                   "Daybook's own guess was contradicted", &problems)
            expect(words(SessionReport.make(for: manual, store: store).origin) == ["Started by you"],
                   "the report did not carry the mark", &problems)
            // Taking the category over makes it the person's, and then the evidence is held against it.
            expect(store.setWorkType(.admin, for: automatic), "the category change was refused", &problems)
            expect(SessionReport.make(for: automatic.recategorised(as: .admin), store: store).contradiction == line,
                   "a category the person took over got no line", &problems)
            return problems
        }
    }
}
