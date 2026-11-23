import Foundation

/// App categories as the story shows and corrects them. A correction is a
/// `purposeOverrides` entry: it changes the app everywhere, past days
/// included, because every shape and total is derived from it.
extension SessionStore {
    /// Posted after a card changes an app's category, so an open Settings list follows.
    static let appPurposesDidChange = Notification.Name("DaybookAppPurposesDidChange")

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
        let overrides = engine.store.purposeOverrides
        let previous = PurposeMap.override(for: bundleID, in: overrides)
        guard previous != purpose else { return previous }
        objectWillChange.send()
        engine.store.savePurposeOverrides(PurposeMap.settingOverride(purpose, for: bundleID, in: overrides), at: now())
        refresh()
        NotificationCenter.default.post(name: Self.appPurposesDidChange, object: self)
        return previous
    }
}
