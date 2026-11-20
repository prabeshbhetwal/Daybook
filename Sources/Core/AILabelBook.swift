import Foundation

/// A label the model proposed that the person has not kept (Phase C, rulings C10 and C15). It lives here, not
/// in the person's categories, and reaches the catalogue only as a hidden definition. Keep moves it into the
/// person's categories under the same id; Remove and Merge take it out of the book.
struct AILabel: Codable, Equatable, Identifiable {
    let id: String              // "ai." + UUID
    var name: String
    var symbolName: String
    var hue: WorkTypeHue
    /// Fixed when made: true exactly when the dominant activity is a focused purpose (C11).
    var countsTowardFocus: Bool
    /// The kinds of session this label was made or used for. A later session of the same kind gets the label
    /// back by code, with no model call, which keeps labels stable.
    var fingerprints: [ActivityFingerprint]
    let created: Date
    var lastUsed: Date
    /// Not reused and not counted toward the limit; records already carrying it keep showing it.
    var archived: Bool
}

/// What the model said for one kind of session, against the category list it was asked with.
struct CachedAnswer: Codable, Equatable {
    let fingerprint: ActivityFingerprint
    let digest: String
    var answer: AIAnswer
    var lastUsed: Date
}

/// The file model behind `ai-labels.json` and the rules of the label book. Pure: the caller says what time it
/// is. It keeps no session name, note, title or address: labels, fingerprints, answers by id, removed names
/// and the last comparisons.
struct AILabelBook: Equatable {
    var labels: [AILabel] = []
    var answers: [CachedAnswer] = []
    /// Names the person removed or merged away, never proposed again.
    var removedNames: [String] = []
    var tally: [TallyEntry] = []
    /// When each unkept label was made, kept apart from `labels` so that keeping, merging or removing one does
    /// not give back the day's limit (C29). Makes older than `labelWindow`, or dated later than the next make's
    /// time, are dropped on that make.
    var madeAt: [Date] = []

    // MARK: Cached answers (C7)

    /// A stable string for the categories offered: their ids, sorted and joined. Not `hashValue`, which is
    /// seeded afresh every launch and could not be stored.
    static func digest(of offered: [String]) -> String { offered.sorted().joined(separator: "|") }

    /// What the model said for this kind of session against this list, or nil: never asked, the list has
    /// changed since (so a cached "none" cannot outlive a category the person just made), or it lapsed.
    func cachedAnswer(for fingerprint: ActivityFingerprint, offered: [String], now: Date) -> AIAnswer? {
        let digest = Self.digest(of: offered)
        return answers.first {
            $0.fingerprint == fingerprint && $0.digest == digest && !Self.lapsed($0.lastUsed, after: AILabelConstants.answerExpiry, now: now)
        }?.answer
    }

    /// Keeps an answer for a record, stamped now, and counts it in the tally. Answers unused for
    /// `answerExpiry` are dropped on every write, so the file never keeps one past its time, and so are
    /// those given against another category list: they can never hit again.
    mutating func recordAnswer(_ answer: AIAnswer, recordID: UUID, fingerprint: ActivityFingerprint,
                               offered: [String], now: Date) {
        let digest = Self.digest(of: offered)
        answers.removeAll { $0.digest != digest || Self.lapsed($0.lastUsed, after: AILabelConstants.answerExpiry, now: now) }
        if let index = answers.firstIndex(where: { $0.fingerprint == fingerprint && $0.digest == digest }) {
            answers[index].answer = answer
            answers[index].lastUsed = now
        } else {
            answers.append(CachedAnswer(fingerprint: fingerprint, digest: digest, answer: answer, lastUsed: now))
        }
        tallyAnswer(answer, recordID: recordID)
    }

    /// A label the person removed or merged away: no cached answer may name it again, or a later session of
    /// its kind would be filed under a label that is gone. The caller takes the label itself out of `labels`
    /// and records its name; the tally keeps its history of matches.
    mutating func forget(labelID: String) { answers.removeAll { $0.answer.id == labelID } }

    // MARK: Unkept labels (C9, C15)

    /// The labels in use at `now`: neither archived nor past the time they would be, so right even before
    /// `archiveStale` has run. The time is the caller's, never the clock's.
    func liveLabels(now: Date) -> [AILabel] { labels.filter { isLive($0, now: now) } }

    /// A label that may be given to a session of this kind without asking the model.
    func reusableLabel(for fingerprint: ActivityFingerprint, now: Date) -> AILabel? {
        liveLabels(now: now).first { $0.fingerprints.contains(fingerprint) }
    }

    /// The limits on making one: none made in the last `labelWindow` seconds (`newLabelsPerDay` of them) and
    /// fewer than `maxUnkeptLabels` alive. The makes are counted, not the labels held, so a label kept or
    /// removed the same day still counts. Whole seconds, so no time zone or clock change moves an edge.
    func canMakeLabel(now: Date) -> Bool {
        madeAt.filter { Self.isRecent($0, now: now) }.count < AILabelConstants.newLabelsPerDay
            && liveLabels(now: now).count < AILabelConstants.maxUnkeptLabels
    }

    /// Made within the last `labelWindow` seconds. One dated after `now` (the clock was set back) is not: it
    /// would block makes until the clock caught up, and is dropped on the next make.
    private static func isRecent(_ made: Date, now: Date) -> Bool {
        (0..<AILabelConstants.labelWindow).contains(now.timeIntervalSince(made))
    }

    /// Makes an unkept label for a session of this kind, drawn and counted as its dominant activity says
    /// (C16, C11), or nil at a limit, when nothing is made. Never under an id a label or a category already has.
    @discardableResult
    mutating func addUnkeptLabel(id: String, name: String, dominant: AppPurpose, fingerprint: ActivityFingerprint,
                                 now: Date) -> AILabel? {
        guard canMakeLabel(now: now), !labels.contains(where: { $0.id == id }),
              !WorkTypeCatalog.shared.allDefinitions.contains(where: { $0.id == id }) else { return nil }
        madeAt.removeAll { !Self.isRecent($0, now: now) }
        madeAt.append(now)
        let look = LabelLook.look(for: dominant)
        let label = AILabel(id: id, name: name, symbolName: look.symbolName, hue: look.hue,
                            countsTowardFocus: dominant.isFocused, fingerprints: [fingerprint], created: now,
                            lastUsed: now, archived: false)
        labels.append(label)
        return label
    }

    /// A session of this kind was given the label: it is in use again, and now also reused for this kind. A
    /// label keeps its newest `maxLabelFingerprints` kinds, so a label in long use cannot grow the file.
    mutating func markUsed(labelID: String, fingerprint: ActivityFingerprint, now: Date) {
        guard let index = labels.firstIndex(where: { $0.id == labelID }) else { return }
        labels[index].lastUsed = now
        guard !labels[index].fingerprints.contains(fingerprint) else { return }
        labels[index].fingerprints.append(fingerprint)
        let excess = labels[index].fingerprints.count - AILabelConstants.maxLabelFingerprints
        if excess > 0 { labels[index].fingerprints.removeFirst(excess) }
    }

    /// Archives what lapsed and drops answers unused for `answerExpiry`, on every write, so the file keeps none
    /// past its time even while nothing is asked. The label stays listed, so records carrying it still resolve;
    /// history is never rewritten.
    mutating func archiveStale(now: Date) {
        for index in labels.indices where isLapsed(labels[index], now: now) { labels[index].archived = true }
        answers.removeAll { Self.lapsed($0.lastUsed, after: AILabelConstants.answerExpiry, now: now) }
    }

    private func isLapsed(_ label: AILabel, now: Date) -> Bool {
        Self.lapsed(label.lastUsed, after: AILabelConstants.labelArchiveAfter, now: now)
    }

    /// Not archived, and not past the time it would be: right even before `archiveStale` has run.
    private func isLive(_ label: AILabel, now: Date) -> Bool { !label.archived && !isLapsed(label, now: now) }

    /// Whole seconds past `limit` since `date`: exactly at the limit has not lapsed.
    private static func lapsed(_ date: Date, after limit: TimeInterval, now: Date) -> Bool {
        now.timeIntervalSince(date).rounded(.down) > limit
    }
}

/// The file as JSON. A missing key reads as empty and an entry this build cannot read is dropped alone: one
/// bad label or answer, from a later build or a damaged file, never costs the rest.
extension AILabelBook: Codable {
    private enum CodingKeys: String, CodingKey { case labels, answers, removedNames, tally, madeAt }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: CodingKeys.self)
        labels = root.entries(.labels)
        answers = root.entries(.answers)
        removedNames = root.entries(.removedNames)
        tally = root.entries(.tally)
        madeAt = root.entries(.madeAt)
    }
}

private struct LossyEntry<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

private extension KeyedDecodingContainer {
    func entries<Value: Decodable>(_ key: Key) -> [Value] {
        (try? decodeIfPresent([LossyEntry<Value>].self, forKey: key))?.compactMap(\.value) ?? []
    }
}
