import Combine
import Foundation

/// The pinned-activity panel's draft. An object because `@State` is
/// unavailable here, and held by the panel rather than its view.
final class ActivityEditorState: ObservableObject, FormDraft {
    @Published var editingID: UUID?
    @Published var name = ""
    @Published var workType: WorkType = .deepWork
    @Published var message: String?
    var consumedTicket: UInt64 = 0
    /// What the form showed when it was set up. The form is always on screen,
    /// so only a change from this is a draft a relaunch would lose.
    private var opened = (name: "", workType: WorkType.deepWork)

    var isOpen: Bool { editingID != nil && (name != opened.name || workType != opened.workType) }

    func beginNew() {
        editingID = UUID(); name = ""; workType = .deepWork; message = nil
        opened = (name, workType)
    }

    func edit(_ activity: SavedActivity) {
        editingID = activity.id; name = activity.name
        workType = activity.startableWorkType; message = nil
        opened = (name, workType)
    }

    func close() { editingID = nil; message = nil }
}
