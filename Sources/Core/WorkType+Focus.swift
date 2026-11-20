import Foundation

/// What a category means for focus (Phase C, ruling C11). Two questions that used to be one: "is this rest?"
/// and "does time here count toward the day's goal?". Totals, goals, streaks and every focus figure ask the
/// second through `countsAsFocus`; anything that only needs to tell rest from work asks `isBreak`.
extension WorkType {
    /// Rest, recorded so a gap on the timeline is explained, never counted and never started by hand.
    var isBreak: Bool { self == .breakTime }

    /// Whether time filed under this category counts as focus: the day's total, goals, streaks, the
    /// dashboard and History's focus figures. A break belongs on the timeline, where it explains a gap,
    /// but never in the focused total: nothing else stopped a session logged as "Break" from filling the
    /// daily goal and holding up a streak. A category the person has set not to count (a leisure one,
    /// say) does not either, though sessions in it are still sessions.
    var countsAsFocus: Bool { !isBreak && WorkTypeCatalog.shared.countsTowardFocus(self) }

    /// Where a record lands when nothing could say what it was. Hidden: no picker, list or Settings shows
    /// it and nothing can be started as it, so it is not in `allCases` and is not focus.
    static let unsorted = WorkType(rawValue: "unsorted")

    /// The kinds a person can actually start: every offered category but rest. `.breakTime` is written by
    /// the away card and by nothing else: offering it under a button reading "Start Focus" produced a
    /// session that could not fill a goal. Retired categories, Unsorted and unkept AI labels are not in
    /// `allCases`, so they are not here. A category set not to count toward focus is here.
    static var startable: [WorkType] { allCases.filter { !$0.isBreak } }

    /// The categories a daily goal can be set for: those that can be started and count toward focus. A goal
    /// for one that does not count could never be met.
    static var goalable: [WorkType] { startable.filter(\.countsAsFocus) }

    /// What to start under when the wanted category cannot be: Deep work, or
    /// the first category still offered when Deep work is retired too.
    static var fallbackStartable: WorkType {
        let offered = startable
        return offered.contains(.deepWork) ? .deepWork : (offered.first ?? .deepWork)
    }

    /// This kind, or the fallback when it is a category no longer offered, hidden or unkept. Break is never
    /// offered and never replaced.
    var startableOrFallback: WorkType {
        isBreak || WorkType.startable.contains(self) ? self : .fallbackStartable
    }
}

extension WorkTypeDefinition {
    /// Not Break, and set to count toward focus. Read from the definition in hand, for callers that hold
    /// one (the goal list's migration) rather than looking it up by identifier.
    var countsAsFocus: Bool { !workType.isBreak && countsTowardFocus }

    /// Listed nowhere and edited by no one: Unsorted, or a label an AI proposed that the person has not kept.
    /// Never the person's to rename, re-icon or keep, so never written into their stored categories.
    var isHidden: Bool { isUnkeptAILabel || id == WorkType.unsorted.rawValue }
}
