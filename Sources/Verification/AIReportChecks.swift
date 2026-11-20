import Foundation

/// What a session report and its row show of the AI (Phase C, rulings C8, C13, C17, C24 and C31): shadow
/// suggestions back after a relaunch with no question asked, a suggestion giving way to a remembered
/// correction, a retired label still carried offering Merge Into and Remove only, the row's mark following the
/// category source, and Keep on a kept label's pick taking the mark away.
enum AIReportChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig
    private typealias Spec = CategoryAssistantRig.Spec

    static let tests: [(String, () -> [String])] = [
        ("A shadow suggestion comes back after a relaunch from the label file, with no question and no write", suggestionSurvivesRelaunch),
        ("A shadow suggestion is not shown while a remembered correction is offered for the session", correctionComesFirst),
        ("A retired label its sessions still carry offers Merge Into and Remove only", retiredLabelOffersRetire),
        ("A session card's signature changes when its category source becomes or stops being the AI's", signatureFollowsTheSource),
        ("Keep on a kept label's AI pick takes the mark away", keepClearsAKeptLabelsMark),
    ]

    @MainActor private static func assigned(_ rig: Rig.Rig) {
        rig.f.store.installCategoryAssistant(rig.assistant)
        rig.mode.assigns = true
        rig.ask()
    }

    private static func suggestionSurvivesRelaunch() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("2") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.ask()
            guard case .pick(let id)? = rig.assistant.suggestions[rig.record.id] else {
                problems.append("shadow mode offered nothing: \(rig.assistant.suggestions)"); return
            }
            let asked = rig.calls.questions.count, file = rig.reloaded().book
            // A relaunch: a new assistant over what the label file holds, told of nothing yet.
            let fresh = CategoryAssistant(store: rig.f.store, labels: rig.reloaded(), assigns: { false })
            fresh.responder = { question in rig.calls.questions.append(question); return Rig.answer("2") }
            rig.f.store.installCategoryAssistant(fresh)
            rig.f.store.noteEndedRecordsForAssistant()
            _ = InstalledAppCatalog.turnRunLoop(until: { fresh.isIdle }, timeout: 5)
            expect(fresh.suggestions[rig.record.id] == .pick(id),
                   "the suggestion did not come back after a relaunch: \(fresh.suggestions)", &problems)
            expect(rig.f.store.aiReport(for: rig.session()).suggestion == .pick(WorkType(rawValue: id)),
                   "the report did not offer the suggestion: \(rig.f.store.aiReport(for: rig.session()))", &problems)
            expect(rig.calls.questions.count == asked, "the model was asked again (\(rig.calls.questions.count))", &problems)
            expect(rig.stored() == rig.record && rig.reloaded().book == file,
                   "bringing the suggestion back wrote the record or the label file", &problems)
        }
    }

    private static func correctionComesFirst() -> [String] {
        Rig.withRig([Spec(seed: 1), Spec(seed: 1)], reply: { _, _ in Rig.answer("2") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.ask(0)
            guard case .pick(let id)? = rig.assistant.suggestions[rig.records[0].id] else {
                problems.append("shadow mode offered nothing: \(rig.assistant.suggestions)"); return
            }
            expect(rig.f.store.aiReport(for: rig.session(0)).suggestion == .pick(WorkType(rawValue: id)),
                   "the report did not offer the suggestion before any correction", &problems)
            // The person files another session of this kind: a remembered correction now matches this one.
            _ = rig.f.store.setWorkType(.learning, for: rig.session(1))
            guard rig.f.store.correctionSuggestion(for: rig.session(0)) == .learning else {
                problems.append("no remembered correction was offered"); return
            }
            let report = rig.f.store.aiReport(for: rig.session(0))
            expect(report.suggestion == nil, "the AI's suggestion showed beside a remembered correction: \(report)", &problems)
        }
    }

    private static func retiredLabelOffersRetire() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            assigned(rig)
            guard let label = rig.assistant.labels.book.labels.first, rig.stored()?.workType.rawValue == label.id else {
                problems.append("no label was made and written"); return
            }
            let type = WorkType(rawValue: label.id)
            let live = rig.f.store.aiReport(for: rig.session())
            expect(live.filing == .label(type) && live.showsMark && live.mergeTargets == WorkType.startable,
                   "an unkept label was not offered with its actions: \(live)", &problems)
            // A Merge Into refused halfway: the label retired, its name removed, its session still carrying it.
            var book = rig.assistant.labels.book
            book.labels[0].archived = true
            book.removedNames.append(book.labels[0].name)
            guard rig.assistant.labels.save(book, at: rig.f.clock.value) == nil else { problems.append("the label was not retired"); return }
            let retired = rig.f.store.aiReport(for: rig.session())
            expect(retired.filing == .retiredLabel(type) && retired.mergeTargets == WorkType.startable,
                   "a retired label still carried did not offer Merge Into and Remove: \(retired)", &problems)
            expect(rig.f.store.removeAILabel(label.id) && rig.stored()?.workType == .unsorted,
                   "Remove on a retired label still carried was refused", &problems)
            expect(rig.f.store.aiReport(for: rig.session()).filing == nil, "a removed label still showed", &problems)
        }
    }

    private static func signatureFollowsTheSource() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("2") }) { rig, problems in
            assigned(rig)
            guard rig.stored()?.categorySource == .ai else { problems.append("no pick was written"); return }
            @MainActor func signature() -> SessionCardSignature {
                let session = rig.session()
                return SessionCardSignature(
                    session: session, apps: [], shape: nil, shapeCaption: nil, activity: nil,
                    canContinue: false, canStartNewSession: false, isOpen: false, clock: nil, liveStatus: nil,
                    power: nil, recordIDs: session.recordIDs, notes: [], editorsOpen: [], metadataError: nil,
                    isHistory: false, canRemove: true, removeBlockReason: nil, pauseTitle: "Pause", canControl: false,
                    minimumRecorded: 30, aiMark: rig.f.store.rowMarks(for: session).aiMark)
            }
            let marked = signature()
            expect(marked.aiMark, "an AI pick's row did not carry the mark", &problems)
            expect(rig.f.store.keepAIPick(rig.session()), "Keep on the pick was refused", &problems)
            let kept = signature()
            expect(kept != marked && !kept.aiMark, "the card's signature did not change when the pick was kept", &problems)
        }
    }

    private static func keepClearsAKeptLabelsMark() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            assigned(rig)
            guard let label = rig.assistant.labels.book.labels.first else { problems.append("no label was made"); return }
            expect(rig.f.store.keepAILabel(label.id), "Keep on the label was refused", &problems)
            let type = WorkType(rawValue: label.id)
            let kept = rig.f.store.aiReport(for: rig.session())
            expect(kept.filing == .pick(type) && kept.showsMark,
                   "a kept label's session did not stay an AI pick with its mark: \(kept)", &problems)
            expect(rig.f.store.keepAIPick(rig.session()), "Keep on a kept label's pick was refused", &problems)
            expect(rig.stored()?.workType == type && rig.stored()?.categorySource == .user,
                   "Keep did not make the pick the person's: \(String(describing: rig.stored()))", &problems)
            let after = rig.f.store.aiReport(for: rig.session())
            expect(after.filing == nil && !after.showsMark && !rig.f.store.rowMarks(for: rig.session()).aiMark,
                   "the mark stayed after Keep: \(after)", &problems)
        }
    }
}
