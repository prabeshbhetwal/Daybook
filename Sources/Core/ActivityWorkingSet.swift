import Foundation

/// A run's working set (spec section 3): the apps the person works across. It
/// starts with the anchor, the app of the first engaged slice (with none, the
/// front app of the first credited slice). An app joins when work leaves the set
/// for it and an engaged slice on a member starts within `returnWindow` of
/// leaving. Membership is hindsight: a joined app's earlier slices count inside.
/// `ThreadApps` ranks apps by recorded seconds and knows no return rule, so it is not reused.
enum ActivityWorkingSet {
    struct Departure: Equatable {
        let at: Date
        /// An engaged slice on a member (as of then) started within `returnWindow` of it.
        let returned: Bool
    }

    /// Members and departures of one run, from its credited slices and beats in time order.
    static func derive(_ slices: [CreditedSlice], beats: [Beat], countsWhileWatching: Bool)
        -> (members: Set<String>, departures: [Date]) {
        let walked = walk(slices, beats: beats, countsWhileWatching: countsWhileWatching)
        return (walked.members, walked.departures.map(\.at))
    }

    /// A departure is the start of an engaged slice on a non-member, of the first held or
    /// passive slice after one that was neither, or of a watching pause where the engine
    /// started it (`ActivityCredit.watchPauses`; not one the session opens with). Quiet-kept
    /// time and `.paused` beats never depart, nor does held time when watching is the work.
    ///
    /// One departure is open at a time: non-members engaged meanwhile are pending, and the
    /// next engaged slice on a member closes it. It returns (pending apps join) only when
    /// that slice starts strictly less than `returnWindow` after it; a split candidate's
    /// test is the complement, `>= returnWindow`. So the first candidate is the same as
    /// reading every slice on its own would give; later departures inside an open one are
    /// not separate. Phase B cuts runs at candidates, and each run starts its own walk.
    static func walk(_ slices: [CreditedSlice], beats: [Beat], countsWhileWatching: Bool)
        -> (members: Set<String>, departures: [Departure]) {
        guard let anchor = slices.first(where: { $0.state == .engaged })?.app ?? slices.first?.app else {
            return ([], [])
        }
        var members: Set<String> = [anchor]
        var pending: Set<String> = []
        var departures: [Departure] = []
        var open: Date?
        var lastDeparted: Bool?

        // Credited slices lie in counted time, so they stand in for the counted spans here.
        let credited = slices.map { DateInterval(start: $0.start, end: $0.end) }
        let watching = ActivityCredit.watchPauses(ActivityCredit.ordered(beats), counted: credited, overrides: [:])
            .filter { !$0.atStart }.map(\.span.start)
        var nextWatch = 0
        func watchUntil(_ moment: Date) {
            while nextWatch < watching.count, watching[nextWatch] <= moment {
                if open == nil { open = watching[nextWatch] }
                nextWatch += 1
            }
        }

        for slice in slices {
            watchUntil(slice.start)
            let departs = slice.state == .passive || (slice.state == .held && !countsWhileWatching)
            if slice.state == .engaged {
                if members.contains(slice.app) {
                    if let left = open {
                        let returned = slice.start.timeIntervalSince(left) < ActivityConstants.returnWindow
                        if returned { members.formUnion(pending) }
                        departures.append(Departure(at: left, returned: returned))
                        open = nil
                        pending = []
                    }
                } else {
                    if open == nil { open = slice.start }
                    pending.insert(slice.app)
                }
            } else if departs, lastDeparted == false, open == nil {
                open = slice.start
            }
            lastDeparted = departs
        }
        watchUntil(.distantFuture)
        if let left = open { departures.append(Departure(at: left, returned: false)) }
        return (members, departures)
    }
}
