import Foundation

/// The values the AI label checks share: a fingerprint, an ended automatic record, the shape that
/// session left, and a label. Moments are offsets from `SelfTest.base`, so nothing depends on a time zone.
enum AIFixture {
    static var base: Date { SelfTest.base }
    static let day: TimeInterval = 86_400

    /// A fingerprint told apart by `seed` alone.
    static func fingerprint(_ seed: Int = 0) -> ActivityFingerprint {
        ActivityFingerprint(shares: (0..<AppPurpose.allCases.count).map { $0 == 0 ? seed : 0 },
                            topApps: ["app.\(seed)", ""], siteKind: "none")
    }

    /// An automatic record as it ends: the app's own start and its own category guess.
    static func record(origin: SessionOrigin? = .automatic, source: DecisionSource? = .builtIn,
                       isAuto: Bool = true, name: String = "Parser") -> SessionRecord {
        SessionRecord(name: name, workType: .deepWork, start: base, end: base.addingTimeInterval(1_800),
                      workSeconds: 1_800, isAuto: isAuto, origin: origin, categorySource: source)
    }

    /// The shape of a session credited `credited` seconds per purpose.
    static func shape(_ credited: [AppPurpose: TimeInterval], counted: TimeInterval = 1_800,
                      depth: SessionDepth? = nil,
                      fingerprint: ActivityFingerprint? = AIFixture.fingerprint()) -> SessionActivityShape {
        SessionActivityShape(
            algorithmVersion: ActivityConstants.algorithmVersion, fidelity: .beats,
            bounds: DateInterval(start: base, duration: 1_800), countedSeconds: counted, signals: [], phases: [],
            depth: depth, label: .mixed, credited: Dictionary(uniqueKeysWithValues: credited.map { ($0.key.rawValue, $0.value) }),
            fingerprint: fingerprint, splitCandidates: [])
    }

    static func label(_ id: String, _ name: String, seed: Int = 0, created: TimeInterval = 0,
                      archived: Bool = false) -> AILabel {
        AILabel(id: id, name: name, symbolName: "film.fill", hue: .red, countsTowardFocus: false,
                fingerprints: [fingerprint(seed)], created: base.addingTimeInterval(created),
                lastUsed: base.addingTimeInterval(created), archived: archived)
    }

    /// A book that has been given one of each kind of thing, for the file round trip.
    static func filledBook() -> AILabelBook {
        var book = AILabelBook()
        book.labels = [label("ai.a", "Films", seed: 1), label("ai.b", "Games", seed: 2, created: day),
                       label("ai.c", "Chess", seed: 3, created: 2 * day, archived: true)]
        let offered = ["deepWork", "custom.x"]
        let now = base.addingTimeInterval(3 * day)
        for (index, answer) in [AIAnswer.pick("deepWork"), .label("ai.a"), .proposed(id: "ai.d", name: "Poems"),
                                .none].enumerated() {
            book.recordAnswer(answer, recordID: UUID(), fingerprint: fingerprint(10 + index), offered: offered,
                              now: now.addingTimeInterval(TimeInterval(index)))
        }
        book.removedNames = ["Gossip"]
        if let first = book.tally.first { book.recordChoice(recordID: first.recordID, chosen: "deepWork") }
        return book
    }
}
