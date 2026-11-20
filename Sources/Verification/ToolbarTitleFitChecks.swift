import Foundation

/// The window's one-line toolbar keeps to the activity and its category; the
/// day's total for the activity, which a narrow window cut off there, is on
/// the story's running card, where it wraps instead.
enum ToolbarTitleFitChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The day's total for the running activity is on its story card, not cut off in the toolbar",
         totalMovesToRunningCard),
    ]

    private static func totalMovesToRunningCard() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let store = FixtureFactory.store(for: .running, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            // A second stretch of the same activity today: the summary exists.
            store.threadSegments = 2
            store.threadStartedAt = store.now().addingTimeInterval(-2 * 3600)
            guard let summary = store.threadSummaryLine else {
                return ["a second stretch should give the activity a day's total, got none"]
            }

            let subtitle = FocusHero.liveSubtitle(mode: .running, store: store)
            expect(!subtitle.contains(summary),
                   "the toolbar's one-line subtitle should not carry the day's total, got '\(subtitle)'",
                   &problems)
            expect(subtitle == store.workType.displayName,
                   "the running subtitle should be the category alone, got '\(subtitle)'", &problems)

            let projection = store.storyDayProjection(on: store.now())
            guard let running = projection.sessions.compactMap({ entry -> DaySession? in
                if case .session(let session) = entry, session.isRunning { return session }
                return nil
            }).first else {
                problems.append("the story should hold the running session's card")
                return problems
            }
            let card = DayStorySessionPresentation.make(
                session: running, isCurrentStoryDay: projection.isCurrentDay, store: store)
            expect(card.threadSummary == summary,
                   "the running card should carry '\(summary)', got \(card.threadSummary ?? "nil")",
                   &problems)
            return problems
        }
    }
}
