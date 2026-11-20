import Foundation

/// "Let AI assign categories to automatic sessions" (Phase C, rulings C8 and C19). Off until the person turns it
/// on, after seeing how often the suggestions matched their own choices; never switched on for them. Its key is
/// left out of a backup: assigning is switched on per Mac. A type of its own because `PersistenceStore` is full.
struct AIAssignSetting {
    static let key = "fc.aiAssignsCategories"
    static let keys = [key]

    let defaults: UserDefaults

    var isOn: Bool {
        get { defaults.bool(forKey: Self.key) }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}
