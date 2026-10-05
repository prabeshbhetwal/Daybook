import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class ActivityRuleEditorState: ObservableObject {
    @Published var selectedID: UUID?
    @Published var name = ""
    @Published var workType: WorkType = .deepWork
    @Published var bundleIDs = Set<String>()
    @Published var enabled = true
    @Published var dwell: TimeInterval = ActivityRule.defaultStartAfter
    @Published var customDwell = ""
    @Published var validationMessage: String?
    @Published var appQuery = ""
    /// True while the form describes a rule that is not saved yet.
    @Published var isNew = false
    /// The rule a Delete is waiting on the reader to confirm.
    @Published var pendingDeletion: ActivityRule?
    /// Bumped when the reader opens the form, so it scrolls into view and its
    /// name field takes the cursor. The form opening itself on arrival does
    /// not ask: nobody chose it.
    @Published private(set) var focusRequest = 0
    /// The last request acted on. Not published: consuming it must not redraw.
    var consumedFocusRequest = 0

    func requestFocus() { focusRequest += 1 }

    func edit(_ rule: ActivityRule) {
        selectedID = rule.id; name = rule.name; workType = rule.workType
        bundleIDs = rule.bundleIDs; enabled = rule.isEnabled
        dwell = ActivityRule.startAfterPresets.contains(rule.startAfter) ? rule.startAfter : -1
        customDwell = dwell == -1 ? String(Int(rule.startAfter)) : ""
        validationMessage = nil
        isNew = false
    }

    func beginNew() {
        selectedID = UUID(); name = ""; workType = .deepWork; bundleIDs = []
        enabled = true; dwell = ActivityRule.defaultStartAfter; customDwell = ""
        validationMessage = nil
        isNew = true
    }

    /// A copy of a rule, ready to be renamed and saved as its own.
    func duplicate(_ rule: ActivityRule) {
        edit(rule)
        selectedID = UUID()
        name = rule.name + " copy"
        isNew = true
    }

    func close() {
        selectedID = nil
        isNew = false
        validationMessage = nil
    }

    func ruleForSaving() -> ActivityRule? {
        let seconds: TimeInterval
        if dwell == -1 {
            switch ActivityRule.validateCustomStartAfter(customDwell) {
            case .success(let value): seconds = value
            case .failure(let error): validationMessage = error.localizedDescription; return nil
            }
        } else { seconds = dwell }
        let cleanName = ActivityRule.normalisedName(name)
        guard !cleanName.isEmpty else { validationMessage = "Enter an activity name."; return nil }
        guard !bundleIDs.isEmpty else { validationMessage = "Choose at least one application."; return nil }
        validationMessage = nil
        return ActivityRule(id: selectedID ?? UUID(), name: cleanName,
            workType: workType, bundleIDs: bundleIDs, isEnabled: enabled, startAfter: seconds)
    }
}

/// Every rule as a card: which apps, what it starts, when. The card's switch
/// turns the rule on and off in place; opening it edits it in the well below.
struct ActivityRulesView: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var editor = ActivityRuleEditorState()
    @Environment(\.focusInterfaceDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let editorID = "activity-rule-editor"

    var body: some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: editor.focusRequest) { _ in
                    // The form opens below the list, often out of sight.
                    DispatchQueue.main.async {
                        withAnimation(Tokens.Motion.animation(Tokens.Motion.reveal, reduceMotion: reduceMotion)) {
                            proxy.scrollTo(Self.editorID, anchor: .top)
                        }
                    }
                }
        }
        .confirmationDialog("Delete “\(editor.pendingDeletion?.name ?? "")”?",
                            isPresented: Binding(get: { editor.pendingDeletion != nil },
                                                 set: { if !$0 { editor.pendingDeletion = nil } }),
                            titleVisibility: .visible,
                            presenting: editor.pendingDeletion) { rule in
            Button("Delete rule", role: .destructive) {
                model.removeActivityRule(id: rule.id)
                if editor.selectedID == rule.id { editor.close() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It stops starting sessions. Sessions it already started are kept.")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            SurfacePanel(title: "Rules", layout: density.layout) {
                Text("A rule starts a session by itself once you have been in one of its apps "
                     + "for its wait, files the session under its category and names it after "
                     + "the rule. An app in two rules asks which one, instead of guessing.")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.activityRules.isEmpty {
                    EmptyState("No rules yet",
                               detail: "Name an activity and pick the apps that belong to it.",
                               icon: "app.badge.checkmark")
                } else {
                    ForEach(model.activityRules) { rule in
                        ActivityRuleCard(rule: rule,
                                         apps: model.installedAppCatalog.applications,
                                         isEditing: editor.selectedID == rule.id && !editor.isNew,
                                         onToggle: { enabled in
                                             var changed = rule
                                             changed.isEnabled = enabled
                                             model.saveActivityRule(changed)
                                         },
                                         onEdit: { open { editor.edit(rule) } },
                                         onDuplicate: { open { editor.duplicate(rule) } },
                                         onDelete: { editor.pendingDeletion = rule })
                    }
                }
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        open { editor.beginNew() }
                    } label: {
                        Label("New rule", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("New rule")
                }
            }
            if editor.selectedID != nil {
                SurfacePanel(title: editor.isNew ? "New rule" : "Edit rule", layout: density.layout) {
                    ActivityRuleForm(model: model, editor: editor)
                }
                .id(Self.editorID)
                .transition(Tokens.Motion.transition(Tokens.Motion.unfold, reduceMotion: reduceMotion))
            }
        }
        // The form opens only when a rule is chosen or New rule is pressed.
        // Opening the first rule on arrival put an editor under the list that
        // nobody had asked for.
        .onAppear { model.installedAppCatalog.refresh() }
    }

    private func open(_ change: () -> Void) {
        withAnimation(Tokens.Motion.animation(Tokens.Motion.reveal, reduceMotion: reduceMotion)) { change() }
        editor.requestFocus()
    }
}

/// One rule: its apps' icons, its name and category, its wait, its switch.
struct ActivityRuleCard: View {
    let rule: ActivityRule
    let apps: [InstalledApplication]
    let isEditing: Bool
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    private var ruleApps: [InstalledApplication] {
        rule.bundleIDs.sorted().map { id in
            apps.first { $0.bundleID == id } ?? InstalledApplication(bundleID: id, name: id, url: nil, isInstalled: false)
        }
    }

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            Button(action: onEdit) {
                HStack(spacing: Tokens.Space.m) {
                    iconStrip
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: Tokens.Space.s) {
                            Text(rule.name)
                                .font(Tokens.Typography.rowTitle.weight(.medium))
                                .lineLimit(1)
                            WorkTypeChip(workType: rule.workType)
                            // Said in words, so an off rule is not told only
                            // by its faded icons.
                            if !rule.isEnabled {
                                Text("Off")
                                    .font(Tokens.Typography.microLabel)
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }
                        Text(detail)
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Tokens.Space.s)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(StoryPressStyle())
            .accessibilityLabel([rule.name, rule.workType.displayName, detail, rule.isEnabled ? nil : "off"]
                .compactMap { $0 }.joined(separator: ", "))
            .accessibilityHint("Edit this rule")
            .accessibilityAddTraits(isEditing ? .isSelected : [])
            // The switch speaks its own state; a label that also said "on"
            // was read as "rule on, off".
            Toggle("", isOn: Binding(get: { rule.isEnabled }, set: onToggle))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel("\(rule.name) rule")
            Menu {
                Button("Edit", action: onEdit)
                Button("Duplicate", action: onDuplicate)
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(Tokens.Typography.control)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More actions for \(rule.name)")
        }
        .padding(.vertical, Tokens.Space.s)
        .padding(.horizontal, Tokens.Space.s)
        .background(isEditing ? Tokens.Colour.focus.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
    }

    /// Up to four icons, overlapping like a stack of cards.
    private var iconStrip: some View {
        HStack(spacing: -6) {
            ForEach(Array(ruleApps.prefix(4).enumerated()), id: \.element.id) { index, app in
                Group {
                    if let url = app.url {
                        Image(nsImage: AppIconProvider.shared.icon(forFile: url.path, size: 26))
                            .resizable()
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable()
                            .foregroundStyle(.tertiary)
                            .padding(4)
                    }
                }
                .frame(width: 26, height: 26)
                .background(StoryStyle.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .zIndex(Double(4 - index))
            }
            if ruleApps.count > 4 {
                Text("+\(ruleApps.count - 4)")
                    .font(Tokens.Typography.microLabel)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
            }
        }
        // Only the pictures fade for an off rule: the words beside them stay
        // readable, and "Off" says it.
        .opacity(rule.isEnabled ? 1 : 0.5)
        .accessibilityHidden(true)
    }

    private var detail: String {
        let names = ruleApps.prefix(3).map(\.name).joined(separator: ", ")
        let more = ruleApps.count > 3 ? " +\(ruleApps.count - 3)" : ""
        return [names + more, "starts after \(Tokens.preciseDuration(rule.startAfter))"]
            .joined(separator: " · ")
    }
}

/// The form for one rule: what to call it, where to file it, how long to
/// wait, and which apps belong to it, with the apps running right now one
/// click away.
struct ActivityRuleForm: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var editor: ActivityRuleEditorState
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack(spacing: Tokens.Space.m) {
                TextField("Activity name", text: Binding(get: { editor.name }, set: { typed in
                    editor.name = typed
                    // Typed only, never on opening a rule: a name that spells
                    // a category files the rule there unless picked otherwise.
                    if let named = SessionNaming.category(named: typed) { editor.workType = named }
                }))
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit(save)
                    .accessibilityLabel("Activity name")
                // The same category menu as the session strip, with Add and
                // Edit category, so a rule can file work under a category
                // made on the spot.
                // The app's own box, as the session strip draws it, not the
                // platform's bezel: the same menu, Add and Edit category included.
                // It says "Category" and the chosen one itself.
                WorkTypePicker(selection: $editor.workType, quiet: true)
            }
            if let named = SessionNaming.contradicts(name: editor.name, workType: editor.workType) {
                Label("\(named.displayName) is also a category. Sessions from this rule will count toward "
                      + "\(editor.workType.displayName), not \(named.displayName).",
                      systemImage: "exclamationmark.triangle")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(Tokens.Colour.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                HStack(spacing: Tokens.Space.m) {
                    Text("Start after")
                        .font(Tokens.Typography.control)
                    Picker("Start after", selection: $editor.dwell) {
                        ForEach(ActivityRule.startAfterPresets, id: \.self) {
                            Text(Tokens.preciseDuration($0)).tag($0)
                        }
                        Text("Custom…").tag(-1.0)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                    if editor.dwell == -1 {
                        HStack(spacing: 4) {
                            TextField("30 to 1800", text: $editor.customDwell)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 96)
                                .onSubmit(save)
                                .accessibilityLabel("Start after, whole seconds")
                            Text("seconds")
                                .font(Tokens.Typography.metadata)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: Tokens.Space.l)
                    Toggle(isOn: $editor.enabled) {
                        Text("Use this rule")
                            .font(Tokens.Typography.control)
                            .fixedSize()
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
                }
                Text("How long you must be in one of its apps before the session begins.")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            chosenApps
            runningNow
            InstalledAppPicker(catalog: model.installedAppCatalog,
                               query: $editor.appQuery, selection: $editor.bundleIDs)
            if let message = editor.validationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(Tokens.Typography.metadata).foregroundStyle(Tokens.Colour.danger)
                    .accessibilityLabel("Rule error: \(message)")
            }
            // Return and Escape belong to the rule only while the reader is
            // in it. The form opens by itself on arrival, and as the Settings
            // sheet's own shortcuts it would have saved on a stray Return,
            // while its Escape lost to the sheet's Close and shut Settings.
            // Return in a field saves; Escape inside the form cancels it.
            HStack(spacing: Tokens.Space.m) {
                Button(editor.isNew ? "Add rule" : "Save rule", action: save)
                    .buttonStyle(.borderedProminent)
                Button("Cancel") { editor.close() }
                Spacer(minLength: 0)
                if !editor.isNew, let id = editor.selectedID,
                   let rule = model.activityRules.first(where: { $0.id == id }) {
                    Button("Delete rule", role: .destructive) { editor.pendingDeletion = rule }
                }
            }
        }
        .onExitCommand { editor.close() }
        .preference(key: OpenInlineFormKey.self,
                    value: OpenInlineForm(name: "rule", cancel: { editor.close() }))
        .announcesChanges(to: editor.validationMessage)
        .onAppear(perform: takeFocusIfAsked)
        .onChange(of: editor.focusRequest) { _ in takeFocusIfAsked() }
    }

    private func save() {
        // Saving is finishing: the card above now shows the rule.
        if let rule = editor.ruleForSaving() {
            model.saveActivityRule(rule)
            editor.close()
        }
    }

    private func takeFocusIfAsked() {
        guard editor.focusRequest != editor.consumedFocusRequest else { return }
        editor.consumedFocusRequest = editor.focusRequest
        // The field must be installed before it can take focus.
        DispatchQueue.main.async { nameFocused = true }
    }

    /// The apps in the rule, as chips that remove on click.
    @ViewBuilder private var chosenApps: some View {
        if !editor.bundleIDs.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text("In this activity")
                    .font(Tokens.Typography.microLabel)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ChipFlow(spacing: Tokens.Space.xs) {
                    ForEach(editor.bundleIDs.sorted(), id: \.self) { id in
                        let app = model.installedAppCatalog.applications.first { $0.bundleID == id }
                        Button {
                            editor.bundleIDs.remove(id)
                        } label: {
                            HStack(spacing: 4) {
                                if let url = app?.url {
                                    Image(nsImage: AppIconProvider.shared.icon(forFile: url.path, size: 14))
                                        .resizable().frame(width: 14, height: 14)
                                }
                                Text(app?.name ?? id).lineLimit(1)
                                Image(systemName: "xmark")
                                    .font(Tokens.Typography.micro.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            .font(Tokens.Typography.metadata)
                            .padding(.horizontal, Tokens.Space.s)
                            .frame(minHeight: 26)
                            .background(Tokens.Colour.focus.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: 13))
                        .accessibilityLabel("Remove \(app?.name ?? id) from this activity")
                    }
                }
            }
        }
    }

    /// Apps open on the Mac right now that are not in the rule yet: the ones
    /// a person usually means, one click to add.
    @ViewBuilder private var runningNow: some View {
        let running = Self.runningApplications().filter { !editor.bundleIDs.contains($0.bundleID) }
        if !running.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text("Running now")
                    .font(Tokens.Typography.microLabel)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ChipFlow(spacing: Tokens.Space.xs) {
                    ForEach(running) { app in
                        Button {
                            editor.bundleIDs.insert(app.bundleID)
                        } label: {
                            HStack(spacing: 4) {
                                if let url = app.url {
                                    Image(nsImage: AppIconProvider.shared.icon(forFile: url.path, size: 14))
                                        .resizable().frame(width: 14, height: 14)
                                }
                                Text(app.name).lineLimit(1)
                                Image(systemName: "plus")
                                    .font(Tokens.Typography.micro.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            .font(Tokens.Typography.metadata)
                            .padding(.horizontal, Tokens.Space.s)
                            .frame(minHeight: 26)
                            .background(Tokens.Colour.elevated, in: Capsule())
                            .overlay(Capsule().strokeBorder(Tokens.Colour.line))
                        }
                        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: 13))
                        .accessibilityLabel("Add \(app.name) to this activity")
                    }
                }
            }
        }
    }

    /// Ordinary apps with a window, not this one and not the system's own.
    static func runningApplications() -> [InstalledApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app -> InstalledApplication? in
                guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return InstalledApplication(bundleID: id, name: name, url: app.bundleURL)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Counts the picker rows that actually rendered. Production ignores the
/// preference; verification reads it to prove a row exists for each published
/// application, rather than only that a scroll region appeared.
struct InstalledAppRowCountKey: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

struct InstalledAppPicker: View {
    @ObservedObject var catalog: InstalledAppCatalog
    @Binding var query: String
    @Binding var selection: Set<String>

    private var filtered: [InstalledApplication] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return catalog.applications }
        return catalog.applications.filter {
            $0.name.localizedCaseInsensitiveContains(value)
                || $0.bundleID.localizedCaseInsensitiveContains(value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text("All applications")
                .font(Tokens.Typography.microLabel)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                // The list below carries this name for VoiceOver.
                .accessibilityHidden(true)
            HStack {
                TextField("Search applications", text: $query).textFieldStyle(.roundedBorder)
                Button { catalog.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh installed applications")
                    .accessibilityLabel("Refresh installed applications")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered) { application in
                        let isOn = selection.contains(application.bundleID)
                        Button {
                            if isOn { selection.remove(application.bundleID) }
                            else { selection.insert(application.bundleID) }
                        } label: {
                            HStack(spacing: Tokens.Space.s) {
                                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    .font(Tokens.Typography.control)
                                    .foregroundStyle(isOn ? AnyShapeStyle(Tokens.Colour.focus)
                                                          : AnyShapeStyle(.secondary))
                                    .frame(width: 18)
                                if let url = application.url {
                                    Image(nsImage: AppIconProvider.shared.icon(forFile: url.path, size: 22))
                                        .resizable().frame(width: 22, height: 22)
                                        .accessibilityHidden(true)
                                } else {
                                    Image(systemName: "app.dashed")
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 22, height: 22)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(application.displayName)
                                        .font(Tokens.Typography.control)
                                    Text(application.bundleID).font(Tokens.Typography.metadata)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Tokens.Space.s)
                            .frame(minHeight: 34)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.control))
                        .accessibilityLabel(application.displayName)
                        .accessibilityValue(isOn ? "in this activity" : "not in this activity")
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                        .preference(key: InstalledAppRowCountKey.self, value: 1)
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 220)
            .padding(.vertical, Tokens.Space.xs)
            .background(StoryStyle.well.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .accessibilityLabel("All applications")
            HStack {
                Button("Add application…", action: addApplication)
                if catalog.isLoading { ProgressView().controlSize(.small) }
            }
        }
    }

    private func addApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let application = InstalledAppCatalog.application(at: url) else { return }
        selection.insert(application.bundleID)
    }
}
