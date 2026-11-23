import Foundation

/// Activity-aware sessions: the phase strip on a session, its words for VoiceOver and its tooltips,
/// when it shows, and how each phase is drawn. Pure: no window, store or clock.
enum SessionPhaseStripChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Each phase reads as its activity and length", phaseLines),
        ("An older session says its phases come from app use only", appsOnlyNote),
        ("A session with no depth claim shows no depth word", depthWords),
        ("VoiceOver hears every phase in order", summaryInOrder),
        ("The phase strip shows only beside an app strip, from two minutes, with phases", showsFromTwoMinutes),
        ("Counted focus is solid, other counted time quiet, and uncounted time outlined", fills),
    ]

    /// A phase from minute `from` to minute `to` of `SelfTest.base`.
    static func phase(_ activity: PhaseActivity, _ from: Double, _ to: Double, counted: Bool = true) -> SessionPhase {
        SessionPhase(start: SelfTest.base.addingTimeInterval(from * 60), end: SelfTest.base.addingTimeInterval(to * 60),
                     activity: activity, counted: counted, credited: [:])
    }

    static func shape(_ phases: [SessionPhase], depth: SessionDepth? = nil,
                      fidelity: ShapeFidelity = .beats) -> SessionActivityShape {
        let end = phases.last?.end ?? SelfTest.base
        return SessionActivityShape(algorithmVersion: ActivityConstants.algorithmVersion, fidelity: fidelity,
                                    bounds: DateInterval(start: SelfTest.base, end: end),
                                    countedSeconds: end.timeIntervalSince(SelfTest.base), signals: [], phases: phases,
                                    depth: depth, label: .activity(.coding), credited: [:],
                                    fingerprint: nil, splitCandidates: [])
    }

    /// Case d: code, browse, code.
    static var codeBrowseCode: [SessionPhase] {
        [phase(.purpose(.coding), 0, 40), phase(.purpose(.research), 40, 50), phase(.purpose(.coding), 50, 80)]
    }

    private static func phaseLines() -> [String] {
        var problems: [String] = []
        let cases: [(SessionPhase, String)] = [
            (phase(.purpose(.coding), 0, 40), "Coding 40 minutes"),
            (phase(.away, 30, 90, counted: false), "Away 1 hour"),
            (phase(.browsing, 0, 10), "Browsing 10 minutes"),
            (phase(.purpose(.writingAI), 0, 80), "Writing & AI 1 hour 20 minutes"),
            // A film inside a session: its time is the session's, but not counted.
            (phase(.purpose(.media), 20, 80, counted: false), "Entertainment 1 hour, not counted"),
        ]
        for (phase, want) in cases {
            let got = SessionPhaseText.phaseLine(phase)
            expect(got == want, "\(phase.activity) reads \"\(want)\", got \"\(got)\"", &problems)
        }
        return problems
    }

    private static func appsOnlyNote() -> [String] {
        var problems: [String] = []
        let older = shape([phase(.purpose(.coding), 0, 30)], fidelity: .appsOnly)
        let note = SessionPhaseText.fidelityNote(older)
        expect(note == "From app use only", "an apps-only shape says so, got \(String(describing: note))", &problems)
        let newer = shape([phase(.purpose(.coding), 0, 30)], depth: .deep)
        expect(SessionPhaseText.fidelityNote(newer) == nil, "a shape from beats has no note", &problems)
        let heard = SessionPhaseText.summary(older)
        expect(heard == "Coding 30 minutes. From app use only.",
               "VoiceOver hears where the phases came from, got \"\(heard)\"", &problems)
        return problems
    }

    private static func depthWords() -> [String] {
        var problems: [String] = []
        let words: [(SessionDepth?, String?)] = [(.deep, "Deep"), (.light, "Light"), (.passive, "Passive"), (nil, nil)]
        for (depth, want) in words {
            let got = SessionPhaseText.depthWord(depth)
            expect(got == want, "\(String(describing: depth)) reads \(String(describing: want)), got \(String(describing: got))",
                   &problems)
        }
        let heard = SessionPhaseText.summary(shape(codeBrowseCode))
        expect(!heard.contains("Deep") && !heard.contains("Light") && !heard.contains("Passive"),
               "with no depth claim VoiceOver hears none, got \"\(heard)\"", &problems)
        return problems
    }

    private static func summaryInOrder() -> [String] {
        var problems: [String] = []
        let heard = SessionPhaseText.summary(shape(codeBrowseCode, depth: .deep))
        expect(heard == "Coding 40 minutes, Browsing & research 10 minutes, Coding 30 minutes. Deep.",
               "the three phases in order, then the depth, got \"\(heard)\"", &problems)
        let lunch = [phase(.purpose(.coding), 0, 30), phase(.away, 30, 90, counted: false), phase(.purpose(.coding), 90, 110)]
        let away = SessionPhaseText.summary(shape(lunch))
        expect(away == "Coding 30 minutes, Away 1 hour, Coding 20 minutes.",
               "lunch is heard where it fell, got \"\(away)\"", &problems)
        return problems
    }

    private static func showsFromTwoMinutes() -> [String] {
        var problems: [String] = []
        let some = shape(codeBrowseCode)
        expect(SessionPhaseStrip.shows(some, lasted: 120), "two minutes with phases shows the strip", &problems)
        expect(!SessionPhaseStrip.shows(some, lasted: 119), "under two minutes does not", &problems)
        expect(!SessionPhaseStrip.shows(nil, lasted: 3_600), "no phases read, no strip", &problems)
        expect(!SessionPhaseStrip.shows(shape([]), lasted: 3_600), "an empty shape, no strip", &problems)
        return problems
    }

    private static func fills() -> [String] {
        var problems: [String] = []
        let cases: [(SessionPhase, SessionPhaseStrip.Fill)] = [
            (phase(.purpose(.coding), 0, 40), .solid),
            (phase(.purpose(.design), 0, 40), .solid),
            (phase(.purpose(.research), 40, 50), .quiet),
            (phase(.purpose(.communication), 40, 50), .quiet),
            (phase(.browsing, 40, 50), .quiet),
            (phase(.purpose(.media), 20, 80, counted: false), .outlined),
            (phase(.away, 30, 90, counted: false), .outlined),
            // Away counted after an answer of "it was work" is still away, drawn quiet.
            (phase(.away, 30, 90), .quiet),
        ]
        for (phase, want) in cases {
            let got = SessionPhaseStrip.fill(phase)
            expect(got == want, "\(phase.activity), counted \(phase.counted): \(want), got \(got)", &problems)
        }
        return problems
    }
}
