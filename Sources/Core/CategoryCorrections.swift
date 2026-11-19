import Foundation

/// One remembered choice: sessions of this kind were filed under `chosen`, and never under a
/// category in `vetoed`. It holds Phase A's fingerprint (purpose shares in 20% steps, two bundle
/// identifiers, a site kind), category names, a count and a date: no title, page, note or time of day.
struct CategoryCorrection: Codable, Equatable {
    /// "category". The away design adds `awayAnswer`, which nothing here reads.
    let kind: String
    let fingerprint: ActivityFingerprint
    var chosen: String          // WorkType raw value
    var vetoed: [String]        // categories the person moved such a session out of
    var count: Int
    var lastUsed: Date
}

/// What one filing did to one remembered choice: the entry as it stood before (nil when there was none)
/// and as the filing left it. Kept with the correction it came from, so Undo can take it back.
struct RememberedFiling: Codable, Equatable {
    let before: CategoryCorrection?
    let after: CategoryCorrection
}

/// The file model behind `corrections.json`, and the whole of the matching rules. Pure: the caller
/// says what time it is, and a match is the fingerprint alone.
struct CategoryCorrections: Equatable {
    static let categoryKind = "category"

    var version = 1
    var entries: [CategoryCorrection] = []
    /// Entries this build cannot read: a kind it does not know, or a shape it does not. Kept as found
    /// and written back, so one of them never costs the rest and a later Daybook still finds its own.
    var unread: [JSONValue] = []

    /// The category to offer for a session of this kind, never one the person moved such a session
    /// out of, and none once the correction lapsed.
    func suggestion(for fingerprint: ActivityFingerprint, now: Date) -> String? {
        guard let entry = entry(for: fingerprint), !Self.lapsed(entry, now: now),
              !entry.vetoed.contains(entry.chosen) else { return nil }
        return entry.chosen
    }

    /// The person filed a session of this kind under `chosen`. `vetoed` is the category it was in,
    /// unless the person had chosen that one themselves: leaving their own choice is no veto.
    @discardableResult
    mutating func record(fingerprint: ActivityFingerprint, chosen: String, vetoed: String?,
                         at moment: Date) -> RememberedFiling {
        let index = entries.firstIndex { $0.kind == Self.categoryKind && $0.fingerprint == fingerprint }
        let previous = index.map { entries[$0] }
        var entry = previous
            ?? CategoryCorrection(kind: Self.categoryKind, fingerprint: fingerprint, chosen: chosen,
                                  vetoed: [], count: 0, lastUsed: moment)
        let counted = entry.chosen == chosen ? entry.count : 0
        entry.count = counted == .max ? counted : counted + 1   // a count already at the limit stays there
        entry.chosen = chosen
        // Choosing a category again is the person's own word: its veto lifts.
        entry.vetoed.removeAll { $0 == chosen }
        if let vetoed, vetoed != chosen, !entry.vetoed.contains(vetoed) { entry.vetoed.append(vetoed) }
        entry.lastUsed = moment
        if let index { entries[index] = entry } else { entries.append(entry) }
        return RememberedFiling(before: previous, after: entry)
    }

    /// Takes one filing back. The entry is rebuilt from the filings of the kind that nobody has undone
    /// (`standing`: made before it; `later`: made after it; both oldest first): the latest of them as it left
    /// the entry, its count cut to the run of standing filings that chose the same category, or no entry when
    /// none stands. Nothing changes when the entry now holds another choice than this filing made. shortcut:
    /// vetoes are the latest standing filing's, and a filing whose receipt aged out of the history counts as
    /// withdrawn; upgrade if either proves to matter. `standing` and `later` have no default: a caller with
    /// none to give says so with `[]`.
    mutating func forget(_ filing: RememberedFiling, standing: [RememberedFiling], later: [RememberedFiling]) {
        guard let index = entries.firstIndex(where: {
            $0.kind == Self.categoryKind && $0.fingerprint == filing.after.fingerprint
        }), entries[index].chosen == filing.after.chosen else { return }
        // Rebuilt from the filings of the kind that still stand, never patched, so no order of undos can
        // leave a withdrawn choice or lose a standing one.
        let survivors = (standing + later).filter { $0.after.fingerprint == filing.after.fingerprint }
        guard var kept = survivors.last?.after else { entries.remove(at: index); return }
        let run = survivors.reversed().prefix { $0.after.chosen == kept.chosen }.count
        kept.count = min(kept.count, run)
        entries[index] = kept
    }

    /// Drops what lapsed. Done on every write, so the file never keeps a choice past its time.
    mutating func pruned(now: Date) {
        entries.removeAll { Self.lapsed($0, now: now) }
    }

    private func entry(for fingerprint: ActivityFingerprint) -> CategoryCorrection? {
        entries.first { $0.kind == Self.categoryKind && $0.fingerprint == fingerprint }
    }

    /// Whole seconds, not calendar days, so a time zone or a clock change cannot move the edge.
    private static func lapsed(_ entry: CategoryCorrection, now: Date) -> Bool {
        now.timeIntervalSince(entry.lastUsed).rounded(.down) > TimeInterval(ActivityConstants.correctionExpiryDays * 86_400)
    }
}

/// The file as JSON. An entry that is not a category choice this build reads, whether newer or
/// malformed, is kept in `unread` instead of failing the whole file.
extension CategoryCorrections: Codable {
    private enum CodingKeys: String, CodingKey { case version, entries }

    private struct Slot: Decodable {
        let entry: CategoryCorrection?
        let unread: JSONValue?

        init(from decoder: Decoder) throws {
            let read = try? CategoryCorrection(from: decoder)
            entry = read?.kind == CategoryCorrections.categoryKind ? read : nil
            unread = entry == nil ? try JSONValue(from: decoder) : nil
        }
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: CodingKeys.self)
        version = try root.decode(Int.self, forKey: .version)
        for slot in try root.decode([Slot].self, forKey: .entries) {
            if let entry = slot.entry { entries.append(entry) } else if let other = slot.unread { unread.append(other) }
        }
    }

    func encode(to encoder: Encoder) throws {
        var root = encoder.container(keyedBy: CodingKeys.self)
        try root.encode(version, forKey: .version)
        var list = root.nestedUnkeyedContainer(forKey: .entries)
        for entry in entries { try list.encode(entry) }
        for other in unread { try list.encode(other) }
    }
}
