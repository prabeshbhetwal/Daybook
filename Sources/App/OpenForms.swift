import Foundation

/// A form whose draft a relaunch would lose while it is open: an activity
/// rule, a category, a pinned activity or a break's name being written.
protocol FormDraft: AnyObject {
    var isOpen: Bool { get }
}

/// The forms an owner's surfaces draw, held weakly; each counts only while it
/// is open. An update's countdown waits while any is.
final class OpenForms {
    private let forms = NSHashTable<AnyObject>.weakObjects()

    /// Tracking a form twice keeps it once.
    func track(_ form: FormDraft) { forms.add(form) }

    var anyOpen: Bool {
        forms.allObjects.contains { ($0 as? FormDraft)?.isOpen == true }
    }
}
