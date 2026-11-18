import Foundation

/// Cutting one ended record in two and joining the halves again, as arithmetic alone (spec section 4):
/// work is divided by counted time, a cut only lands inside the work, and joining gives the record back.
enum SplitRecordChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A record splits in two inside it: work is divided by counted time around its pauses and the total never moves",
         splitDividesWork),
        ("A cut at the start, the end, outside, at a paused span's edge or inside one is refused, and a break never splits",
         refusedCuts),
        ("A record without pause detail spreads its work across the two halves by time", evenSpread),
        ("The tail begins as the choice says and carries the head's origin; the head keeps everything it had",
         tailProvenance),
        ("Joining the halves gives back the record they were cut from, and only while they touch", mergeRestores),
    ]

    static func at(_ seconds: TimeInterval) -> Date { SelfTest.base.addingTimeInterval(seconds) }

    /// An hour of work with ten minutes paused inside it (3000 s counted), the way an automatic session is written.
    static func original(paused: [DateInterval]? = [DateInterval(start: at(1200), end: at(1800))],
                         work: Double = 3000, origin: SessionOrigin? = .automatic) -> SessionRecord {
        SessionRecord(id: UUID(), name: "Report", workType: .deepWork, start: at(0), end: at(3600), workSeconds: work,
                      detectedApp: "com.apple.dt.Xcode", threadID: UUID(), isAuto: origin == .automatic,
                      pausedSpans: paused, plannedLength: 3000, origin: origin, categorySource: .builtIn,
                      nameByApp: true)
    }

    static let video = SplitTail(name: "Video", workType: .learning, source: .correction, nameByApp: true)

    private static func splitDividesWork() -> [String] {
        var problems: [String] = []
        let record = original()
        guard let cut = record.split(at: at(2400), tail: video) else { return ["a cut inside the record was refused"] }
        let (head, tail) = (cut.head, cut.tail)
        expect(head.id == record.id && head.threadID == record.threadID && head.start == record.start
               && head.end == at(2400), "the head is not the original's first part: \(head)", &problems)
        expect(tail.start == at(2400) && tail.end == record.end, "the tail is not the rest: \(tail)", &problems)
        expect(tail.id != record.id && tail.threadID != record.threadID, "the tail shares an identity", &problems)
        // The pause lies in the head's 40 minutes, so 30 of them count; the tail's 20 all do.
        expect(head.workSeconds == 1_800 && tail.workSeconds == 1_200,
               "work was \(head.workSeconds) and \(tail.workSeconds), not 1800 and 1200", &problems)
        expect(head.workSeconds + tail.workSeconds == record.workSeconds, "the work no longer adds up", &problems)
        expect(head.pausedSpans == record.pausedSpans && tail.pausedSpans == [],
               "the paused spans were not shared out: \(String(describing: head.pausedSpans)) \(String(describing: tail.pausedSpans))",
               &problems)
        // Cut inside the counted time on the other side of the pause: the pause stays whole in the tail.
        if let late = record.split(at: at(900), tail: video) {
            expect(late.head.workSeconds == 900 && late.tail.workSeconds == 2_100
                   && late.tail.pausedSpans == record.pausedSpans && late.head.pausedSpans == [],
                   "a cut before the pause gave \(late.head.workSeconds) and \(late.tail.workSeconds)", &problems)
        } else { problems.append("a cut before the pause was refused") }
        return problems
    }

    private static func refusedCuts() -> [String] {
        var problems: [String] = []
        let record = original()
        for (label, moment) in [("the start", 0.0), ("the end", 3_600), ("before it", -60), ("after it", 3_700),
                                ("the start of a pause", 1_200), ("inside a pause", 1_500), ("the end of a pause", 1_800)] {
            expect(record.split(at: at(moment), tail: video) == nil, "a cut at \(label) was allowed", &problems)
        }
        expect(record.split(at: at(1_199), tail: video) != nil && record.split(at: at(1_801), tail: video) != nil,
               "a cut a second clear of a pause was refused", &problems)
        let rest = SessionRecord(name: "Break", workType: .breakTime, start: at(0), end: at(3_600),
                                 workSeconds: 3_600, breakOrigin: .started)
        expect(rest.split(at: at(1_800), tail: video) == nil, "a break was split", &problems)
        return problems
    }

    private static func evenSpread() -> [String] {
        var problems: [String] = []
        let record = original(paused: nil)
        guard let cut = record.split(at: at(1_800), tail: video) else { return ["a record without pause detail was refused"] }
        expect(cut.head.workSeconds == 1_500 && cut.tail.workSeconds == 1_500,
               "the even spread gave \(cut.head.workSeconds) and \(cut.tail.workSeconds)", &problems)
        expect(cut.head.pausedSpans == nil && cut.tail.pausedSpans == nil, "pause detail appeared from nowhere", &problems)
        if let odd = record.split(at: at(1_234), tail: video) {
            expect(abs(odd.head.workSeconds + odd.tail.workSeconds - 3_000) < 1e-9
                   && abs(odd.head.workSeconds - 3_000 * 1_234 / 3_600) < 1e-6,
                   "an uneven cut gave \(odd.head.workSeconds) and \(odd.tail.workSeconds)", &problems)
        }
        return problems
    }

    private static func tailProvenance() -> [String] {
        var problems: [String] = []
        let ruleID = UUID()
        var rule = original(origin: .rule)
        rule.originRuleID = ruleID
        rule.originRuleName = "Morning writing"
        rule.categorySource = .rule
        rule.nameByApp = false
        let picked = SplitTail(name: rule.name, workType: .learning, source: .user, nameByApp: false)
        guard let cut = rule.split(at: at(2_400), tail: picked) else { return ["the rule's session was refused"] }
        expect(cut.tail.origin == .rule && cut.tail.originRuleID == ruleID && cut.tail.originRuleName == "Morning writing"
               && cut.tail.isAuto == rule.isAuto, "the tail did not begin as its head did: \(cut.tail)", &problems)
        expect(cut.tail.workType == .learning && cut.tail.categorySource == .user && cut.tail.name == "Report"
               && cut.tail.nameByApp == false, "the tail did not take the choice made: \(cut.tail)", &problems)
        expect(cut.head.name == rule.name && cut.head.workType == rule.workType
               && cut.head.categorySource == .rule && cut.head.nameByApp == false && cut.head.originRuleID == ruleID
               && cut.head.detectedApp == rule.detectedApp && cut.head.plannedLength == rule.plannedLength,
               "the head lost something it had: \(cut.head)", &problems)
        expect(cut.tail.plannedLength == nil && cut.tail.breakOrigin == nil, "the tail inherited a plan or a break", &problems)
        let withApp = SplitTail(name: "Video", workType: .learning, source: .builtIn, nameByApp: true,
                                detectedApp: "com.apple.Safari")
        expect(original().split(at: at(2_400), tail: withApp)?.tail.detectedApp == "com.apple.Safari",
               "the tail's app was not kept", &problems)
        return problems
    }

    private static func mergeRestores() -> [String] {
        var problems: [String] = []
        for record in [original(), original(paused: nil), original(paused: [], work: 3_600)] {
            guard let cut = record.split(at: at(2_400), tail: video) else { problems.append("a cut was refused"); continue }
            expect(SessionRecord.merged(head: cut.head, tail: cut.tail) == record,
                   "joining the halves did not give the record back: \(String(describing: SessionRecord.merged(head: cut.head, tail: cut.tail)))",
                   &problems)
        }
        guard let cut = original().split(at: at(2_400), tail: video) else { return problems + ["no cut"] }
        var apart = cut.tail
        apart.start = at(2_500)
        expect(SessionRecord.merged(head: cut.head, tail: apart) == nil, "halves with a gap between were joined", &problems)
        expect(SessionRecord.merged(head: cut.tail, tail: cut.head) == nil, "the halves were joined the wrong way round", &problems)
        let rest = SessionRecord(name: "Break", workType: .breakTime, start: at(2_400), end: at(3_000),
                                 workSeconds: 600, breakOrigin: .started)
        expect(SessionRecord.merged(head: cut.head, tail: rest) == nil, "a break was joined into a session", &problems)
        expect(SessionRecord.merged(head: cut.head, tail: cut.head) == nil, "a record was joined to itself", &problems)
        return problems
    }
}
