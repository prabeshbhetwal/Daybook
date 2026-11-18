import Foundation

/// What Daybook remembers of how the person files a kind of session: a match is the fingerprint
/// alone, the veto holds, an unused choice lapses after 90 whole days whatever the time zone, and
/// the file holds nothing but the fingerprint, category names, counts and dates.
enum CategoryCorrectionChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A correction is suggested for the same fingerprint and for no other", suggestsForSameFingerprint),
        ("A category the person moved a session out of is never suggested", vetoedIsNeverSuggested),
        ("Choosing a category again counts it, and choosing another starts the count again", countFollowsTheChoice),
        ("A correction lapses 90 whole days after it was last used, in any time zone, and is pruned on the next write",
         expiresAfterNinetyDays),
        ("The corrections file holds the fingerprint, category names, counts and dates, nothing else", keepsNothingElse),
    ]

    static func fingerprint(_ shares: [Int] = [5, 0, 0, 0, 0, 0, 0],
                            apps: [String] = ["com.example.editor", ""]) -> ActivityFingerprint {
        ActivityFingerprint(shares: shares, topApps: apps, siteKind: "none")
    }

    private static func suggestsForSameFingerprint() -> [String] {
        var problems: [String] = []
        var corrections = CategoryCorrections()
        let now = SelfTest.base
        corrections.record(fingerprint: fingerprint(), chosen: "learning", vetoed: "deepWork", at: now)
        expect(corrections.suggestion(for: fingerprint(), now: now.addingTimeInterval(60)) == "learning",
               "the same fingerprint was not offered the chosen category", &problems)
        expect(corrections.suggestion(for: fingerprint([0, 0, 0, 0, 0, 5, 0]), now: now) == nil,
               "another mix of purposes was offered the category", &problems)
        expect(corrections.suggestion(for: fingerprint(apps: ["com.example.other", ""]), now: now) == nil,
               "another top app was offered the category", &problems)
        expect(CategoryCorrections().suggestion(for: fingerprint(), now: now) == nil,
               "an empty store offered a category", &problems)
        return problems
    }

    private static func vetoedIsNeverSuggested() -> [String] {
        var problems: [String] = []
        var corrections = CategoryCorrections()
        let now = SelfTest.base
        corrections.record(fingerprint: fingerprint(), chosen: "learning", vetoed: "deepWork", at: now)
        expect(corrections.entries.first?.vetoed == ["deepWork"],
               "the category moved out of was not kept as vetoed: \(String(describing: corrections.entries.first))",
               &problems)
        // A file that names one category as both chosen and vetoed suggests neither.
        var both = CategoryCorrections()
        both.entries = [CategoryCorrection(kind: CategoryCorrections.categoryKind, fingerprint: fingerprint(),
                                           chosen: "deepWork", vetoed: ["deepWork"], count: 3, lastUsed: now)]
        expect(both.suggestion(for: fingerprint(), now: now) == nil, "a vetoed category was suggested", &problems)
        // Choosing it again is the person's own word: the veto lifts. Leaving the same category is no veto.
        corrections.record(fingerprint: fingerprint(), chosen: "deepWork", vetoed: "learning", at: now)
        expect(corrections.suggestion(for: fingerprint(), now: now) == "deepWork"
               && corrections.entries.first?.vetoed == ["learning"],
               "choosing a vetoed category again did not lift its veto: \(String(describing: corrections.entries.first))",
               &problems)
        corrections.record(fingerprint: fingerprint(), chosen: "admin", vetoed: "admin", at: now)
        expect(corrections.entries.first?.vetoed.contains("admin") == false,
               "a category was vetoed in the same act that chose it", &problems)
        return problems
    }

    private static func countFollowsTheChoice() -> [String] {
        var problems: [String] = []
        var corrections = CategoryCorrections()
        let start = SelfTest.base
        for step in 0..<3 {
            corrections.record(fingerprint: fingerprint(), chosen: "learning", vetoed: nil,
                               at: start.addingTimeInterval(TimeInterval(step * 60)))
        }
        let entry = corrections.entries.first
        expect(corrections.entries.count == 1 && entry?.count == 3
               && entry?.lastUsed == start.addingTimeInterval(120),
               "three choices of one category gave \(String(describing: entry))", &problems)
        corrections.record(fingerprint: fingerprint(), chosen: "admin", vetoed: nil, at: start.addingTimeInterval(300))
        expect(corrections.entries.first?.chosen == "admin" && corrections.entries.first?.count == 1,
               "a different choice did not start the count again: \(String(describing: corrections.entries.first))",
               &problems)
        return problems
    }

    private static func expiresAfterNinetyDays() -> [String] {
        var problems: [String] = []
        let lapse = TimeInterval(ActivityConstants.correctionExpiryDays * 86_400)
        // Local noon either side of a clock change, in zones that change and one that does not.
        var anchors = (0..<53).map { SelfTest.base.addingTimeInterval(TimeInterval($0) * 7 * 86_400) }
        for (zone, year, month, day) in [("Europe/Berlin", 2026, 10, 20), ("Australia/Sydney", 2026, 9, 15),
                                         ("America/New_York", 2026, 10, 20), ("Pacific/Kiritimati", 2026, 10, 20)] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone) ?? .current
            if let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) {
                anchors.append(noon)
            }
        }
        for used in anchors {
            var corrections = CategoryCorrections()
            corrections.record(fingerprint: fingerprint(), chosen: "learning", vetoed: nil, at: used)
            expect(corrections.suggestion(for: fingerprint(), now: used.addingTimeInterval(lapse)) == "learning",
                   "a correction lapsed before 90 days were up (used \(used))", &problems)
            expect(corrections.suggestion(for: fingerprint(), now: used.addingTimeInterval(lapse + 1)) == nil,
                   "a correction still steered a suggestion 90 days and a second later (used \(used))", &problems)
        }
        var corrections = CategoryCorrections()
        let used = SelfTest.base
        corrections.record(fingerprint: fingerprint(), chosen: "learning", vetoed: nil, at: used)
        let later = used.addingTimeInterval(lapse + 1)
        corrections.record(fingerprint: fingerprint([0, 5, 0, 0, 0, 0, 0]), chosen: "admin", vetoed: nil, at: later)
        expect(corrections.entries.count == 2, "the lapsed entry was dropped before a write pruned it", &problems)
        corrections.pruned(now: later)
        expect(corrections.entries.map(\.chosen) == ["admin"],
               "pruning kept \(corrections.entries.map(\.chosen))", &problems)
        return problems
    }

    private static func keepsNothingElse() -> [String] {
        var problems: [String] = []
        var corrections = CategoryCorrections()
        corrections.record(fingerprint: fingerprint(), chosen: "learning", vetoed: "deepWork", at: SelfTest.base)
        guard let data = try? JSONEncoder().encode(corrections),
              let document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = document["entries"] as? [[String: Any]], let entry = entries.first,
              let marked = entry["fingerprint"] as? [String: Any] else {
            return ["the corrections did not encode as a document with entries"]
        }
        expect(Set(document.keys) == ["version", "entries"], "the document holds \(document.keys.sorted())", &problems)
        expect(Set(entry.keys) == ["kind", "fingerprint", "chosen", "vetoed", "count", "lastUsed"],
               "an entry holds \(entry.keys.sorted())", &problems)
        expect(Set(marked.keys) == ["shares", "topApps", "siteKind"], "a fingerprint holds \(marked.keys.sorted())", &problems)
        let decoded = try? JSONDecoder().decode(CategoryCorrections.self, from: data)
        expect(decoded == corrections, "the document did not read back as it was written", &problems)
        return problems
    }
}
