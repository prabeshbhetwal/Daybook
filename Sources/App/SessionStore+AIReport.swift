import Combine
import Foundation

/// What a session report shows of the on-device AI's part in one session (Phase C, rulings C8, C13, C17, C31 and
/// C32), worked out here so the report only draws it and calls the actions in `SessionStore+AILabels.swift`.
struct AISessionReport: Equatable {
    /// What the AI filed the session under.
    enum Filing: Equatable {
        /// One of the person's categories, picked by the AI: Keep (`keepAIPick`) or Change (the category picker).
        /// A label the person kept stays an AI pick on its sessions until each is kept (C31).
        case pick(WorkType)
        /// A label the AI made and the person has not kept: Keep or Rename (`keepAILabel`), Merge Into
        /// (`mergeAILabel`) or Remove (`removeAILabel`).
        case label(WorkType)
        /// A label the person merged or removed that the session still carries, as a refused Merge Into or Remove
        /// leaves it: Merge Into and Remove only, done again. Keep refuses it.
        case retiredLabel(WorkType)
        /// A label the AI made that aged out unused (C15): never offered again, yet still kept, renamed, merged or
        /// removed from its sessions (C32).
        case lapsedLabel(WorkType)

        /// The label Keep and Rename can make the person's; nil for a pick or a label the person retired.
        var keepableLabel: WorkType? {
            switch self {
            case .label(let type), .lapsedLabel(let type): return type
            default: return nil
            }
        }
    }

    /// Shadow mode's offer, taken with Use (`useAISuggestion`).
    enum Suggestion: Equatable {
        case pick(WorkType)
        /// A label the AI made earlier for this kind of session; Use keeps it.
        case label(WorkType)
        /// A new category, Films: Use makes it one of the person's.
        case newCategory(name: String)

        /// What `answer` is shown as; nil for none.
        init?(_ answer: AIAnswer) {
            switch answer {
            case .pick(let id): self = .pick(WorkType(rawValue: id))
            case .label(let id): self = .label(WorkType(rawValue: id))
            case .proposed(_, let name): self = .newCategory(name: name)
            case .none: return nil
            }
        }
    }

    var filing: Filing?
    /// Where Merge Into can take a label's sessions: every category that can be started. Empty without a label.
    var mergeTargets: [WorkType] = []
    /// Nil while a remembered correction is offered for the session: the person's word comes first (C8).
    var suggestion: Suggestion?
    /// Whether the AI mark shows beside the category: some stretch carries a category the AI set (C17).
    var showsMark = false
}

extension SessionStore {
    /// The label file the assistant keeps, for the Settings row (`AICategorySource`). Nil without an assistant.
    var aiLabelStore: AILabelStore? { activityEvidence.aiLabels }

    /// Fires when what `aiReport` reads beside the archive changes: the assistant's suggestions or the label file.
    @MainActor var aiReportChanges: AnyPublisher<Void, Never> {
        let saved = NotificationCenter.default.publisher(for: AILabelStore.didSave).map { _ in }
        guard let assistant = activityEvidence.categoryAssistant else { return saved.eraseToAnyPublisher() }
        // Past the current value, which `@Published` sends on subscribing.
        return saved.merge(with: assistant.$suggestions.dropFirst().map { _ in }).eraseToAnyPublisher()
    }

    /// The stretch carrying the category `session` shows, when the AI set it: the one test of the AI mark, on the
    /// row and in the report (C17, C31). A stretch the AI filed under another category does not mark this one.
    func aiFiledStretch(of session: DaySession, in stretches: [SessionRecord]) -> SessionRecord? {
        stretches.first { $0.categorySource == .ai && $0.workType == session.workType }
    }

    /// The one answer shadow mode offers for `session`, shown by the report and taken by Use (C8): the first, in the
    /// session's own order, of a stretch the app itself filed. One the person or the AI filed offers nothing. Each
    /// answer is checked again as a relaunch would (`stillUsable`): a category or label retired or aged out since
    /// offers nothing, and a new name a category now holds is a pick of it. Nothing while on-device AI is off.
    @MainActor func offeredAIAnswer(for session: DaySession, in stretches: [SessionRecord]) -> AIAnswer? {
        guard appleIntelligenceEnabled, let assistant = activityEvidence.categoryAssistant else { return nil }
        let builtIn = Set(stretches.filter { $0.effectiveCategorySource == .builtIn }.map(\.id))
        return session.recordIDs.lazy.filter(builtIn.contains).compactMap { self.offeredAIAnswer(for: $0, assistant) }
            .first { $0.id != nil }
    }

    /// What one stretch's own suggestion comes to now, or nil.
    @MainActor func offeredAIAnswer(for id: UUID, _ assistant: CategoryAssistant) -> AIAnswer? {
        guard assistant.offersWanted, var answer = assistant.suggestions[id], let target = categoryAskTarget(for: id)
        else { return nil }
        // A label kept since (Keep, or a refused Use whose label file could not be put back) is the person's now (C25).
        if case .label(let kept) = answer, WorkType.startable.contains(WorkType(rawValue: kept)) { answer = .pick(kept) }
        return assistant.stillUsable(answer, in: assistant.labels.book, at: now(), target: target)
    }

    /// Everything the report shows of the AI for `session`, in one value. A label the AI made is read from the
    /// label file, archived or not, since a refused Merge Into or Remove, or age (C15), can leave sessions carrying one.
    @MainActor func aiReport(for session: DaySession) -> AISessionReport {
        let stretches = records(of: session), picked = aiFiledStretch(of: session, in: stretches)
        var report = AISessionReport(showsMark: picked != nil)
        // One the person's categories hold is theirs, a Keep whose label file was not written (C10).
        let carried = Set(stretches.map(\.workType.rawValue)).subtracting(engine.store.workTypeDefinitions.map(\.id))
        if let book = activityEvidence.aiLabels?.book, let label = book.labels.first(where: { carried.contains($0.id) }) {
            let type = WorkType(rawValue: label.id)
            report.filing = label.archived && book.removedNames.contains(label.name) ? .retiredLabel(type)
                : book.liveLabels(now: now()).contains(where: { $0.id == label.id }) ? .label(type) : .lapsedLabel(type)
            report.mergeTargets = WorkType.startable
        } else if let picked {
            report.filing = .pick(picked.workType)
        }
        // The offer first: the remembered correction is a scan of the archive per stretch.
        guard !session.isRunning, let answer = offeredAIAnswer(for: session, in: stretches),
              correctionSuggestion(for: session) == nil else { return report }
        report.suggestion = AISessionReport.Suggestion(answer)
        return report
    }
}
