import Foundation

/// What a review of the AI report found (Phase C, rulings C8, C15, C21, C22 and C32): the report and Use
/// reading one answer, the open card's AI part following the assistant and the label file, a label archived for
/// age still kept from its sessions while one the person retired is not, Use saying what it adds, the Settings
/// switch's reason handed in, and the editor's focus switch saved as set.
enum AIOfferChecks: CheckSuite {
    typealias Rig = CategoryAssistantRig

    static let tests: [(String, () -> [String])] = [
        ("The suggestion a report shows is the one Use files, across a session's stretches", reportAndUseAgree),
        ("Use never files a stretch's old answer once the person set that stretch's category", useSkipsThePersonsStretch),
        ("An open report's AI part follows a withdrawn suggestion and a saved label file", cardFollowsTheAI),
        ("A label archived for age can still be kept from its sessions; one the person removed cannot", agedLabelKeeps),
        ("Use says when it also adds a category", useHintSaysWhatItAdds),
        ("The Settings switch's reason for no model is handed in, never read from the live model", reasonIsHandedIn),
        ("The category editor saves Counts toward focus goals as the switch was left", editorFocusRoundTrips),
        ("A suggested label removed since is no longer offered, so Use is never a button that does nothing", retiredSuggestionGoes),
        ("Keep or Rename never gives an AI-made label the name of another category", keepRefusesATakenName),
    ]

    /// Two stretches of one session, the app's own filing on each, asked about one after the other.
    static func twoStretches(reply: @escaping @MainActor (Int, CategoryQuestion) async throws -> CategoryAnswerChoice,
                                     _ body: @MainActor (Rig.Rig, inout [String]) -> Void) -> [String] {
        let thread = UUID()
        var first = Rig.Spec(seed: 1), second = Rig.Spec(seed: 2)
        first.threadID = thread
        second.threadID = thread
        return Rig.withRig([first, second], reply: reply) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.ask(0)
            rig.ask(1)
            body(rig, &problems)
        }
    }

    /// The session both stretches make, as the archive holds them now, in the order the session lists them.
    @MainActor static func joined(_ rig: Rig.Rig) -> DaySession {
        let a = rig.stored(0) ?? rig.records[0], b = rig.stored(1) ?? rig.records[1]
        return DaySession(id: a.id, threadID: a.threadID, name: a.name, workType: a.workType, start: a.start, end: b.end,
                          worked: a.workSeconds + b.workSeconds, stretches: 2,
                          spans: [DateInterval(start: a.start, end: a.end), DateInterval(start: b.start, end: b.end)],
                          recordIDs: [a.id, b.id], isRunning: false)
    }

    /// Two different picks, one per stretch, or nil with the reason in `problems`.
    @MainActor private static func picks(_ rig: Rig.Rig, _ problems: inout [String]) -> (String, String)? {
        guard case .pick(let a)? = rig.assistant.suggestions[rig.records[0].id],
              case .pick(let b)? = rig.assistant.suggestions[rig.records[1].id], a != b else {
            problems.append("shadow mode did not offer two different picks: \(rig.assistant.suggestions)")
            return nil
        }
        return (a, b)
    }

    private static func reportAndUseAgree() -> [String] {
        twoStretches(reply: { count, _ in Rig.answer(count == 1 ? "2" : "3") }) { rig, problems in
            guard picks(rig, &problems) != nil else { return }
            let shown = rig.f.store.aiReport(for: joined(rig)).suggestion
            expect(rig.use(joined(rig)), "Use was refused", &problems)
            let filed = rig.stored(0).map { AISessionReport.Suggestion.pick($0.workType) }
            expect(shown != nil && shown == filed,
                   "the report showed \(String(describing: shown)) but Use filed \(String(describing: filed))", &problems)
        }
    }

    private static func useSkipsThePersonsStretch() -> [String] {
        twoStretches(reply: { count, _ in Rig.answer(count == 1 ? "2" : "3") }) { rig, problems in
            guard let (stale, offered) = picks(rig, &problems), var mine = rig.stored(0) else { return }
            // The person files the first stretch themselves; its answer is left behind, never withdrawn.
            mine.workType = .learning
            mine.categorySource = .user
            guard rig.f.engine.rewriteRecords([mine]) else { problems.append("the person's filing was refused"); return }
            let shown = rig.f.store.aiReport(for: joined(rig)).suggestion
            expect(shown == .pick(WorkType(rawValue: offered)), "the report offered \(String(describing: shown))", &problems)
            expect(rig.use(joined(rig)), "Use was refused", &problems)
            let filed = rig.stored(1)?.workType.rawValue
            expect(filed == offered && filed != stale,
                   "Use filed \(filed ?? "nothing"), not the second stretch's \(offered) (the first's was \(stale))", &problems)
        }
    }

    private static func cardFollowsTheAI() -> [String] {
        var problems = Rig.withRig(reply: { _, _ in Rig.answer("2") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.ask()
            let cache = SessionReportCache()
            expect(cache.ai(for: rig.session(), store: rig.f.store).suggestion != nil, "the card showed no suggestion", &problems)
            rig.assistant.withdraw([rig.record.id])
            let after = cache.ai(for: rig.session(), store: rig.f.store)
            expect(after.suggestion == nil, "the card kept a withdrawn suggestion: \(after)", &problems)
        }
        problems += Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            assigned(rig)
            let cache = SessionReportCache()
            guard case .label(let type)? = cache.ai(for: rig.session(), store: rig.f.store).filing else {
                problems.append("the card showed no label"); return
            }
            retire(rig)
            let after = cache.ai(for: rig.session(), store: rig.f.store)
            expect(after.filing == .retiredLabel(type), "the card missed the saved label file: \(after)", &problems)
        }
        return problems
    }

    private static func agedLabelKeeps() -> [String] {
        var problems = Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            assigned(rig)
            guard let label = rig.assistant.labels.book.labels.first else { problems.append("no label was made"); return }
            // Unused past the limit: the next save of the label file archives it (C15).
            rig.f.clock.advance(AILabelConstants.labelArchiveAfter + 1)
            guard rig.assistant.labels.save(rig.assistant.labels.book, at: rig.f.clock.value) == nil,
                  rig.assistant.labels.book.labels.first?.archived == true else {
                problems.append("the label was not archived for age"); return
            }
            let type = WorkType(rawValue: label.id)
            let aged = rig.f.store.aiReport(for: rig.session())
            expect(aged.filing == .lapsedLabel(type) && aged.filing?.keepableLabel == type
                   && aged.mergeTargets == WorkType.startable,
                   "a label archived for age did not offer Keep, Rename, Merge Into and Remove: \(aged)", &problems)
            expect(aged.filing.map(AILabelActions.sentence) == "On-device AI made the category Films for this. It is no longer suggested.",
                   "an aged label read \(aged.filing.map(AILabelActions.sentence) ?? "nothing")", &problems)
            expect(rig.f.store.keepAILabel(label.id) && rig.f.persistence.workTypeDefinitions.contains { $0.id == label.id },
                   "Keep on a label archived for age was refused", &problems)
        }
        problems += Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            assigned(rig)
            guard let label = rig.assistant.labels.book.labels.first else { problems.append("no label was made"); return }
            retire(rig)
            let retired = rig.f.store.aiReport(for: rig.session())
            expect(retired.filing == .retiredLabel(WorkType(rawValue: label.id)) && retired.filing?.keepableLabel == nil,
                   "a label the person removed offered Keep: \(retired)", &problems)
            expect(!rig.f.store.keepAILabel(label.id), "Keep brought back a label the person removed", &problems)
        }
        return problems
    }

    private static func useHintSaysWhatItAdds() -> [String] {
        var problems: [String] = []
        let made = AISuggestionRow.useHint(for: .newCategory(name: "Writing"))
        let pick = AISuggestionRow.useHint(for: .pick(.deepWork))
        expect(made == "Adds Writing to your categories and files this session under it.", "a new category's Use said \(made)", &problems)
        expect(pick == "Files this session under \(WorkType.deepWork.displayName).", "a pick's Use said \(pick)", &problems)
        return problems
    }

    private static func reasonIsHandedIn() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-ai-offer-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["no preferences suite"] }
        defer { MemoryDefaults.remove(named: suite) }
        let settings = SettingsModel(store: PersistenceStore(defaults: defaults), isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        settings.aiCategories = AICategorySource(setting: AIAssignSetting(defaults: defaults), labels: nil,
                                                 modelAvailable: { false }, unavailableReason: { "Stand-in reason." })
        settings.useAppleIntelligence = true
        expect(settings.aiAssignDisabledReason == "Stand-in reason.",
               "the reason was not the one handed in: \(settings.aiAssignDisabledReason ?? "none")", &problems)
        return problems
    }

    private static func editorFocusRoundTrips() -> [String] {
        var problems: [String] = []
        let id = "selftest-focus-\(UUID().uuidString)"
        let definition = WorkTypeDefinition(id: id, name: "Films", symbolName: "film", hue: .blue, countsTowardFocus: false)
        let editor = CategoryEditorState()
        editor.edit(definition)
        let untouched = editor.definitionForSaving(existing: [definition])
        expect(untouched?.countsTowardFocus == false, "an untouched draft saved \(String(describing: untouched?.countsTowardFocus))", &problems)
        editor.countsTowardFocus.toggle()
        let flipped = editor.definitionForSaving(existing: [definition])
        expect(flipped?.countsTowardFocus == true, "the flipped switch saved \(String(describing: flipped?.countsTowardFocus))", &problems)
        return problems
    }

    private static func retiredSuggestionGoes() -> [String] {
        Rig.withRig([Rig.Spec(seed: 1), Rig.Spec(seed: 1)], reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            assigned(rig)
            rig.mode.assigns = false
            rig.ask(1)
            guard let label = rig.assistant.labels.book.labels.first,
                  rig.f.store.aiReport(for: rig.session(1)).suggestion == .label(WorkType(rawValue: label.id)) else {
                problems.append("the second session was not offered the label: \(rig.assistant.suggestions)"); return
            }
            expect(rig.f.store.removeAILabel(label.id), "Remove was refused", &problems)
            let after = rig.f.store.aiReport(for: rig.session(1))
            expect(after.suggestion == nil, "a removed label was still offered: \(after)", &problems)
        }
    }

    private static func keepRefusesATakenName() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            assigned(rig)
            guard let label = rig.assistant.labels.book.labels.first else { problems.append("no label was made"); return }
            let taken = WorkType.meetings.displayName.lowercased()
            expect(!rig.f.store.keepAILabel(label.id, as: taken), "Rename took the name of \(WorkType.meetings.displayName)", &problems)
            expect(!rig.f.persistence.workTypeDefinitions.contains { $0.id == label.id }
                   && rig.assistant.labels.book.labels.contains { $0.id == label.id },
                   "a refused Rename still kept the label", &problems)
        }
    }

    // MARK: - Fixtures

    @MainActor private static func assigned(_ rig: Rig.Rig) {
        rig.f.store.installCategoryAssistant(rig.assistant)
        rig.mode.assigns = true
        rig.ask()
    }

    /// What a Merge Into or Remove refused halfway leaves: the label retired by the person, its session still
    /// carrying it.
    @MainActor private static func retire(_ rig: Rig.Rig) {
        var book = rig.assistant.labels.book
        guard !book.labels.isEmpty else { return }
        book.labels[0].archived = true
        book.removedNames.append(book.labels[0].name)
        _ = rig.assistant.labels.save(book, at: rig.f.clock.value)
    }
}
