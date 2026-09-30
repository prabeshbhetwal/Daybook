import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// The period's winning focus stretch is its clipped contribution. A large
    /// break and a larger out-of-period tail are never eligible to win.
    static func testReviewLongestFocusClipsBoundsAndExcludesBreaks() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(base)
            let calendar = Calendar.current
            guard let bounds = calendar.dateInterval(of: .weekOfYear, for: clock.value) else {
                return ["could not build Review week bounds"]
            }
            let archive = makeArchive(clock)
            archive.append(SessionRecord(
                name: "Starts outside", workType: .deepWork,
                start: bounds.start.addingTimeInterval(-30 * 60),
                end: bounds.start.addingTimeInterval(30 * 60),
                workSeconds: 60 * 60))
            archive.append(SessionRecord(
                name: "Inside", workType: .learning,
                start: bounds.start.addingTimeInterval(2 * 3_600),
                end: bounds.start.addingTimeInterval(2 * 3_600 + 40 * 60),
                workSeconds: 40 * 60))
            archive.append(SessionRecord(
                name: "Long break", workType: .breakTime,
                start: bounds.start.addingTimeInterval(3 * 3_600),
                end: bounds.start.addingTimeInterval(5 * 3_600),
                workSeconds: 2 * 3_600))
            archive.append(SessionRecord(
                name: "Ends outside", workType: .admin,
                start: bounds.end.addingTimeInterval(-20 * 60),
                end: bounds.end.addingTimeInterval(40 * 60),
                workSeconds: 60 * 60))

            let usage = makeUsageArchive(clock, sessions: [], accurateFrom: bounds.start)
            let persistence = PersistenceStore(
                defaults: UserDefaults(suiteName: suiteName) ?? .standard)
            persistence.removeAll()
            let engine = SessionEngine(store: persistence, archive: archive,
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.refreshReview(period: .week)

            expectClose(store.reviewLongestFocusSeconds, 40 * 60,
                        "period-clipped longest focus", &problems)
            expect(store.reviewLongestFocusName == "Inside",
                   "the in-period focus stretch wins", &problems)
            expect(store.reviewWorkTypeShares.allSatisfy { $0.workType != .breakTime },
                   "breaks remain excluded from Review work type", &problems)
            return problems
        }
    }

    /// A named rest is evidence only for its clipped record interval. It cannot
    /// inherit the duration of the larger elided inactivity gap around it.
    static func testTimelineRestEvidenceStaysCanonical() -> [String] {
        var problems: [String] = []
        let day = Calendar.current.startOfDay(for: base)
        let gap = TimelineGap(start: day.addingTimeInterval(9 * 3_600),
                              end: day.addingTimeInterval(12 * 3_600),
                              xStart: 0.4, xEnd: 0.44)
        let tea = SessionRecord(name: "Tea break", workType: .breakTime,
                                start: day.addingTimeInterval(10 * 3_600),
                                end: day.addingTimeInterval(10.5 * 3_600),
                                workSeconds: 30 * 60)
        // Crosses the gap's right boundary: only the fifteen minutes inside the
        // gap are eligible for its presentation.
        let handover = SessionRecord(name: "Handover", workType: .breakTime,
                                     start: day.addingTimeInterval(11.75 * 3_600),
                                     end: day.addingTimeInterval(12.25 * 3_600),
                                     workSeconds: 30 * 60)

        let evidence = TimelineGapEvidence(gap: gap, breaks: [tea, handover])
        expect(evidence.rests.count == 2,
               "two overlapping canonical rests remain two rest slices", &problems)
        if evidence.rests.count == 2 {
            expectClose(evidence.rests[0].start.timeIntervalSince(day), 10 * 3_600,
                        "the inside rest keeps its start", &problems)
            expectClose(evidence.rests[0].end.timeIntervalSince(day), 10.5 * 3_600,
                        "the inside rest keeps its end", &problems)
            expectClose(evidence.rests[0].duration, 30 * 60,
                        "the inside rest keeps its own duration", &problems)
            expectClose(evidence.rests[1].start.timeIntervalSince(day), 11.75 * 3_600,
                        "the boundary-crossing rest keeps its inside start", &problems)
            expectClose(evidence.rests[1].end.timeIntervalSince(day), 12 * 3_600,
                        "the boundary-crossing rest clips at the gap end", &problems)
            expectClose(evidence.rests[1].duration, 15 * 60,
                        "the boundary-crossing rest labels only its clipped duration", &problems)
        }
        expect(evidence.unknown.count == 2,
               "unknown inactivity remains on both sides of the named evidence", &problems)
        expectClose(evidence.unknown.reduce(0) { $0 + $1.duration }, 135 * 60,
                    "surrounding inactivity stays distinct from named rests", &problems)
        return problems
    }

    /// Focus is an operational surface, so every engine state needs one clear
    /// presentation contract. Awaiting a decision is deliberately exceptional:
    /// the honest answers replace ordinary session controls. Continuations are
    /// equally bounded — a compact action panel must not grow into history.
    static func testFocusSurfaceStateAndContinuationLimit() -> [String] {
        var problems: [String] = []
        let cases: [(SessionState, FocusSurfaceMode, String, FocusPrimaryAction?)] = [
            (.idle, .idle, "Ready to focus", .start),
            (.running, .running, "Focus in progress", .pause),
            (.paused(reason: .manual), .paused, "Ready to continue?", .resume),
            (.paused(reason: .watching), .watching, "Watching quietly", .resume),
            (.awaitingUserDecision(away: 20 * 60, lastApp: "Xcode"),
             .awaitingDecision, "What happened while you were away?", nil)
        ]

        for (state, expectedMode, expectedPrompt, expectedAction) in cases {
            let mode = FocusSurfaceMode(state: state)
            expect(mode == expectedMode,
                   "\(state) maps to \(expectedMode), got \(mode)", &problems)
            expect(mode.primaryPrompt == expectedPrompt,
                   "\(expectedMode) keeps its primary prompt", &problems)
            expect(mode.primaryAction == expectedAction,
                   "\(expectedMode) keeps one appropriate primary action", &problems)
        }
        expect(!FocusSurfaceMode.awaitingDecision.showsOrdinaryControls,
               "awaiting a decision replaces ordinary session controls", &problems)
        expect(FocusSurfaceMode.running.showsOrdinaryControls,
               "running retains its ordinary controls", &problems)

        let now = base
        let threads = (0..<4).map { index in
            ThreadSummary(threadID: UUID(), name: "Thread \(index)", workType: .deepWork,
                          totalWorked: Double(index + 1) * 600, segments: index + 1,
                          firstStart: now.addingTimeInterval(Double(-index) * 900),
                          lastEnd: now.addingTimeInterval(Double(-index) * 300),
                          isRunning: false)
        }
        let quickStarts = (0..<4).map {
            QuickStart(id: "quick-\($0)", name: "Quick \($0)", workType: .admin)
        }
        let threadRows = FocusContinuationSource.rows(
            threads: threads, quickStarts: quickStarts, limit: 9)
        expect(threadRows == threads.prefix(3).map { .thread($0) },
               "threads are preferred and capped at three", &problems)

        let quickRows = FocusContinuationSource.rows(
            threads: [], quickStarts: quickStarts, limit: 9)
        expect(quickRows == quickStarts.prefix(3).map { .quickStart($0) },
               "quick starts fill the empty thread source and stop at three", &problems)
        expect(FocusContinuationSource.rows(
            threads: threads, quickStarts: quickStarts, limit: 0).isEmpty,
               "a zero continuation limit yields no rows", &problems)
        return problems
    }

    /// The composition guard owns everything around the hero as well as the
    /// hero itself. An unresolved away question must have exactly one exit: an
    /// answer from its four-choice grid. Automatic-session correction remains
    /// available in every other live state, including quiet and declared pauses.
    static func testFocusSurfaceCompositionGuards() -> [String] {
        var problems: [String] = []

        let awaiting = FocusSurfaceComposition(
            state: .awaitingUserDecision(away: 20 * 60, lastApp: "Xcode"),
            hasPendingDecision: false,
            isAutomatic: true)
        expect(awaiting.mode == .awaitingDecision,
               "engine decision state composes as awaiting decision", &problems)
        expect(!awaiting.showsContinuationSection,
               "awaiting decision suppresses every continuation action", &problems)
        expect(!awaiting.showsAutomaticSessionControls,
               "awaiting decision suppresses automatic correction controls", &problems)

        let previewPending = FocusSurfaceComposition(
            state: .running,
            hasPendingDecision: true,
            isAutomatic: true)
        expect(previewPending.mode == .awaitingDecision
                   && !previewPending.showsContinuationSection
                   && !previewPending.showsAutomaticSessionControls,
               "a preview/live pending flag applies the same whole-surface guard", &problems)

        let automaticStates: [SessionState] = [
            .running,
            .paused(reason: .manual),
            .paused(reason: .watching),
            .paused(reason: .away)
        ]
        for state in automaticStates {
            let composition = FocusSurfaceComposition(
                state: state,
                hasPendingDecision: false,
                isAutomatic: true)
            expect(composition.showsContinuationSection,
                   "\(state) keeps safe continuation composition", &problems)
            expect(composition.showsAutomaticSessionControls,
                   "\(state) keeps automatic correction and Undo available", &problems)
        }

        let manual = FocusSurfaceComposition(
            state: .paused(reason: .manual),
            hasPendingDecision: false,
            isAutomatic: false)
        expect(!manual.showsAutomaticSessionControls,
               "manual sessions do not show automatic correction controls", &problems)
        let idle = FocusSurfaceComposition(
            state: .idle,
            hasPendingDecision: false,
            isAutomatic: true)
        expect(!idle.showsAutomaticSessionControls,
               "idle never exposes automatic-session controls", &problems)
        return problems
    }
}
