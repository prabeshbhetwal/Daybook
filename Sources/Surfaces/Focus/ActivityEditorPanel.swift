import SwiftUI
import AppKit

final class ActivityEditorPanelModel: ObservableObject {
    @Published var request: ActivityEditorRequest = .new
    @Published var ticket: UInt64 = 0
}

/// A small floating window for the user's own list of activities: add one,
/// rename, change its category, reorder, remove. Opened from the activity
/// menu, the same way the category panel opens from the category picker.
@MainActor final class ActivityEditorPanel {
    static let shared = ActivityEditorPanel()

    private var panel: NSPanel?
    private var closeObserver: NSObjectProtocol?
    private let model = ActivityEditorPanelModel()
    static var width: CGFloat { 460.zoomed }

    var isVisible: Bool { panel?.isVisible ?? false }
    var title: String? { panel?.title }

    func show(_ request: ActivityEditorRequest, store: SessionStore) {
        model.request = request
        model.ticket &+= 1
        let panel = self.panel ?? makePanel(store: store)
        panel.title = request == .new ? "Pin activity" : "Pinned activities"
        if !panel.isVisible { position(panel) }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Every `show` starts the form afresh, so nothing in a closed panel is
    /// worth keeping: its window and SwiftUI tree, which would otherwise go on
    /// following the store, are let go and built again on the next `show`.
    func close() {
        guard let panel else { return }
        panel.orderOut(nil)
        release(panel)
    }

    private func release(_ closing: NSPanel) {
        guard panel === closing else { return }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        closing.contentView = nil
        panel = nil
    }

    private func makePanel(store: SessionStore) -> NSPanel {
        let content = ActivityEditorPanelView(store: store, model: model, onClose: { [weak self] in self?.close() })
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: ActivityEditorPanel.width, height: 420.zoomed),
                            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        // The body carries its own title band, the way the app's sheets do;
        // the window's title only names it in Mission Control.
        panel.titleVisibility = .hidden
        panel.hideStandardButtons()
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        self.panel = panel
        // A system close (⌘W) ends the panel the same way `close` does.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self, weak panel] _ in
                MainActor.assumeIsolated {
                    guard let self, let panel else { return }
                    self.release(panel)
                }
            }
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { panel.center(); return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                     y: frame.midY - size.height / 2 + frame.height * 0.08))
    }
}

/// The form's draft. An object because `@State` is unavailable here.
final class ActivityEditorState: ObservableObject {
    @Published var editingID: UUID?
    @Published var name = ""
    @Published var workType: WorkType = .deepWork
    @Published var message: String?
    var consumedTicket: UInt64 = 0

    func beginNew() {
        editingID = UUID(); name = ""; workType = .deepWork; message = nil
    }

    func edit(_ activity: SavedActivity) {
        editingID = activity.id; name = activity.name
        workType = activity.startableWorkType; message = nil
    }

    func close() { editingID = nil; message = nil }
}

/// The panel's content, one surface: the pinned list, recent names to pin
/// with a click, and the form, always present. Click a pinned row to edit
/// it in the form; leave the form blank to pin something new.
struct ActivityEditorPanelView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var model: ActivityEditorPanelModel
    @ObservedObject private var catalog = WorkTypeCatalog.shared
    @StateObject private var editor = ActivityEditorState()
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Pinned activities",
                        subtitle: "They lead the activity menu, in this order. Anything you type is kept "
                            + "as a recent name on its own; pin the ones you come back to.",
                        onClose: onClose)
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                pinnedList
                if !store.recentActivities.isEmpty, store.canPinActivity { recentPins }
                form
            }
            .padding(Tokens.Space.xl)
        }
        .frame(width: ActivityEditorPanel.width)
        .background(Tokens.Colour.ground)
        .tint(Tokens.Colour.focus)
        .controlSize(Tokens.Zoom.rootControlSize)
        .onAppear(perform: consume)
        .onChange(of: model.ticket) { consume() }
    }

    private func consume() {
        let fresh = model.ticket != editor.consumedTicket
        editor.consumedTicket = model.ticket
        // The form is always there; a fresh ask clears it for a new pin, and
        // an empty form on appearance is set up the same way.
        if fresh || editor.editingID == nil { editor.beginNew() }
    }

    // MARK: List

    @ViewBuilder private var pinnedList: some View {
        if store.savedActivities.isEmpty {
            Text("Nothing pinned yet.")
                .font(Tokens.Typography.body)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(store.savedActivities.enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index < store.savedActivities.count - 1 {
                        Divider().padding(.leading, 52.zoomed)
                    }
                }
            }
            .background(Tokens.Colour.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
                .strokeBorder(Tokens.Colour.line))
        }
    }

    private func row(_ item: SavedActivity) -> some View {
        let selected = editor.editingID == item.id
        let retired = !WorkType.startable.contains(item.workType)
        return Button { editor.edit(item) } label: {
            HStack(spacing: Tokens.Space.m) {
                WorkTypeMark(workType: item.workType, size: 28.zoomed)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(Tokens.Typography.rowTitle)
                    Text(item.workType.displayName + (retired ? " · retired, starts as Deep work" : ""))
                        .font(Tokens.Typography.body)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Tokens.Space.s)
                Image(systemName: "pencil")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(selected ? AnyShapeStyle(Tokens.Colour.focus) : AnyShapeStyle(.secondary))
            }
            .padding(.horizontal, Tokens.Space.m)
            .frame(minHeight: 44.zoomed)
            .background(selected ? StoryStyle.well : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: 0))
        .accessibilityLabel("\(item.name), \(item.workType.displayName)")
        .accessibilityHint("Edit this pinned activity")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Recent

    private var recentPins: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text("Recent · click to pin")
                .font(Tokens.Typography.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ChipFlow(spacing: Tokens.Space.xs) {
                ForEach(store.recentActivities.prefix(6)) { quick in
                    Button { _ = store.pinActivity(quick) } label: {
                        HStack(spacing: Tokens.Space.xs) {
                            WorkTypeMark(workType: quick.workType, size: 20.zoomed)
                            Text(quick.name)
                                .font(Tokens.Typography.body)
                                .lineLimit(1)
                        }
                        .padding(.leading, Tokens.Space.xs)
                        .padding(.trailing, Tokens.Space.m)
                        .frame(minHeight: 28.zoomed)
                        .background(Tokens.Colour.elevated, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: 14.zoomed))
                    .help("Pin \(quick.name)")
                    .accessibilityLabel("Pin \(quick.name)")
                }
            }
        }
    }

    // MARK: Form

    private var form: some View {
        let existing = store.savedActivities.firstIndex { $0.id == editor.editingID }
        let isNew = existing == nil
        return VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack(spacing: Tokens.Space.m) {
                WorkTypeMark(workType: editor.workType, size: 44.zoomed)
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    HStack(spacing: Tokens.Space.s) {
                        Text(isNew ? "Pin an activity" : "Editing a pinned activity")
                            .font(Tokens.Typography.body)
                            .foregroundStyle(.secondary)
                        if !isNew {
                            Button("New") { editor.beginNew() }
                                .buttonStyle(StoryLinkStyle())
                                .accessibilityLabel("Clear the form to pin a new activity")
                        }
                    }
                    TextField("Activity name", text: $editor.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260.zoomed)
                        .onSubmit(save)
                        .accessibilityLabel("Activity name")
                }
            }
            HStack(spacing: Tokens.Space.s) {
                Text("Category")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
                WorkTypePicker(selection: $editor.workType)
            }
            if let message = editor.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Tokens.Colour.danger)
            }
            HStack(spacing: Tokens.Space.s) {
                Button(isNew ? "Pin" : "Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isNew && !store.canPinActivity)
                    .help(isNew && !store.canPinActivity ? "Eight is the limit. Unpin one to pin another." : "")
                Spacer(minLength: Tokens.Space.s)
                if let index = existing, let id = editor.editingID {
                    Button("Move up") { store.moveSavedActivity(id: id, up: true) }
                        .disabled(index == 0)
                    Button("Move down") { store.moveSavedActivity(id: id, up: false) }
                        .disabled(index == store.savedActivities.count - 1)
                    Button("Unpin", role: .destructive) {
                        store.removeSavedActivity(id: id)
                        editor.beginNew()
                    }
                }
            }
        }
        .padding(Tokens.Space.m)
        .background(Tokens.Colour.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
            .strokeBorder(Tokens.Colour.line))
    }

    private func save() {
        guard let id = editor.editingID else { return }
        let name = SavedActivities.normalisedName(editor.name)
        guard !name.isEmpty else { editor.message = "Give the activity a name."; return }
        if store.saveActivity(SavedActivity(id: id, name: name, workType: editor.workType)) {
            editor.beginNew()
        } else if !store.canPinActivity && !store.savedActivities.contains(where: { $0.id == id }) {
            editor.message = "Eight is the limit. Unpin one to pin another."
        } else {
            editor.message = "“\(name)” is already pinned."
        }
    }
}
