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

    func edit(_ rule: ActivityRule) {
        selectedID = rule.id; name = rule.name; workType = rule.workType
        bundleIDs = rule.bundleIDs; enabled = rule.isEnabled
        dwell = ActivityRule.startAfterPresets.contains(rule.startAfter) ? rule.startAfter : -1
        customDwell = dwell == -1 ? String(Int(rule.startAfter)) : ""
        validationMessage = nil
    }

    func beginNew() {
        selectedID = UUID(); name = ""; workType = .deepWork; bundleIDs = []
        enabled = true; dwell = ActivityRule.defaultStartAfter; customDwell = ""
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

struct ActivityRulesView: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var editor = ActivityRuleEditorState()

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack {
                Text("Activity rules").font(Tokens.Typography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("New rule") { editor.beginNew() }.buttonStyle(.bordered)
            }
            if model.activityRules.isEmpty {
                Text("No rules yet. Add applications to an activity, then choose whether rule automation may act.")
                    .font(Tokens.Typography.metadata).foregroundStyle(.secondary)
            } else {
                ForEach(model.activityRules) { rule in
                    Button { editor.edit(rule) } label: {
                        HStack {
                            Label(rule.name, systemImage: rule.workType.symbolName)
                            Spacer()
                            Text("\(rule.bundleIDs.count) app\(rule.bundleIDs.count == 1 ? "" : "s") · \(Int(rule.startAfter))s")
                                .foregroundStyle(.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityHint("Edit this activity rule")
                }
            }
            if editor.selectedID != nil { editorForm }
        }
        .onAppear {
            model.installedAppCatalog.refresh()
            if editor.selectedID == nil, let first = model.activityRules.first { editor.edit(first) }
        }
    }

    private var editorForm: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Divider()
            TextField("Activity name", text: $editor.name).textFieldStyle(.roundedBorder)
            Picker("Work type", selection: $editor.workType) {
                ForEach(WorkType.startable, id: \.self) { Text($0.displayName).tag($0) }
            }
            HStack {
                Picker("Start after", selection: $editor.dwell) {
                    ForEach(ActivityRule.startAfterPresets, id: \.self) {
                        Text(Tokens.preciseDuration($0)).tag($0)
                    }
                    Text("Custom…").tag(-1.0)
                }
                if editor.dwell == -1 {
                    TextField("30–1800 seconds", text: $editor.customDwell)
                        .frame(width: 140).accessibilityLabel("Custom whole seconds")
                }
                Toggle("Enabled", isOn: $editor.enabled)
            }
            InstalledAppPicker(catalog: model.installedAppCatalog,
                               query: $editor.appQuery, selection: $editor.bundleIDs)
            if let message = editor.validationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(Tokens.Typography.metadata).foregroundStyle(.red)
                    .accessibilityLabel("Rule error: \(message)")
            }
            HStack {
                Button("Save rule") {
                    if let rule = editor.ruleForSaving() { model.saveActivityRule(rule) }
                }.buttonStyle(.borderedProminent)
                if let id = editor.selectedID, model.activityRules.contains(where: { $0.id == id }) {
                    Button("Delete", role: .destructive) {
                        model.removeActivityRule(id: id); editor.selectedID = nil
                    }
                }
            }
        }
        .padding(Tokens.Space.m)
        .background(StoryStyle.well, in: RoundedRectangle(cornerRadius: Tokens.Radius.nested))
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
            HStack {
                TextField("Search applications", text: $query).textFieldStyle(.roundedBorder)
                Button { catalog.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh installed applications")
                    .accessibilityLabel("Refresh installed applications")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered) { application in
                        Toggle(isOn: Binding(
                            get: { selection.contains(application.bundleID) },
                            set: { selected in
                                if selected { selection.insert(application.bundleID) }
                                else { selection.remove(application.bundleID) }
                            })) {
                            HStack {
                                if let url = application.url {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                        .resizable().frame(width: 20, height: 20)
                                        .accessibilityHidden(true)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(application.displayName)
                                    Text(application.bundleID).font(Tokens.Typography.metadata)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }.toggleStyle(.checkbox).frame(minHeight: 32)
                        .preference(key: InstalledAppRowCountKey.self, value: 1)
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 220)
            .accessibilityLabel("Applications in this activity")
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
