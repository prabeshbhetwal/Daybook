import Foundation

/// The site signal (phase D). With `.siteKind` on, a stretch of an ambiguous app (a browser)
/// the person has not given a purpose is read by the kind of site it showed, through the same
/// rules as an app with that rule. Without the signal, sites are ignored entirely.
extension ActivityCredit {
    /// The site that decides a piece's credit, nil when none does. A purpose the person chose
    /// for the app beats the site. Any app may be honoured, not only those the purpose map calls
    /// ambiguous: only a browser the person confirmed is ever read for a site.
    static func honouredSite(_ site: SiteKind?, app: String, _ input: CreditInput) -> SiteKind? {
        input.signals.contains(.siteKind) && !isOverridden(app, input.purposeOverrides) ? site : nil
    }

    static func isOverridden(_ app: String, _ overrides: [String: String]) -> Bool {
        PurposeMap.override(for: app, in: overrides) != nil
    }

    /// Whether a held run's holder is read as a browser: ambiguous in the map, or, with the signal
    /// on and no purpose set by the person, its own slices in the run carry a site.
    static func holdsAsBrowser(_ app: String, in run: ArraySlice<Beat>, overrides: [String: String],
                               signals: Set<SignalKind>) -> Bool {
        isAmbiguous(app, overrides) || (signals.contains(.siteKind) && !isOverridden(app, overrides)
            && run.contains { $0.slices.contains { $0.app == app && $0.site != nil } })
    }

    /// A held browser is watching, unless its own slices in the run were on a meeting for most
    /// of their seconds: then it is a call. Without the signal it is always watching.
    static func heldBrowserPurpose(_ app: String, in run: ArraySlice<Beat>, signals: Set<SignalKind>) -> AppPurpose {
        guard signals.contains(.siteKind) else { return .media }
        var meeting = 0, total = 0
        for slice in run.flatMap(\.slices) where slice.app == app {
            total += slice.seconds
            if slice.site == .meeting { meeting += slice.seconds }
        }
        return meeting * 2 > total ? .communication : .media
    }
}

extension PurposeRule {
    /// What the rule gives for this input, as `PurposeMap.purpose` reads a mapped app.
    func purpose(_ activity: InputActivity) -> AppPurpose {
        switch self {
        case .fixed(let purpose): return purpose
        case .ambiguous(let active, let passive): return activity == .active ? active : passive
        }
    }

    var isAmbiguous: Bool {
        if case .ambiguous = self { return true }
        return false
    }
}

extension ActivityDerivation {
    /// The fingerprint's site kind: the kind with the most credited seconds, ties by
    /// `SiteKind.allCases` order; "none" when no credited slice carries one.
    static func siteKind(_ slices: [CreditedSlice]) -> String {
        var seconds: [SiteKind: TimeInterval] = [:]
        for slice in slices where slice.purpose != nil {
            if let site = slice.site { seconds[site, default: 0] += slice.end.timeIntervalSince(slice.start) }
        }
        var best: SiteKind?
        for kind in SiteKind.allCases where (seconds[kind] ?? 0) > (best.flatMap { seconds[$0] } ?? 0) { best = kind }
        return best?.rawValue ?? "none"
    }
}
