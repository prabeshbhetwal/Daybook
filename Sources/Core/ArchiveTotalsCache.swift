import Foundation

/// The archive's day-by-day totals and the streaks read off them, kept until a record changes or the category
/// catalogue does. Whether a record counts toward focus is read from its category's setting, which can change
/// with no record written, so the cache is stamped with the catalogue's generation when it is emptied.
struct ArchiveTotalsCache {
    var dailyTotals: [Date: TimeInterval]?
    var bestStreak: Int?
    var currentStreak: (day: Date, qualifiesToday: Bool, count: Int)?
    private var generation = WorkTypeCatalog.shared.generation

    /// Empties the cache and stamps it with the catalogue as it is now.
    mutating func clear() { self = ArchiveTotalsCache() }

    /// Empties the cache when the catalogue has changed since it was last emptied.
    mutating func dropIfCatalogueChanged() {
        if generation != WorkTypeCatalog.shared.generation { clear() }
    }
}
