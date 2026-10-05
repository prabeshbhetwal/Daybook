import Foundation
import SwiftUI

/// History says what its rows leave out or cannot vouch for. The store kept
/// these notices for a long time while no view drew them; these checks
/// render the column and look for the notice's evidence.
enum HistoryNoticeChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("History draws its integrity notices, even when they leave it no rows, and none when there are none",
         noticesRender),
    ]

    private static func noticesRender() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            @MainActor func drawn(_ store: SessionStore) -> Set<StoryRenderEvidence> {
                let navigation = MainWindowModel(store: store)
                navigation.open(tab: .review)
                let settings = SettingsModel(store: store.engine.store, isTrackingEnabled: true,
                                             onChange: {}, onTrackingChanged: { _ in })
                return StoryWorkspaceChecks.renderFrame(
                    HistoryWorkspace(store: store, navigation: navigation, settings: settings, scrolls: false),
                    width: 1_160, height: 1_000).evidence
            }
            func names(_ evidence: Set<StoryRenderEvidence>) -> [String] { evidence.map(\.rawValue).sorted() }

            // Without an app-usage file the archive is accurate only from now,
            // so the fixture's week of Xcode is preserved legacy use.
            let legacy = FixtureFactory.store(for: .idleWithHistory)
            legacy.refreshReview()
            let legacyNotices = legacy.historyIntegrityNotices
            expect(legacyNotices.contains { $0.localizedCaseInsensitiveContains("legacy") },
                   "app use from before the accuracy date should raise a legacy notice, got \(legacyNotices)",
                   &problems)
            let legacyDrawn = drawn(legacy)
            expect(legacyDrawn.isSuperset(of: [.historyIntegrityNotice, .historyTree]),
                   "History with a legacy notice should draw it with the tree, drew \(names(legacyDrawn))",
                   &problems)
            FixtureFactory.cleanUp()

            // The only record spans more days than History places on rows,
            // so the column is otherwise empty: the notice is its only account.
            let omitted = FixtureFactory.store(for: .firstRun, accurateUsage: true)
            let end = omitted.now().addingTimeInterval(-3_600)
            if let start = Calendar.current.date(byAdding: .day,
                                                 value: -(HistoryStats.maximumCalendarDaysPerRecord + 10),
                                                 to: end) {
                let failure = omitted.engine.archive.append(SessionRecord(
                    name: "Clock jump", workType: .deepWork, start: start, end: end,
                    workSeconds: end.timeIntervalSince(start)))
                expect(failure == nil, "the over-long record should save, got \(failure ?? "")", &problems)
            } else {
                problems.append("could not date the over-long record")
            }
            omitted.refreshReview()
            expect(omitted.historyDays.isEmpty && !omitted.historyIntegrityNotices.isEmpty,
                   "an over-long only record should leave no rows and one notice, got \(omitted.historyDays.count) "
                       + "rows and \(omitted.historyIntegrityNotices)", &problems)
            let omittedDrawn = drawn(omitted)
            expect(omittedDrawn.isSuperset(of: [.historyIntegrityNotice, .historyEmpty]),
                   "History emptied by an omitted record should still draw the notice, drew \(names(omittedDrawn))",
                   &problems)
            FixtureFactory.cleanUp()

            let clean = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            clean.refreshReview()
            expect(clean.historyIntegrityNotices.isEmpty,
                   "accurate, day-sized records should raise no notice, got \(clean.historyIntegrityNotices)",
                   &problems)
            let cleanDrawn = drawn(clean)
            expect(cleanDrawn.contains(.historyTree) && !cleanDrawn.contains(.historyIntegrityNotice),
                   "History with nothing to qualify should draw no notice, drew \(names(cleanDrawn))", &problems)
            FixtureFactory.cleanUp()
            return problems
        }
    }
}
