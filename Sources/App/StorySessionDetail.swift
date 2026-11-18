import Foundation

struct StorySessionDetail {
    let apps: [AppRank]
    let text: String?
    /// The card's line under its figures; nil when there is nothing to add.
    let caption: String?
    /// The report's line under its figures, which already include recorded
    /// app use and the time range.
    let reportNote: String?
    /// Canonical app/gap timeline. The old bins remain during the chart
    /// migration, but ranks, captions and prose all use this same evidence.
    let activity: RecordedActivity
    let bins: [SessionShape.Bin]
    /// The session's phases: from its beats, else the snapshot it kept, else its app use alone.
    /// The row reads them here and never works them out. The day's projection leaves them nil; an open
    /// card adds them (`openSessionDetail`).
    var phases: SessionActivityShape?
}
