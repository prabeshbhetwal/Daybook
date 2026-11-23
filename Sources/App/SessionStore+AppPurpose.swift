import Foundation

/// App categories as the story shows and corrects them. A correction is a
/// `purposeOverrides` entry: it changes the app everywhere, past days
/// included, because every shape and total is derived from it.
extension SessionStore {
    var purposeOverrides: [String: String] { engine.store.purposeOverrides }

    func appPurpose(_ bundleID: String) -> AppPurpose {
        PurposeMap.shownPurpose(for: bundleID, overrides: engine.store.purposeOverrides)
    }

    func appPurposeSource(_ bundleID: String) -> PurposeSource {
        PurposeMap.source(for: bundleID, overrides: engine.store.purposeOverrides)
    }

    /// Sets an app's category, or clears the person's choice with nil.
    /// Returns the override that was there, for Undo.
    @discardableResult
    func setAppPurpose(_ purpose: AppPurpose?, for bundleID: String) -> AppPurpose? {
        var overrides = engine.store.purposeOverrides
        let previous = overrides[bundleID].flatMap(AppPurpose.init(rawValue:))
        guard previous != purpose else { return previous }
        objectWillChange.send()
        overrides[bundleID] = purpose?.rawValue
        engine.store.purposeOverrides = overrides
        refresh()
        return previous
    }
}
