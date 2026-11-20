import Foundation

/// Phase C, fix round 4: Keep writes the person's category before the label file lets the label go, an answer
/// is offered only once the label file holds it and no longer once offers are not wanted, a Settings name taken
/// by a hidden on-device AI category says how to free it, and a label carries no invisible format character but a joiner.
enum AILabelSafetyChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig

    static let tests: [(String, () -> [String])] = [
        ("Keep puts the label in the person's categories before it leaves the label file", keepWritesCategoryFirst),
        ("Turning assigning on withdraws shadow mode's offers, and Use refuses one shown before", assigningWithdrawsOffers),
        ("An answer the label file could not take is not offered", unsavedAnswerIsNotOffered),
        ("A name taken by a hidden on-device AI category says how to free it", hiddenLabelClashSaysSo),
        ("A label with an invisible format character is refused, but a joiner is kept and ignored when matching", formatCharactersAreRefused),
        ("Turning the assigning switch in Settings refreshes the app at once", assignSwitchRefreshes),
    ]

    /// What the person's categories held when the label file was last saved.
    private final class Seen { var heldAtSave: Bool? }

    private static func keepWritesCategoryFirst() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.mode.assigns = true
            rig.ask()
            guard let label = rig.assistant.labels.book.labels.first else { return problems.append("no label was made") }
            // A crash just after the label file is written leaves what that moment holds: the id must be the person's.
            let seen = Seen(), persistence = rig.f.persistence, id = label.id
            let observer = NotificationCenter.default.addObserver(
                forName: AILabelStore.didSave, object: rig.assistant.labels, queue: nil) { _ in
                seen.heldAtSave = persistence.workTypeDefinitions.contains { $0.id == id }
            }
            defer { NotificationCenter.default.removeObserver(observer) }
            expect(rig.f.store.keepAILabel(id), "Keep was refused: \(String(describing: rig.f.store.correctionError))", &problems)
            expect(seen.heldAtSave == true,
                   "the label file let the label go before the person's categories held it: \(String(describing: seen.heldAtSave))",
                   &problems)
            expect(persistence.workTypeDefinitions.contains { $0.id == id && !$0.isUnkeptAILabel && $0.name == "Films" },
                   "the kept label is not among the person's categories", &problems)
            expect(!rig.reloaded().book.labels.contains { $0.id == id }, "the kept label is still in the label file", &problems)
        }
    }

    /// No refresh between the switch and Use, as when the report is open; then one, which takes the offers away.
    private static func assigningWithdrawsOffers() -> [String] {
        let turned = Rig.withRig(reply: { _, _ in Rig.answer("2") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.ask()
            guard let shown = rig.f.store.aiReport(for: rig.session()).suggestion else { return problems.append("nothing was offered") }
            rig.mode.assigns = true
            refusesOffer(shown, rig, &problems)
            rig.f.store.refresh()
            expect(rig.assistant.suggestions.isEmpty, "a refresh with assigning on kept the offers: \(rig.assistant.suggestions)", &problems)
        }
        // Assigning turned on while the model was thinking: the answer is kept for shadow mode, not shown.
        let hook = Rig.Hook()
        return turned + Rig.withRig(reply: { _, _ in hook.run(); return Rig.answer("2") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            hook.run = { rig.mode.assigns = true }
            rig.ask()
            expect(rig.assistant.suggestions[rig.record.id] != nil, "the answer was not kept for shadow mode", &problems)
            refusesOffer(.pick(.meetings), rig, &problems)
        }
    }

    @MainActor private static func refusesOffer(_ shown: AISessionReport.Suggestion, _ rig: Rig.Rig, _ problems: inout [String]) {
        expect(rig.f.store.aiReport(for: rig.session()).suggestion == nil,
               "the report offers a suggestion with assigning on: \(rig.assistant.suggestions)", &problems)
        expect(!rig.f.store.useAISuggestion(shown, for: rig.session()), "Use took a shadow suggestion with assigning on", &problems)
        expect(rig.stored()?.workType == .deepWork,
               "the session's category changed: \(String(describing: rig.stored()?.workType.rawValue))", &problems)
    }

    private static func unsavedAnswerIsNotOffered() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("2") }) { rig, problems in
            guard let unblock = AILaunchChecks.blockLabelFile(rig) else { return problems.append("the label file could not be held") }
            defer { unblock() }
            rig.ask()
            expect(rig.calls.questions.count == 1, "the model was asked \(rig.calls.questions.count) times, not once", &problems)
            expect(rig.assistant.suggestions.isEmpty,
                   "an answer the label file did not take was offered: \(rig.assistant.suggestions)", &problems)
        }
    }

    private static func hiddenLabelClashSaysSo() -> [String] {
        var problems: [String] = []
        let hidden = WorkTypeDefinition(id: "ai.films", name: "Films", symbolName: "film", hue: .grey, isUnkeptAILabel: true)
        let own = WorkTypeDefinition(id: "custom.films", name: "Films", symbolName: "film", hue: .grey)
        let onHidden = WorkTypeDefinition.nameProblem("Films", for: "custom.new", among: [hidden])
        expect(onHidden == "An on-device AI category is already called “Films”. Keep or remove it from one of its sessions first.",
               "a clash with a hidden label read: \(String(describing: onHidden))", &problems)
        let onOwn = WorkTypeDefinition.nameProblem("Films", for: "custom.new", among: [own])
        expect(onOwn == "Another category is already called “Films”.", "a clash with the person's own read: \(String(describing: onOwn))",
               &problems)
        return problems
    }

    private static func formatCharactersAreRefused() -> [String] {
        var problems: [String] = []
        // A zero-width space and a left-to-right mark are refused, and so is a joiner that follows no letter.
        for odd in ["Fi\u{200B}lms", "Fi\u{200E}lms", "\u{200D}Films", "Fi\u{200D}\u{200D}lms", "Fi\u{200C}\u{200C}lms"] {
            let scalars = odd.unicodeScalars.map { String($0.value, radix: 16) }
            expect(LabelAudit.clean(odd) == nil, "a label with an invisible character was kept: \(scalars)", &problems)
        }
        // A joiner is kept, since real words need it, but a name with one is the same as the name without.
        expect(LabelAudit.matches("Fi\u{200D}lms", "Films"), "a name with a zero-width joiner did not match Films", &problems)
        // Persian "mi-khaham" and "ketab-khani" with a non-joiner, Sinhala "shri" with a joiner after a virama.
        for word in ["\u{0645}\u{06CC}\u{200C}\u{062E}\u{0648}\u{0627}\u{0647}\u{0645}",
                     "\u{06A9}\u{062A}\u{0627}\u{0628}\u{200C}\u{062E}\u{0648}\u{0627}\u{0646}\u{06CC}",
                     "\u{0DC1}\u{0DCA}\u{200D}\u{0DBB}\u{0DD3}"] {
            let scalars = word.unicodeScalars.map { String($0.value, radix: 16) }
            expect(LabelAudit.clean(word) == word, "a label with a joiner a real word needs was refused: \(scalars)", &problems)
        }
        let films = WorkTypeDefinition(id: "custom.films", name: "Films", symbolName: "film", hue: .grey)
        expect(WorkTypeDefinition.nameProblem("Fi\u{200D}lms", for: "custom.new", among: [films]) != nil,
               "a Settings name with a zero-width joiner did not clash with Films", &problems)
        expect(LabelAudit.clean("Films") == "Films", "a plain label was refused", &problems)
        expect(LabelAudit.clean("Home Films") == "Home Films", "a two-word label was refused", &problems)
        return problems
    }

    /// The refresh is what takes shadow mode's offers off an open report (`followSwitch`).
    private static func assignSwitchRefreshes() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-ai-assign-refresh-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["no preferences suite"] }
        defer { MemoryDefaults.remove(named: suite) }
        var refreshes = 0
        let settings = SettingsModel(store: PersistenceStore(defaults: defaults), isTrackingEnabled: true,
                                     onChange: { refreshes += 1 }, onTrackingChanged: { _ in })
        settings.aiCategories = AICategorySource(setting: AIAssignSetting(defaults: defaults), labels: nil,
                                                 modelAvailable: { true }, unavailableReason: { "No model in this check." })
        settings.aiAssignsCategories = true
        expect(refreshes == 1, "turning assigning on refreshed \(refreshes) times, not once", &problems)
        settings.aiAssignsCategories = false
        expect(refreshes == 2, "turning assigning off refreshed \(refreshes) times in all, not twice", &problems)
        return problems
    }
}
