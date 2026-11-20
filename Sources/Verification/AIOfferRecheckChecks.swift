import Foundation

/// The offer is checked again when it is shown and when it is taken (Phase C, rulings C8, C12, C25 and C32): two
/// proposals of one name make one category, Keep never gives an aged label a name a live one holds, Use refuses an
/// offer that lapsed while the report was open, and turning on-device AI off takes every offer away.
enum AIOfferRecheckChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig

    static let tests: [(String, () -> [String])] = [
        ("Two new categories proposed with one name become one category, whichever is used first", oneNameOneCategory),
        ("Keep refuses an aged label the name of a live one", agedKeepRefusesALiveName),
        ("Use refuses, with the reason shown, a suggestion that lapsed while the report was open", useRefusesALapsedOffer),
        ("Turning on-device AI off takes its suggestions out of the report, open or not, and out of Use", offerFollowsTheSwitch),
    ]

    private static func oneNameOneCategory() -> [String] {
        Rig.withRig([Rig.Spec(seed: 1), Rig.Spec(seed: 2)], reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.ask(0)
            rig.ask(1)
            guard case .proposed(let first, _)? = rig.assistant.suggestions[rig.records[0].id],
                  case .proposed(let second, _)? = rig.assistant.suggestions[rig.records[1].id], first != second else {
                problems.append("shadow mode did not propose Films twice: \(rig.assistant.suggestions)"); return
            }
            expect(rig.f.store.useAISuggestion(.newCategory(name: "Films"), for: rig.session(0)), "Use on the first was refused", &problems)
            let shown = rig.f.store.aiReport(for: rig.session(1)).suggestion
            expect(shown == .pick(WorkType(rawValue: first)), "the second session was offered \(String(describing: shown))", &problems)
            _ = shown.map { rig.f.store.useAISuggestion($0, for: rig.session(1)) }
            let films = rig.f.persistence.workTypeDefinitions.filter { $0.name == "Films" }.map(\.id)
            expect(films == [first], "the person's categories called Films were \(films)", &problems)
            expect(rig.stored(1)?.workType.rawValue == first,
                   "the second session was filed under \(rig.stored(1)?.workType.rawValue ?? "nothing"), not \(first)", &problems)
        }
    }

    private static func agedKeepRefusesALiveName() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            assigned(rig)
            guard let aged = rig.assistant.labels.book.labels.first else { problems.append("no label was made"); return }
            rig.f.clock.advance(AILabelConstants.labelArchiveAfter + 1)
            var book = rig.assistant.labels.book
            book.archiveStale(now: rig.f.clock.value)
            let live = book.addUnkeptLabel(id: "ai.selftest-live", name: "Films", dominant: .media,
                                           fingerprint: AIFixture.fingerprint(9), now: rig.f.clock.value)
            guard live != nil, rig.assistant.labels.save(book, at: rig.f.clock.value) == nil,
                  rig.assistant.labels.book.liveLabels(now: rig.f.clock.value).map(\.id) == ["ai.selftest-live"] else {
                problems.append("no live label shared the aged one's name: \(rig.assistant.labels.book.labels)"); return
            }
            expect(!rig.f.store.keepAILabel(aged.id), "Keep made a second Films", &problems)
            expect(rig.f.store.correctionError?.contains("already called") == true,
                   "the refusal said \(rig.f.store.correctionError ?? "nothing")", &problems)
            expect(!rig.f.persistence.workTypeDefinitions.contains { $0.id == aged.id }, "the aged label was kept", &problems)
        }
    }

    private static func useRefusesALapsedOffer() -> [String] {
        Rig.withRig([Rig.Spec(seed: 1), Rig.Spec(seed: 1)], reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            assigned(rig)
            rig.mode.assigns = false
            rig.ask(1)
            guard let label = rig.assistant.labels.book.labels.first,
                  let shown = rig.f.store.aiReport(for: rig.session(1)).suggestion,
                  shown == .label(WorkType(rawValue: label.id)) else {
                problems.append("the second session was not offered the label: \(rig.assistant.suggestions)"); return
            }
            let before = rig.stored(1)
            rig.f.clock.advance(AILabelConstants.labelArchiveAfter + 1)
            // The label lapsed and nothing else: the session is still one the assistant would ask about.
            guard rig.f.store.categoryAskTarget(for: rig.records[1].id) != nil,
                  !rig.assistant.labels.book.liveLabels(now: rig.f.clock.value).contains(where: { $0.id == label.id }) else {
                problems.append("the label did not lapse on its own"); return
            }
            expect(!rig.f.store.useAISuggestion(shown, for: rig.session(1)), "Use took a lapsed suggestion", &problems)
            expect(rig.f.store.correctionError?.hasPrefix("That suggestion is no longer offered.") == true,
                   "Use refused saying \(rig.f.store.correctionError ?? "nothing")", &problems)
            expect(rig.stored(1) == before, "the session changed: \(String(describing: rig.stored(1)))", &problems)
            expect(!rig.f.persistence.workTypeDefinitions.contains { $0.id == label.id }, "the lapsed label was kept", &problems)
        }
    }

    private static func offerFollowsTheSwitch() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("2") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.ask()
            let cache = SessionReportCache()
            guard let shown = cache.ai(for: rig.session(), store: rig.f.store).suggestion else {
                problems.append("no suggestion was offered: \(rig.assistant.suggestions)"); return
            }
            let before = rig.stored()
            rig.f.persistence.useAppleIntelligence = false
            let open = cache.ai(for: rig.session(), store: rig.f.store).suggestion
            expect(open == nil, "the open report kept \(String(describing: open))", &problems)
            let fresh = rig.f.store.aiReport(for: rig.session()).suggestion
            expect(fresh == nil, "the report offered \(String(describing: fresh))", &problems)
            expect(!rig.f.store.useAISuggestion(shown, for: rig.session()), "Use filed with on-device AI off", &problems)
            expect(rig.stored() == before, "the session changed: \(String(describing: rig.stored()))", &problems)
        }
    }

    @MainActor private static func assigned(_ rig: Rig.Rig) {
        rig.f.store.installCategoryAssistant(rig.assistant)
        rig.mode.assigns = true
        rig.ask()
    }
}
