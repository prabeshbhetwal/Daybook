import SwiftUI

/// The search that reaches the whole archive: a field whose words can be
/// anything a session or break is known by (see `historySearchHits`), the
/// two filters that narrow it, and a way to clear them. It heads History, so
/// it is always there to type into.
struct HistoryFindBar: View {
    @ObservedObject var store: SessionStore
    /// Bumped by ⌘F; each bump puts the cursor in the field.
    let focusRequest: Int
    /// "12 sessions", shown in the field while a search runs.
    var matchCount: String?
    @FocusState private var fieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let searchableHint = "Searches session names, old names, notes, named breaks, apps, "
        + "categories, dates and times of day. Command F puts the cursor here."
    private static let generalPrompt = "Find anything: a name, note, break, app, category, date or time"
    private static let exampleSeconds: TimeInterval = 3.5

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tokens.Space.s) {
                field
                appFilter
                workTypeFilter
                clearButton
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                field
                HStack(spacing: Tokens.Space.s) {
                    appFilter
                    workTypeFilter
                    clearButton
                }
            }
        }
        .onChange(of: focusRequest) { fieldFocused = true }
    }

    // MARK: Field

    private var query: String { store.historyFilter.query }
    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
    }

    private var field: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(fieldFocused ? AnyShapeStyle(StoryStyle.focus) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            ZStack(alignment: .leading) {
                if query.isEmpty { placeholder.accessibilityHidden(true) }
                TextField("", text: queryBinding)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onExitCommand { fieldFocused = false }
                    .accessibilityLabel("Find a session")
                    .accessibilityHint(Self.searchableHint)
            }
            if !query.isEmpty {
                if let matchCount {
                    Text(matchCount)
                        .font(Tokens.Typography.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                }
                Button { store.setHistoryQuery("") } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .transition(.opacity)
            } else if !fieldFocused {
                keycap.transition(.opacity)
            }
        }
        .padding(.horizontal, Tokens.Space.m)
        .frame(height: FilterChip<EmptyView, EmptyView>.height)
        // The halo sits on the fill alone, so the text never blurs with it.
        .background(fieldShape.fill(Tokens.Colour.elevated)
            .shadow(color: StoryStyle.focus.opacity(fieldFocused ? 0.28 : 0), radius: 6.zoomed))
        .overlay(fieldShape.strokeBorder(fieldFocused ? StoryStyle.focus : Tokens.Colour.line,
                                         lineWidth: fieldFocused ? 1.5.zoomed : 1))
        .animation(Tokens.Motion.animation(Tokens.Motion.selection, reduceMotion: reduceMotion),
                   value: fieldFocused)
        .animation(Tokens.Motion.animation(Tokens.Motion.selection, reduceMotion: reduceMotion),
                   value: query.isEmpty)
    }

    /// While the field waits, it offers things worth typing, taken from the
    /// reader's own record. Typing, it says the general rule; with Reduce
    /// Motion, it says only that.
    @ViewBuilder private var placeholder: some View {
        let lines = [Self.generalPrompt] + examples.map { "Try “\($0)”" }
        if fieldFocused || reduceMotion || lines.count == 1 {
            promptText(Self.generalPrompt)
        } else {
            TimelineView(.periodic(from: .now, by: Self.exampleSeconds)) { context in
                let index = Int(context.date.timeIntervalSinceReferenceDate / Self.exampleSeconds) % lines.count
                promptText(lines[index])
                    .id(index)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: index)
            }
        }
    }

    private func promptText(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
    }

    /// Two recent names, two apps, a day and a time of day: one of each kind
    /// the search understands, and none that cannot match. "Yesterday" is
    /// offered only when yesterday holds a session: offered unconditionally,
    /// it sent the reader to an empty result after a day off.
    private var examples: [String] {
        var seen = Set<String>()
        let names = store.quickStarts.prefix(2).map(\.name)
        let apps = store.historyAppBundleIDs.prefix(2).map(store.historyAppName(for:))
        let calendar = SessionStore.historyCalendar
        let workedYesterday = store.historyDays.contains {
            $0.sessions > 0 && calendar.isDateInYesterday($0.date)
        }
        return (names + apps + (workedYesterday ? ["yesterday"] : []) + ["afternoon"])
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private var keycap: some View {
        Text("⌘F")
            .font(Tokens.Typography.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6.zoomed)
            .padding(.vertical, 2.zoomed)
            .overlay(RoundedRectangle(cornerRadius: 5.zoomed, style: .continuous).strokeBorder(Tokens.Colour.line))
            .accessibilityHidden(true)
    }

    // MARK: Filters

    /// Only while something is being searched.
    @ViewBuilder private var clearButton: some View {
        if store.historyFilter.isActive {
            Button("Clear") {
                store.clearHistoryFilters()
                fieldFocused = false
            }
            .buttonStyle(StoryLinkStyle())
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .accessibilityLabel("Clear search and filters")
        }
    }

    private var appFilter: some View {
        let picked = store.historyFilter.appBundleID
        return FilterChip(title: picked.map(store.historyAppName(for:)) ?? "All apps",
                          isActive: picked != nil,
                          filterName: "App filter",
                          clearLabel: "Show all apps",
                          onClear: { store.setHistoryApp(nil) }) {
            if let picked {
                AppIcon(bundleID: picked, size: 16.zoomed, appName: store.historyAppName(for: picked))
            } else {
                Image(systemName: "app")
            }
        } items: {
            Picker("App", selection: Binding(get: { store.historyFilter.appBundleID },
                                             set: store.setHistoryApp)) {
                Text("All apps").tag(String?.none)
                Divider()
                ForEach(store.historyAppBundleIDs, id: \.self) { bundleID in
                    Label {
                        Text(store.historyAppName(for: bundleID))
                    } icon: {
                        Self.menuIcon(for: bundleID)
                    }
                    .tag(String?.some(bundleID))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .redrawn(on: [picked ?? ""] + store.historyAppBundleIDs)
    }

    /// A menu row's icon must be an image: a macOS menu draws a view icon as
    /// its text, so an uninstalled app's letter tile stood in for its name
    /// and "T" picked Tolaria. Without an icon to load, a plain symbol.
    @ViewBuilder static func menuIcon(for bundleID: String) -> some View {
        if let icon = AppIconProvider.shared.icon(for: bundleID, size: 16) { // zoom: fixed (a native menu row keeps the system menu size)
            Image(nsImage: icon)
        } else {
            Image(systemName: "app.dashed")
        }
    }

    private var workTypeFilter: some View {
        let picked = store.historyFilter.workType
        return FilterChip(title: picked?.displayName ?? "All categories",
                          isActive: picked != nil,
                          tint: picked.map(Tokens.Palette.workType) ?? StoryStyle.action,
                          ink: picked.map(StoryStyle.workTypeInk) ?? StoryStyle.action,
                          filterName: "Category filter",
                          clearLabel: "Show all categories",
                          onClear: { store.setHistoryWorkType(nil) }) {
            Image(systemName: picked?.symbolName ?? "square.grid.2x2")
                .symbolRenderingMode(.hierarchical)
        } items: {
            Picker("Category", selection: Binding(get: { store.historyFilter.workType },
                                                  set: store.setHistoryWorkType)) {
                Label("All categories", systemImage: "square.grid.2x2").tag(WorkType?.none)
                Divider()
                ForEach(WorkType.allCases) { type in
                    Label(type.displayName, systemImage: type.symbolName).tag(WorkType?.some(type))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .redrawn(on: [picked?.rawValue ?? ""]
                    + WorkType.allCases.map { "\($0.rawValue)|\($0.displayName)|\($0.symbolName)" })
    }

    private var queryBinding: Binding<String> {
        Binding(get: { store.historyFilter.query }, set: store.setHistoryQuery)
    }
}
