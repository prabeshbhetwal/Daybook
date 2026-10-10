import Foundation

/// The activity-rule and category forms Settings shows, kept outside the
/// pages that draw them. Settings rebuilds a page whenever the reader
/// switches page or searches, and a form held by the page lost its unsaved
/// draft each time without asking, where a note draft survives for the reader
/// to save or cancel. One pair per `SettingsModel`, so a draft ends only when
/// the reader saves it or closes the form.
final class SettingsDrafts {
    let rule = ActivityRuleEditorState()
    let category = CategoryEditorState()

    private static let held = NSMapTable<SettingsModel, SettingsDrafts>.weakToStrongObjects()

    static func of(_ model: SettingsModel) -> SettingsDrafts {
        if let drafts = held.object(forKey: model) { return drafts }
        let drafts = SettingsDrafts()
        held.setObject(drafts, forKey: model)
        // A relaunch would lose them too: an update waits while one is open.
        model.track(drafts.rule)
        model.track(drafts.category)
        return drafts
    }
}
