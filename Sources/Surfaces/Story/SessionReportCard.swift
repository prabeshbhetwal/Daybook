import Combine
import SwiftUI

/// A report and its activity list, kept for a session that has finished:
/// nothing in it changes while the card is open, though the store publishes
/// every second. A running session's is rebuilt as it grows.
final class SessionReportCache: ObservableObject {
    private var built: (report: SessionReport, list: ReportActivityList, categories: String)?

    /// Kept until the session changes or an app's category does: a category edited from the
    /// report itself redraws its phases and lines at once.
    func build(for session: DaySession, store: SessionStore) -> (report: SessionReport, list: ReportActivityList) {
        let categories = SessionActivityShape.digest(store.purposeOverrides)
        if !session.isRunning, let built, built.report.session == session, built.categories == categories {
            return (built.report, built.list)
        }
        let report = SessionReport.make(for: session, store: store)
        let list = ReportActivityList.make(
            listed: report.listedIntervals, power: report.power(for:),
            gapTitle: { report.gapReasons[$0.id]?.title ?? "Not recorded" })
        built = (report, list, categories)
        return (report, list)
    }

    /// What `aiReport` reads of the session and the settings: not its length, which grows while it runs.
    private struct AIKey: Equatable {
        let recordIDs: [UUID], isRunning: Bool, workType: WorkType, aiOn: Bool
    }
    private var ai: (key: AIKey, revision: SessionStore.EvidenceRevision, report: AISessionReport)?
    private var aiWatch: AnyCancellable?

    /// The AI's part, kept until the session's stretches, the on-device AI switch, the records or the categories
    /// change (`sameArchive`), or the assistant's suggestions or the label file do (`aiReportChanges`). A label
    /// lapsing with time alone is not seen here; Use checks the offer again (`useAISuggestion`).
    @MainActor func ai(for session: DaySession, store: SessionStore) -> AISessionReport {
        if aiWatch == nil {
            aiWatch = store.aiReportChanges.sink { [weak self] in
                self?.ai = nil
                self?.objectWillChange.send()
            }
        }
        let key = AIKey(recordIDs: session.recordIDs, isRunning: session.isRunning, workType: session.workType,
                        aiOn: store.appleIntelligenceEnabled)
        let revision = store.evidenceRevision
        if let ai, ai.key == key, ai.revision.sameArchive(as: revision) { return ai.report }
        let report = store.aiReport(for: session)
        ai = (key, revision, report)
        return report
    }
}

struct SessionReportCard: View {
    @ObservedObject var store: SessionStore
    let session: DaySession
    let onClose: () -> Void
    @StateObject private var cache = SessionReportCache()
    /// A suggested category the person took here. The session the card was opened with is stale
    /// from then on, so the report is read for it with that category until Undo.
    @State private var filed: CorrectionFiling?
    /// The on-device AI's part, handed in by a snapshot; read from the store otherwise.
    var ai: AISessionReport? = nil

    var body: some View {
        let filing = filed?.standing(in: store.corrections)
        let shown = filing.map { session.recategorised(as: $0.category) } ?? session
        let (report, list) = cache.build(for: shown, store: store)
        let ai = self.ai ?? cache.ai(for: shown, store: store)
        StorySheet(title: "Session report", onClose: onClose) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                    if filing != nil || report.suggestion != nil {
                        CorrectionSuggestionRow(store: store, session: session, offer: report.suggestion,
                                                filed: Binding(get: { filing }, set: { filed = $0 }))
                    }
                    if let aiFiling = ai.filing {
                        AILabelActions(store: store, session: shown, filing: aiFiling, mergeTargets: ai.mergeTargets, onChanged: onClose)
                    }
                    if filing == nil, let suggestion = ai.suggestion {
                        AISuggestionRow(store: store, session: shown, suggestion: suggestion, onChanged: onClose)
                    }
                    if report.split != nil || report.mergeBack != nil {
                        SplitOfferRow(store: store, offer: report.split, mergeBack: report.mergeBack, onChanged: onClose)
                    }
                    SessionReportView(report: report, activityList: list, purposeStore: store)
                }
                .padding(Tokens.Space.xl)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: StoryStyle.tileRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: StoryStyle.tileRadius, style: .continuous)
            .strokeBorder(StoryStyle.line))
        .shadow(color: .black.opacity(0.18), radius: 24.zoomed, y: 8.zoomed)
        .accessibilityAddTraits(.isModal)
    }
}
