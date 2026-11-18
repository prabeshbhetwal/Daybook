import SwiftUI

/// A report and its activity list, kept for a session that has finished:
/// nothing in it changes while the card is open, though the store publishes
/// every second. A running session's is rebuilt as it grows.
final class SessionReportCache: ObservableObject {
    private var built: (report: SessionReport, list: ReportActivityList)?

    func build(for session: DaySession, store: SessionStore) -> (report: SessionReport, list: ReportActivityList) {
        if !session.isRunning, let built, built.report.session == session { return built }
        let report = SessionReport.make(for: session, store: store)
        let list = ReportActivityList.make(
            listed: report.listedIntervals, power: report.power(for:),
            gapTitle: { report.gapReasons[$0.id]?.title ?? "Not recorded" })
        built = (report, list)
        return (report, list)
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

    var body: some View {
        let filing = filed?.standing(in: store.corrections)
        let shown = filing.map { session.recategorised(as: $0.category) } ?? session
        let (report, list) = cache.build(for: shown, store: store)
        StorySheet(title: "Session report", onClose: onClose) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                    if filing != nil || report.suggestion != nil {
                        CorrectionSuggestionRow(store: store, session: session, offer: report.suggestion,
                                                filed: Binding(get: { filing }, set: { filed = $0 }))
                    }
                    if report.split != nil || report.mergeBack != nil {
                        SplitOfferRow(store: store, offer: report.split, mergeBack: report.mergeBack, onChanged: onClose)
                    }
                    SessionReportView(report: report, activityList: list)
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
