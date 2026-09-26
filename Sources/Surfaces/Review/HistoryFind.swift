import SwiftUI

/// The search that reaches the whole archive: a field for names, notes,
/// apps, categories and dates, the two menus that narrow it, and a way out.
struct HistoryFindBar: View {
    @ObservedObject var store: SessionStore
    let onClose: () -> Void
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tokens.Space.s) {
                field
                appMenu
                workTypeMenu
                closeButton
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                field
                HStack(spacing: Tokens.Space.s) {
                    appMenu
                    workTypeMenu
                    closeButton
                }
            }
        }
        .onAppear { fieldFocused = true }
    }

    private var field: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Find a session: name, note, app, category or date", text: queryBinding)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .onExitCommand(perform: onClose)
            if !store.historyFilter.query.isEmpty {
                Button { store.setHistoryQuery("") } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Tokens.Space.m)
        .frame(minHeight: 32)
        .background(Tokens.Colour.elevated,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
            .strokeBorder(Tokens.Colour.line))
        .accessibilityLabel("Find a session")
    }

    private var closeButton: some View {
        Button("Done") {
            store.clearHistoryFilters()
            onClose()
        }
        .buttonStyle(StoryLinkStyle())
        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
        .accessibilityLabel("Close search")
    }

    private var appMenu: some View {
        Menu {
            Button("All apps") { store.setHistoryApp(nil) }
            Divider()
            ForEach(store.historyAppBundleIDs, id: \.self) { bundleID in
                Button(store.historyAppName(for: bundleID)) { store.setHistoryApp(bundleID) }
            }
        } label: {
            Label(store.historyFilter.appBundleID.map(store.historyAppName(for:)) ?? "All apps",
                  systemImage: "app")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
        .accessibilityLabel("App filter, selected "
                            + (store.historyFilter.appBundleID.map(store.historyAppName(for:)) ?? "all apps"))
    }

    private var workTypeMenu: some View {
        Menu {
            Button { store.setHistoryWorkType(nil) } label: {
                Label("All categories", systemImage: "square.grid.2x2").labelStyle(.titleAndIcon)
            }
            Divider()
            ForEach(WorkType.allCases) { type in
                Button { store.setHistoryWorkType(type) } label: {
                    Label(type.displayName, systemImage: type.symbolName).labelStyle(.titleAndIcon)
                }
            }
        } label: {
            Label(store.historyFilter.workType?.displayName ?? "All categories",
                  systemImage: store.historyFilter.workType?.symbolName ?? "square.grid.2x2")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
        .accessibilityLabel("Category filter, selected "
                            + (store.historyFilter.workType?.displayName ?? "all categories"))
    }

    private var queryBinding: Binding<String> {
        Binding(get: { store.historyFilter.query }, set: store.setHistoryQuery)
    }
}

/// Matches across the archive, under the month they fall in. A picked hit
/// previews its day in the rail; a double-click opens that day's story.
struct HistoryFindResults: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @StateObject private var picked = HoverBox()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let hits = store.historySearchHits()
        let months = HistoryHitMonth.group(hits)
        return LazyVStack(alignment: .leading, spacing: Tokens.Space.l) {
            Text(summary(hits))
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
            if hits.isEmpty {
                EmptyState("No matching sessions",
                           detail: "Try a session name, a word from a note, an app, a category or a date.",
                           icon: "magnifyingglass")
            }
            ForEach(months) { month in
                VStack(alignment: .leading, spacing: 2) {
                    Text(month.title)
                        .font(Tokens.Typography.metadata.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Tokens.Space.s)
                        .padding(.bottom, Tokens.Space.xs)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(month.hits) { hit in
                        HistoryHitRow(hit: hit, isSelected: picked.id == hit.id.uuidString) {
                            withAnimation(Tokens.Motion.animation(Tokens.Motion.selection,
                                                                  reduceMotion: reduceMotion)) {
                                let id = hit.id.uuidString
                                picked.id = picked.id == id ? nil : id
                                if picked.id != nil { navigation.selectReviewDay(hit.day) } else { navigation.clearReviewDay() }
                            }
                        } onOpen: {
                            navigation.openStory(.day, containing: hit.day)
                        }
                    }
                }
            }
        }
        .onChange(of: store.historyFilter) { _ in picked.id = nil }
    }

    private func summary(_ hits: [HistorySearchHit]) -> String {
        guard !hits.isEmpty else { return "Searching everything on record." }
        let word = hits.count == 1 ? "session matches" : "sessions match"
        return "\(hits.count) \(word) across everything on record, "
            + "\(Tokens.duration(hits.reduce(0) { $0 + $1.worked })) of focus between them."
    }
}

/// The archive's own figures: what a year's rail always carries.
struct HistoryArchiveTiles: View {
    let facts: HistoryArchiveFacts
    let now: Date
    var appLimit = FocusConstants.defaultMenuApps

    var body: some View {
        StoryTile(title: "On record", trailing: facts.firstDay.map { "since \(Self.sinceLabel($0))" }) {
            Text(Tokens.preciseDuration(facts.focused))
                .font(Tokens.Typography.metricValue.monospacedDigit())
            Text(note)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !facts.categories.isEmpty {
            StoryTile(title: "All-time categories", trailing: nil) {
                CategoryShareBar(shares: facts.categories)
            }
        }
        if !facts.apps.isEmpty {
            StoryTile(title: facts.apps.count > appLimit ? "All-time top \(appLimit) apps" : "All-time apps",
                      trailing: facts.apps.count == 1 ? "1 recorded" : "\(facts.apps.count) recorded") {
                ForEach(Array(facts.apps.prefix(appLimit).enumerated()), id: \.element.id) { index, app in
                    StoryAppRow(app: app, rank: index)
                }
            }
        }
    }

    private var note: String {
        var parts = [facts.dayCount == 1 ? "1 day" : "\(facts.dayCount) days",
                     facts.sessionCount == 1 ? "1 session" : "\(facts.sessionCount) sessions"]
        if facts.longestStreak > 1 { parts.append("longest streak \(facts.longestStreak) days") }
        return parts.joined(separator: " · ")
    }

    static func sinceLabel(_ date: Date) -> String {
        Tokens.australianDate("d MMM yyyy").string(from: date)
    }
}

/// Search hits under the month they fall in, newest first.
struct HistoryHitMonth: Identifiable {
    let start: Date
    let hits: [HistorySearchHit]
    var id: Date { start }

    var title: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: start)
    }

    static func group(_ hits: [HistorySearchHit], calendar: Calendar = .current) -> [HistoryHitMonth] {
        var groups: [HistoryHitMonth] = []
        var current: [HistorySearchHit] = []
        var open: Date?
        for hit in hits {
            let start = calendar.dateInterval(of: .month, for: hit.day)?.start ?? hit.day
            if let openStart = open, openStart != start {
                groups.append(HistoryHitMonth(start: openStart, hits: current))
                current = []
            }
            open = start
            current.append(hit)
        }
        if let openStart = open, !current.isEmpty { groups.append(HistoryHitMonth(start: openStart, hits: current)) }
        return groups
    }
}

/// One matched session: when, what, which category, how long, and the words
/// that matched when they were not in the name.
struct HistoryHitRow: View {
    let hit: HistorySearchHit
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: HistoryRowLayout.spacing) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Calendar.current.component(.day, from: hit.start))")
                        .font(Tokens.Typography.sectionTitle.monospacedDigit())
                    Text(Tokens.weekdayName(hit.start).prefix(3).uppercased())
                        .font(Tokens.Typography.microLabel)
                        .foregroundStyle(isSelected ? AnyShapeStyle(Tokens.Colour.focus)
                                                    : AnyShapeStyle(.secondary))
                }
                .frame(width: HistoryRowLayout.dateWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Tokens.Space.s) {
                        Text(hit.name)
                            .font(Tokens.Typography.rowTitle.weight(.medium))
                            .lineLimit(1)
                        WorkTypeChip(workType: hit.workType)
                    }
                    Text(detail)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Tokens.Space.s)
                Text(Tokens.duration(hit.worked))
                    .font(Tokens.Typography.rowTitle.weight(.semibold).monospacedDigit())
                    .frame(width: HistoryRowLayout.figureWidth, alignment: .trailing)
            }
            .padding(.vertical, Tokens.Space.s)
            .padding(.horizontal, HistoryRowLayout.inset)
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .background(isSelected ? Tokens.Colour.focus.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.nested))
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen() })
        .accessibilityLabel("\(hit.name), \(hit.workType.displayName), \(Tokens.longDate(hit.start)), "
                            + "\(Tokens.spent(hit.worked))" + (isSelected ? ", selected" : ""))
        .accessibilityHint(isSelected ? "Clears the preview" : "Previews this day beside the list")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Open as a story", onOpen)
    }

    private var detail: String {
        var parts = [Tokens.timeRange(hit.start, hit.end)]
        if let note = hit.noteSnippet { parts.append("“\(note)”") }
        if !hit.matchedApps.isEmpty { parts.append(hit.matchedApps.prefix(3).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}
