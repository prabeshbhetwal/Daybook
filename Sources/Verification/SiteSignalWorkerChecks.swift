import Foundation

/// The site reader's worker: a stale answer is dropped where it arrives, and a
/// browser that answers slowly cannot hold the worker. Fakes only.
enum SiteSignalWorkerChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An answer that arrives after recording ended or a newer request is dropped", staleAnswerDropped),
        ("A read gives up once it has taken a second", readDeadline),
    ]

    private typealias Rig = SiteSignalChecks.Rig

    private static func staleAnswerDropped() -> [String] {
        var problems: [String] = []
        let interruptions: [(String, (Rig) -> Void)] = [
            ("recording ended", { $0.reader.reset() }),
            ("a newer request was made", { rig in
                rig.deferred = []
                rig.request(at: 30)
            }),
        ]
        for (name, interrupt) in interruptions {
            let rig = Rig("stale-answer-" + name.replacingOccurrences(of: " ", with: "-"))
            defer { rig.close() }
            rig.held = []
            rig.fake.answer = .address("https://www.youtube.com/")
            rig.request()
            expect(rig.fake.asked.count == 1 && rig.delivered.isEmpty, "\(name): the read did not run first", &problems)
            interrupt(rig)
            let answers = rig.held ?? []
            rig.held = nil
            answers.forEach { $0() }
            expect(rig.delivered.isEmpty, "\(name): the stale answer was delivered: \(rig.delivered)", &problems)
        }
        return problems
    }

    /// A tree whose web area is the sixth element met, breadth-first.
    private static func walk(secondsPerElement: TimeInterval) -> String {
        let children: [Int: [Int]] = [0: [1, 2, 3], 1: [4], 3: [5]]
        var clock: TimeInterval = 0
        do {
            let address = try AXSiteAddressReader.walk(
                from: 0, startedAt: 0, now: { clock },
                role: { element in
                    clock += secondsPerElement
                    return element == 5 ? "AXWebArea" : "AXGroup"
                },
                children: { children[$0] ?? [] },
                url: { $0 == 5 ? "https://example.com/" : nil })
            return address ?? "none"
        } catch {
            return "timed out"
        }
    }

    private static func readDeadline() -> [String] {
        var problems: [String] = []
        expect(SiteSignalConstants.readDeadline == 1.0, "the deadline is \(SiteSignalConstants.readDeadline) s", &problems)
        let quick = walk(secondsPerElement: 0.15)
        expect(quick == "https://example.com/", "a browser answering in time gave \(quick)", &problems)
        let slow = walk(secondsPerElement: 0.3)
        expect(slow == "timed out", "a browser taking 0.3 s per element gave \(slow)", &problems)
        return problems
    }
}
