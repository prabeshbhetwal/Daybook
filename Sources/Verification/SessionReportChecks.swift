import Foundation
import SwiftUI
import AppKit

/// Checks for the full session report and in-app dictation: the report says
/// everything the card summarises, the window model opens and closes it, and
/// spoken words land after what was already written.
enum SessionReportChecks {
    static let tests: [(String, () -> [String])] = [
        ("The session report lists every app, stretch, visit and note", reportContents),
        ("The window opens and closes the report through its model", reportRoute),
        ("Dictation merges spoken words after the written note", dictationMerge),
        ("Removing a session takes its stretches out and Undo puts them back", removal)
    ]

    /// The store mirrors engine state through the main queue; a fixture
    /// built a moment ago has nothing published until the loop turns.
    private static func daySessions(of store: SessionStore) -> [DaySession] {
        let deadline = Date().addingTimeInterval(2)
        while store.daySessions.isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
        return store.daySessions.compactMap { entry -> DaySession? in
            if case .session(let session) = entry { return session }
            return nil
        }
    }

    private static func reportContents() -> [String] {
        var failures: [String] = []
        let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
        // The story's day is published once its canvas appears and asks for it.
        let navigation = MainActor.assumeIsolated {
            MainWindowModel(selectedTab: .story, storyScope: .day, store: store)
        }
        store.setDashboardVisible(true)
        store.refresh()
        let sessions = daySessions(of: store)
        _ = navigation
        guard let session = sessions.max(by: { $0.recordIDs.count < $1.recordIDs.count }) else {
            return ["The fixture day has no session to report on"]
        }
        if let recordID = session.recordIDs.first {
            store.beginNoteEditing(for: recordID)
            store.setNoteDraft("Kept the parser small.", for: recordID)
            _ = store.saveNote(for: recordID)
        }
        let report = SessionReport.make(for: session, store: store)
        let detail = store.storySessionDetail(session)
        if report.apps.count != detail.apps.count || report.apps.map(\.bundleID) != detail.apps.map(\.bundleID) {
            failures.append("The report did not list the same apps as the card's evidence, in the same order")
        }
        if report.stretches.count != session.recordIDs.count {
            failures.append("The report listed \(report.stretches.count) stretches for \(session.recordIDs.count) records")
        }
        if zip(report.stretches, report.stretches.dropFirst()).contains(where: { $0.start > $1.start }) {
            failures.append("Stretches are not in time order")
        }
        if report.intervals.count != detail.activity.intervals.count {
            failures.append("The report dropped recorded intervals")
        }
        if report.visitCount != detail.activity.intervals.filter({ !$0.isGap }).count {
            failures.append("The visit count does not match the recorded intervals")
        }
        if !session.recordIDs.isEmpty, report.notes != ["Kept the parser small."] {
            failures.append("The saved note did not reach the report: \(report.notes)")
        }
        if report.title.isEmpty {
            failures.append("The report has no title")
        }
        // Colours: the day's mapping wins, the rest are told apart, grey only past six.
        let ranks = (0..<9).map { AppRank(bundleID: "app.\($0)", appName: "App \($0)", total: Double(100 - $0), share: 0.1, longest: 10) }
        let colours = SessionReport.colourIndices(apps: ranks, dayIndices: ["app.3": 2, "app.8": 6])
        if colours["app.3"] != 2 {
            failures.append("An app with a day colour lost it")
        }
        let first = ranks.prefix(6).compactMap { colours[$0.bundleID] }
        if Set(first).count != 6 || first.contains(6) {
            failures.append("The first six apps did not get six distinct named colours: \(first)")
        }
        if colours["app.7"] != 6 || colours["app.8"] != 6 {
            failures.append("Apps past the palette did not fall to grey")
        }
        return failures
    }

    private static func reportRoute() -> [String] {
        var failures: [String] = []
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory)
            store.refresh()
            let navigation = MainWindowModel(selectedTab: .story, storyScope: .day, store: store)
            store.setDashboardVisible(true)
            guard let session = daySessions(of: store).first else {
                failures.append("The fixture day has no session")
                return
            }
            if navigation.reportSession != nil {
                failures.append("A report was open before anyone asked")
            }
            navigation.openReport(for: session)
            if navigation.reportSession?.id != session.id {
                failures.append("Opening the report did not record which session it is for")
            }
            navigation.closeReport()
            if navigation.reportSession != nil {
                failures.append("Closing the report left it open")
            }
            // The overlay hosts and renders without a window of its own.
            navigation.openReport(for: session)
            let host = NSHostingView(rootView: SessionReportCard(store: store, session: session, onClose: {}))
            host.frame = NSRect(x: 0, y: 0, width: 720, height: 700)
            host.layoutSubtreeIfNeeded()
            if host.fittingSize.height <= 0 {
                failures.append("The report card did not lay out")
            }
        }
        return failures
    }

    private static func removal() -> [String] {
        var failures: [String] = []
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            let navigation = MainWindowModel(selectedTab: .story, storyScope: .day, store: store)
            store.setDashboardVisible(true)
            store.refresh()
            guard let session = daySessions(of: store).max(by: { $0.recordIDs.count < $1.recordIDs.count }) else {
                failures.append("The fixture day has no session"); return
            }
            let ids = Set(session.recordIDs)
            let before = store.engine.archive.records
            let removedRecords = before.filter { $0.threadID == session.threadID }
            guard !removedRecords.isEmpty else { failures.append("The session has no archived stretches"); return }
            if !store.canRemoveSession(session) {
                failures.append("An idle, archived session was not removable")
            }
            guard store.removeSession(session) else {
                failures.append("Removal failed: \(store.correctionError ?? "no reason")"); return
            }
            let after = store.engine.archive.records
            if after.contains(where: { $0.threadID == session.threadID }) {
                failures.append("Removed stretches are still in the archive")
            }
            if after.count != before.count - removedRecords.count {
                failures.append("Removal touched records outside the session")
            }
            if store.corrections.last?.correction != .removed
                || store.corrections.last?.removedRecords?.map(\.id) != removedRecords.map(\.id) {
                failures.append("The journal did not keep the removed records for Undo")
            }
            let notices = store.storyTimelineItems(on: session.start)
            if !notices.contains(where: { item in
                if case .correction(_, let title, _) = item { return title == "Session removed" }
                return false
            }) {
                failures.append("The story shows no 'Session removed' notice where the session was")
            }
            guard store.undoLastCorrection() else {
                failures.append("Undo failed: \(store.correctionError ?? "no reason")"); return
            }
            let restored = store.engine.archive.records.filter { ids.contains($0.id) }
                .sorted { $0.start < $1.start }
            if restored != removedRecords.sorted(by: { $0.start < $1.start }) {
                failures.append("Undo did not restore the same records")
            }
            _ = navigation
        }
        return failures
    }

    private static func dictationMerge() -> [String] {
        var failures: [String] = []
        let cases: [(String, String, String)] = [
            ("", "hello there", "hello there"),
            ("Already written.", "and more", "Already written. and more"),
            ("Already written. ", "  and more ", "Already written. and more"),
            ("Kept.", "", "Kept."),
            ("", "", "")
        ]
        for (base, spoken, expected) in cases where SpeechDictation.merge(base: base, transcript: spoken) != expected {
            failures.append("merge(\"\(base)\", \"\(spoken)\") gave \"\(SpeechDictation.merge(base: base, transcript: spoken))\"")
        }
        MainActor.assumeIsolated {
            let dictation = SpeechDictation()
            if dictation.isListening || dictation.isBusy || dictation.status != .idle {
                failures.append("Dictation did not start idle")
            }
            dictation.stop()
            if dictation.status != .idle {
                failures.append("Stopping while idle changed the status")
            }
        }
        return failures
    }
}
